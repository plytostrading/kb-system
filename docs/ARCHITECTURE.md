# Knowledge Base System — Architecture

## 1. Purpose

This document defines the architecture for a persistent, literature-grounded
knowledge management system. The system is **topic-agnostic** — it works for any
project or domain, not just quantitative finance.

The system:
- discovers and absorbs published academic work, white papers, blog posts,
  YouTube videos, Twitter/X threads, and other content types
- maintains a structured, evolving knowledge base organized by project and domain
- reviews project artifacts (code, plans, decisions) against the knowledge base
  for domain correctness
- accumulates knowledge incrementally — never re-reads absorbed material
- surfaces contradictions, gaps, and deviations from published best practices
- supports multiple concurrent projects with optional cross-project knowledge sharing

## 2. Design Principles

1. **Literature-first**: Every review starts from what the published literature says,
   then assesses whether our implementation conforms. Outside-in, not inside-out.

2. **Compounding intelligence**: Each new source is woven into the existing knowledge
   mesh — cross-referenced with related sources, integrated into domain syntheses,
   and stored as semantic insights in working memory. The 50th source creates 10 notes
   woven into a mesh of 500, not 10 isolated notes.

3. **Link density over note count**: The value of the knowledge base is proportional
   to its cross-reference density. Orphan sources with zero connections are a quality
   defect, not a contribution.

4. **Contradiction preservation**: When sources disagree, both claims are preserved
   with full provenance. The system never silently overwrites — contradictions are
   decision points that surface to the user.

5. **Provenance chains**: Every claim in a domain synthesis traces back to a specific
   source. Not "the literature recommends..." but "[LW2004] recommends linear shrinkage
   for p < n; [LW2012] extends this to nonlinear for p/n > 1."

6. **Token discipline**: The review engine follows a strict read budget per domain
   (<8,000 tokens). Hot cache first, then mem0, then domain synthesis, then specific
   sources only if needed, then project artifacts.

7. **Credit awareness**: Fast.io's free tier provides 5,000 monthly credits. Skills
   prefer direct note reads (`workspace/read-note`) over RAG queries (`ai/chat-create`)
   when the target note is known. RAG is reserved for cross-document synthesis where
   the relevant sources are not known in advance.

8. **Topic agnosticism**: Skills are generic engines; all project-specific knowledge
   (domains, search queries, code paths, checklists) lives in project manifests.
   Adding a new project is a file creation, not a skill change.

9. **Source-type extensibility**: The source adapter pattern separates discovery
   (finding content) from extraction (reading content). New source types are added
   by declaring an adapter in the manifest — no skill code changes needed.

10. **Graceful degradation**: The system works with zero external API credentials
    (web search fallback for everything). Each API/MCP connection added improves
    quality: richer metadata, structured search, full content extraction.

## 3. Persistence Stack

### 3.1 Fast.io — The Library (cloud document storage with built-in AI)

Fast.io is the cloud source of truth for all knowledge base content. It is an
agent-first workspace platform backed by MediaFire infrastructure.

**Why Fast.io:**
- 19 consolidated MCP tools with action-based routing (~200+ actions total)
- Native markdown notes — first-class `.md` note type created/read/updated via
  dedicated API (`workspace/create-note`, `workspace/read-note`, `workspace/update-note`)
- Notes are auto-indexed for RAG when workspace intelligence is enabled
- Built-in RAG chat (`ai/chat-create` with `folders_scope`) — scoped to any folder
  depth, no separate Hub management
- Semantic search built into `storage/search` — search by meaning, not just keyword
- 17 metadata-specific actions including AI-powered extraction and stale detection
- Native task management, work logs, and approval workflows
- File and note versioning with version restore
- 50 GB storage, 5,000 monthly credits on free agent plan
- CLI tool (`fastio`) with local MCP server mode (`fastio mcp`)
- MCP endpoints: Streamable HTTP at `https://mcp.fast.io/mcp`,
  legacy SSE at `https://mcp.fast.io/sse`

**Workspace structure:**

Workspace name: `shared-kb` (intelligence: **enabled**)

```
shared-kb/                                  # Fast.io workspace (intelligence ON)
├── manifests/                              # Synced project manifest copies
│   └── quant-weak-signal.yaml              # Cloud copy of project manifest
├── quant-weak-signal/                      # Project folder
│   ├── hot.md                              # Note: session context (~500 words)
│   ├── INDEX.md                            # Note: master source index
│   ├── sources/                            # Folder
│   │   ├── LW2004-shrinkage-estimator.md   # Note: source summary
│   │   ├── LW2012-nonlinear-shrinkage.md
│   │   ├── dP2018-ch12-cpcv.md
│   │   └── ...
│   ├── domains/                            # Folder
│   │   ├── covariance-estimation.md        # Note: domain synthesis
│   │   ├── signal-construction.md
│   │   └── ...
│   └── assessments/                        # Folder
│       ├── 2026-04-12-initial-review.md    # Note: dated assessment
│       └── ...
└── {future-project}/                       # Another project folder
    ├── hot.md
    ├── INDEX.md
    ├── sources/
    ├── domains/
    └── assessments/
```

Each project gets its own folder tree. This provides natural isolation for
`folders_scope` in RAG queries.

**Workspace topology: isolated-first, opt-in sharing.**

All skills scope to the current project folder by default. Cross-project
knowledge sharing requires an explicit `--cross-project` flag.

| Operation | Default (isolated) | With `--cross-project` |
|-----------|-------------------|----------------------|
| Fast.io `storage/search` | `folders_scope: "{project_folder}"` | `folders_scope: "/"` (workspace root) |
| Fast.io `ai/chat-create` | `folders_scope: "{project_folder}"` | `folders_scope: "/"` |
| mem0 query | Include `[{project_name}]` tag in query | Omit project tag — search all |
| mem0 store | Always tag with `[{project_name}]` | Always tag (never store untagged) |

This means:
- Working within a project: clean signal, no noise from unrelated projects
- Explicit cross-project scan: `--cross-project` surfaces relevant findings
  from other projects that may share domains or concepts
- mem0 entries are always tagged on write (even during cross-project queries)
  so they can be scoped later

**Domain scoping for RAG queries:**

RAG queries use `folders_scope` to target a specific project or domain:

```
# Project-scoped (default):
ai/chat-create:
  type: chat_with_files
  folders_scope: "<project-sources-folder-id>:1"
  query_text: "What assumptions do sources make about input data centering?"

# Cross-project (with --cross-project):
ai/chat-create:
  type: chat_with_files
  folders_scope: "<workspace-root-id>:1"
  query_text: "What assumptions do sources make about input data centering?"
```

Domains are folders. Restructuring domains later (splitting, merging) requires
only moving notes between folders.

**Activity logging:**

The changelog is implemented via Fast.io's native work log (`worklog/append`),
an append-only chronological record. Each sub-skill appends an entry on completion.
The work log is queryable via `worklog/list` and supports AI summaries via
`event/summarize`.

**Metadata template** (applied to source notes via `workspace/metadata-template-create`):

| Field           | Type   | Example                                      |
|-----------------|--------|----------------------------------------------|
| source_id       | string | LW2004                                       |
| title           | string | A well-conditioned estimator...              |
| authors         | string | Ledoit, Wolf                                 |
| year            | number | 2004                                         |
| type            | enum   | paper/preprint/white_paper/blog/book_chapter/youtube/twitter |
| domain          | string | covariance-estimation                        |
| project         | string | quant-weak-signal                            |
| date_absorbed   | date   | 2026-04-12                                   |
| status          | enum   | absorbed/pending/superseded/low_relevance    |
| cross_refs      | string | LW2012, DeMiguel2009                         |
| content_url     | string | https://doi.org/...                          |

Metadata can be set manually (`workspace/metadata-set`) or auto-extracted from
note content (`workspace/metadata-extract`). Fast.io's stale metadata detection
automatically re-extracts when template definitions change.

### 3.2 mem0 — The Researcher's Notebook (semantic working memory)

mem0 stores extracted insights, decisions, cross-cutting conclusions, and working
knowledge drawn FROM the literature.

**What mem0 stores:**
- Insights: "LW2004 assumes mean-zero data; our z-scoring satisfies this assumption"
- Decisions: "We chose lambda=0.9 fallback based on James-Stein high-shrinkage literature"
- Cross-references: "Three sources (LW2004, Chen2010, Schafer2005) agree that p/n < 1
  is the safe regime for linear shrinkage; our p=171, n~300 per cell is in this regime"
- Contradictions: "LW2004 recommends linear shrinkage but LW2012 shows nonlinear is
  superior — need to assess our p/n ratio to determine which applies"
- Review conclusions: "2026-04-12 review found lambda=0.9 justified but 30-sample
  threshold lacks published support"

**Project scoping (isolated-first):**

All mem0 entries are tagged with the project name on write. Queries include the
project tag by default — cross-project queries omit the tag.

```
# Writing (always tagged):
"[quant-weak-signal] LW2004 assumes mean-zero data; our z-scoring satisfies this."

# Querying (project-scoped, default):
query: "[quant-weak-signal] covariance estimation assumptions"

# Querying (cross-project, with --cross-project flag):
query: "covariance estimation assumptions"   # no project tag → searches all
```

This ensures project isolation by default while allowing intentional
cross-pollination. An insight stored for project A only surfaces in project B
when you explicitly ask for it.

**What mem0 does NOT store:**
- Full source summaries (those live in Fast.io)
- Domain syntheses (those live in Fast.io)
- File content of any kind (Fast.io is the document store)

**The division:**
- Fast.io = the library (auditable, navigable, version-controlled, AI-queryable)
- mem0 = the researcher's notebook (fast recall, semantic search, cross-cutting insights)
- Read the library to learn; consult the notebook to remember what you learned

**mem0 connection — API-key HTTP MCP is the default:**

There are two ways to connect mem0 to Claude Code. **The recommended path
is the official API-key HTTP MCP** (`https://mcp.mem0.ai/mcp`,
documented at `https://docs.mem0.ai/platform/mem0-mcp`). It exposes nine
data tools and has no `authenticate` tool at all — there is no OAuth
lockout surface. Install it via:

```
npx mcp-add --name mem0-mcp --type http --url "https://mcp.mem0.ai/mcp" --clients "claude code"
```

…and provide an API key from the mem0 Dashboard. This is the path every
new install should use.

The **alternative path is an OAuth-based connector** (e.g. a Claude.ai
Connector that wraps mem0). It exposes `authenticate` and
`complete_authentication` tools and uses rate-limited auth attempts.
Repeated auth calls against this connector cause account lockouts that
take days to clear. Skills **never** call `authenticate` or
`complete_authentication` under any circumstances — authentication is
a user-initiated action only.

**Zero-cost availability check (no auth attempts):**

Each skill checks whether mem0 **data tools** are present in the tool
registry — a local lookup with zero network traffic and zero auth
attempts:

- **Any data tool present** (e.g. `mcp__mem0-mcp__add_memory`,
  `mcp__mem0-mcp__search_memories`) → mem0 is usable. Use normally.
- **Only `authenticate`/`complete_authentication` present** → the user
  has the OAuth connector and has not completed OAuth. Skip all mem0
  usage silently and buffer writes. The recommended resolution is to
  switch to the API-key HTTP MCP above, which eliminates the lockout
  surface mechanically.
- **No mem0 tools at all** → mem0 is not installed. Skip silently.

If mem0 is usable but a data call fails at runtime (timeout, rate limit),
the skill sets `mem0_available = false` for the rest of that run and
buffers remaining writes. No cooldown files or cross-skill propagation
needed — each skill independently checks the tool registry.

**Write-through buffer:**

When mem0 is not available (not authenticated, or runtime failure), write
operations are buffered to `{project_folder}/mem0-pending.md` in Fast.io
via `workspace/update-note`. Each pending entry has this format:

```markdown
## Pending: {date} — {source_id or context}
- Type: {insight|contradiction|finding}
- Content: "[{project_name}] {the mem0 entry text}"
```

The pending queue is flushed **automatically** by `kb-refresh` whenever
mem0 data tools are available. Since kb-refresh runs as the first step of
every `kb-review` orchestration, this means: the moment you install the
API-key HTTP MCP (or otherwise expose mem0 data tools), the very next
review cycle drains the queue with no manual action.

The flush can also be triggered in isolation via `kb-refresh --flush-mem0`.

Flush behavior:
1. Checks mem0 data tool availability (zero-cost registry check)
2. If no data tools present → skips silently (Category 9 lint reports the count)
3. If data tools present → reads `mem0-pending.md`, flushes all entries, clears queue
4. If a call fails mid-flush → stops, reports partial progress

This ensures **zero data loss and eventual delivery** — insights are
captured in Fast.io immediately and promoted to mem0 automatically as
soon as data tools are present in the registry.

### 3.3 Obsidian — Local Viewing Layer (optional)

Obsidian can open a local export of the Fast.io workspace as a vault for graph view,
backlinks, and tag navigation. This is a read-only convenience layer — the source
of truth is always Fast.io.

Use `fastio` CLI or the `download` MCP tool to export notes to a local directory.
This is not required for the system to function.

### 3.4 Session Journaling — Durable Chain-of-Thought

**Why this exists.** kb-* skills produce artifacts (notes, syntheses,
assessments) and mem0 captures high-level insights, but the actual
reasoning — decision alternatives, diagnostic findings, revisions, dead
ends — lives in the session transcripts Claude Code keeps locally and
aged-out of the agent's context. That chain-of-thought is the single
richest record of why choices were made. Without persistence, it
evaporates as soon as the session compacts or the transcript is
trimmed. Session journaling promotes this record from ephemeral local
state to project-scoped KB memory.

**What gets captured.** Claude Code writes per-project session
transcripts to `~/.claude/projects/{sanitized-cwd}/{session_id}.jsonl`.
Each line is a JSON event. Assistant messages have content blocks of
type `text`, `tool_use`, and (when extended thinking is enabled)
`thinking`. The thinking blocks once contained the agent's internal
reasoning — diagnosis, decision deliberation, self-correction, plan
revision — and were the primary raw material the `kb-capture` skill
consumed.

**Environmental caveat — Claude Code 2.1.116+ redacts thinking at
write-time.** As of Claude Code ≈2.1.116 (April 2026, changed
silently — not in any changelog entry), every `thinking` content
block written to the JSONL is stripped to empty string, leaving only
the `signature` field (500–32K-byte Anthropic-encrypted protobuf for
server-side session-resume forward-chaining). Signatures are opaque
and not client-decodable; `--debug api --debug-file` operates at a
layer below the redaction and does not recover pre-redaction content
(empirically verified). This silently degrades retrospective
distillation quality for any session run under post-2.1.116 Claude
Code.

Operationally:

- **Reflexive distillation** (kb-capture invoked from within the
  session being captured) is UNAFFECTED — it uses the agent's own
  working memory, which never touches the redaction path. Remains
  the highest-fidelity mode.
- **Retrospective distillation** of pre-2.1.116 sessions is
  UNAFFECTED — those JSONLs have cleartext thinking.
- **Retrospective distillation** of post-2.1.116 sessions is
  DEGRADED — only user turns, assistant text, tool calls, and tool
  results survive; thinking is gone.

**Recovery path for post-2.1.116 retrospective distillation:**
terminal capture at launch. `script(1)` or `asciinema` preserves
what appears on the terminal; when Claude Code runs in verbose mode
(Ctrl+O), thinking IS rendered to the terminal and therefore
captured. A future kb-capture version will consume terminal-capture
files as an additional distillation source; v1 reads only JSONL.
Recommended launch wrapper (put in shell rc):

```
alias claude='script -q -f -c claude ~/.claude-captures/$(date +%F-%H%M%S).typescript'
```

Journaling skill behavior when encountering redacted sessions: tag
`fidelity: degraded` on the distilled note's front-matter; surface
the redaction explicitly in the Session Metadata Notes section so
future readers understand why the decision count is lower than the
live session produced.

**How it's stored.** `kb-capture` produces two artifact classes per
session:

1. **Distilled journal note** — `{project_folder}/journal/{date}-
   {session_id}-distilled.md`. Structured markdown with front-matter
   metadata (session_id, outcome, projects_touched, prompt_version_hash,
   counts), a session summary, enumerated Decisions (each with
   Context / Decision / Alternatives / Rationale / Artifacts), a
   Diagnostics section for non-obvious findings, an Insights section
   for generalizable patterns, an Artifacts Touched list, and Open
   Threads. Auto-indexed for RAG — future semantic searches surface
   relevant decisions alongside sources and syntheses.
2. **Raw dump (optional, gated by --raw)** —
   `{project_folder}/journal/raw/{date}-{session_id}-raw.md`. Verbatim
   capture of thinking blocks + tool calls + messages. Not indexed for
   RAG. Forensic / audit use only. Cost-gated because raw transcripts
   can be 30–50KB per session and Fast.io RAG ingestion is ~10
   credits/page.

**Bookmark and deduplication.** A bookmark at
`{project_folder}/journal/.bookmark.yaml` tracks captured session IDs
and the last-captured timestamp. `kb-capture` compares the transcript
directory against the bookmark AND against the journal INDEX (defense
in depth) before distilling, so re-running the skill is idempotent and
safe after bookmark loss.

**Integration with the rest of the KB.**

- **Hot cache** — `kb-capture` writes a "Recent decisions" section to
  `{project}/hot.md`. `kb-assess` already reads hot.md as Layer 1
  Context, so recent decisions become part of every assessment without
  consuming additional token budget.
- **mem0** — `kb-capture` promotes 2–3 highest-signal Insights per
  capture to mem0 (tagged `[{project}][JOURNAL-{date}]`). If mem0 is
  unavailable, buffered to `mem0-pending.md` like any other write.
- **Staleness lint** — Category 10 in `kb-refresh` flags uncaptured
  sessions. Severity escalates with count (Info → Warning → Error at
  ≥10 uncaptured sessions).

**Privacy / data egress.** Thinking tokens can contain sensitive
material (strategy hypotheses, credential-adjacent paths, debugging
traces). `kb-capture` surfaces a privacy notice on first-ever capture
and requires explicit confirmation. The manifest supports a
`journal.redact_patterns` field (regex list) but enforcement is
deferred to a future release — in v1, the manifest accepts the field
and the skill warns if non-empty.

**Prompt version hash.** The distillation prompt is a quality
determinant of the journal entry — changes to it alter output fidelity
over time. Each distilled note includes the sha256 hash of the
distillation prompt in front-matter, so "what prompt produced this
entry" is always queryable. When the prompt changes, the bookmark
records the transition and the skill surfaces a prompt-drift event.

**Outcome tagging.** `kb-capture --outcome {success|partial|failed}`
marks captured sessions. Downstream skills can (in future versions)
weight journal context by outcome — a `failed` session's reasoning
should not be treated as authoritative design knowledge. In v1 the
tag is recorded but not consumed.

**What this does NOT solve.** Journaling does not redact, does not
compress older entries automatically, and does not fetch context from
third-party tools (e.g. your IDE's local chat history). It reads
Claude Code's own transcripts and nothing else. See `kb-capture.md`
for the complete behavior spec.

### 3.5 Active Journaling via kb-note — Vendor-Independent Capture

**Why this exists.** §3.4's retrospective distillation depends on
Claude Code writing thinking content to its JSONL. When Claude Code
2.1.116+ silently redacted that content (2026-04-23 decisions log
entry), retrospective distillation for affected sessions lost its
richest input. Active journaling is the resilient alternative:
instead of reconstructing reasoning from transcripts after the fact,
agents (and users) record decisions AS they're made, writing
directly to Fast.io through our own skill surface — no dependency
on any vendor's internal representation.

**Layered design (the "Framing C" architectural choice,
2026-04-23):** kb-system now has THREE capture paths, each
reinforcing the others:

1. **Active journaling** (`kb-note` — primary path for decisions
   made under post-2.1.116 Claude Code). Agents invoke kb-note
   during sessions via the Skill tool; users can invoke via
   `/kb-note --project X --type decision ...`. Entries are written
   immediately to `{project_folder}/journal/notes/` as individual
   markdown files with structured front-matter. `fidelity: full`
   is guaranteed because the agent's in-context reasoning is the
   source.
2. **Retrospective distillation** (`kb-capture` — unchanged;
   catches what active journaling missed). Runs end-of-session or
   during the next `/kb-review`. Reads JSONL + any terminal
   captures + existing active notes for the same session. Writes a
   session-summary note that adds narrative arc and flags
   decisions inferred from tool calls but not actively journaled.
   Fidelity depends on Claude Code version and whether terminal
   capture was used.
3. **Terminal capture** (forensic fallback). `script(1)`,
   `asciinema`, or `tmux pipe-pane` wraps the claude CLI at
   launch. Captures what renders on the terminal, which — when
   verbose mode is on — includes thinking. v1 kb-capture reads
   JSONL only; a future version will consume terminal captures as
   an additional source.

No single capture path can fail silently: if the vendor changes
JSONL format again, active notes survive. If the agent forgets to
invoke kb-note, retrospective distillation catches up. If both
fail (future vendor change + agent discipline collapse), terminal
capture is the forensic last resort.

**Entry types in active notes.** Four type values with distinct
templates:

- `decision` — choice among alternatives, weighed trade-offs
- `diagnostic` — non-obvious observation that forces decisions
  elsewhere
- `insight` — generalizable pattern or principle (auto-promoted
  to mem0)
- `open_thread` — unresolved question parked for future resumption

Templates are codified in the `kb-note` skill body so the agent
produces structurally consistent entries without per-invocation
schema lookup.

**Storage structure.** Active notes live at one file per decision:
`{project_folder}/journal/notes/{YYYY-MM-DD}-{session_id8}-{seq:03d}-{slug}.md`.
This coexists with retrospective session summaries at
`{project_folder}/journal/{YYYY-MM-DD}-{session_id}-distilled.md`.
INDEX.md links both in a unified view; the `distillation_source`
front-matter field (`active` vs `jsonl` vs `working_memory+jsonl`)
lets readers filter by provenance.

**mem0 promotion policy.** Only `insight` entries auto-promote to
mem0 on write, tagged `[{project_name}][JOURNAL-{date}]`. The
other three types stay local to Fast.io — they're discoverable via
semantic search but don't elevate to the project-wide recall layer.
Rationale: mem0 is for cross-session, cross-domain pattern-matching;
specific decisions and diagnostics don't meet that bar.

**Coherence with kb-capture (Q3 = both always run):** when both
paths execute for the same session, active notes are AUTHORITATIVE
for the decisions they cover, and retrospective distillation adds
the narrative arc + catches missed decisions. The two are never in
conflict over the same decision because the distillation prompt is
kb-capture-side aware of existing active notes and deliberately
doesn't re-emit them.

**What active journaling requires that retrospective doesn't.**
Agent discipline. Without a CLAUDE.md instruction or project
convention that tells agents to invoke kb-note during work, active
journaling degenerates to "happens when the user remembers." To
keep the active path effective, project CLAUDE.md files should
include something like:

```
When making a non-trivial decision during work on this project,
invoke `/kb-note --project {name} --type decision --title "..."`
with the decision details. Non-trivial means: choosing among
≥2 considered alternatives, reversing a prior choice, or any
decision with implications beyond the immediate change.
```

The kb-note skill body documents the invocation criteria in more
detail; CLAUDE.md just points at it.

**Future extensions** (not in v1):

- MCP tool variant (`mcp__kb__record_decision`) for strict
  schema enforcement at call time, rather than prompt-level
  enforcement. Would require building a small MCP server; v1
  uses skill-level enforcement which catches ~95% of cases at
  ~20% of the build cost.
- Terminal-capture reader in kb-capture, so `.typescript` /
  `.cast` files are consumed as supplementary source.
- Weighted-trust retrieval in kb-assess, using `distillation_source`
  + `fidelity` + `outcome` to filter or boost journal context.

### 3.6 YouTube Channel Model & Video-Driven Discovery

**Why this exists.** The earlier YouTube integration was per-video
transactional: discover, absorb, write a source note. Channels
existed only as plain strings in the manifest's `seed_channels`
list. This meant you couldn't query "what channels does the KB
know about?", couldn't accumulate per-channel metadata
(productivity, quality signal, topics), and couldn't expand the
corpus using the graph structure of YouTube (same-creator recent
uploads, related videos). Section 3.6 lifts channels to a
first-class artifact class and adds a channel-scoped discovery
round.

**Artifact layout:**

```
{project}/
  channels/
    INDEX.md                       # roster (active + deprecated)
    {handle-slug}.md               # one file per channel
  sources/
    {source_id}-{slug}.md          # existing per-video notes,
                                    #   with `parent_channel` front-matter
```

**Channel artifact schema.** Front-matter captures
`channel_id` (YouTube's UC-prefixed internal ID), `handle`,
`title`, `subscribers`, `total_uploads`, `topics`,
`relevant_domains`, `videos_in_kb`, `videos_pending`,
`videos_rejected`, `first_seen`, `last_seen`, `last_scan`,
`status` (seed | discovered | deprecated), `quality_signal`
(high | medium | low), `scan_interval_days`. Body has
Description, Why this channel, Videos in KB (growing list),
Videos rejected (quality-threshold rejections), Related channels.

**Two status classes.** `seed` channels come from the manifest's
`seed_channels` list — explicitly trusted, curated by the user.
`discovered` channels are created automatically by `kb-absorb`
when a video's parent channel isn't yet in the KB. Over time,
users can promote productive discovered channels to seed status
by editing the front-matter. `deprecated` suppresses channel-
scoped expansion without deleting the artifact — preserves the
historical record of videos that came from the channel.

**Differentiated quality thresholds.** Channel-scoped discovery
applies three thresholds depending on the provenance of the
candidate (manifest `channel_discovery.seed_threshold`,
`discovered_threshold`, `related_threshold`):

| Provenance | Default threshold | Rationale |
|------------|-------------------|-----------|
| Seed-channel recent upload | 2 (lenient) | Channel is already trusted by user |
| Discovered-channel upload | 3 (default) | Productivity not yet proven |
| Related video (via tag search) | 4 (strict) | Adjacent not directly sought |

**kb-absorb responsibility (channel artifact maintenance).**
When absorbing a YouTube source, the skill resolves the parent
channel via `mcp__youtube-api__getVideoDetails` (1 quota unit).
If the channel artifact doesn't exist → create it with
`status: discovered`. If it does → increment `videos_in_kb`,
update `last_seen`, append to "Videos in KB" list. The video
source note's front-matter gains `parent_channel:
channel-{handle-slug}` for bidirectional linkage. Channel
artifacts are NOT auto-promoted to mem0 (they're local sources,
not cross-project insights).

**kb-discover responsibility (Round 2.5 channel-scoped
expansion).** After Round 2's query-driven gap-fill, if the
YouTube API MCP has the full 8 tools registered AND the manifest
has `channel_discovery.enabled: true`:

- **Sub-Round A — Recent uploads from known channels.** For each
  seed and discovered channel whose `last_scan + scan_interval_days`
  is in the past, call
  `searchVideos({channelId, order: "date", maxResults: 10})`.
  100 quota units per channel. Dedup + threshold per
  provenance. Update `last_scan` regardless of yield.
- **Sub-Round B — Tag-matched "related" videos.** YouTube Data
  API's `relatedToVideoId` was deprecated 2023. Approximation:
  for each recently-absorbed YouTube source (capped at
  `max_expansions_per_review`), pull the video's tags via
  `getVideoDetails(includeTags: true)`, construct a compact
  query from 3-5 highest-signal tags, and run `searchVideos(
  order: "relevance", recency: "pastYear")`. 101 quota units per
  expansion. Apply the strict `related_threshold`.

**kb-refresh responsibility (Categories 11 + 12).**
- Category 11 flags channels with stale `last_scan`
  (severity scales with count).
- Category 12 flags low-productivity channels (in KB > 90 days
  with `videos_in_kb == 0`) — a curation signal; Info severity.

**Quota economics.** A kb-review cycle with 10 scheduled
channel scans + 20 related-video expansions consumes
`10 * 100 + 20 * 101 = 3020 quota units`, ~30% of the 10,000/day
free tier. `scan_interval_days` (default 14) and
`max_expansions_per_review` (default 20) are the primary cost
controls. Tuning these is the recommended first response to
quota pressure.

**What this doesn't yet include** (future work, not in this
version):
- Playlist artifacts. YouTube playlists have coherent
  topical structure (e.g., a conference's talks) that channels
  don't. The `@kirbah/mcp-youtube` package doesn't expose
  playlist tools; would require either switching MCPs or
  building a playlist reader ourselves.
- Creator graph (who interviews whom, co-occurrence edges
  across channels). Could be inferred post-hoc from absorbed
  content but needs a dedicated analysis pass.
- Channel topic auto-inference. `getChannelStatistics`
  doesn't return topic IDs; would need transcript- or
  tag-clustering pass. Punted; users fill `topics` manually
  for now.

## 4. Project Manifests

All project-specific knowledge lives in **project manifest** files — YAML
configurations that define domains, search queries, source adapters, code paths,
review checklists, and cross-project relationships.

**Authoritative copy:** `.claude/kb-projects/{project-name}.yaml` (git-versioned)
**Cloud copy:** Fast.io `manifests/{project-name}.yaml`

### 4.1 Manifest Sync Verification

Both copies include `manifest_version` (integer) and `content_hash` (SHA-256 of
content excluding the hash field itself). The `kb-review` meta-skill verifies
sync on every invocation:

```
1. Read local manifest from .claude/kb-projects/{project}.yaml
2. Read cloud manifest via workspace/read-note on manifests/{project}.yaml
3. Compare content_hash values
4. If match → proceed
5. If mismatch →
   a. Compare manifest_version — higher version is likely authoritative
   b. Show diff summary to user
   c. Ask: "Local is v3, cloud is v2. Push local to cloud? (y/n)"
   d. On confirmation, sync via workspace/update-note
   e. Update content_hash in both copies
```

The hash is auto-computed by the meta-skill. When editing manifests manually,
leave `content_hash` empty — the skill will compute and fill it on next run.

### 4.2 Manifest Schema

See `templates/manifest-template.yaml` in this repo for the schema, or any consuming project's `.claude/kb-projects/` for live examples. Key sections:

```yaml
project:
  name: string                    # Unique project identifier
  description: string             # What this project reviews
  workspace: string               # Fast.io workspace name
  project_folder: string          # Folder within workspace
  assessment_mode: enum           # code_vs_literature | knowledge_synthesis
                                  # | decision_audit | plan_review

domains:                          # List of knowledge domains
  - name: string                  # Domain identifier (kebab-case)
    description: string
    search_queries: [string]      # Starting search queries for discovery
    code_paths: [string]          # Optional — code files to review (for code_vs_literature)
    review_checklist: [string]    # Optional — domain-specific review questions
    foundational_sources: [string] # Key references to seed the KB

source_adapters:                  # How to discover and extract each content type
  {type_name}:
    discovery:
      preferred: string           # MCP tool or method name
      fallback: string            # Fallback method
    pre_processing:               # Optional — semantic enrichment before extraction
      preferred: string           # MCP tool (e.g., notebooklm_mcp)
      fallback: string            # "skip" = no pre-processing
    extraction:
      preferred: string
      fallback: string            # Optional
    credentials: {key: value}     # Required credentials (env: references)
    quality_threshold: int        # Minimum relevance score (default: 3)
    seed_channels: [string]       # Optional — seed accounts/channels for discovery
    seed_accounts: [string]       # Optional — seed Twitter/X accounts

cross_project_links:              # Optional relationships to other projects
  - project: string
    shared_domains: [string]

staleness:                        # Tunable thresholds
  stale_days: int                 # Default: 30
  aging_days: int                 # Default: 7
  unreviewed_days: int            # Default: 30
```

### 4.3 Assessment Modes

The manifest's `assessment_mode` determines how the assessment skill operates:

| Mode | What It Assesses | Artifacts Reviewed |
|------|------------------|--------------------|
| `code_vs_literature` | Pipeline code against literature consensus | Source code files from `code_paths` |
| `knowledge_synthesis` | Current understanding of a topic | No code — pure KB synthesis report |
| `decision_audit` | Past decisions against domain knowledge | Design docs, ADRs, decision records |
| `plan_review` | Project plans against literature | Planning docs, roadmaps |

## 5. Source Adapter Registry

The source adapter pattern separates **discovery** (finding content) from
**extraction** (reading content for absorption). Each source type declares
a preferred MCP/API path and a fallback web-search path.

### 5.1 Built-In Adapters

| Source Type | Discovery (preferred) | Discovery (fallback) | Pre-Processing (optional) | Extraction (preferred) | Extraction (fallback) |
|-------------|----------------------|---------------------|--------------------------|----------------------|----------------------|
| `paper` | Scholar Gateway MCP | WebSearch | — | WebFetch (DOI/URL) | WebFetch |
| `preprint` | Scholar Gateway MCP | WebSearch | — | WebFetch | WebFetch |
| `white_paper` | WebSearch | — | — | WebFetch | — |
| `blog` | WebSearch | — | — | WebFetch | — |
| `book_chapter` | WebSearch | — | — | WebFetch | — |
| `youtube` | YouTube API MCP | WebSearch `site:youtube.com` | NotebookLM (batch, queries) | YouTube Transcript MCP | WebFetch (partial) |
| `twitter` | Twitter MCP (`search_tweets`) | WebSearch `site:x.com` | — | Twitter MCP (`get_tweet_thread`) | WebFetch (partial) |

### 5.2 Adapter Resolution at Runtime

Skills check MCP tool availability at invocation time for each phase:

```
For each source_type in manifest.source_adapters:
  For each phase in [discovery, pre_processing, extraction]:
    1. If phase not defined for this source type → skip phase
    2. Check if preferred MCP tool is callable (test with a no-op or lightweight call)
    3. If available → use preferred path
    4. If not available AND fallback == "skip" → skip this phase entirely
    5. If not available AND fallback exists → warn user, use fallback
    6. If not available AND no fallback → error (unless phase is optional)
    7. Log which path was used in work log
```

The three phases are:
- **Discovery:** Finding content (required — always has a fallback)
- **Pre-processing:** Optional semantic enrichment (currently: NotebookLM for YouTube)
- **Extraction:** Reading raw content for absorption (required)

This means the system **degrades gracefully** — it works with zero MCP credentials
(web search only), gets better with each API connected, and the user can add
credentials incrementally. Pre-processing phases are always optional; their
`fallback: skip` means the pipeline simply omits that enrichment step.

### 5.3 YouTube Adapter Details

The YouTube adapter has a three-phase pipeline: discovery → pre-processing
(optional) → extraction. The pre-processing phase is the NotebookLM enrichment
step — when available, it provides citation-backed semantic analysis that raw
transcript extraction cannot.

```
Discovery                Pre-Processing (optional)       Extraction
┌──────────────┐        ┌───────────────────────┐       ┌─────────────────┐
│ YouTube API  │───────▶│ NotebookLM            │──────▶│ Transcript MCP  │
│ (or WebSearch│        │ - Batch-add videos    │       │ (raw transcript │
│  fallback)   │        │ - Structured queries  │       │  + timestamps)  │
└──────────────┘        │ - Citation-backed     │       └─────────────────┘
                        │   claims extraction   │              │
                        │ fallback: skip ───────┼──────────────┘
                        └───────────────────────┘
```

**Discovery via YouTube API MCP** (ZubeidHendricks/youtube-mcp-server):
- Programmatic search with metadata filtering (channel, upload date, view count)
- 10,000 daily API quota units; search costs 100 units (~100 searches/day)
- Requires `YOUTUBE_API_KEY` environment variable

**Pre-Processing via NotebookLM** (optional enrichment):

NotebookLM provides semantic analysis of YouTube content that goes beyond raw
transcript extraction. Instead of getting a flat text dump and manually
identifying claims, NotebookLM:

- Accepts YouTube URLs directly — no transcript pre-extraction needed
- Produces **source-grounded answers** (citations pinned to specific videos
  and timestamps, never from training data)
- Enables **cross-source synthesis** when multiple videos are in the same
  notebook (e.g., "Where do these three talks on covariance estimation agree
  and disagree?")
- Generates structured outputs: claims, assumptions, agreements, disagreements,
  gaps — all with source citations

**Notebook topology:** One notebook per `{project}-{domain}`. Notebooks
persist across absorption cycles, accumulating cross-source context. As more
videos are added to a domain notebook, the cross-source synthesis becomes
richer.

**When NotebookLM adds value vs. when to skip:**

| Scenario | NotebookLM Value | Recommendation |
|----------|-----------------|----------------|
| Long-form talks (>15 min) | High — dense claims, complex arguments | Use |
| Multi-video domain batch | High — cross-source synthesis | Use |
| Technical presentations | High — precise claims need grounding | Use |
| Short clips (<5 min) | Low — insufficient content for semantic analysis | Skip |
| Visual-heavy content (code demos) | Low — meaning is in visuals, not speech | Skip |
| Single video, simple topic | Low — transcript extraction is sufficient | Skip |

**Access paths:**

1. **Community MCP server** (`notebooklm-mcp-ultimate`, kabuto-png/notebooklm-mcp-ultimate on GitHub):
   ~44 tools including `create_notebook_remote`, `add_youtube_source`,
   `add_url_source`, `add_text_source`, `ask_question`, `list_sources`,
   `summarize_source`, and several research-assistance tools
   (`discover_sources`, `research_topic`). Uses Playwright browser
   automation for authentication — a real Chrome window opens for
   Google login (MFA intact); session state is persisted locally. No
   manual cookie export needed for interactive use. For headless /
   server use, `GOOGLE_AUTH_COOKIES_PATH` points to a pre-exported
   Playwright storageState JSON file.

   Rate limit: NotebookLM's free tier allows ~50 queries/day per account.
   `re_auth` lets you switch accounts when hitting the limit.

   Previous recommendation (PleasePrompto/notebooklm-mcp v1.2.1, 16
   tools) was read-only — no programmatic source addition — so
   `add_youtube_source` from kb-absorb's design would not work against
   it. kabuto-png/notebooklm-mcp-ultimate supersedes it for
   pre-processing flows that need to add sources programmatically.

2. **Official Enterprise API**: `notebooks.sources.batchCreate` supports YouTube
   URLs via `videoContent.youtubeUrl`. OAuth via gcloud. Requires Enterprise
   tier. Better for automation and team use.

**Fallback:** When NotebookLM is unavailable (`fallback: skip`), the pipeline
skips pre-processing entirely and proceeds to direct transcript extraction.
The system degrades to the standard transcript-based absorption flow — still
functional, but without cross-source synthesis or citation-backed claims.

**Extraction via YouTube Transcript MCP** (`@kimtaeyoon83/mcp-server-youtube-transcript`):
- Uses public YouTube caption endpoints — no API key needed
- `get_transcript` tool with options: url, lang, include_timestamps, strip_ads
- Set `include_timestamps=true` so kb-absorb's "Key Claims with timestamps"
  template works correctly
- `strip_ads=true` (default) filters out sponsorship/promo content by
  chapter markers
- Always runs, even with NotebookLM — raw transcript is the permanent snapshot

**Source note format for YouTube (with NotebookLM enrichment):**
```markdown
# {Video Title}

**ID:** {source_id}
**Channel:** {channel_name}
**Upload Date:** {date}
**Type:** youtube
**Domain:** {domain}
**URL:** {youtube_url}
**Date Absorbed:** {date}
**Duration:** {HH:MM:SS}
**NotebookLM:** {yes|no — whether enrichment was applied}

## NotebookLM Extraction
### Claims (citation-backed)
1. {Claim} — [Source: {video_title}, {timestamp}]
2. ...

### Cross-Source Agreements
- {Point of agreement} — [{video_A}], [{video_B}]

### Cross-Source Disagreements
> [!contradiction]
> {Video A} claims X [{timestamp}]. {Video B} claims Y [{timestamp}].
> Sources: [{video_A}], [{video_B}]
> Resolution: pending

### Gaps Identified
- {Topic not covered by any source in this domain}

## Key Claims (with timestamps)
1. [{MM:SS}] {Specific claim from the video — from raw transcript}
2. [{MM:SS}] {Another claim}

## Transcript Excerpt
{Relevant portions only — not the full transcript}

## Assumptions & Limitations
...
## Relevance to Our Project
...
## Cross-References
...
```

When NotebookLM is not used, the `## NotebookLM Extraction` section is omitted
and the note uses the standard format with only Key Claims and Transcript Excerpt.

**Snapshot principle:** Both the raw transcript excerpt AND the NotebookLM
extraction are captured at absorption time. YouTube videos can go private or
be deleted — the note IS the permanent record. The raw transcript provides
the ground truth; the NotebookLM extraction provides the semantic analysis.

### 5.4 Twitter/X Adapter Details

**Discovery via Twitter MCP** (armatrix/twitter-mcp):
- `search_tweets` with advanced query syntax
- `get_trends` for topic discovery
- `get_user_timeline` for monitoring seed accounts
- 13 read tools total; ~$0.15/1K calls via twitterapi.io
- Requires `TWITTERAPI_KEY` environment variable

**Extraction via Twitter MCP:**
- `get_tweet_thread` for full thread unrolling
- `get_tweet_replies` and `get_tweet_quotes` for context
- Captures the complete thread, not just the first tweet

**Source note format for Twitter/X:**
```markdown
# {Thread Opening Line or Topic}

**ID:** {source_id}
**Author:** @{handle} ({display_name})
**Date:** {date}
**Type:** twitter
**Domain:** {domain}
**URL:** {tweet_url}
**Date Absorbed:** {date}
**Thread Length:** {N tweets}

## Full Thread
1. {First tweet text}
2. {Second tweet text}
...

## Key Claims
1. {Specific claim extracted from thread}

## Context
- Replying to: {if applicable}
- Quote-tweeting: {if applicable}

## Assumptions & Limitations
...
## Relevance to Our Project
...
## Cross-References
...
```

**Snapshot principle:** The full thread text is captured at absorption time.
Tweets are ephemeral — they can be deleted or accounts suspended. The note IS
the permanent record. Always capture full thread content, not just URLs.

**Quality bar:** Twitter sources require `quality_threshold >= 4` (vs 3 for papers)
because the signal-to-noise ratio is lower. Author credentials and community
validation (quality of engagement, not just volume) factor into the score.

### 5.5 Scholar Gateway Adapter Details

**Already connected** as `mcp__claude_ai_Scholar_Gateway__semanticSearch`.

- Semantic search over peer-reviewed literature with citations and provenance
- Year filtering for recency
- Returns structured passages with proper citation chains
- No API key needed — available immediately

### 5.6 Adding New Source Types

To add a new source type (e.g., podcast, Substack, Reddit, Discord):

1. Add the type to the manifest's `source_adapters` section
2. Specify discovery and extraction methods (MCP tool or web fallback)
3. Define a source note template in this document (Section 6)
4. Add the type to the metadata template's `type` enum

No skill code changes are needed — the skills read the adapter configuration
from the manifest at runtime.

## 6. Hot Cache

**Location:** Note `{project_folder}/hot.md` in Fast.io (one per project)
**Read via:** `workspace/read-note`
**Write via:** `workspace/update-note`

**Purpose:** Eliminate session startup overhead. Every sub-skill reads this note
first (~500 tokens, 0.25% of context window, 4-6x ROI on token investment).

**Contents (maintained by all sub-skills):**

```markdown
# Hot Cache — {project_name}
## Last Updated: {date}

## Last Activity
- Phase: discovery
- Domain focus: covariance-estimation
- Sources found: 3 new, 2 already absorbed

## Pending Work
- 3 sources awaiting absorption (see INDEX.md status=pending)
- regime-models domain synthesis needs update (2 new sources since last update)

## Key Decisions (this cycle)
- Confirmed: lambda=0.9 fallback justified by James-Stein literature
- Open: 30-sample threshold needs published support — flagged as finding

## Open Questions
- Is nonlinear shrinkage (LW2012) worth implementing given our p/n ratio?
- Should we add deflated Sharpe ratio to validation criteria?
```

**Update rules:**
- Every sub-skill writes to hot.md on completion via `workspace/update-note`
- Content is overwritten, not appended (keeps it ~500 words)
- Only working state — no historical record (that's the work log)

## 7. Note Templates

All knowledge base content is stored as Fast.io notes (native markdown documents
with automatic RAG indexing when workspace intelligence is enabled).

### 7.1 Source Note Template (General)

```markdown
# {Title}

**ID:** {source_id}
**Authors:** {authors}
**Year:** {year}
**Type:** {paper|preprint|white_paper|blog|book_chapter|youtube|twitter}
**Domain:** {domain}
**Project:** {project_name}
**URL:** {canonical_url}
**Date Absorbed:** {date}

## Key Claims
1. {Specific, falsifiable claim from the source}
2. {Another claim}
3. ...

## Assumptions & Limitations
- {What the source assumes that may or may not hold for us}
- ...

## Relevance to Our Project
- {Specific connection to our implementation or domain understanding}
- ...

## Actionable Recommendations
- {What we should do or check based on this source}
- ...

## Cross-References
- **Extends:** [[source_id]] — {how}
- **Contradicts:** [[source_id]] — {what and why}
- **Superseded by:** [[source_id]] — {if applicable}
- **Referenced by:** [[source_id]], [[source_id]]

## Contradictions
> [!contradiction]
> {Source A} claims X. {Source B} claims Y.
> Sources: [[A]], [[B]]
> Resolution: {pending | resolved — rationale}
```

YouTube and Twitter source notes use the extended templates defined in
Sections 5.3 and 5.4 respectively.

### 7.2 Domain Synthesis Note Template

```markdown
# {Domain Name} — Literature Synthesis

**Project:** {project_name}
**Last Updated:** {date}
**Sources:** {count} absorbed, {count} pending
**Status:** {current|stale|needs-review}

## Consensus View
{What the literature collectively agrees on, with citations [SOURCE_ID]}

## Open Debates
{Where the literature disagrees, with both sides cited}

## Recommendations for Our Project
{Specific, actionable recommendations grounded in literature}

### Confirmed Conformances
- {Where our project matches literature recommendations} — [SOURCE_ID]

### Identified Deviations
- {Where our project deviates from literature} — Severity: {critical|important|informational}
  - What we do: {description}
  - What literature recommends: {description} — [SOURCE_ID]
  - Justification for deviation: {if any}

## Contradictions (Unresolved)
> [!contradiction]
> ...

## Gap Areas
- {Topics where we have insufficient literature coverage}
```

### 7.3 Assessment Note Template

```markdown
# Domain Review Assessment — {date}

**Project:** {project_name}
**Scope:** {domains reviewed}
**Assessment Mode:** {code_vs_literature|knowledge_synthesis|decision_audit|plan_review}
**Knowledge Base State:** {N sources absorbed, M pending}
**Artifact State:** {git commit hash, branch, or N/A for non-code projects}

## Executive Summary
{2-3 sentence overview of findings}

## Findings by Severity

### Critical
{Findings where our project contradicts strong literature consensus}

### Important
{Findings where our project deviates from best practices without clear justification}

### Informational
{Observations, suggestions, and areas for further investigation}

## Domain-by-Domain Results

### {Domain 1}
- Conformances: {count}
- Deviations: {count by severity}
- Key finding: {one sentence}

### {Domain 2}
...

## Recommendations
1. {Prioritized action items}

## Literature Gaps
- {Domains or questions where we need more sources}
```

## 8. Skill Architecture

Five Claude Code skills implement this architecture. All are generic — project-
specific behavior comes from the manifest.

| Skill | File | Purpose |
|-------|------|---------|
| `/kb-review` | `kb-review.md` | Meta-skill orchestrator |
| `/kb-discover` | `kb-discover.md` | Multi-round, multi-source discovery |
| `/kb-absorb` | `kb-absorb.md` | Source absorption with cross-referencing |
| `/kb-assess` | `kb-assess.md` | Token-disciplined assessment against KB |
| `/kb-refresh` | `kb-refresh.md` | Staleness detection + lint + maintenance |

All skills accept `--project {name}` to identify which manifest to load.

### 8.1 Orchestration Flow

```
/kb-review --project quant-weak-signal [--scope all|domain-name] [--phase discovery|absorb|assess|refresh|all]

    ┌──────────────────────────────────────┐
    │  0. READ MANIFEST                    │
    │  Load .claude/kb-projects/{project}  │
    │  Verify sync with cloud copy         │
    └──────────┬───────────────────────────┘
               │
    ┌──────────▼───────────────────────────┐
    │  1. READ HOT CACHE                   │
    │  workspace/read-note({project}/hot)  │
    │  Determine current state             │
    └──────────┬───────────────────────────┘
               │
    ┌──────────▼───────────────────────────┐
    │  2. REFRESH / LINT (if needed)       │
    │  Check staleness per domain          │
    │  Run 8-category lint                 │
    │  Determine which phases to run       │
    └──────────┬───────────────────────────┘
               │
    ┌──────────▼───────────────────────────┐
    │  3. DISCOVERY (if stale > N days)    │
    │  Source adapter dispatch per type    │
    │  Multi-round: search → gap-fill →   │
    │  dedup → add to INDEX as pending     │
    └──────────┬───────────────────────────┘
               │
    ┌──────────▼───────────────────────────┐
    │  4. ABSORPTION (for pending sources) │
    │  Pre-process (if available, e.g.    │
    │    NotebookLM for YouTube batches)  │
    │  Type-specific extraction            │
    │  Read → summarize → cross-reference  │
    │  → detect contradictions → update    │
    │  domain synthesis → store in mem0    │
    │  Notes auto-indexed for RAG          │
    └──────────┬───────────────────────────┘
               │
    ┌──────────▼───────────────────────────┐
    │  5. ASSESSMENT (artifacts vs KB)     │
    │  Per domain: read synthesis →        │
    │  query mem0 → read artifacts →       │
    │  assess → rate findings → write      │
    └──────────┬───────────────────────────┘
               │
    ┌──────────▼───────────────────────────┐
    │  6. JOURNAL CAPTURE (chain-of-       │
    │  thought → Fast.io)                  │
    │  Read local transcripts (JSONL) →    │
    │  distill decisions/diagnostics/      │
    │  insights → write journal note →     │
    │  promote highlights to mem0 →        │
    │  advance bookmark                    │
    └──────────┬───────────────────────────┘
               │
    ┌──────────▼───────────────────────────┐
    │  7. UPDATE HOT CACHE + WORK LOG      │
    │  workspace/update-note(hot.md)       │
    │  worklog/append (activity record)    │
    └──────────────────────────────────────┘
```

### 8.2 Agent Parallelism

| Phase     | Parallelizable? | Strategy |
|-----------|----------------|----------|
| Discovery | Yes — domains independent | Parallel agents per domain |
| Absorption | Yes — each source independent | Up to 5 parallel agents (batch) |
| Assessment | Partially | Layers 1-4 parallel, synthesis sequential |
| Refresh   | Yes — lint checks independent | Single agent, parallelized internally |

### 8.3 Token Budget per Domain Review

| Step | Source | Budget |
|------|--------|--------|
| 1. Hot cache | Fast.io: workspace/read-note({project}/hot.md) | ~500 tokens |
| 2. Working memory | mem0 query (project-scoped) | ~500 tokens |
| 3. Domain synthesis | Fast.io: workspace/read-note({project}/domains/{domain}.md) | ~2,000 tokens |
| 4. Specific sources (if needed) | Fast.io: workspace/read-note({project}/sources/*.md) (2-3 notes) | ~2,000 tokens |
| 5. Project artifacts | Local files from manifest code_paths (or N/A) | ~2,000 tokens |
| **Total** | | **<8,000 tokens** |

### 8.4 Credit Budget

Fast.io free agent plan: 50 GB storage, 5,000 monthly credits.

| Operation | Credit cost | Monthly estimate (1 project) | Credits/month |
|-----------|------------|-------------------------------|---------------|
| Storage | 100/GB | ~0.001 GB | ~1 |
| Note ingestion (RAG) | 10/page | ~200 pages | ~2,000 |
| AI chat queries | 1/100 tokens | ~50K tokens | ~500 |
| Bandwidth | 212/GB | ~0.01 GB | ~3 |
| **Total** | | | **~2,500** |

Headroom: ~50% for one project. With multiple projects, skills should:
1. Prefer `workspace/read-note` (free) over `ai/chat-create` (costs credits)
2. Batch note updates rather than updating one field at a time (re-ingestion cost)
3. Report credit usage in the work log
4. Alert when estimated monthly usage exceeds 4,000 credits

## 9. Refresh Cadence

| Frequency | Action | Trigger |
|-----------|--------|---------|
| Weekly | Discovery scan — search all domains, add new sources to Pending | `/kb-discover` or auto via `/kb-review` |
| Monthly | Absorb pending + update syntheses + run assessment | `/kb-review --phase all` |
| On-demand | Full review when project artifacts change materially | User invokes `/kb-review` |

### 9.1 Staleness Detection

Thresholds are configurable per project via the manifest's `staleness` section.

```
For each domain:
  last_discovery = max(date_absorbed) of sources in that domain
  last_assessment = date of most recent assessment referencing that domain

  if today - last_discovery > staleness.stale_days → STALE
  if today - last_discovery > staleness.aging_days → AGING
  if today - last_assessment > staleness.unreviewed_days → UNREVIEWED
  else → CURRENT (skip unless --force)
```

## 10. Lint Categories

The `/kb-refresh` skill checks 9 categories of knowledge base health:

| # | Category | Description | Severity |
|---|----------|-------------|----------|
| 1 | Orphan sources | Source notes with zero cross-references | Warning |
| 2 | Dead references | Cross-references to non-existent source IDs | Error |
| 3 | Unresolved contradictions | Contradiction callouts with status=pending | Warning |
| 4 | Missing sources | Domain syntheses citing source IDs not in KB | Error |
| 5 | Incomplete metadata | Source notes missing required fields | Warning |
| 6 | Empty sections | Source notes with placeholder content | Warning |
| 7 | Stale index | INDEX.md out of sync with workspace folder contents | Error |
| 8 | Stale syntheses | Domain synthesis not updated after new source absorption | Warning |
| 9 | Pending mem0 queue | Entries in mem0-pending.md awaiting flush | Info/Warning |
| 10 | Uncaptured journal sessions | Local transcripts exist that are newer than the journal bookmark | Info/Warning/Error (severity scales with count) |
| 11 | Stale channel scans | YouTube channels with `last_scan + scan_interval_days` elapsed and `status != deprecated` | Info/Warning/Error (severity scales with count) |
| 12 | Low-productivity channels | Channels in KB > 90 days with `videos_in_kb == 0` — curation signal | Info |

## 11. Fast.io Tool Quick Reference

Key MCP tool/action mappings used by the skills:

| Operation | Fast.io Tool | Action |
|-----------|-------------|--------|
| Create note | `workspace` | `create-note` |
| Read note | `workspace` | `read-note` |
| Update note | `workspace` | `update-note` |
| List folder contents | `storage` | `list` |
| Search (keyword + semantic) | `storage` | `search` |
| Create folder | `storage` | `create-folder` |
| RAG chat (scoped) | `ai` | `chat-create` (type: chat_with_files, folders_scope) |
| RAG chat (specific files) | `ai` | `chat-create` (type: chat_with_files, files_attach) |
| Set metadata | `workspace` | `metadata-set` |
| Extract metadata (AI) | `workspace` | `metadata-extract` |
| Create metadata template | `workspace` | `metadata-template-create` |
| Append work log | `worklog` | `append` |
| List work log | `worklog` | `list` |
| Create task | `task` | `create-task` |
| Update task status | `task` | `change-status` |
| Activity summary (AI) | `event` | `summarize` |
| Note version history | `storage` | `version-list` |
| Restore note version | `storage` | `version-restore` |

## 12. External MCP Tool Reference

MCP servers used by source adapters:

| MCP Server | Source Types | Phase | Tools Used | Credentials |
|------------|-------------|-------|------------|-------------|
| Scholar Gateway | paper, preprint | discovery | `semanticSearch` | None (Claude.ai integration) |
| YouTube Data API (`@kirbah/mcp-youtube`) | youtube | discovery | `searchVideos`, `getVideoDetails`, `getChannelStatistics`, `getTranscripts` (fallback) | `YOUTUBE_API_KEY` |
| NotebookLM (`notebooklm-mcp-ultimate`) | youtube | pre-processing | `create_notebook_remote`, `add_youtube_source`, `add_url_source`, `ask_question`, `list_sources`, `summarize_source`, `discover_sources` (~44 tools total) | Interactive: Playwright browser auth via `setup_auth` tool (no env var). Headless: `GOOGLE_AUTH_COOKIES_PATH`. |
| YouTube Transcript (`@kimtaeyoon83/mcp-server-youtube-transcript`) | youtube | extraction | `get_transcript` | None (public caption endpoints) |
| Twitter/X (armatrix) | twitter | discovery + extraction | `search_tweets`, `get_tweet_thread`, `get_user_timeline` | `TWITTERAPI_KEY` |
| WebSearch (built-in) | all types | discovery (fallback) | keyword search | None |
| WebFetch (built-in) | all types | extraction (fallback) | content extraction | None |

### 12.1 Credential Management

Credentials are managed at three layers:

**Layer 1: `.env` (project root, git-ignored) — secret values**

Store API keys and tokens here. This file is in `.gitignore` and must never
be committed. The `kb-review` skill checks for required env vars on startup.

```bash
# YouTube Data API v3
YOUTUBE_API_KEY=AIza...

# Twitter/X reads via twitterapi.io
TWITTERAPI_KEY=tw_...

# Fast.io workspace token
FASTIO_TOKEN=ft_...

# mem0 API key — required for the official HTTP MCP at https://mcp.mem0.ai/mcp
# (recommended install; see §3.2). Avoid OAuth-based connectors.
MEM0_API_KEY=m0_...
```

**Layer 2: `.claude/settings.json` (project-level) — MCP server wiring**

Connects Claude Code to MCP servers. References env vars with `${VAR}` syntax.
This file CAN be committed (no secrets, only variable references).

```json
{
  "mcpServers": {
    "fast-io": {
      "url": "https://mcp.fast.io/mcp",
      "headers": { "Authorization": "Bearer ${FASTIO_TOKEN}" }
    },
    "youtube-api": {
      "command": "npx",
      "args": ["-y", "@kirbah/mcp-youtube"],
      "env": { "YOUTUBE_API_KEY": "${YOUTUBE_API_KEY}" }
    },
    "youtube-transcript": {
      "command": "npx",
      "args": ["-y", "@kimtaeyoon83/mcp-server-youtube-transcript"],
      "env": {}
    },
    "notebooklm": {
      "command": "npx",
      "args": ["-y", "notebooklm-mcp-ultimate"],
      "env": {}
    },
    "twitter": {
      "command": "npx",
      "args": ["-y", "@armatrix/twitter-mcp"],
      "env": { "TWITTERAPI_KEY": "${TWITTERAPI_KEY}" }
    }
  }
}
```

Note: Scholar Gateway may already be connected via Claude.ai's built-in
integrations (the `claude_ai_` prefix tools), which use OAuth flows managed
by Claude.ai itself — no env vars needed.

**For mem0, prefer the API-key HTTP MCP over any OAuth-based Claude.ai
Connector.** The OAuth path rate-limits auth attempts and can lock the
account for days; the API-key path has no `authenticate` tool to call,
so the lockout failure mode cannot occur. Install with:

```
npx mcp-add --name mem0-mcp --type http --url "https://mcp.mem0.ai/mcp" --clients "claude code"
```

or add to `.claude/settings.json`:

```json
"mem0-mcp": {
  "type": "http",
  "url": "https://mcp.mem0.ai/mcp",
  "headers": { "Authorization": "Bearer ${MEM0_API_KEY}" }
}
```

**Layer 3: Project manifest `mcp_servers` section — declares requirements**

The manifest's `mcp_servers` section documents what each service does, whether
it's required, and how to get credentials. The `kb-review` meta-skill reads
this section and produces a service status report on every invocation.

### 12.2 How to Get Each Credential

| Service | Env Var | How to Obtain |
|---------|---------|---------------|
| Fast.io | `FASTIO_TOKEN` | Fast.io dashboard → API Keys, or `fastio auth login` |
| YouTube Data API | `YOUTUBE_API_KEY` | Google Cloud Console → APIs & Services → YouTube Data API v3 → Create Credentials → API Key (free tier: 10K units/day) |
| NotebookLM (community MCP, `notebooklm-mcp-ultimate`) | *(none for interactive use)* or `GOOGLE_AUTH_COOKIES_PATH` for headless | Interactive: run the `setup_auth` MCP tool once — Chrome opens, log in to Google normally (MFA supported), session state saved locally. No manual cookie export needed. Headless only: export a Playwright storageState JSON from a machine with a browser, copy to server, set the env var to the path. |
| NotebookLM (Enterprise API) | — | `gcloud auth login` + Enterprise tier subscription; uses OAuth, not env vars |
| Twitter/X reads | `TWITTERAPI_KEY` | twitterapi.io → Sign Up → Dashboard → API Key (~$0.15/1K calls) |
| mem0 | `MEM0_API_KEY` | app.mem0.ai → Dashboard → API Keys. Use with the official HTTP MCP at https://mcp.mem0.ai/mcp — see §3.2. Do not use OAuth-based connectors. |
| Scholar Gateway | — | Connected via Claude.ai — complete OAuth flow once in Claude.ai settings |
| YouTube Transcript | — | No credentials needed (uses yt-dlp locally) |

### 12.3 Startup Verification

The `kb-review` meta-skill performs a service check on every invocation
(see the Prerequisites Check in `kb-review.md`). It:
1. Checks each `mcp_servers` entry from the manifest
2. For mem0: checks tool registry for data tools (zero-cost, zero auth
   attempts) — see Section 3.2. Reports as available, "misconfigured
   (OAuth connector, no data tools)", or absent
3. For all other services: tests connectivity via the `check_tool`
4. Verifies env vars are set for credentialed services
5. Reports full status table with setup instructions for anything missing
6. Blocks execution only if `required: true` services are unavailable
7. Proceeds with fallbacks for optional services, noting degraded quality

This means you can start with zero credentials (WebSearch fallback for everything)
and incrementally add credentials as you see value. Each credential you add
upgrades one or more source adapters from fallback to preferred path.

## 13. Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-12 | Fast.io as primary storage | Native markdown notes with auto-RAG indexing; 19 MCP tools (~200+ actions); agent-first design; 50 GB + 5,000 credits free; folder-scoped RAG replaces Hub management |
| 2026-04-12 | Pivoted from Box.com to Fast.io | Non-technical reasons drove the pivot; Fast.io proved technically superior — native notes, built-in RAG, semantic search, task/worklog/approval systems Box lacks |
| 2026-04-12 | mem0 as semantic working memory | Fast recall, cross-session persistence, semantic search; complements Fast.io's structured storage |
| 2026-04-12 | Obsidian as optional local viewer | Not required for system to function; convenience for graph navigation |
| 2026-04-12 | No Pinecone | Fast.io RAG + semantic search covers document queries; mem0 covers semantic memory; Pinecone would be redundant |
| 2026-04-12 | Hot cache pattern | Eliminates 2-3K token session recap; 4-6x ROI on ~500 token investment |
| 2026-04-12 | Contradiction preservation | In quant finance, contradictions between papers are the signal; silent overwrite hides decision points |
| 2026-04-12 | Multi-round discovery | Single-pass misses adjacent work; 2-3 rounds catch cited works and related concepts |
| 2026-04-12 | Work log over CHANGELOG.md | Fast.io native worklog is append-only, queryable, supports AI summaries; no read-modify-write race condition |
| 2026-04-12 | Credit-aware skill design | Skills prefer direct note reads over RAG queries when target is known; batch note updates to reduce re-ingestion cost |
| 2026-04-13 | Generalized to topic-agnostic system | Skills are generic engines; project manifests define all domain-specific knowledge. Supports arbitrary topics, not just quant finance |
| 2026-04-13 | Project manifest with dual-location sync | Local (.claude/kb-projects/) for git versioning + Fast.io (manifests/) for cloud access. Hash-based sync verification on every invocation |
| 2026-04-13 | Source adapter pattern | Separates discovery from extraction; supports MCP APIs with web fallback; graceful degradation with zero credentials |
| 2026-04-13 | YouTube + Twitter as first-class source types | YouTube via Data API + Transcript MCP; Twitter via armatrix MCP. Snapshot principle for ephemeral content |
| 2026-04-13 | Renamed skills quant-* → kb-* | Topic-agnostic naming; all project knowledge in manifests, not skill files |
| 2026-04-13 | All 6 quant domains from day one | Full coverage for quant project; domains are per-project via manifest |
| 2026-04-13 | Pluggable assessment modes | code_vs_literature, knowledge_synthesis, decision_audit, plan_review — manifest selects mode per project |
| 2026-04-13 | Isolated-first workspace topology | Projects are scoped by default (Fast.io folders_scope + mem0 project tags). Cross-project sharing requires explicit --cross-project flag. Prevents noise from unrelated projects while allowing intentional cross-pollination |
| 2026-04-13 | NotebookLM as YouTube pre-processing step | Raw transcripts lose semantic structure; NotebookLM provides citation-backed claims, cross-source synthesis, and gap identification. Optional phase — falls back to direct transcript when unavailable. One notebook per project-domain accumulates cross-source context over time |
| 2026-04-13 | Three-phase adapter pipeline (discovery → pre-processing → extraction) | Pre-processing is an optional semantic enrichment step between discovery and extraction. Currently only YouTube uses it (via NotebookLM), but the pattern is extensible to other source types. `fallback: skip` preserves graceful degradation |
| 2026-04-13 | Extracted KB system to standalone repo | KB system is topic-agnostic and serves multiple projects. Standalone repo with symlink-based installation into consuming projects. Skills symlinked into .claude/skills/, architecture doc symlinked into .claude/kb-docs/. Single .kb-link config file per consuming project stores relative path to KB repo |
| 2026-04-13 | Write-through buffer for mem0 | Failed mem0 writes buffer to Fast.io `{project_folder}/mem0-pending.md` instead of being lost. Queue flushed by `kb-refresh --flush-mem0`. Category 9 lint monitors queue depth. Zero data loss even with prolonged mem0 outage |
| 2026-04-14 | Zero-cost mem0 availability (replaces lazy auth, cooldown file, status propagation) | Previous approach (lazy auth + cooldown file + cross-skill propagation) still caused account lockouts because probe calls and MCP server connection-level auth accumulated. New approach: skills check the tool registry for mem0 data tools — a local lookup with zero network traffic, zero auth attempts. If data tools exist → authenticated, use freely. If only authenticate/complete_authentication exist → not authenticated, skip entirely. Authentication is user-initiated only. Removed: cooldown files, `--mem0-status` argument, cross-skill propagation, probing logic |
| 2026-04-21 | Session journaling as a new artifact class | Claude Code writes per-project transcripts (JSONL) to `~/.claude/projects/{sanitized-cwd}/` including extended-thinking blocks. Those blocks are the richest record of WHY choices were made and evaporate when sessions age out. `kb-capture` reads transcripts, distills via a versioned prompt, writes a structured journal note to `{project_folder}/journal/`, promotes 2–3 highest-signal insights to mem0, and adds a "Recent decisions" section to hot.md. Raw dumps are opt-in via `--raw` (forensic use only, not RAG-indexed by default) because their ingestion cost is much higher than distilled notes. Category 10 lint monitors uncaptured-session debt. Privacy: thinking tokens are uploaded verbatim; `journal.redact_patterns` in the manifest is a future extension point. First-order win: decisions become queryable across sessions. Second-order: agents onboarding to a project can prime on hot.md's Recent Decisions section. Third-order: over months the journal becomes a compliance-grade record of design intent |
| 2026-04-23 | Thinking-tokens redaction forces reflexive-or-terminal-capture path | Claude Code ≈2.1.116 silently changed the JSONL writer to redact `thinking` block contents, keeping only the `signature` field (opaque Anthropic-encrypted protobuf for session-resume, not client-decodable). Empirically verified: `--debug api --debug-file` does not recover pre-redaction thinking either — the capture layer sits below the redaction. Consequence for kb-capture: reflexive distillation (from working memory during the session) remains full-fidelity, retrospective distillation of pre-2.1.116 sessions remains full-fidelity, but retrospective distillation of post-2.1.116 sessions is structurally degraded unless the session was launched under `script(1)` / `asciinema` / `tmux pipe-pane`. Skill updated to detect the redaction (thinking=empty + signature=long) and tag `fidelity: degraded` accordingly. Future kb-capture version will consume terminal-capture artifacts as an additional distillation source; v1 reads JSONL only and reports the degradation honestly. First-order: any post-2.1.116 session without a terminal capture arrangement loses its reasoning trace permanently. Second-order: the `fidelity` front-matter field on journal entries becomes semantically meaningful for downstream weighted-trust retrieval. Third-order: documents a real-world risk of depending on another vendor's internal data representations — even an undocumented, silent client-side change can break a downstream consumer's whole value proposition |
| 2026-04-23 | Active journaling via kb-note as primary path (Framing C — layered capture) | Thinking redaction reframed the journaling design: retrospective distillation alone is structurally vulnerable to vendor data-representation changes. Framing C resolves this by making active journaling the primary path, with retrospective distillation and terminal capture as overlapping backups. New skill `kb-note` lets agents (via Skill tool) and users (via slash command) record individual decisions/diagnostics/insights/open-threads to Fast.io during sessions — `{project}/journal/notes/{date}-{sid8}-{seq}-{slug}.md` per entry. Four entry-type templates enforce structural consistency via skill prompt. `insight` entries auto-promote to mem0; others stay local. Q1=C (both slash command and programmatic invocation, unified skill). Q2=A (file per decision — enables independent linking/deletion). Q3=A (retrospective always runs as catch-up and narrative-arc view, aware of existing active notes to avoid duplication). MCP tool variant deferred to v2 if schema drift becomes observable. First-order: reasoning is preserved at decision-time, independent of vendor representation choices. Second-order: journal quality stops being a function of Claude Code's version. Third-order: establishes "own the capture path" as a durable design principle for future kb-system integrations — don't depend on internal representations we don't control |
| 2026-04-23 | Phase 3 (terminal-capture reader) + Phase 4 (weighted-trust retrieval) designs approved; not yet implemented | Design docs committed to `docs/design-roadmap/phase-3-terminal-capture-reader.md` and `docs/design-roadmap/phase-4-weighted-trust-retrieval.md`. Phase 3 extends kb-capture to consume `.typescript` / `.cast` terminal captures as a supplementary distillation source, recovering thinking content that Claude Code 2.1.116+ redacts from JSONL. Session matching is timestamp-window; cross-referencing via ordinal correlation (Nth thinking block in terminal = Nth redacted block in JSONL). Introduces `fidelity: partial` as a new enum value. Phase 4 adds a trust-scoring layer to kb-assess's Layer 1 Context read, where each journal entry in hot.md gets a composite score `trust = source_factor * outcome_factor * compaction_factor` and is rendered into the assessment context using budget-aware truncation bands. Phase 4 depends on Phase 3 because of the partial enum addition. Implementation scheduling TBD. First-order: when shipped, retrospective distillation regains full fidelity for any session that had terminal capture at launch, and kb-assess findings carry explicit provenance/trust metadata. Second-order: the fidelity field on journal front-matter becomes semantically load-bearing in retrieval, not just informational. Third-order: design-roadmap folder convention established as the place where approved-but-unbuilt extensions live, with phase-numbered docs that become reference material after shipping |
| 2026-04-23 | Correct claim: ~/.claude/settings.json `env` block does NOT propagate to stdio MCP subprocesses | Earlier commits claimed "settings.json env block inherits to MCP subprocesses via normal env inheritance" — empirically false for the @kirbah/mcp-youtube stdio MCP registered on this machine. Verification: MCP registered without explicit `-e YOUTUBE_API_KEY=...` saw only `getTranscripts` in its tool registry (the 0-quota tool gated on "no key required"); the other 7 tools (search/metadata/channel) did not register because the MCP's own gating logic did not see the env var. Fix: register stdio MCPs with explicit `-e KEY=value` on the `claude mcp add` command line so the value is stored in `~/.claude.json` and passed to the subprocess at launch. HTTP MCPs (fast-io, mem0) are unaffected — they use `--header` and pass auth at request time, not subprocess-env time. Manifest template updated (youtube_api section) to document the correct install command. First-order: YouTube Data API access now actually works for this machine's kb-system install. Second-order: all stdio MCPs must be registered with explicit env; documented in the template for future project setups. Third-order: the "single canonical home per secret" claim still holds (`~/.claude.json` is the home), but the mechanism is explicit `-e` at registration time, not settings.json env-block inheritance. Documented the distinction so future users don't repeat the mistake |
