---
name: kb-capture
description: >
  Session-journaling sub-skill. Reads Claude Code session transcripts from
  ~/.claude/projects/ (including thinking blocks, tool calls, and
  assistant/user messages), distills them into structured decision journals
  persisted in Fast.io at {project_folder}/journal/, promotes high-signal
  insights to mem0 (or buffers when mem0 is unavailable), and updates
  hot.md with recent decisions. Topic-agnostic.
---

# KB Capture — Session Journal Sub-Skill

You are the journaling engine of the Knowledge Base system. Your job is
to read the agent's own reasoning traces from Claude Code's local
transcripts, distill them into structured decision journals, and persist
them where future sessions and future reviewers can learn from them.

**Architecture reference:** `.claude/kb-docs/ARCHITECTURE.md` §3.4
(Session Journaling).

## Arguments

- `--project`: **required** — project name (loads manifest from
  `.claude/kb-projects/`)
- `--since`: default `7d`. Accepts `{n}d` (e.g. `7d`, `30d`), an ISO
  date (`2026-04-14`), `last-capture` (resume from bookmark), or `all`
  (replay full history — expensive, explicit opt-in only).
- `--dry-run`: list sessions that would be captured; do not write.
- `--raw`: also persist a verbatim raw dump of thinking + tool calls +
  messages to `{project_folder}/journal/raw/{date}-{sid}-raw.md`.
  Not RAG-indexed (stored via a path Fast.io excludes from workspace
  intelligence, or marked `rag_indexed: false`). Forensic review only.
- `--outcome {success|partial|failed}`: tag all captured sessions in
  this invocation. Used by future skills to weight journal context.
- `--cross-project`: include transcripts from other project directories
  (`~/.claude/projects/*/`), not just the current cwd's transcript
  folder. Distilled notes list all projects touched.

## Step 0: Load Manifest

Read `.claude/kb-projects/{project}.yaml`. Extract:

- `project.project_folder` — Fast.io folder for journal writes
- `project.name` — for tagging mem0 entries
- `journal.distillation_budget_tokens` (optional, default 3000) — soft
  cap on tokens spent per session distillation
- `journal.retain_raw_days` (optional, default 30) — raw dumps older
  than this can be archived; not enforced in this skill, noted for a
  future `kb-archive` skill
- `journal.redact_patterns` (optional, default []) — regex list to
  scrub before upload. **Not implemented in v1** — manifest accepts
  the field but the skill ignores it. Log a warning if non-empty.

## Step 0.5: mem0 Availability Check

Same zero-cost tool-registry check as other skills. **NEVER call
`mcp__mem0-mcp__authenticate` or `complete_authentication`.** If only
authenticate tools are present, set `mem0_available = false` and buffer
promotions to `{project_folder}/mem0-pending.md`.

## Privacy Notice (surface on first run)

Before first-ever capture for a project, surface:

```
KB Capture — Privacy Notice
Thinking tokens from your Claude Code session(s) will be uploaded
verbatim to Fast.io at {workspace}/{project_folder}/journal/. Thinking
blocks can contain debugging traces, file paths, strategy hypotheses,
internal deliberation, and references to credentials or sensitive
business logic. Redaction is NOT applied by default.

If this is not acceptable:
  - Cancel this run (Ctrl-C before confirming)
  - Or add regex patterns to manifest.journal.redact_patterns (note:
    enforcement is slated for a future release; v1 does not redact)
  - Or use --dry-run to review what would be uploaded before committing
  - Or keep --raw off (distilled summaries are shorter and have less
    incidental-detail risk than raw dumps)

Proceed? [y/N]
```

On subsequent runs, skip the prompt unless `--raw` is being enabled for
the first time (raw dumps warrant re-consent because they carry more
incidental detail than distilled summaries).

## Execution Flow

### Step 1: Locate Session Transcripts

**Important: resolve symlinks before sanitizing.** Claude Code writes
per-project transcript folders using the REAL path of the working
directory, not the path the user typed. If the working directory is a
symlink (for example, `/data/github/algobrute-engine` resolving to
`/media/smalik/data/github/algobrute-engine`), naive sanitization of
the typed path produces a folder name that does not exist on disk.

Compute the sanitized cwd as follows:

```
real_cwd   = realpath(cwd)   # resolves all symlinks in the path
sanitized  = "-" + real_cwd.lstrip("/").replace("/", "-")

# Example:
#   cwd       = /data/github/algobrute-engine (a symlink)
#   real_cwd  = /media/smalik/data/github/algobrute-engine
#   sanitized = -media-smalik-data-github-algobrute-engine
```

Transcript directory: `~/.claude/projects/{sanitized}/`.

**Fallback** (defensive — in case the sanitization convention changes
in a future Claude Code version): if the computed directory does not
exist but `~/.claude/projects/` has other subfolders, scan each
`*.jsonl` file's first 20 events for a `cwd` field (user or attachment
events typically carry it). Match transcripts whose recorded cwd
equals `real_cwd`. Report the recovered mapping so future runs can
update the sanitization rule if needed.

List `*.jsonl` files in the resolved directory. With `--cross-project`,
also list files under other project directories; tag each with its
source cwd (recoverable by un-sanitizing the folder name or by reading
the cwd field from the transcript itself).

### Step 2: Determine Capture Scope

Read the bookmark from Fast.io via `workspace/read-note`:
`{project_folder}/journal/bookmark.md`.

**Why `.md` not `.yaml`:** Fast.io's `workspace/create-note` requires a
`.md` extension. Earlier drafts of this spec used `.bookmark.yaml`; in
practice the skill must use a markdown filename. The YAML payload goes
inside a fenced code block within the markdown file, like so:

````markdown
# Journal Bookmark — {project_name}

```yaml
last_captured_at: "2026-04-21T08:00:00Z"
captured_session_ids:
  - "94dca334-cbb5-4a8d-826b-7ba54173802d"
  - "..."
prompt_version_hash: "sha256:..."
```
````

Parsers: look for the first fenced ```yaml``` block in the file and
parse that; ignore any surrounding prose.

If bookmark doesn't exist → first run; create empty.

Filter transcripts to capture:

1. Apply `--since`:
   - `7d` (default): mtime within last 7 days
   - `{n}d`: mtime within last N days
   - ISO date: mtime on or after that date
   - `last-capture`: mtime > bookmark.last_captured_at
   - `all`: no mtime filter
2. Exclude session IDs already in `bookmark.captured_session_ids`
3. Cross-check with existing `{project_folder}/journal/INDEX.md` —
   session IDs present there are already captured regardless of
   bookmark state (defense in depth against bookmark loss)

If no sessions to capture → report "Nothing to capture" and exit.

### Step 3: For Each New Session

Process sessions sequentially (not parallel — distillation is
stateful within a session).

#### 3a: Extract Content from Transcript

**Distillation-source strategy — reflexive beats retrospective for the
current session.** Empirically, when the skill is invoked from within
the session being captured, distilling from the agent's **working
memory** produces higher-fidelity output than parsing the same
session's JSONL. Working memory carries the agent's implicit arc
(decision-and-revert structure, why alternatives were rejected, what
the agent actually weighed) which the JSONL only encodes as a
sequence of discrete thinking blocks requiring reconstruction.

**Critical constraint — Claude Code 2.1.116+ redacts thinking at
write-time.** As of Claude Code version 2.1.116 (released mid-April
2026, silently — not in any changelog), every `thinking` content
block written to the JSONL is stripped to empty string, leaving only
the `signature` field (a 500–32K-byte Anthropic-encrypted protobuf
used for server-side session-resume forward-chaining). Signatures
are opaque and not client-decodable. No hook event receives the
pre-redaction thinking, and `--debug api --debug-file` operates at a
layer below the redaction — empirically verified to produce zero
`"type":"thinking"` blocks in the debug log.

**Detecting the redaction in practice:** a JSONL thinking block with
`thinking: ""` AND `signature: <long hex>` means the content was
redacted at write-time. Count such blocks and record them as
`compaction_events` proxy — they represent the same thing operationally
(thinking is gone; only outcomes survive).

**Recovery path forward** (for any session you expect to distill
retrospectively): terminal capture at launch, before the session
starts. `script(1)` or `asciinema` preserve what appears on-screen —
if verbose mode (Ctrl+O) is enabled, thinking *is* rendered to the
terminal. Example:

```
# Make every Claude Code launch recoverable:
alias claude='script -q -f -c claude ~/.claude-captures/$(date +%F-%H%M%S).typescript'
# Or, for a cleaner replayable format:
alias claude='asciinema rec -c claude ~/.claude-captures/$(date +%F-%H%M%S).cast'
```

If terminal captures exist for a session, kb-capture (future version)
can consume them as an additional distillation source. v1 looks at
JSONL only.

**For each session being captured, classify its distillation source:**

- **Session is the currently-executing one** (reflexive):
  - → prefer working-memory distillation. Use the JSONL only for
    specific artifacts (tool call args, commit SHAs, timestamps).
  - → Front-matter: `distillation_source: working_memory+jsonl`,
    `fidelity: full` (reflexive distillation has access to reasoning
    the JSONL never had, redaction notwithstanding).
- **Session is historical, pre-2.1.116 Claude Code** (retrospective,
  thinking present):
  - → Parse the JSONL as a rich source. Thinking blocks have
    cleartext content. Reconstruction is possible.
  - → Front-matter: `distillation_source: jsonl`, `fidelity: full`.
- **Session is historical, post-2.1.116 Claude Code** (retrospective,
  thinking redacted — the common case going forward):
  - → Parse the JSONL for user turns, assistant text output, tool
    calls, and tool results. Thinking is gone.
  - → If a terminal capture (script/asciinema/tmux pipe-pane) exists
    for the session, use it as supplementary source and upgrade
    fidelity accordingly.
  - → Front-matter: `distillation_source: jsonl`, `fidelity: degraded`,
    and set `compaction_events` to the count of redacted-thinking
    blocks. This is NOT the same semantics as
    context-window compaction, but operationally it's the same
    signal: reasoning that happened is no longer recoverable. Surface
    this explicitly in the Session Metadata Notes section of the
    distilled output so readers understand why the retrospective
    note has fewer decisions than the live session produced.
- **Session went through context-window compactions** (orthogonal
  to the redaction issue):
  - → Additionally tag `fidelity: degraded` if ≥3 compaction events.
  - → Each compaction event replaced detailed thinking with a
    summary; decisions from within that summary window will be
    less recoverable even from terminal captures.

**JSONL parsing (all sessions, retrospective or for verification):**

Use `Read` on the JSONL file. For large transcripts (>2000 lines),
read in pages. Parse each line as JSON.

Collect:
- **User messages**: `type == "user"`, extract text blocks. Filter out
  tool results (those are paired with earlier tool_use blocks).
- **Assistant text output**: `type == "assistant"` with `content` blocks
  of type `text`. This is what the agent said to the user.
- **Thinking blocks**: `type == "assistant"` with `content` blocks of
  type `thinking`. This is the agent's internal reasoning.
- **Tool calls**: `type == "assistant"` with `content` blocks of type
  `tool_use`. Capture tool name, input args (truncate large args to
  first 500 chars with `[...truncated]` marker).
- **Tool results**: paired with tool_use via `tool_use_id`. Capture
  first 500 chars of output with truncation marker; drop ANSI color
  codes.

Capture session metadata:
- `session_id`: UUID from filename
- `start_time`: first message timestamp
- `end_time`: last message timestamp
- `cwd`: infer from sanitized folder name
- `message_count`, `thinking_block_count`, `tool_call_count`

#### 3a.5: Read Existing Active Notes for This Session

Before distilling, check whether the agent (or user) actively
journaled decisions during this session via the `kb-note` skill.
Active notes are AUTHORITATIVE for the decisions they cover —
retrospective distillation must NOT re-emit them, and MUST link
to them.

1. Compute `session_id8 = session_id[:8]` (same short form kb-note
   uses in filenames).
2. List files in `{project_folder}/journal/notes/` via
   `storage/list` or `workspace/read-note` on the INDEX —
   match filenames of the form `{YYYY-MM-DD}-{session_id8}-*.md`.
3. For each matching file, `workspace/read-note` to extract:
   - `seq` (from front-matter)
   - `type` (decision / diagnostic / insight / open_thread)
   - `title` (from front-matter)
   - The first 2-3 sentences of the body (for summary / dedup check)
   - Full file path (for linking)
4. Build an `active_notes` list, ordered by `seq`. This becomes
   input to the distillation prompt in 3b.

If no active notes exist for this session → empty list, proceed
normally. Retrospective distillation behaves as it did before
Phase 2 — it covers everything, because nothing was actively
journaled.

If active notes exist → the distillation prompt receives them and
must:
- Exclude the decisions they cover from its own `Decisions`
  section (no duplication)
- Cross-link to them via the `Related` subsection of each
  retrospective decision it DOES emit (so readers can navigate
  between active and retrospective entries for the same session)
- Populate a new `Missed Decisions` section — decisions the
  distiller inferred from the user/assistant/tool arc that
  weren't in the active-notes list. This is the "what the agent
  forgot to actively journal" signal.

#### 3b: Distill into Structured Journal Note

Apply the distillation prompt below. The distillation is performed by
the Claude instance executing this skill (reflexive: the agent reads
its own prior thinking).

**Distillation prompt (version: journal-distill-v2):**

```
You are reading session transcript material — user turns, assistant
text output, tool calls, thinking blocks where available — PLUS a
list of active notes already journaled for this session via the
kb-note skill. Your job is to produce a RETROSPECTIVE SESSION
SUMMARY that COMPLEMENTS those active notes, NOT duplicates them.

Rules:
- Be faithful to the source. Do not invent reasoning that wasn't
  present. Compress redundancy; preserve branches and revisions.
- If the active notes cover a decision, do NOT re-emit that decision
  in your Decisions section. Cross-link to the active note via the
  Related subsection of any retrospective decision that depends on it.
- Decisions you infer from the user/assistant/tool arc that were
  NOT in the active notes go into a separate "Missed Decisions"
  section. This is the signal of "what the agent should have
  journaled but didn't" — it's the primary signal that feeds the
  catch-up value of retrospective distillation when active
  journaling is used.
- Diagnostics, Insights, Open Threads: follow the same
  authoritative-active rule. If the active notes already cover a
  finding, don't re-emit it; cross-link when referencing.
- Session Summary and narrative-arc content (the WHY of the whole
  session, not just individual decisions) is the UNIQUE value of
  the retrospective summary. Always write it, even when active
  notes are comprehensive. This is how retrospective distillation
  earns its keep in the layered design.

Output this structure (markdown). Omit sections that would be empty.

---
session_id: {sid}
date: {YYYY-MM-DD}
start_time: {HH:MM}
end_time: {HH:MM}
duration: {Nh Nm}
cwd: {path}
projects_touched: [{list}]
outcome: {success|partial|failed|unspecified}
raw_available: {true|false}
distillation_source: {working_memory+jsonl|jsonl}
fidelity: {full|degraded}
prompt_version_hash: sha256:{hash of this distillation prompt}
thinking_block_count: {N}
tool_call_count: {N}
user_turn_count: {N}
compaction_events: {N}
active_notes_count: {N}
active_notes_referenced:
  - notes/{filename1}
  - notes/{filename2}
missed_decisions_count: {N}
---

# Session Journal — {date} — {one-line topic}

## Session Summary
2-3 sentences. What was worked on, what the arc was.

## Active Notes (cross-reference, not re-emission)

If the session has active notes, list them here as a navigation aid
BEFORE the Decisions section:

- [seq 001, decision] Title — link to notes/{filename}
- [seq 002, insight] Title — link
- ...

This is a thin index. Do NOT re-describe the content of active
notes here. Readers click through to the individual note files.

## Decisions

Numbered list. For each non-trivial decision that was NOT covered
by an active note:

### D{N}: {short title in imperative voice}
**Context:** what situation prompted it
**Decision:** the choice made
**Alternatives considered:** other approaches weighed + reasons rejected
**Rationale:** why this one (causal, not just preferential)
**Artifacts:** commits, files, notes this decision produced or affected
**Related:** earlier decisions (D{M}), active notes (notes/{filename}),
or external refs (commit SHAs, URLs, prior journals)

Rule of thumb: a decision is journal-worthy when (a) the agent chose
among ≥2 considered alternatives, (b) the choice hinges on non-obvious
reasoning, or (c) the choice has implications beyond the immediate
change. "Read this file to check syntax" is NOT a decision. "Use
cherry-pick instead of interactive rebase because content-equivalence
is mechanically provable via tree SHAs" IS a decision.

**Coverage rule:** if an active note covers a decision in full
(same Context, Decision, Alternatives, Rationale), DO NOT re-emit
it here. Cross-link from Missed Decisions or from dependent
decisions' Related field if relevant.

## Missed Decisions (if any)

Decisions inferred from the user/assistant/tool arc that were NOT
captured in active notes. This section is the primary catch-up
value of retrospective distillation when active journaling is
used. Format is the same as Decisions above — each entry a full
D{N} block so that after this distillation runs, every decision
in the session is either (a) in an active note or (b) in Missed
Decisions. Nothing falls through.

If active_notes_count is zero, this section is equivalent to
Decisions — merge them under a single "Decisions" header and
omit "Missed Decisions." If active_notes_count is non-zero,
both sections may exist and are complementary.

## Diagnostics
Non-obvious findings that changed the plan. Each: what was observed,
what it implied, what changed as a result. Diagnostic ≠ decision — it's
a fact that forced decisions elsewhere. Apply the same "exclude active
notes" rule: if a diagnostic is already in an active `diagnostic`-type
note, skip it here and link from the Related section of any dependent
decision.

## Insights
Generalizable patterns or principles surfaced that extend beyond this
session. Be honest: if nothing general came up, omit the section.
Again, exclude insights already in active `insight`-type notes.

## Artifacts Touched
- Commits: {repo}@{sha} — {subject}
- Files modified: {repo}/{path}
- Fast.io notes: {path}
- Active notes: {list of notes/{filename} links for this session}
- External: URLs consulted

## Open Threads
Unresolved items the agent noted but didn't close in this session.
Exclude threads already in active `open_thread`-type notes.

## Session Metadata Notes
Any patterns in the session worth noting for distillation-quality
feedback (e.g. "agent got stuck for 20 min on X, took approach Y
after Z", "13 active notes recorded during session — active
journaling is working well here", or "0 active notes despite long
session — agent may not have been prompted to journal, check
CLAUDE.md configuration"). Keep brief.
```

When applying this prompt, give yourself a soft budget of
`journal.distillation_budget_tokens` tokens (default 3000) for the
output. If a session has many distinct decisions, err toward a longer
note; if the session was mostly routine, keep it terse.

#### 3c: Compute Prompt Version Hash

Compute `sha256` of the distillation prompt text (the block between the
triple-backticks above, verbatim). Bake into the front-matter.

#### 3d: Write Raw Dump (if --raw)

Path: `{project_folder}/journal/raw/{date}-{session_id}-raw.md`.

Format: a markdown file with one section per content type:

```markdown
# Raw Session Dump — {date} — {session_id}

This is a forensic-grade verbatim capture of session content. Not
auto-indexed for RAG. See the distilled note at
../{date}-{session_id}-distilled.md for the structured summary.

## User Turns
...verbatim user messages...

## Assistant Text Output
...verbatim text responses...

## Thinking Blocks
...verbatim thinking blocks, one per `### Block {N} at {timestamp}`...

## Tool Calls
...tool_use blocks with name/args, paired with truncated results...
```

Use `workspace/create-note`. Apply metadata: `rag_indexed: false` (if
Fast.io supports per-note RAG opt-out — otherwise accept the cost of
indexing raw dumps).

#### 3e: Write Distilled Note

Path: `{project_folder}/journal/{date}-{session_id}-distilled.md`.

Use `workspace/create-note`. Apply metadata:

- `type: journal_entry`
- `session_id`, `date`, `outcome`, `projects_touched` (from front-matter)
- `prompt_version_hash`

The note will be auto-indexed for RAG; future semantic searches across
the KB will surface relevant journal entries alongside sources and
syntheses.

#### 3f: Update INDEX.md

Use `workspace/update-note` on `{project_folder}/journal/INDEX.md`.
Append a row per session:

```markdown
| {session_id} | {date} | {duration} | {decision_count} | {outcome} | [distilled]({link}) |
```

Format:

```markdown
# Journal Index — {project_name}
Last updated: {date}

## Captured Sessions
| session_id | date | duration | decisions | outcome | link |
|------------|------|----------|-----------|---------|------|
| ... |

## Decision Quick Reference

Unified view across active notes (from kb-note) and retrospective
session summaries. Each row tagged with its source:

- 2026-04-23 / 7d26f67a / active D001 (decision): Framing C layered paths → notes/2026-04-23-7d26f67a-001-....md
- 2026-04-23 / 0343f10a / retro D001 (decision, missed): ... → 2026-04-23-0343f10a-distilled.md#d1
- ...
```

The `source` column distinguishes `active` entries (written at
decision-time via kb-note, `fidelity: full`) from `retro` entries
(retrospective distillation by kb-capture; fidelity depends on
JSONL + Claude Code version + terminal-capture availability). The
`(missed)` suffix on retro entries flags decisions that weren't
covered by an active note — the signal for whether active
journaling discipline is working.

The quick reference lets readers scan the full decision history
without opening each journal. Cap at ~100 most-recent entries;
older ones remain in the per-session notes and the table above.

### Step 4: Update Hot Cache

Read `{project_folder}/hot.md` via `workspace/read-note`. Append (or
replace, if present) a section combining the most recent decisions
across BOTH active notes (from kb-note) and retrospective summaries
(from this run + prior runs). The goal: kb-assess's Layer 1 Context
read gets a unified, provenance-tagged view.

```markdown
## Recent Decisions (from journal captures)
Last captured: {date}
- [active]  D{N} ({date} / {sid-prefix}): {title} — {one-line rationale}
- [retro]   D{N} ({date} / {sid-prefix}): {title} — {one-line rationale}
- [retro-missed] D{N} ({date} / {sid-prefix}): {title} — {one-line rationale}
- ...
(up to 5 most recent decisions across all captured sessions)
```

This is what `kb-assess`'s Layer 1 Context read picks up (it already
reads hot.md) — no budget impact on assessment.

### Step 5: Promote Insights to mem0

Select the 2–3 highest-signal distilled Insights from the newly
captured sessions. High-signal = generalizable (applies beyond this
one session), concrete (specific not vague), and non-obvious.

For each selected insight:
- Prepare entry: `[{project_name}][JOURNAL-{date}] {insight text}`
- If `mem0_available`: call `mcp__mem0-mcp__add_memory` with the entry.
  On failure, set `mem0_available = false` and buffer the rest.
- If not `mem0_available`: buffer to `{project_folder}/mem0-pending.md`
  via `workspace/update-note`.

Example promotion:

```
[weak-signal-strategy][JOURNAL-2026-04-21] Language choice steers LLM
agent behavior: "not authenticated" status nudges the agent to retry
authentication; "misconfigured" nudges reconfiguration. Framing is a
control mechanism, especially when agents read docs as operational
instructions. Applied in kb-system c9ed5cd.
```

### Step 6: Advance Bookmark

Write updated bookmark to
`{project_folder}/journal/bookmark.md` via `workspace/update-note`
(or `workspace/create-note` if this is the first capture). The file
is markdown with a fenced YAML block inside — see the format note in
Step 2.

````markdown
# Journal Bookmark — {project_name}

```yaml
last_captured_at: {ISO-8601 now}
captured_session_ids:
  - {all previous}
  - {newly captured}
prompt_version_hash: sha256:{current prompt version}
captured_session_count: {total}
```
````

If `prompt_version_hash` differs from the previous bookmark, log it
— this is a prompt drift event and may warrant a meta-journal entry
describing what changed in the prompt.

### Step 7: Append Work Log + Report

Append via `worklog/append`. If the worklog endpoint is unavailable
(5xx errors), fall back to appending an audit section to `hot.md` —
see "Worklog Endpoint Fallback" below. The fallback must preserve the
same semantic content (sessions/decisions/promotions counts and the
journal-INDEX pointer) so future readers of either surface get the
same record.

```
[{project}] Capture complete. Sessions: {N} captured, {M} skipped (already indexed).
Decisions extracted: {N}. Insights promoted to mem0: {N} ({M} buffered).
Outcome tags: {counts}. Raw dumps written: {N} (if --raw).
Prompt version: {version_id} (hash: {short}).
mem0: {available|misconfigured|unavailable}.
```

User-facing report:

```
KB Capture Complete — {date}
Project: {project_name}
Since: {resolved --since value}

Sessions captured: {N}
  {session_id}: {date} — {duration} — {decision_count} decisions — {outcome}
  ...

Decisions extracted: {N total}
Top insights promoted:
  1. {insight 1}
  2. {insight 2}
  3. {insight 3}

Journal entries: {project_folder}/journal/{date}-*-distilled.md
Raw dumps: {N written, gated by --raw} (non-indexed)
mem0 promotions: {N stored, M buffered}
Bookmark advanced to: {timestamp}

Next capture: run /kb-capture --project {project} --since last-capture
  (or let kb-refresh's Category 10 lint remind you)
```

## Distillation Fidelity Rules

- **Be faithful.** If the thinking shows "tried X, then Y, reverted to
  X because W", the distilled Decision should show that arc in
  Alternatives Considered, not collapse to "chose X."
- **Don't editorialize.** No opinions about the quality of reasoning;
  only fact-based extraction.
- **Preserve hashes.** If the thinking references commit SHAs, file
  paths, tool call IDs, copy them verbatim into Artifacts Touched.
- **Cross-reference.** If a decision depends on an earlier decision
  (same session or prior), note it under Related.
- **When in doubt, include.** A slightly-too-long decision entry is
  recoverable; a missing decision is invisible after the raw transcript
  ages out.

## Character Encoding Guidance

Fast.io's `workspace/create-note` has tripped on doubly-encoded UTF-8
escape sequences (e.g. `â` for U+2192 `→` arrow) — the
validator rejects the malformed bytes. Two patterns that avoid it:

1. **Prefer direct Unicode characters** in note content — write `→`,
   not `→`. If the writing tool's string escaping cannot be
   controlled, fall back to (2).
2. **Prefer ASCII substitutes** when Unicode won't round-trip —
   `->` for `→`, `--` for `—`, `"..."` for `"…"`. Slightly less
   typographically pleasing; guaranteed to write.

This applies to journal note bodies, front-matter values, and anything
written via `workspace/create-note` / `workspace/update-note`. Bookmark
files inherit the same constraint.

## Worklog Endpoint Fallback

If `worklog/append` returns a 5xx error (observed as a persistent 500
response against Fast.io during the first real-world exercise of this
skill — tracked as a Fast.io upstream issue, not a skill bug), fall
back to writing the worklog entry as an audit section appended to
`{project_folder}/hot.md`:

```markdown
## Capture Audit — {date} (worklog-unavailable fallback)
- Sessions captured: {N}
- Decisions extracted: {N}
- mem0 promotions: {N}
- See detail in journal/INDEX.md
```

This preserves the work-log semantics (timestamped record of activity)
even when the dedicated worklog endpoint is unavailable. On the next
capture, retry `worklog/append` first; only fall back if it still
errors.

## Credit Awareness

- **Distilled note ingestion**: ~10–20 credits per session
  (1–2 pages, Fast.io RAG indexing).
- **Raw dump ingestion (if --raw)**: potentially hundreds of credits
  per session (large content, indexing cost). v1 writes raw dumps to
  a `raw/` subfolder; if your Fast.io workspace respects a `raw/`
  exclusion for indexing, cost drops to near-zero storage-only.
  **Decision:** treat raw dumps as forensic-only; don't capture them
  by default.
- **mem0 add_memory**: minor cost; ~2–3 entries per session is
  negligible on Fast.io's side (mem0 has its own billing).
- **Distillation LLM cost**: paid in the current session's token budget
  (the skill runs in Claude Code). Per-session distillation typically
  2–5K input tokens (transcript) + 1–3K output tokens (structured
  note). At Opus rates, roughly $0.10–0.50 per session.

**Budget gating**: if `journal.distillation_budget_tokens` in the
manifest is set, the skill will refuse to emit a note longer than
that many tokens (truncation, not failure — flagged in the output).

## What This Skill Does NOT Do

- Does not modify source code or project artifacts.
- Does not absorb journal entries as KB sources (they live in
  `journal/` alongside `sources/` but are not the same type). Future
  `kb-absorb --include-journals` may be added for retrospective
  synthesis, not v1.
- Does not redact sensitive content. `journal.redact_patterns` is
  accepted in the manifest but ignored until a future release.
- Does not delete or archive old raw dumps. `journal.retain_raw_days`
  is noted for a future `kb-archive` skill.
- Does not heuristically infer `outcome` — if `--outcome` is not
  passed, all captured sessions are tagged `unspecified`.
- Does not capture sessions currently in progress. If a transcript
  file's mtime is within the last 60 seconds, skip it and note
  "N sessions in-progress; retry after they close."

## Scheduling Guidance

Run this skill:
- **After any significant work session** — manually, while context is fresh.
- **During every `/kb-review`** — the meta-skill can invoke `kb-capture`
  as its final phase so routine reviews also rotate recent decisions
  into the KB.
- **Weekly as standalone** — `/kb-capture --project X --since 7d` picks
  up anything missed.

The meta-skill (`/kb-review`) runs this as Step 4 if the `--phase`
argument includes `journal` (or is `all`, the default).
