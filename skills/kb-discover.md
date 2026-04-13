---
name: kb-discover
description: >
  Multi-round, multi-source discovery sub-skill. Searches for new content across
  all source types defined in the project manifest. Uses source adapter dispatch
  to route through MCP APIs when available, falling back to web search.
  Deduplicates against the existing knowledge base in Fast.io.
---

# KB Discover — Literature & Content Search Sub-Skill

You are the discovery engine of the Knowledge Base system. Your job is to find
new, relevant content that the knowledge base does not yet contain.

**Architecture reference:** `.claude/kb-docs/ARCHITECTURE.md` (symlinked from KB system repo)

## Arguments

- `--project`: **required** — project name (loads manifest from `.claude/kb-projects/`)
- `--scope`: `all` (default) or comma-separated domain names
- `--cross-project`: when set, dedup checks search across ALL project folders in
  the workspace (not just the current project). This surfaces sources already
  absorbed by other projects that may be relevant — they can be cross-referenced
  rather than re-absorbed.

## Step 0: Load Manifest

Read `.claude/kb-projects/{project}.yaml`. Extract:
- `domains` — domain list with `search_queries` and `foundational_sources`
- `source_adapters` — per-type discovery and extraction configuration
- `project.project_folder` — Fast.io folder path

## Source Adapter Dispatch

For each source type in the manifest's `source_adapters`, determine the
discovery method at runtime:

```
For each source_type:
  1. Check if preferred MCP tool is available
  2. If yes → use preferred discovery path
  3. If no → use fallback (typically WebSearch)
  4. Track which path is used for the work log
```

### Adapter-Specific Discovery Methods

**paper / preprint (Scholar Gateway):**
```
mcp__claude_ai_Scholar_Gateway__semanticSearch:
  query: {search_query from manifest — use full natural language, not keywords}
  inferred_intent: "Finding published research on {domain} for {project}"
  start_year: {optional — for recency filtering}
```

**youtube (YouTube API MCP → fallback: WebSearch):**
```
Preferred: YouTube API MCP search tool
  query: {search_query}
  Filters: channel authority, upload date, view count

Fallback: WebSearch
  query: "{search_query} site:youtube.com"
```
Also check `seed_channels` from manifest — scan recent uploads from seed channels.

**twitter (Twitter MCP → fallback: WebSearch):**
```
Preferred: twitter_mcp search_tweets
  query: {search_query with advanced syntax}
  Also: get_user_timeline for each seed_account in manifest

Fallback: WebSearch
  query: "{search_query} site:x.com"
```
Also check `seed_accounts` from manifest — scan recent posts from seed accounts.

**blog / white_paper / book_chapter (WebSearch):**
```
WebSearch:
  query: {search_query}
```

## Execution: Three-Round Discovery

### Round 1: Broad Search

For each domain in scope, run search queries from the manifest across all
source types defined in `source_adapters`:

For each result, extract:
- Title
- Authors / Channel / Handle
- Year / Date
- Source type (paper/preprint/white_paper/blog/book_chapter/youtube/twitter)
- URL or DOI
- One-sentence relevance summary

### Round 1.5: Deduplicate

Before Round 2, check each found source against the existing KB:

1. Use `storage/search` (semantic) to check if a source with a similar title,
   author, or topic already exists.
   - **Default (isolated):** scope search to `{project_folder}` only
   - **With `--cross-project`:** scope search to workspace root — this catches
     sources absorbed by other projects. Mark these as `exists_in:{other_project}`
     rather than `already_absorbed` — they may warrant a cross-reference note
     in this project without re-absorbing.
2. Read `INDEX.md` via `workspace/read-note` on `{project_folder}/INDEX.md`
   and check for matching source_id or title.
3. Mark sources as `new`, `already_absorbed`, or `exists_in:{other_project}`.

Drop already-absorbed sources. Continue with `new` sources only.

### Round 2: Gap-Fill Search

Read the Round 1 results. For each new source:
- Extract cited works and adjacent concepts mentioned
- Identify foundational references that our KB should have but doesn't
- Search for these specific missing references

Also check the manifest's `foundational_sources` list per domain — ensure
each foundational source is represented in the KB. If not, add to the
candidate list.

Also look for:
- Recent survey papers/videos that cover multiple concepts in the domain
- Content that directly challenges or updates our foundational sources
- Practitioner critiques of methods used in the project

### Round 3: Contradiction & Quality Check

For each candidate source from Rounds 1-2:
- Read the abstract, summary, or opening (use WebFetch for URLs, YouTube
  transcript MCP for videos, Twitter MCP for thread previews)
- Assess relevance score (1-5): does this source say something our KB needs?
- Apply type-specific quality threshold from manifest (default: 3, twitter: 4)
- Check for contradictions with existing domain knowledge:
  - Read the domain synthesis note via `workspace/read-note` on
    `{project_folder}/domains/{domain}.md`
  - Does this new source contradict any existing consensus claims?
  - If yes, flag it explicitly

### Output: Update INDEX.md

For each new source that passes the quality filter:

Update INDEX.md via `workspace/update-note` on `{project_folder}/INDEX.md`:

```
| {source_id} | {title} | {authors} | {year} | {type} | {domain} | {today} | pending | {relevance_score} |
```

Report to the orchestrator:

```
Discovery Complete — {date}
Project: {project_name}

Domains searched: {list}
Source adapters used:
  paper: Scholar Gateway (preferred)
  youtube: WebSearch fallback (YouTube API MCP not connected)
  twitter: Twitter MCP (preferred)
  blog: WebSearch

Round 1: {N} results found, {N} already in KB, {N} new
Round 2: {N} gap-fill results found, {N} new
Round 3: {N} passed quality filter

New sources pending absorption:
  {domain-1}: {N} — {titles}
  {domain-2}: {N} — {titles}
  ...

By source type:
  papers: {N}, youtube: {N}, twitter: {N}, blogs: {N}

Potential contradictions flagged: {N}
  - {source} may contradict {existing_claim} in {domain}
```

Append work log entry via `worklog/append`:
```
[{project}] Discovery complete. Domains: {list}. Found {N} new sources
({N} paper, {N} youtube, {N} twitter, {N} blog). {N} passed quality filter.
Adapters: {which preferred vs fallback}.
```

## Quality Criteria

A source passes the quality filter if:
- **Relevance >= threshold**: directly relates to the project's domains
  (threshold is per-type from manifest; default 3, twitter 4)
- **Credibility**: published in peer-reviewed venue, from recognized
  practitioner/firm, established YouTube channel, or verified expert account
- **Recency consideration**: foundational works are always relevant;
  for practitioner content/tweets/videos, prefer last 3 years
- **Not a duplicate**: does not substantially overlap with an already-absorbed source

## Token Discipline

- Do NOT read full papers or watch full videos during discovery. Read abstracts,
  introductions, video descriptions, and thread openings only.
- Discovery is about finding sources, not understanding them. Absorption does the
  deep reading.
- Budget: ~1,000 tokens per source evaluation in Rounds 2-3.

## Credit Awareness

- Use `storage/search` for dedup (semantic search) — more credit-efficient than
  multiple `ai/chat-create` sessions.
- Prefer `workspace/read-note` for reading INDEX.md and domain syntheses (free).
- Scholar Gateway has no credit cost.
- YouTube API has a separate quota (10K units/day) — not charged to Fast.io credits.
- Twitter MCP costs ~$0.15/1K calls — budget aware, but separate from Fast.io credits.
