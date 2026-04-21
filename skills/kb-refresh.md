---
name: kb-refresh
description: >
  Knowledge base maintenance sub-skill. Checks staleness per domain using
  project-specific thresholds from the manifest, runs 9-category lint across
  the knowledge base stored in Fast.io, fixes auto-fixable issues, flushes
  pending mem0 writes, and reports what needs human attention. Topic-agnostic.
---

# KB Refresh — Staleness Detection & Lint Sub-Skill

You are the maintenance engine of the Knowledge Base system. Your job is to
assess the health of the knowledge base and fix what can be fixed automatically.

**Architecture reference:** `.claude/kb-docs/ARCHITECTURE.md` (symlinked from KB system repo; Sections 9, 10)

## Arguments

- `--project`: **required** — project name (loads manifest from `.claude/kb-projects/`)
- `--scope`: `all` (default) or comma-separated domain names
- `--fix`: auto-fix issues where possible (default: report only)
- `--lint-only`: skip staleness check, run lint only
- `--flush-mem0`: attempt to flush pending mem0 writes from `mem0-pending.md`

## Step 0: Load Manifest

Read `.claude/kb-projects/{project}.yaml`. Extract:
- `project.project_folder` — Fast.io folder path
- `domains` — domain list
- `staleness` — threshold configuration (stale_days, aging_days, unreviewed_days)

## mem0 Availability (for --flush-mem0)

mem0 is optional. **NEVER call `authenticate` or `complete_authentication`.**
Authentication is a user-initiated action only.

Determine `mem0_available` by checking the tool registry:

- If mem0 **data tools** (e.g. `mcp__mem0-mcp__search_memories`,
  `mcp__mem0-mcp__add_memory`, `mcp__mem0-mcp__get_memories`, or any of
  the other seven data tools documented at `https://docs.mem0.ai/platform/mem0-mcp`)
  exist as callable tools → `mem0_available = true`.
- If the only mem0 tools are `authenticate` / `complete_authentication`
  → `mem0_available = false`. The user has the OAuth-based connector and
  has not completed OAuth. **Do not call `authenticate`.** If `--flush-mem0`
  was requested, report: "mem0 not available — flush skipped. Either
  complete OAuth manually or, preferably, switch to the official API-key
  HTTP MCP (`https://mcp.mem0.ai/mcp`) to eliminate the OAuth lockout risk."

This check is local (tool registry lookup) and generates **zero auth
attempts.**

If `mem0_available = true` but a data call fails at runtime, set
`mem0_available = false`. Report flush skipped with reason.

## Execution Flow

### Step 1: Staleness Check

Read INDEX.md via `workspace/read-note` on `{project_folder}/INDEX.md`.
For each domain in scope, compute using thresholds from manifest:

```
last_discovery = max(date_absorbed) among sources in this domain
last_assessment = date of most recent assessment note referencing this domain

Staleness (thresholds from manifest.staleness):
  STALE:      today - last_discovery > staleness.stale_days
  AGING:      today - last_discovery > staleness.aging_days
  UNREVIEWED: today - last_assessment > staleness.unreviewed_days (but discovery is recent)
  CURRENT:    neither stale nor unreviewed
```

If `last_discovery` is null for a domain (no sources yet), it is `EMPTY`.

Report:
```
Domain Staleness Report — {date}
Project: {project_name}

  {domain-1}:  CURRENT (last discovery: ..., last assessment: ...)
  {domain-2}:  AGING   (last discovery: ..., last assessment: ...)
  {domain-3}:  STALE   (last discovery: ..., last assessment: ...)
  {domain-4}:  EMPTY   (no sources absorbed)
  ...

Recommendation:
  - {domain-3}: needs full cycle (discovery + absorb + assess)
  - {domain-2}: needs discovery scan
  - {domain-4}: needs initial population
```

### Step 2: Lint — 9 Category Scan

Run all 9 lint categories. Each produces findings with severity and, where
possible, an auto-fix. All operations are scoped to `{project_folder}/`.

#### Category 1: Orphan Sources

**Check:** Source notes with zero cross-references.
**How:** `storage/list` on `{project_folder}/sources/`, then `workspace/read-note`
each to check `## Cross-References`.
**Severity:** Warning
**Auto-fix:** Cannot auto-fix. Suggest re-running absorption.

#### Category 2: Dead References

**Check:** Cross-reference entries pointing to source IDs not in the KB.
**How:** Build source_id set from INDEX.md. `storage/search` for `[[...]]` patterns.
Flag references to IDs not in the set.
**Severity:** Error
**Auto-fix:** Add missing source to INDEX.md as `status=pending`.

#### Category 3: Unresolved Contradictions

**Check:** `[!contradiction]` callouts with `Status: pending`.
**How:** `storage/search` for "contradiction" in project folder. Read matched notes.
**Severity:** Warning
**Auto-fix:** Cannot auto-fix. Report with conflicting claims and source IDs.

#### Category 4: Missing Sources

**Check:** Domain syntheses citing source IDs not in `sources/`.
**How:** Read each domain synthesis. Extract `[SOURCE_ID]` citations. Check INDEX.md.
**Severity:** Error
**Auto-fix:** Add missing source_ids to INDEX.md as `status=pending`.

#### Category 5: Incomplete Metadata

**Check:** Source notes missing required fields (source_id, title, authors, year,
type, domain, date_absorbed).
**How:** Read each source note, parse header, check for missing fields.
**Severity:** Warning
**Auto-fix with --fix:** Fill from INDEX.md or note content if available.

#### Category 6: Empty Sections

**Check:** Source notes with placeholder content in required sections.
**How:** Read each source note, check `## Key Claims`, `## Relevance to Our Project`,
`## Cross-References` for substantive content.
**Severity:** Warning
**Auto-fix:** Cannot auto-fix. Flag for re-absorption.

#### Category 7: Stale Index

**Check:** INDEX.md out of sync with workspace folder contents.
**How:** `storage/list` on `{project_folder}/sources/`, compare with INDEX.md entries.
**Severity:** Error
**Auto-fix with --fix:** Notes without INDEX entry → add as `status=unindexed`.
INDEX entries without notes → mark as `status=missing_file`.

#### Category 8: Stale Syntheses

**Check:** Domain syntheses not updated after new source absorption.
**How:** Compare latest `date_absorbed` per domain against synthesis `Last Updated`.
**Severity:** Warning
**Auto-fix:** Cannot auto-fix. Flag for synthesis update.

#### Category 9: Pending mem0 Queue

**Check:** `{project_folder}/mem0-pending.md` exists and has entries.
**How:** `workspace/read-note` on `{project_folder}/mem0-pending.md`. Count
`## Pending:` sections.
**Severity:** Info (if ≤5 entries), Warning (if >5 entries)
**Auto-fix:** Flushed automatically in Step 5 when mem0 is available.
Can also be triggered in isolation via `--flush-mem0`.

### Step 3: Report

```
Lint Report — {date}
Project: {project_name}

Summary:
  Errors:   {N} (must fix before next assessment)
  Warnings: {N} (should fix, not blocking)

Findings:

  [ERROR] Dead reference: source "Chen2010" referenced in LW2004 but not in KB
    → Auto-fix available: add Chen2010 to INDEX.md as pending

  [WARNING] Orphan source: "harvey-liu-zhu-2016" has zero cross-references
    → Suggested: re-run absorption to build cross-references

  [WARNING] Unresolved contradiction in {domain}
    → {source_A} claims X; {source_B} claims Y
    → Requires human resolution

  [ERROR] Stale index: 2 notes in sources/ not in INDEX.md
    → Auto-fix available: add to INDEX.md as unindexed

  [INFO] Pending mem0 queue: 3 entries awaiting flush
    → Run with --flush-mem0 to attempt flush
  ...

Auto-fixable: {N} issues
  Run with --fix to apply automatic fixes.

mem0 pending queue: {N} entries
  Run with --flush-mem0 to flush.

Manual attention needed: {N} issues
  {list of issues requiring human judgment}
```

Append work log via `worklog/append`:
```
[{project}] Refresh/lint complete. Scope: {domains}. {N} errors, {N} warnings.
{N} auto-fixed (if --fix). {N} require manual attention.
mem0: {available|not authenticated|unavailable}. Pending: {N}. {Flushed N / skipped}.
```

### Step 4: Apply Auto-Fixes (if --fix)

If `--fix` was passed:
1. Apply all auto-fixable changes via `workspace/update-note`
2. Re-run affected lint categories to verify
3. Report what was fixed and what remains

### Step 5: Flush mem0 Pending Queue (automatic)

This step runs **automatically** whenever `mem0_available = true`. It also
runs in isolation when `--flush-mem0` is passed. This ensures the pending
queue is drained as part of routine review cycles — no manual intervention
needed once mem0 is authenticated.

1. Read `{project_folder}/mem0-pending.md` via `workspace/read-note`
2. If no pending entries → skip silently (nothing to report)
3. If not `mem0_available` →
   - If `--flush-mem0` was explicitly passed: report "mem0 not authenticated
     — {N} entries remain in queue. Complete mem0 authentication first."
   - Otherwise: skip silently (Category 9 lint already reported the count)
4. For each `## Pending:` section, extract the content and store in mem0:
   - Tag with the project name from the `Content:` field
   - On success → mark entry as flushed
   - On failure mid-flush → set `mem0_available = false`, stop, report
     partial progress
5. After all entries are flushed, clear `mem0-pending.md` via
   `workspace/update-note` (replace with empty marker):

   ```markdown
   # mem0 Pending Queue — {project_name}
   ## Status
   Last flushed: {date}. Queue empty.
   ```

6. Report:
   ```
   mem0 Flush — {date}
   Entries flushed: {N}
   Entries remaining: {N} (if partial)
   ```

## Credit Awareness

- This skill is read-heavy. Use `workspace/read-note` (free) for all direct reads.
- Use `storage/search` for cross-note searches — more credit-efficient than
  multiple `ai/chat-create` sessions.
- Use `storage/list` for folder enumeration.
- Avoid `ai/chat-create` entirely during lint.

## Scheduling Guidance

This skill should run:
- **Before every assessment** — to ensure KB health
- **After every absorption** — to catch issues introduced by new sources
- **Weekly as standalone** — routine KB maintenance

The meta-skill (`/kb-review`) runs this automatically as Step 2.
