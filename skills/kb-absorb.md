---
name: kb-absorb
description: >
  Source absorption sub-skill. Reads pending sources using type-specific extraction
  (Scholar Gateway for papers, YouTube Transcript MCP for videos, Twitter MCP for
  thread unrolling, WebFetch for blogs). Creates structured notes in Fast.io, detects
  contradictions, builds bidirectional cross-references, updates domain syntheses, and
  stores semantic insights in mem0.
---

# KB Absorb — Source Absorption Sub-Skill

You are the absorption engine of the Knowledge Base system. Your job is to deeply
read new sources, extract structured knowledge, weave them into the existing
knowledge mesh, and detect contradictions.

**Architecture reference:** `.claude/kb-docs/ARCHITECTURE.md` (symlinked from KB system repo; Sections 5, 7)

## Arguments

- `--project`: **required** — project name (loads manifest from `.claude/kb-projects/`)
- `--scope`: `all` (default) or comma-separated domain names
- `--source`: absorb a specific source by ID (skips INDEX.md lookup)
## Step 0: Load Manifest

Read `.claude/kb-projects/{project}.yaml`. Extract:
- `source_adapters` — per-type extraction configuration
- `project.project_folder` — Fast.io folder path
- `project.name` — for mem0 tagging

## mem0 Availability

mem0 is optional. **NEVER call `authenticate` or `complete_authentication`.**
Authentication is a user-initiated action only.

At the start of this skill, determine `mem0_available` by checking the tool
registry:

- If mem0 **data tools** (e.g. `mcp__mem0-mcp__search_memories`,
  `mcp__mem0-mcp__add_memory`, `mcp__mem0-mcp__get_memories`, or any of
  the other seven data tools documented at `https://docs.mem0.ai/platform/mem0-mcp`)
  exist as callable tools → `mem0_available = true`.
- If the only mem0 tools are `authenticate` / `complete_authentication`
  → `mem0_available = false`. The user has the OAuth-based connector and
  has not completed OAuth. **Do not attempt to fix this. Do not call
  authenticate. Skip all mem0 usage silently.** The recommended resolution
  is to replace the OAuth connector with the official API-key HTTP MCP
  (`https://mcp.mem0.ai/mcp`) — documented in the user guide.

This check is local (tool registry lookup) and generates **zero network
traffic, zero auth attempts.**

If `mem0_available = true` but a data call fails at runtime (timeout, rate
limit, server error), set `mem0_available = false` for the rest of this
skill run. Do not retry. Buffer any pending writes to
`{project_folder}/mem0-pending.md`.

## Execution Flow

### Step 1: Identify Pending Sources

Read INDEX.md via `workspace/read-note` on `{project_folder}/INDEX.md`.
Filter for entries with `status=pending` in the target domain(s).

If no pending sources, report "Nothing to absorb" and exit.

### Step 2: For Each Pending Source (parallelizable)

Process each source through the full absorption pipeline:

#### 2a. Type-Specific Extraction

Route extraction through the appropriate adapter based on the source's `type`
field in INDEX.md:

**paper / preprint / white_paper / blog / book_chapter:**
- Use `WebFetch` on the source URL
- For papers: focus on abstract, introduction, methodology overview, key
  results/tables, conclusion, and sections directly relevant to the project
- For blog posts: read the full post

**youtube:**

Check the manifest's `source_adapters.youtube.pre_processing` field. If
`preferred: notebooklm_mcp` is set AND the NotebookLM MCP is available,
use the NotebookLM enrichment flow (Step 2a-YT below). Otherwise, fall
through to direct transcript extraction.

- **Direct extraction (no NotebookLM):**
  - **Preferred:** Use YouTube Transcript MCP to extract full transcript
    - Paginate if transcript > 50K characters
    - Extract key timestamps where domain-relevant claims are made
  - **Fallback:** Use `WebFetch` on the video page (partial transcript only)
- **Snapshot:** Capture transcript excerpt in the note — the video may go private

#### 2a-YT. NotebookLM Enrichment Flow (YouTube Pre-Processing)

When NotebookLM MCP is available, YouTube sources go through a semantic
enrichment step BEFORE standard extraction. This produces citation-backed,
cross-source synthesis that raw transcripts cannot provide.

**Notebook management (one per project-domain):**

1. Check for existing notebook named `{project}-{domain}` via
   `mcp__notebooklm__list_notebooks` (or the library-registry variant
   `mcp__notebooklm__search_notebooks` if using the notebooklm-mcp-
   ultimate package's local library tools)
2. If exists → reuse (accumulates cross-source context over time)
3. If not → create via `mcp__notebooklm__create_notebook_remote` with
   name `{project}-{domain}` and description from the manifest's
   domain description

**Batch-add videos:**

4. For all pending YouTube sources in this domain, batch-add to the notebook
   via `mcp__notebooklm__add_youtube_source` (one call per video URL)
   - NotebookLM natively accepts YouTube URLs via `videoContent.youtubeUrl`
   - No transcript extraction needed at this stage — NotebookLM processes
     the video directly

**Run structured extraction queries:**

5. After sources are added, query the notebook via `mcp__notebooklm__ask_question`
   with these structured prompts (adapt domain name as needed). Note: the
   ask_question tool accepts a `notebook_id` or `notebook_url` parameter
   — pass it explicitly rather than relying on the currently-selected
   notebook, because each domain has its own:

   ```
   Q1: "What are the specific, falsifiable claims made across all sources
       about {domain}? List each claim with the source that makes it."

   Q2: "What assumptions do these sources make? What are their stated
       limitations? Cite each source."

   Q3: "Where do these sources agree with each other? Where do they
       disagree? Cite both sides of any disagreement."

   Q4: "What specific, actionable recommendations do these sources make
       for implementing {domain} in practice? Cite sources."

   Q5: "What topics related to {domain} are NOT covered by these sources?
       What gaps exist in the collective knowledge?"
   ```

6. Each NotebookLM response comes with **source citations** (pinned to
   specific videos and timestamps). Preserve these citations verbatim —
   they become the provenance chain in the source note.

**Merge with raw transcript:**

7. ALSO extract the raw transcript via YouTube Transcript MCP (the standard
   extraction path). The raw transcript serves as the snapshot — NotebookLM's
   analysis may not be reproducible if the notebook is deleted.

8. The final source note includes BOTH:
   - `## NotebookLM Extraction` — citation-backed structured claims from Q1-Q5
   - `## Transcript Excerpt` — raw transcript segments (standard snapshot)

**When NotebookLM adds value vs. when it doesn't:**

- **High value:** Long-form content (>15 min), multi-video domain batches,
  content with dense technical claims, cross-source synthesis
- **Low value:** Short clips (<5 min), single-video absorption, content
  that's mostly visual (code demos, live trading)
- When estimated value is low, skip pre-processing even if available

**Source note format with NotebookLM enrichment:**

```markdown
# {Video Title}

**ID:** {source_id}
...standard metadata...

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

### Gaps Identified by NotebookLM
- {Topic not covered}

## Key Claims (with timestamps)
{Standard extraction — from raw transcript}

## Transcript Excerpt
{Relevant portions — snapshot for permanence}

## Assumptions & Limitations
...
## Relevance to Our Project
...
## Cross-References
...
```

**twitter:**
- **Preferred:** Use Twitter MCP `get_tweet_thread` for full thread unrolling
  - Also use `get_tweet_replies` and `get_tweet_quotes` for context
- **Fallback:** Use `WebFetch` on the tweet URL (may only get first tweet)
- **Snapshot:** Capture full thread text in the note — tweets are ephemeral

#### 2a-CH. Channel artifact maintenance (YouTube only)

For every YouTube source, maintain a corresponding channel artifact
in `{project_folder}/channels/`. Channel artifacts are first-class
notes that accumulate metadata about productive source creators;
they enable channel-scoped discovery (kb-discover Round 2.5) and
provide a roster view of the creator corpus.

**Step 2a-CH.1: Resolve the parent channel from the video**

If the preferred discovery path ran and the MCP tool exposed the
video's `channelId`, use it directly. Otherwise, fetch via
`mcp__youtube-api__getVideoDetails({videoIds: [this_video_id]})`
(costs 1 quota unit). The returned `snippet.channelId` is the
canonical UC-prefixed YouTube internal channel ID; the
`snippet.channelTitle` is the display name.

To resolve the `@handle` (needed for the filename slug), use
`mcp__youtube-api__searchVideos({query: channel_title, type:
"channel", maxResults: 1})` if the handle isn't already known —
the first result's `snippet.customUrl` yields the handle. Cache
this mapping; re-resolving for every video is wasteful.

**Step 2a-CH.2: Check for existing channel artifact**

Slug the handle: lowercase, strip the leading `@`, alphanumerics
and dashes only. Path:
`{project_folder}/channels/{handle-slug}.md`.

Use `workspace/read-note` to check existence. Three cases:

- **Exists**: read front-matter. Increment `videos_in_kb` by 1.
  Update `last_seen` to today. Append the new video to the
  "Videos in KB" section. Re-write the note via
  `workspace/update-note`. Continue to 2b.

- **Does not exist**: create it with the template below. Mark
  `status: discovered` (NOT `seed` — seeds come from the manifest
  `seed_channels` list; discovered means "we found it while
  absorbing a video"). Continue to 2b.

- **Exists but marked `status: deprecated`**: note this in the
  source note's `Session Metadata Notes` section ("parent channel
  {handle} is marked deprecated; video absorption proceeding but
  future auto-expansion from this channel is suppressed") and
  continue. Do NOT update the channel artifact's `videos_in_kb`
  count — the video is absorbed but deliberately orphaned from
  the channel roster.

**Step 2a-CH.3: Channel artifact template (first-time creation)**

Use `workspace/create-note` with this body:

```markdown
---
source_id: channel-{handle-slug}
type: youtube_channel
channel_id: UC...                   # YouTube's internal ID
handle: '@{handle}'
title: {channel display title}
subscribers: {N}                    # from getChannelStatistics
total_uploads: {N}                  # from getChannelStatistics
topics: []                          # manually populated or auto-inferred later
relevant_domains: []                # populate when the user reviews / curates
videos_in_kb: 1
videos_pending: 0
videos_rejected: 0
first_seen: {YYYY-MM-DD}
last_seen: {YYYY-MM-DD}
last_scan: null                     # set when kb-discover scans this channel
status: discovered                  # discovered | seed | deprecated
quality_signal: medium              # medium by default; user-overridable
scan_interval_days: 14              # default; per-channel override via manifest
---

# {Channel Title}

## Description
{Auto-populated from getChannelStatistics if available. User can edit.}

## Why this channel
Discovered via video absorption: {video_source_id} on {date}.

## Videos in KB
- {video_source_id}: {Video Title} ({upload_date}) — [link to source note]

## Videos rejected (below quality threshold)
_(populated by kb-discover Round 3 when scanning this channel)_

## Related channels
_(populated over time via co-occurrence in absorbed content)_
```

Apply metadata via `workspace/metadata-set`:
`type: youtube_channel`, `source_id`, `channel_id`, `handle`,
`status`, `quality_signal`.

**Step 2a-CH.4: Update the video source note's front-matter**

When writing the video's source note in Step 2e, include in
front-matter:
```yaml
parent_channel: channel-{handle-slug}
```

This creates the bidirectional link: channel → videos-in-KB list
(via the channel's body) and video → parent channel (via
front-matter).

**Step 2a-CH.5: Update the channels INDEX**

Use `workspace/update-note` on
`{project_folder}/channels/INDEX.md`. Create the file if absent
with this structure:

```markdown
# Channel Index — {project_name}
Last updated: {date}

## Active Channels
| handle | title | status | quality | videos | last seen | scan next |
|--------|-------|--------|---------|--------|-----------|-----------|
| @flirtingwithmodels | Flirting with Models | seed | high | 3 | 2026-04-23 | 2026-04-30 |
| ... |

## Deprecated Channels
| handle | title | deprecated on | reason |
|--------|-------|--------------|--------|

## Topic Coverage
| domain | active channels |
|--------|-----------------|
```

Re-sort the Active Channels table by `last seen` descending after
any update.

**Step 2a-CH.6: mem0 promotion policy for channels**

Channels are NOT auto-promoted to mem0. They're discoverable via
Fast.io semantic search and via the INDEX roster, but don't elevate
to mem0's cross-project recall layer. This matches the
kb-note insight-only promotion policy: mem0 is for generalizable
patterns, not project-specific sources.

#### 2b. Extract Structured Knowledge

From the source content (regardless of type), extract:

1. **Key Claims** — specific, falsifiable statements the source makes.
   Not vague summaries like "discusses covariance estimation."
   Instead: "Proves that the oracle approximating shrinkage estimator is
   asymptotically optimal when p/n → γ ∈ (0,∞)."
   For YouTube: include timestamps `[MM:SS]` for each claim.

2. **Assumptions & Limitations** — what the source takes for granted.
   "Assumes i.i.d. returns" or "Tested only on US equities 1990-2010."
   For Twitter: note the informal/unverified nature if applicable.

3. **Methodology** (if applicable) — what approach they used and how.

4. **Relevance to Our Project** — map claims to specific project artifacts:
   - For `code_vs_literature` projects: which source files and design decisions
     does this relate to? Use `file_path:line_number` format.
   - For `knowledge_synthesis` projects: which domain understanding does this
     update or challenge?

5. **Actionable Recommendations** — what should we do or check?

#### 2c. Contradiction Detection

Read the current domain synthesis note via `workspace/read-note` on
`{project_folder}/domains/{domain}.md`. Compare the new source's Key Claims
against the synthesis's Consensus View.

For each potential contradiction:
- Is this a genuine conflict, or a difference in scope/assumptions?
- If genuine: create a `[!contradiction]` callout with:
  - Both claims, verbatim
  - Both source IDs
  - The key difference
  - Status: `pending` (never auto-resolve)

**Store the contradiction in mem0** (if `mem0_available`):

Prepare the entry (tagged with project name):
```
"[{project_name}][CONTRADICTION] {source_A} claims X but {source_B} claims Y.
Key difference: {what differs}. Domain: {domain}.
Affects: {which part of our project}."
```

**If `mem0_available`:** Store directly. If the call fails, set
`mem0_available = false` and buffer this entry instead.

**If not `mem0_available`:** Buffer by appending to
`{project_folder}/mem0-pending.md` via `workspace/update-note`:

```markdown
## Pending: {date}
- Type: contradiction
- Content: "[{project_name}][CONTRADICTION] {source_A} claims X but {source_B} claims Y. ..."
```

#### 2d. Cross-Reference Building (Bidirectional)

For the new source, identify relationships with existing sources:

1. **Extends**: new source builds on existing work
2. **Contradicts**: new source disagrees
3. **Supersedes**: new source obsoletes existing recommendations
4. **Complements**: new source covers a different angle
5. **Cites**: new source references existing source

Write these into the new source note's `## Cross-References` section.

**CRITICAL — Bidirectional update:** Also update existing source notes.
Read the existing note via `workspace/read-note`, then update via
`workspace/update-note` to add the reverse cross-reference.

#### 2e. Write Source Note

Create the source note using the appropriate template (general, YouTube,
or Twitter — see ARCHITECTURE.md Sections 5.3, 5.4, 7.1).

Use `workspace/create-note` with path:
`{project_folder}/sources/{source_id}-{slug}.md`

Apply structured metadata via `workspace/metadata-set`:
- source_id, title, authors, year, type, domain, project, date_absorbed, status=absorbed

Notes are **automatically indexed for RAG** when workspace intelligence is
enabled — no separate registration needed.

#### 2f. Store Insights in mem0 (or buffer)

Extract the 2-3 most important insights. Tag with project name.
These should be cross-cutting conclusions, not summaries:

Good: "[quant-weak-signal] LW2004 proves linear shrinkage is optimal for p < n
with normally distributed data. Our z-scored signals approximate normality, and
p=171 < n~300 per regime cell, so linear shrinkage is justified."

Bad: "[quant-weak-signal] LW2004 is about covariance estimation."

Each entry should connect the source's claims to our project.

**If `mem0_available`:** Store directly. If a call fails, set
`mem0_available = false` and buffer this + all subsequent entries.

**If not `mem0_available`:** Buffer all entries to
`{project_folder}/mem0-pending.md` via `workspace/update-note`. Append each
insight as a pending entry:

```markdown
## Pending: {date} — {source_id}
- Type: insight
- Content: "[{project_name}] {insight text}"
```

The pending queue is flushed by `kb-refresh --flush-mem0` when the user
has completed mem0 authentication and data tools are available.

### Step 3: Update Domain Synthesis

After absorbing all pending sources in a domain, update the domain synthesis note:

1. Read current `{project_folder}/domains/{domain}.md` via `workspace/read-note`
2. Incorporate new sources' claims into the Consensus View (with citations)
3. Add any new contradictions to the Open Debates section
4. Update Recommendations for Our Project
5. Update source count and last_updated date
6. Write updated synthesis via `workspace/update-note`

The synthesis should read as a coherent narrative, not a list of summaries.
A reader should be able to understand the domain's state of knowledge by reading
only the synthesis.

### Step 4: Update INDEX.md

Use `workspace/update-note` on `{project_folder}/INDEX.md` to change status
from `pending` to `absorbed` for all processed sources. Update `date_absorbed`.

### Step 5: Report

```
Absorption Complete — {date}
Project: {project_name}

Sources absorbed: {N}
  {source_id}: {title} — {domain} [{type}]
  ...

Extraction methods used:
  Scholar Gateway: {N} sources
  YouTube Transcript MCP: {N} sources
  Twitter MCP thread unroll: {N} sources
  WebFetch: {N} sources

Cross-references created: {N}
  {source_A} ↔ {source_B}: {relationship}
  ...

Contradictions detected: {N}
  [!contradiction] {brief description} — {domain}
  ...

Domain syntheses updated: {list}
mem0 insights stored: {N stored} ({N buffered} buffered to mem0-pending.md)
mem0: {available|not authenticated|unavailable (runtime failure)}
```

Append work log via `worklog/append`:
```
[{project}] Absorption complete. {N} sources absorbed ({N} paper, {N} youtube,
{N} twitter, {N} blog). {N} cross-refs created. {N} contradictions detected.
mem0: {available|not authenticated|unavailable}. {N} stored, {N} buffered.
```

## Quality Standards for Source Notes

A well-absorbed source note must have:
- [ ] At least 3 specific Key Claims (not vague summaries)
- [ ] At least 1 Assumption & Limitation identified
- [ ] At least 1 Relevance to Our Project entry
- [ ] At least 1 Actionable Recommendation
- [ ] At least 1 Cross-Reference to another source in the KB
- [ ] No empty sections (placeholder content is a lint violation)
- [ ] For YouTube: timestamps on key claims
- [ ] For Twitter: full thread captured (not just first tweet)

If a source cannot meet these standards, mark it as `status=low_relevance`
in INDEX.md and skip.

## Token Discipline

- Read source content thoroughly — absorption IS the deep reading phase
- But don't read entire 40-page papers. Focus on: abstract, introduction,
  methodology overview, key results/tables, conclusion
- For YouTube: focus on transcript segments relevant to the domain, not the
  entire 45-minute video
- For Twitter: full thread is usually manageable; skip reply chains unless
  they contain substantive additions
- Budget: ~3,000 tokens of source content per source; ~1,000 tokens for
  the generated source note

## Credit Awareness

- Use `workspace/create-note` for new source notes (ingestion costs ~10
  credits/page for RAG indexing)
- Batch cross-reference updates: do all updates for a source before moving
  to the next, to minimize re-ingestion cycles
- Prefer `workspace/read-note` (free) over `ai/chat-create` for reading notes
- YouTube Transcript MCP and Twitter MCP have their own cost models (separate
  from Fast.io credits)
