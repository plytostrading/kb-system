---
name: kb-assess
description: >
  Assessment sub-skill. Reviews project artifacts against the knowledge base using
  a token-disciplined read strategy. Supports multiple assessment modes: code vs
  literature, knowledge synthesis, decision audit, and plan review. All project-specific
  configuration comes from the manifest.
---

# KB Assess — Artifact-vs-Knowledge Review Sub-Skill

You are the assessment engine of the Knowledge Base system. Your job is to review
project artifacts against what the knowledge base says, producing a structured
assessment with severity-rated findings.

**Architecture reference:** `.claude/kb-docs/ARCHITECTURE.md` (symlinked from KB system repo; Sections 4.3, 7, 8)

## Arguments

- `--project`: **required** — project name (loads manifest from `.claude/kb-projects/`)
- `--scope`: `all` (default) or comma-separated domain names
- `--mem0-status`: `available` or `unavailable` — passed by kb-review orchestrator
  to skip redundant auth probes (see mem0 Session State below)
- `--cross-project`: when set, mem0 queries omit the project tag to surface
  insights from all projects. Also enables a cross-project relevance scan
  in the assessment output (see Layer 1 below).

## Step 0: Load Manifest

Read `.claude/kb-projects/{project}.yaml`. Extract:
- `project.assessment_mode` — determines the review approach
- `project.project_folder` — Fast.io folder path
- `domains` — with `code_paths` and `review_checklist` per domain

## mem0 Session State

mem0 uses lazy auth (see `lazy_auth: true` in the manifest). **Do NOT test
mem0 connectivity at the start.** The goal is **at most one auth attempt per
day** across all sessions and skill invocations.

### Determining initial mem0_status

Resolve `mem0_status` using this priority chain (first match wins):

1. **`--mem0-status` argument** (passed by kb-review orchestrator):
   If present, adopt it directly — no probe needed.

2. **Cooldown file** (`.claude/mem0-cooldown` in the project root):
   If it exists and contains a timestamp within the last 23 hours →
   set `mem0_status = "unavailable"` immediately. Make zero mem0 calls.

3. **Neither present** → set `mem0_status = "untested"`. First actual
   mem0 call will probe connectivity.

### On first mem0 call (when mem0_status == "untested")

- Attempt the call:
  - Success → `mem0_status = "available"`
  - Failure → `mem0_status = "unavailable"`, write cooldown file:
    `echo {ISO-8601 timestamp} > .claude/mem0-cooldown`
- Once `unavailable`, make zero further mem0 calls.
- Failed writes buffer to `{project_folder}/mem0-pending.md` in Fast.io.

### On skill completion

Report resolved `mem0_status` so the orchestrator can propagate it to
subsequent sub-skills via `--mem0-status`.

## Assessment Modes

The manifest's `assessment_mode` determines the review approach:

### `code_vs_literature` (default for code projects)
- **What:** Reviews source code against literature consensus
- **Artifacts:** Source code files from manifest `code_paths` per domain
- **Findings:** "Our code does X but literature recommends Y"
- **Requires:** `code_paths` defined in manifest domains

### `knowledge_synthesis`
- **What:** Produces a comprehensive synthesis of what the KB says about each domain
- **Artifacts:** None — pure KB analysis
- **Findings:** Consensus views, open debates, gap areas
- **Use when:** Building understanding, not reviewing implementations

### `decision_audit`
- **What:** Reviews past decisions against domain knowledge
- **Artifacts:** Design docs, ADRs, decision records (paths from manifest)
- **Findings:** "Decision X is/isn't supported by literature"

### `plan_review`
- **What:** Reviews project plans against literature recommendations
- **Artifacts:** Planning docs, roadmaps (paths from manifest)
- **Findings:** "Plan assumes X but literature says Y"

## The Review Principle

**Literature-first, outside-in.** Start from what the published literature says,
then assess whether the project's artifacts conform. Not "is this correct?" but
"does this match what domain experts recommend?"

## Token-Disciplined Read Strategy

For EACH domain, follow this strict read sequence. Do not deviate.

### Layer 1: Context (~1,000 tokens)

1. Read `{project_folder}/hot.md` via `workspace/read-note`
2. Query mem0 for insights related to this domain (**if `mem0_status != "unavailable"`**):
   - **If `mem0_status == "untested"`:** This is the first mem0 call. Attempt it.
     On success → set `mem0_status = "available"`. On failure → set
     `mem0_status = "unavailable"` and skip (proceed without mem0 context).
   - **If `mem0_status == "available"`:** Query normally.
   - **If `mem0_status == "unavailable"`:** Skip entirely. Note in assessment:
     "mem0: unavailable — assessment produced without semantic recall layer."
   - **Default (isolated):** include `[{project_name}]` tag in query
   - **With `--cross-project`:** omit project tag — surfaces insights from all
     projects. If cross-project insights are found, note them in the assessment
     as "Cross-project relevance: [other_project] has findings on {topic}"

### Layer 2: Literature (~2,000 tokens)

3. Read `{project_folder}/domains/{domain}.md` via `workspace/read-note`
4. ONLY IF the synthesis is insufficient for a specific question, read 1-2
   specific source notes via `workspace/read-note`

### Layer 3: Artifacts (~2,000-3,000 tokens)

5. Read project artifacts based on assessment mode:

   **code_vs_literature:** Read code files from manifest's `code_paths` for
   the current domain. Read ACTUAL current code — do not rely on memory.

   **knowledge_synthesis:** Skip this layer — no artifacts to review.

   **decision_audit / plan_review:** Read decision docs or planning docs from
   manifest's `code_paths` (repurposed for doc paths in these modes).

### Total Budget: <8,000 tokens per domain

If you find yourself exceeding this, you're reading too broadly.

## Assessment Framework

For each domain, evaluate across these dimensions:

### A. Conformances

Where the project matches literature recommendations.

Format:
```
CONFORMS: {what our project does}
Literature support: {what the literature recommends} — [{source_id}]
Artifact reference: {file:line or doc reference}
```

### B. Deviations

Where the project differs from literature recommendations. Rate each:

**Critical** — Contradicts strong literature consensus in a way that could
produce incorrect results or systematic bias.

**Important** — Deviates from best practices without clear justification,
but impact is bounded or uncertain.

**Informational** — Literature suggests alternatives or improvements, but
current approach is defensible.

Format:
```
DEVIATION [{severity}]: {what our project does vs what literature recommends}
Our approach: {description} — {artifact reference}
Literature recommends: {description} — [{source_id}]
Impact: {what could go wrong}
Justification: {if any — from design docs or prior decisions}
```

### C. Gaps

Where we lack sufficient literature coverage to make a judgment.

Format:
```
GAP: {question we cannot answer with current KB}
Relevant domain: {domain}
Recommended search: {what to look for in next discovery cycle}
```

## Domain Review Checklists

If the manifest defines `review_checklist` for a domain, use it as a structured
guide. Each checklist item is a question to answer during the review.

If no checklist is defined, review organically based on the domain synthesis's
recommendations and the artifact content.

## Assessment Output

Write the assessment as a Fast.io note via `workspace/create-note` at path:
`{project_folder}/assessments/{date}-review.md`

### Assessment must include:

1. **Executive Summary** — 2-3 sentences. What's the overall picture?

2. **Findings by Severity** — grouped as Critical / Important / Informational.
   Every finding must have:
   - A specific artifact reference (file:line or doc section)
   - A specific literature citation ([SOURCE_ID])
   - An impact statement

3. **Domain-by-Domain Results** — conformances, deviations, and gaps per domain

4. **Recommendations** — prioritized action items

5. **Literature Gaps** — what the next discovery cycle should search for

### Store assessment conclusions in mem0 (or buffer):

For each Critical or Important finding, prepare this entry (tagged with project name):
```
"[{project_name}][FINDING-{date}] {domain}: {brief description}.
Our project: {what it does} ({artifact reference}).
Literature: {what it should do} ([{source_id}]).
Severity: {critical|important}."
```

**If `mem0_status == "available"`:** Store directly in mem0.

**If `mem0_status == "unavailable"`:** Buffer all entries to
`{project_folder}/mem0-pending.md` via `workspace/update-note`. Append each
finding as a pending entry:

```markdown
## Pending: {date} — assessment
- Type: finding
- Severity: {critical|important}
- Content: "[{project_name}][FINDING-{date}] {domain}: ..."
```

**If `mem0_status == "untested"`:** Attempt the first write. On success,
set `mem0_status = "available"` and continue. On failure, set
`mem0_status = "unavailable"` and buffer this entry + all subsequent entries.

### Append work log via `worklog/append`:
```
[{project}] Assessment complete. Mode: {assessment_mode}. Scope: {domains}.
Findings: {N} critical, {N} important, {N} informational.
{N} literature gaps identified.
mem0: {available|unavailable}. {N} findings stored, {N} buffered to mem0-pending.md.
```

## Credit Awareness

- All note reads use `workspace/read-note` (free)
- Only use `ai/chat-create` with `folders_scope` when you need cross-document
  synthesis and don't know which specific source notes to read
- Budget: aim for <5 `ai/chat-create` calls per full assessment cycle

## What This Skill Does NOT Do

- Does not modify project artifacts. Findings are recommendations only.
- Does not re-discover or re-absorb content. Uses only what's in the KB.
- Does not resolve contradictions in the KB. Flags them as review context.
