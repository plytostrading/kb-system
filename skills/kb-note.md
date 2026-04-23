---
name: kb-note
description: >
  Active-journaling sub-skill — records a single decision, diagnostic,
  insight, or open thread directly to Fast.io during a live session.
  Invokable by agents during development work (via the Skill tool) or
  by users (via slash command). Complements kb-capture's retrospective
  distillation by capturing reasoning at decision-time rather than
  post-hoc, removing dependency on Claude Code's JSONL transcript
  representation.
---

# KB Note — Active Journaling Sub-Skill

You are the active-journaling engine of the Knowledge Base system.
Your job is to record a single piece of reasoning — a decision, a
diagnostic finding, a generalizable insight, or an open thread — to
Fast.io as it happens, so the reasoning is preserved even if the
session's JSONL transcript later redacts thinking content.

**Architecture reference:** `.claude/kb-docs/ARCHITECTURE.md` §3.5
(Active Journaling via kb-note).

## Invocation paths

Two surfaces, same behavior:

- **User-typed slash command** — user types
  `/kb-note --project X --type decision --title "..."` and then the
  agent fills in the body. Useful for manual journaling or for users
  who want to force a record of a specific decision.
- **Agent-programmatic via the Skill tool** — the agent invokes
  `Skill("kb-note", "--project X --type decision --title \"...\"\n\n<body>")`
  during development work. This is the primary path — it runs
  without user interruption, mid-flow, as the agent makes non-trivial
  decisions.

When to invoke (agent discipline — also codified in CONTRIBUTING.md):

- **Do invoke** when the agent chooses among ≥2 considered
  alternatives; when reversing a prior choice; when diagnosing a
  non-obvious issue; when surfacing a generalizable pattern; when
  marking an unresolved question.
- **Don't invoke** for routine lookups, boilerplate generation,
  simple fixes, or answering factual questions. The journal is for
  reasoning worth preserving — not a tool call log.

## Arguments

- `--project`: **required** — project name (loads manifest from
  `.claude/kb-projects/`)
- `--type`: **required** — one of `decision`, `diagnostic`,
  `insight`, `open_thread`
- `--title`: **required** — short imperative title, under ~70 chars
  (becomes part of the filename slug and the INDEX row)
- Body: the structured markdown following the per-type template
  below, provided in the skill's input (after the argument line)

## Step 0: Load Manifest

Read `.claude/kb-projects/{project}.yaml`. Extract:
- `project.project_folder` — Fast.io folder path
- `project.name` — for mem0 tagging

## Step 0.5: mem0 Availability Check

Same zero-cost tool-registry check used by other kb-* skills.
**NEVER call `mcp__mem0-mcp__authenticate` or
`complete_authentication`.** If only authenticate tools are
present, set `mem0_available = false` — insight promotions will
be buffered to `mem0-pending.md`.

## Step 1: Resolve Session Context

Compute the current session identifier:

1. Resolve the real path of the current working directory
   (`realpath(cwd)`) — symlinks must be resolved before sanitizing.
2. Sanitize: `-` + real_cwd with `/` replaced by `-`.
3. Locate the newest JSONL file at
   `~/.claude/projects/{sanitized}/*.jsonl` ordered by mtime.
4. Extract the session_id from the filename (it's the UUID portion).

If no transcript exists (e.g., running in a non-Claude-Code context
or dry-run), set `session_id = "adhoc-" + iso8601(now)` and
continue — active journaling is valuable even outside Claude Code.

Determine the sequence number:

- List existing notes in `{project_folder}/journal/notes/` matching
  the current `{date}-{session_id_short}-*` pattern.
- `seq = count + 1` (1-indexed, zero-padded to 3 digits).

## Step 2: Validate Type and Assemble Body

Four per-type templates. The body provided by the caller (user or
agent) MUST follow the matching template. If it doesn't, the skill
should re-prompt with the expected section headers rather than
silently accept a malformed body.

### Type: `decision`

Used when choosing among alternatives; when a non-obvious
trade-off is weighed; when a choice has implications beyond the
immediate change.

```markdown
## Context
1-3 sentences. What situation prompted this decision?

## Decision
1-2 sentences. What was chosen, in imperative voice.

## Alternatives considered
Bulleted list. Each alternative + why it was rejected.

## Rationale
Why this one (causal reasoning, not just preference).

## Artifacts
- Commits: {repo}@{sha} — {subject}
- Files: {repo}/{path}[:{line}]
- Notes: {fast.io-path}
- External: {URL}

## Related
Links to earlier decisions in this session (D{N}) or prior journals
by session_id + seq. Leave "None" if no prior cross-references.

## Implications
1-3 bullets. First-order direct consequences; note second- and
third-order effects if they shaped the decision.
```

### Type: `diagnostic`

Used when a non-obvious observation changes the plan — a finding
that forces decisions elsewhere but isn't itself a decision.

```markdown
## Observation
What was observed. Concrete — include exact output, error
messages, file:line references, or metric values.

## Implication
What this finding means. What it invalidates, reveals, or forces.

## Action
What was done or deferred in response.

## Artifacts
- Commits, files, or tool outputs that captured the observation.
```

### Type: `insight`

Used for generalizable patterns or principles that transcend the
immediate session — things worth promoting to mem0 for cross-session
recall.

```markdown
## Pattern
The generalizable principle, stated as a rule or heuristic.

## Example
The concrete case that surfaced it.

## Applies when
Constraints on when the pattern holds — boundaries of the
generalization.

## Counterexamples
Cases where the pattern doesn't apply (optional but valuable when
relevant).
```

### Type: `open_thread`

Used for unresolved questions the agent surfaces but cannot close
within the current session.

```markdown
## Question
What needs to be resolved, phrased as a question.

## Attempted
What has been tried so far (if anything). Leave "None" if the
question is being parked without any attempt.

## Blocker
Why it's unresolved — missing information, external dependency,
requires human judgment, etc.

## Resumption plan
Optional. What should the next attempt look like? What does the
agent need in order to close this thread?
```

## Step 3: Write the Note to Fast.io

Slug the title: lowercase, alphanumerics and dashes only, max 40
chars, trim trailing/leading dashes.

Path: `{project_folder}/journal/notes/{YYYY-MM-DD}-{sid8}-{seq:03d}-{slug}.md`

Where `sid8` is the first 8 characters of the session_id (enough
for local disambiguation without bloating filenames).

Use `workspace/create-note` with the full body prepended by
front-matter:

```markdown
---
entry_type: note
type: {decision|diagnostic|insight|open_thread}
session_id: {full_session_id}
seq: {1-indexed number within this session}
date: {YYYY-MM-DD}
title: {the title verbatim}
distillation_source: active
fidelity: full
created_at: {ISO-8601 timestamp}
---

# {title}

{body from Step 2}
```

Apply metadata via `workspace/metadata-set`:
- `type: journal_note` (class of artifact)
- `entry_type: {decision|diagnostic|insight|open_thread}` (per-type)
- `session_id`, `seq`, `date`, `title`

## Step 4: Promote Insights to mem0 (type=insight only)

If `type == insight`:

- Prepare entry: `[{project_name}][JOURNAL-{date}] {title} — {Pattern line from body}`.
- If `mem0_available`: call `mcp__mem0-mcp__add_memory` with the
  entry. On failure, fall back to buffering.
- If not `mem0_available` OR runtime call fails: buffer to
  `{project_folder}/mem0-pending.md` via `workspace/update-note`:

```markdown
## Pending: {date} — active journal insight
- Type: insight
- Content: "[{project_name}][JOURNAL-{date}] {title} — {Pattern}"
```

Only `insight` entries auto-promote. `decision`, `diagnostic`, and
`open_thread` entries remain discoverable via semantic search over
the journal folder but are not elevated to mem0 by default — they
don't meet the "generalizable, cross-session valuable" bar that
mem0 is for.

## Step 5: Update the Journal INDEX.md

Use `workspace/update-note` on `{project_folder}/journal/INDEX.md`.
Add the note to the "Active Notes" section (creating it if
absent):

```markdown
## Active Notes
| date | session | seq | type | title | link |
|------|---------|-----|------|-------|------|
| 2026-04-23 | 7d26f67a | 001 | decision | Framing C — layered journaling paths | [notes/2026-04-23-7d26f67a-001-framing-c-layered-journaling-paths.md](notes/...) |
```

Active Notes should be ordered newest-first. Cap at ~100 visible
rows; older entries remain in the per-note files and can be
queried via `storage/search`.

Also append a one-line entry to the "Decision Quick Reference"
section (for `type=decision` and `type=insight` only — diagnostics
and open_threads don't normally warrant quick-ref cards):

```markdown
## Decision Quick Reference
- 2026-04-23 / 7d26f67a / D001 (active): Framing C — layered journaling paths → link
- ...
```

## Step 6: Update Hot Cache

Read `{project_folder}/hot.md` via `workspace/read-note`. Append
(or update) the "Recent Decisions" section to include the new
entry. This section is what `kb-assess`'s Layer 1 Context read
picks up — every active journal entry flows into future
assessments within 1 invocation.

Cap at 10 most-recent entries across both active and retrospective
sources. Remove older ones from hot.md (they remain in
journal/INDEX.md for durable lookup).

## Step 7: Append Work Log + Report

Append via `worklog/append` (with hot.md fallback if the worklog
endpoint returns 5xx, per the convention in kb-capture):

```
[{project}] Active note recorded: {type} "{title}" (seq {seq},
session {sid8}). Mem0 promotion: {applied|skipped|buffered}.
```

Brief user-facing confirmation:

```
KB Note recorded
  type:      {type}
  title:     {title}
  file:      journal/notes/{filename}
  session:   {sid8} (seq {seq})
  mem0:      {promoted|buffered|skipped (not an insight)}
```

## Coherence with kb-capture (Q3 = A — both always run)

Active notes and retrospective session summaries coexist in the
journal folder:

- Active notes: `{project_folder}/journal/notes/*.md` — one per
  decision / diagnostic / insight / open-thread, written at the
  moment the agent makes them. `distillation_source: active`,
  `fidelity: full`.
- Retrospective session summaries: `{project_folder}/journal/
  {date}-{sid}-distilled.md` — one per session, produced by
  kb-capture post-session. `distillation_source: jsonl` or
  `working_memory+jsonl`, fidelity depends on Claude Code version
  and compaction events.

When both exist for the same session, the active notes are
AUTHORITATIVE for the decisions they cover. The retrospective
summary adds narrative arc and catches decisions the agent didn't
actively journal. Readers can cross-reference via the session_id
shared in front-matter.

kb-capture (from the refresh at the start of every kb-review)
reads existing active notes for a session before writing the
retrospective summary — so it can:
1. Explicitly skip decisions already in active notes (no
   duplication in the summary's Decisions list).
2. Flag "new" decisions it inferred from the JSONL arc that
   weren't in active notes (i.e., what the agent forgot to
   journal).

## Quality Standards for Active Notes

A well-formed active note must:

- [ ] Match the per-type template (all required sections filled
      with substantive content; no placeholder text).
- [ ] Reference at least one concrete artifact in the Artifacts
      section (except for type=open_thread, where the question
      IS the artifact).
- [ ] Use imperative voice in the title (e.g., "Migrate X to Y",
      not "Migration of X to Y" or "Migrated X to Y").
- [ ] Be self-contained — a reader 6 months from now should
      understand the entry without needing to re-hydrate session
      context.

If the body provided by the caller is malformed (missing required
sections, empty body), the skill returns a validation error and
does NOT write. The caller is expected to retry with a corrected
body. Silent acceptance would degrade the journal quality floor.

## Token Discipline

- Read the manifest once, cache in skill invocation
- Skip the JSONL transcript entirely — active journaling does not
  need to parse transcripts
- Read INDEX.md only when updating (Step 5) to avoid unnecessary
  Fast.io round-trips
- Hot cache update (Step 6) is one read + one write

Per-invocation token budget: typically under 500 tokens of input
(title + body) + under 1000 tokens of work (manifest load, writes).

## Credit Awareness

- Each note = 1 `workspace/create-note` (~10–20 Fast.io credits for
  ingestion + RAG indexing)
- INDEX update = 1 `workspace/update-note` (~2–5 credits)
- Hot cache update = 1 `workspace/read-note` (free) + 1
  `workspace/update-note` (~2–5 credits)
- mem0 promotion (insights only): tiny cost on mem0's side
- worklog append: typically 1–2 credits

**Per-note cost:** ~15–30 Fast.io credits. A session with 10
actively journaled decisions costs ~200 credits — 4% of the
free-tier monthly budget. Significant but not worrying.

## Privacy Note

Active notes carry whatever the agent (or user) wrote in the body.
They are uploaded verbatim to Fast.io. This is the same privacy
posture as kb-capture's distilled notes — no redaction is applied
in v1. The `journal.redact_patterns` field in the manifest is
accepted but not enforced (future release).

## Scheduling Guidance

The agent (or user) should invoke kb-note:

- **After a decision is made, before moving on to the next work
  item.** Fresh context produces better structured entries than
  retrospective recall.
- **When diagnosing a non-obvious failure** — the observation +
  implication pair is gold for future sessions debugging similar
  failures.
- **When a generalizable pattern surfaces** — the pattern gets
  auto-promoted to mem0, where future sessions can find it.
- **When parking an unresolved question** — open_thread entries
  prevent "I'll remember this" from becoming "I forgot this."

Not after every tool call. Not after every commit. The rhythm
should match "moments a careful engineer would write down a note
for their future self."
