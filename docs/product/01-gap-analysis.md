# Product Gap Analysis

Assessment of the gap between the KB System repo and the commercial product
described in the product requirements document.

Date: April 2026

---

## 1. Current State Inventory

The repo contains **zero application code**. It is 4,026 lines of markdown,
YAML, and shell across 11 files:

| Category | Files | Lines | What it is |
|----------|-------|-------|-----------|
| Skill prompts | 5 `.md` files | 1,500 | Instructions for Claude Code (natural language, not executable code) |
| Architecture spec | 1 `.md` file | 1,132 | System design document |
| User guide | 1 `.md` file | 1,205 | Documentation |
| Manifest template | 1 `.yaml` file | 189 | Project configuration schema |
| Install script | 1 `.sh` file | 165 | Symlink creator |
| README + gitignore | 2 files | ~200 | Packaging |

The entire "product" today is a set of prompt-engineering documents that
guide Claude Code to orchestrate MCP tools against Fast.io and mem0. There
is no web UI, no API, no database, no auth, no billing, no job queue, no
ingestion pipeline — none of the infrastructure a commercial SaaS requires.

## 2. What the Repo Provides

What the repo does provide is something harder to reproduce than code: a
deeply specified domain model.

### 2.1 A Fully Specified Domain Model

The architecture doc, skill files, and manifest schema collectively define
exactly how evidence review should work — the orchestration flow, source
adapter pipeline, contradiction detection logic, assessment framework,
severity taxonomy, lint categories, staleness model, and cross-project
isolation semantics.

A team building this from scratch would spend 4-6 weeks just on design
discovery before writing code. That work is done.

### 2.2 Battle-Tested Prompt Engineering

The 1,500 lines of skill prompts encode the "judgment" layer — how to
extract claims from a paper, how to detect contradictions, how to assess
code against literature, how to write a synthesis. These are directly
portable as system prompts for the LLM calls in the product. This is the
part that's hardest to get right and took multiple iterations.

### 2.3 A Manifest Schema That Is Already the Product's Data Model

The `project`, `domains`, `source_adapters`, `mcp_servers`, and `staleness`
sections map almost 1:1 to the product's configuration surface. The schema
doesn't need redesign — it needs a UI wrapper.

## 3. Work Areas Required

### 3.1 Web Application (Frontend)

**Exists today:** Nothing.

**Required:** Project creation/management UI (replaces YAML manifest editing),
domain definition wizard, source browser, assessment report viewer, dashboard,
onboarding flow, settings, export.

**Estimate:** 8-12 weeks solo; 5-7 weeks for a two-person team.

### 3.2 Backend API & Orchestration

**Exists today:** The orchestration logic exists as natural-language
instructions in the five skill files. No executable code.

**Required:** API server, job queue for async review runs, orchestration
engine that translates skill logic into executable workflows.

**Estimate:** 10-16 weeks solo; 6-10 weeks for a two-person team.

### 3.3 Source Ingestion Pipeline

**Exists today:** Skill files describe extraction; Claude Code executes it
via MCP tools interactively. No standing ingestion service.

**Required:** Document upload (PDF, markdown, plaintext), URL scraping,
academic paper search integration, YouTube transcript extraction, Twitter
thread retrieval, structured extraction pipeline.

**What carries over:** The source adapter pattern (preferred -> fallback) and
the three-phase pipeline (discovery -> pre-processing -> extraction) are
directly implementable. The structured extraction prompts from kb-absorb are
reusable.

**Estimate:** 6-8 weeks solo; 4-5 weeks for a two-person team.

### 3.4 Storage & Data Model

**Exists today:** Fast.io accessed via MCP tools. No relational database.

**Required:** User accounts and project ownership, multi-tenant data
isolation, search (keyword + semantic), version history.

**Decision:** Keep Fast.io as the document/note layer and add Postgres for
user/project/billing metadata? Or replace Fast.io entirely with own storage
+ vector DB?

**Estimate:** 4-6 weeks (with Fast.io); 10-14 weeks (replacing Fast.io).

### 3.5 Authentication & Billing

**Exists today:** Nothing.

**Required:** User registration and auth, subscription management (Stripe),
credit system for usage-based billing, usage metering and enforcement.

**Estimate:** 3-4 weeks.

### 3.6 Scheduled Refresh & Background Jobs

**Exists today:** Nothing. Current system is entirely manual.

**Required:** Scheduled staleness checks, background job execution, job
status tracking, retry/failure handling.

**Estimate:** 3-4 weeks.

### 3.7 Onboarding & Templates

**Exists today:** The manifest template is a generic YAML file with comments.

**Required:** Guided onboarding flow, domain templates for common use cases,
pre-built search queries, "first review" experience.

**Estimate:** 2-3 weeks for flow + 1-2 weeks per batch of templates.

## 4. Total Effort Summary

| Work Area | Weeks (solo senior eng) | Weeks (2-person team) | Reuse from repo |
|-----------|------------------------|-----------------------|-----------------|
| Web frontend | 8-12 | 5-7 | None (new build) |
| Backend orchestration | 10-16 | 6-10 | Skill logic as prompts; manifest schema as data model |
| Ingestion pipeline | 6-8 | 4-5 | Adapter pattern; extraction prompts |
| Storage & data model | 4-6 | 3-4 | Fast.io integration if kept |
| Auth & billing | 3-4 | 2-3 | None (new build) |
| Background jobs | 3-4 | 2-3 | Staleness logic from kb-refresh |
| Onboarding & templates | 3-5 | 2-3 | Manifest template structure |
| **Total** | **37-55 weeks** | **24-35 weeks** | |

Roughly **6-10 months solo, or 4-6 months with a two-person team** to a
shippable v1 matching the PRD's Starter + Builder tiers.

## 5. Critical Architecture Decision

The single highest-leverage decision: how does the product execute reviews?

| Option | Build time | Per-run cost | Predictability |
|--------|-----------|-------------|----------------|
| **A: Agent SDK** — wrap skill prompts, let Claude drive | Fastest (weeks) | Highest (~$2-6/run) | Lowest |
| **B: Deterministic code + LLM at decision points** | Slowest (months) | Lowest (~$0.30-1.00/run) | Highest |
| **C: Hybrid** — code pipeline, agent for assessment | Middle | Middle (~$0.50-2.00/run) | High for pipeline, medium for assessment |

At $5/month Starter with credits, Option A's per-run cost makes the unit
economics fragile. Option B is the strongest commercially but the longest
build. Option C is likely the right answer — the skill files already
implicitly separate the "mechanical" skills (discover, refresh) from the
"judgment" skills (absorb, assess).

**Decision: Option A (Agent SDK) selected** for speed to market. Validate
the product-market fit first; optimize unit economics after.

## 6. Recommended Launch Sequence

**Phase 0 (2-3 weeks):** Validate the bet. Build a minimal wrapper around
the existing skill logic using Agent SDK. No billing, no auth. Test whether
the core output (cited, severity-ranked findings) resonates with users before
investing in infrastructure.

**Phase 1 (8-10 weeks):** Starter tier MVP. Auth, single project,
document/URL upload, deterministic discovery + ingestion, agent-powered
assessment, findings report, Stripe billing with credit metering.

**Phase 2 (6-8 weeks):** Builder tier. Multiple projects, scheduled refresh,
contradiction dashboard, all assessment modes, richer source types.

**Phase 3 (4-6 weeks):** Polish. Onboarding templates, export, domain health
dashboard, progressive disclosure of advanced features.
