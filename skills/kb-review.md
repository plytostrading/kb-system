---
name: kb-review
description: >
  Meta-skill orchestrator for the Knowledge Base system. Runs a literature-grounded
  review of any project against a persistent knowledge base stored in Fast.io.
  Orchestrates discovery, absorption, assessment, and refresh sub-skills. Topic-agnostic —
  all project-specific behavior comes from the project manifest.
---

# KB Review — Meta-Skill

You are the orchestrator of the Knowledge Base review system. Your job is to coordinate
the sub-skills that discover literature, absorb it into the knowledge base, and review
project artifacts against domain best practices.

**Architecture reference:** `.claude/kb-docs/ARCHITECTURE.md` (symlinked from KB system repo)

## Arguments

Parse the user's invocation for:
- `--project`: **required** — the project name (matches a manifest file in `.claude/kb-projects/`)
- `--scope`: `all` (default) or a specific domain name (must exist in the project's manifest)
- `--phase`: `all` (default), `discovery`, `absorb`, `assess`, `refresh`
- `--force`: skip staleness checks, run everything
- `--cross-project`: opt-in cross-project knowledge sharing (default: OFF)
  When enabled: Fast.io searches scope to workspace root instead of project folder;
  mem0 queries omit the project tag to surface insights from all projects.
  This flag is passed through to all sub-skills.

If `--project` is omitted and only one manifest exists in `.claude/kb-projects/`,
use that one. If multiple manifests exist, ask the user which project.

## Step 0: Load and Verify Manifest

1. Read the manifest file from `.claude/kb-projects/{project}.yaml`
2. Read the cloud copy from Fast.io via `workspace/read-note` on
   `manifests/{project}.yaml`
3. Compare `content_hash` values:
   - If match → proceed
   - If cloud copy doesn't exist → this is first run; push local to cloud
   - If mismatch → compare `manifest_version`, show diff, ask user which
     is authoritative. Sync before proceeding.
4. Compute and update `content_hash` if it's empty (manual edit detected)

From the manifest, extract:
- `project.workspace` and `project.project_folder` — Fast.io locations
- `project.assessment_mode` — determines how assessment works
- `domains` — the domain list and their configuration
- `source_adapters` — how to discover/extract each source type
- `staleness` — threshold configuration

## Prerequisites Check

Before running any phase, verify services from the manifest's `mcp_servers`
section. For each server:

1. Check if the MCP tool specified in `check_tool` is callable
2. If `required: true` and unavailable → report setup instructions and **stop**
3. If `required: false` and unavailable → warn, note which fallback will be used

For services that need credentials:
- Check if the environment variable from `credentials[].env` is set
- If missing and the service has `how_to_get`, include that in the setup report

### mem0 — Zero-Cost Availability Check

**NEVER call `mcp__mem0-mcp__authenticate` or `complete_authentication`.**
Authentication is a user-initiated action only.

Check whether mem0 **data tools** (e.g. `mcp__mem0-mcp__search`,
`mcp__mem0-mcp__add`) exist as callable tools in the tool registry:

- **Data tools exist** → mem0 is authenticated and usable. Report as available.
- **Only `authenticate`/`complete_authentication` exist** → mem0 is NOT
  authenticated. Report as "not authenticated" and proceed without mem0.
  Each sub-skill will independently detect this and skip mem0 / buffer writes.

This check is a local tool-registry lookup — **zero network traffic, zero
auth attempts.**

**Report the full service status before proceeding:**

```
KB System — Service Status
Project: {project_name}

  ✓ Fast.io         — connected (workspace: shared-kb)          [REQUIRED]
  ✗ mem0            — not authenticated (data tools unavailable) [optional → writes buffered]
  ✓ Scholar Gateway — connected (via Claude.ai integration)     [optional]
  ✗ YouTube API     — YOUTUBE_API_KEY not set                   [optional → WebSearch fallback]
    → Get key: https://console.cloud.google.com → YouTube Data API v3
  ✓ YouTube Transcript — connected (no credentials needed)      [optional]
  ✗ NotebookLM     — GOOGLE_COOKIES not set                    [optional → skip pre-processing]
    → Export Google cookies via browser extension; see notebooklm-mcp README
  ✗ Twitter MCP     — TWITTERAPI_KEY not set                    [optional → WebSearch fallback]
    → Get key: https://twitterapi.io → Dashboard → API Key

Services available: 4/7
Fallback active for: mem0 (writes buffered), youtube discovery, youtube pre-processing (skipped), twitter discovery+extraction
```

If any required service is unavailable, stop and provide setup instructions.
If only optional services are missing, ask the user whether to proceed with
fallbacks or pause to configure credentials.

After the service check, verify the **Fast.io project folder structure**.
Use `storage/list` on the workspace. If the project folder is missing,
offer to create the scaffold:
- `{project_folder}/` with subfolders: `sources/`, `domains/`, `assessments/`
- `{project_folder}/hot.md` note
- `{project_folder}/INDEX.md` note
- `manifests/` folder (if it doesn't exist)

## Execution Flow

### Step 1: Read Hot Cache

Use `workspace/read-note` to read `{project_folder}/hot.md`.
If it doesn't exist, this is the first run — note that and proceed.

From the hot cache, extract:
- Last activity (what phase ran last, when)
- Pending work (sources awaiting absorption, stale domains)
- Open questions from prior sessions

### Step 2: Determine What to Run

If `--phase all` (default), determine which phases are needed:

```
For each domain in scope (from manifest):
  Check INDEX.md (via workspace/read-note) for last_discovery and last_assessment dates.
  Read staleness thresholds from manifest.

  if --force:
    run all phases
  elif last_discovery is None or (today - last_discovery) > staleness.stale_days:
    STALE → run discovery + absorb + assess
  elif (today - last_discovery) > staleness.aging_days:
    AGING → run discovery (absorb + assess only if new sources found)
  elif last_assessment is None or (today - last_assessment) > staleness.unreviewed_days:
    UNREVIEWED → run assess only
  else:
    CURRENT → skip (report as current)
```

Report the plan to the user before executing:
```
Project: {project_name}
Domain Status:
  {domain-1}: STALE (last discovery: ...) → discovery + absorb + assess
  {domain-2}: AGING (last discovery: ...) → discovery scan
  {domain-3}: CURRENT → skip
  ...

Source adapter status:
  paper:   Scholar Gateway (preferred) ✓
  youtube: YouTube API (preferred) ✗ → using WebSearch fallback
           NotebookLM pre-processing ✗ → skipping (direct transcript)
  twitter: Twitter MCP (preferred) ✓
  ...

Proceed? [the user must confirm]
```

### Step 3: Run Sub-Skills

Invoke sub-skills using the Skill tool in the determined order. Pass `--project`
and (if set) `--cross-project` to each sub-skill.

Each sub-skill independently checks mem0 data tool availability via the tool
registry (a zero-cost local check). No cross-skill mem0 state propagation
is needed.

1. **Refresh/Lint** (always first):
   `Skill("kb-refresh", "--project {name} --scope {scope}")`

2. **Discovery** (if needed):
   `Skill("kb-discover", "--project {name} --scope {domains} [--cross-project]")`

3. **Absorption** (if pending sources exist):
   `Skill("kb-absorb", "--project {name} --scope {domains}")`

4. **Assessment** (if needed):
   `Skill("kb-assess", "--project {name} --scope {domains} [--cross-project]")`

Note: `--cross-project` is passed to discovery and assessment (where cross-project
knowledge adds value) but NOT to absorption or refresh (which are always project-scoped).

### Step 4: Update Hot Cache

After all phases complete, update `{project_folder}/hot.md` via `workspace/update-note`:

```markdown
# Hot Cache — {project_name}
## Last Updated: {today}

## Last Activity
- Phase: {what just ran}
- Domains: {which domains were in scope}
- Sources discovered: {count new}
- Sources absorbed: {count}
- Assessment produced: {yes/no, date}

## Pending Work
- {N} sources awaiting absorption
- {domains} need synthesis updates
- {domains} have unresolved contradictions

## Key Decisions (this cycle)
- {decisions made or confirmed during this review}

## Open Questions
- {questions surfaced by this review that need human input}
```

### Step 5: Append Work Log

Use `worklog/append` to record the session activity:

```
[{project_name}] Phase: {what ran}. Scope: {domains}.
Discovery: {N new sources found}. Absorption: {N sources absorbed}.
Assessment: {N critical, N important, N informational}.
Lint: {N issues found, N auto-fixed}.
Adapters: {which preferred vs fallback paths used}.
mem0: {available|not authenticated|unavailable}. {N} writes buffered.
```

### Step 6: Report to User

```
KB Review Complete — {date}
Project: {project_name}

Domains reviewed: {list}
Sources: {N} total in KB, {N} new this session
Findings: {N} critical, {N} important, {N} informational

Top findings:
1. [CRITICAL] {one-line summary} — {domain}
2. [IMPORTANT] {one-line summary} — {domain}
3. ...

Full assessment: {project_folder}/assessments/{date}-review.md

Open questions requiring your input:
- {question 1}
- {question 2}

Optional services:
  mem0: {available|not authenticated|unavailable} — {N} writes buffered to mem0-pending.md
```

## Credit Awareness

Fast.io free plan: 5,000 monthly credits across all projects. This skill should:
- Prefer `workspace/read-note` (free) over `ai/chat-create` (costs credits)
- Batch note updates to reduce re-ingestion cost
- Report approximate credit usage in the work log entry
- Warn if estimated monthly usage exceeds 4,000 credits

## Error Handling

- If a sub-skill fails, report the error and continue with remaining phases.
- If Fast.io is unreachable, report and stop — the KB is the foundation.
- If mem0 is unreachable, continue with reduced capability (no semantic recall).
- If a preferred source adapter MCP is unavailable, fall back to web search
  and note the degraded quality in the assessment.

## What This Skill Does NOT Do

- Does not modify project source code or artifacts. It produces findings only.
- Does not auto-resolve contradictions. It flags them for human decision.
- Does not run tests or validation suites.
