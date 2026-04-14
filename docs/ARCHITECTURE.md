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

**Zero-cost availability check (no auth attempts):**

mem0 uses OAuth with rate-limited authentication attempts. Repeated auth
attempts cause account lockouts. The system generates **zero auth attempts**
from the skill layer by using a tool-registry check instead of probing:

**How it works:** Each skill checks whether mem0 **data tools** (e.g.
`mcp__mem0-mcp__search`, `mcp__mem0-mcp__add`) exist as callable tools:

- **Data tools exist** → mem0 is authenticated. Use normally.
- **Only `authenticate`/`complete_authentication` exist** → mem0 is NOT
  authenticated. Skip all mem0 usage silently. Buffer writes.

This is a local tool-registry lookup — zero network traffic, zero auth
attempts. Skills **never** call `authenticate` or `complete_authentication`.
Authentication is a user-initiated action only.

If mem0 is authenticated but a data call fails at runtime (timeout, rate
limit), the skill sets `mem0_available = false` for the rest of that run
and buffers remaining writes. No cooldown files or cross-skill propagation
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

The pending queue is flushed by `kb-refresh --flush-mem0`:
1. Checks mem0 data tool availability (zero-cost registry check)
2. If not authenticated → reports "mem0 not authenticated — flush skipped"
3. If authenticated → reads `mem0-pending.md`, flushes all entries, clears queue
4. If a call fails mid-flush → stops, reports partial progress

This ensures **zero data loss** — insights are captured in Fast.io immediately
and promoted to mem0 when the user has completed authentication.

### 3.3 Obsidian — Local Viewing Layer (optional)

Obsidian can open a local export of the Fast.io workspace as a vault for graph view,
backlinks, and tag navigation. This is a read-only convenience layer — the source
of truth is always Fast.io.

Use `fastio` CLI or the `download` MCP tool to export notes to a local directory.
This is not required for the system to function.

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

1. **Community MCP server** (PleasePrompto/notebooklm-mcp): 16 tools including
   `list_notebooks`, `create_notebook`, `add_youtube_source`, `query_notebook`.
   Uses browser cookies for authentication. Current recommended path for
   individual use.

2. **Official Enterprise API**: `notebooks.sources.batchCreate` supports YouTube
   URLs via `videoContent.youtubeUrl`. OAuth via gcloud. Requires Enterprise
   tier. Better for automation and team use.

**Fallback:** When NotebookLM is unavailable (`fallback: skip`), the pipeline
skips pre-processing entirely and proceeds to direct transcript extraction.
The system degrades to the standard transcript-based absorption flow — still
functional, but without cross-source synthesis or citation-backed claims.

**Extraction via YouTube Transcript MCP** (hancengiz/youtube-transcript-mcp):
- yt-dlp based — no API key needed
- Automatic pagination for transcripts > 50K characters
- Returns full transcript with timestamps
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
    │  6. UPDATE HOT CACHE + WORK LOG      │
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
| YouTube Data API (ZubeidHendricks) | youtube | discovery | search, video metadata | `YOUTUBE_API_KEY` |
| NotebookLM (PleasePrompto) | youtube | pre-processing | `list_notebooks`, `create_notebook`, `add_youtube_source`, `query_notebook` | `GOOGLE_COOKIES` |
| YouTube Transcript (hancengiz) | youtube | extraction | transcript extraction | None (yt-dlp) |
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

# mem0 API key (if using self-hosted, not Claude.ai integration)
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
      "args": ["-y", "@zubeidhendricks/youtube-mcp-server"],
      "env": { "YOUTUBE_API_KEY": "${YOUTUBE_API_KEY}" }
    },
    "youtube-transcript": {
      "command": "npx",
      "args": ["-y", "youtube-transcript-mcp"],
      "env": {}
    },
    "notebooklm": {
      "command": "npx",
      "args": ["-y", "notebooklm-mcp"],
      "env": { "GOOGLE_COOKIES": "${GOOGLE_COOKIES}" }
    },
    "twitter": {
      "command": "npx",
      "args": ["-y", "@armatrix/twitter-mcp"],
      "env": { "TWITTERAPI_KEY": "${TWITTERAPI_KEY}" }
    }
  }
}
```

Note: Scholar Gateway and mem0 may already be connected via Claude.ai's built-in
integrations (the `claude_ai_` prefix tools). These use OAuth flows managed by
Claude.ai itself — no env vars needed.

**Layer 3: Project manifest `mcp_servers` section — declares requirements**

The manifest's `mcp_servers` section documents what each service does, whether
it's required, and how to get credentials. The `kb-review` meta-skill reads
this section and produces a service status report on every invocation.

### 12.2 How to Get Each Credential

| Service | Env Var | How to Obtain |
|---------|---------|---------------|
| Fast.io | `FASTIO_TOKEN` | Fast.io dashboard → API Keys, or `fastio auth login` |
| YouTube Data API | `YOUTUBE_API_KEY` | Google Cloud Console → APIs & Services → YouTube Data API v3 → Create Credentials → API Key (free tier: 10K units/day) |
| NotebookLM (community MCP) | `GOOGLE_COOKIES` | Export Google account cookies via browser extension (e.g., EditThisCookie); see PleasePrompto/notebooklm-mcp README for format |
| NotebookLM (Enterprise API) | — | `gcloud auth login` + Enterprise tier subscription; uses OAuth, not env vars |
| Twitter/X reads | `TWITTERAPI_KEY` | twitterapi.io → Sign Up → Dashboard → API Key (~$0.15/1K calls) |
| mem0 | `MEM0_API_KEY` | app.mem0.ai → Dashboard → API Keys (if not using Claude.ai integration) |
| Scholar Gateway | — | Connected via Claude.ai — complete OAuth flow once in Claude.ai settings |
| YouTube Transcript | — | No credentials needed (uses yt-dlp locally) |

### 12.3 Startup Verification

The `kb-review` meta-skill performs a service check on every invocation
(see the Prerequisites Check in `kb-review.md`). It:
1. Checks each `mcp_servers` entry from the manifest
2. For mem0: checks tool registry for data tools (zero-cost, zero auth
   attempts) — see Section 3.2. Reports as available or "not authenticated"
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
