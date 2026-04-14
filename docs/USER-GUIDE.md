# KB System — User Guide

Complete installation and usage guide for Linux and macOS.

---

## Table of Contents

1. [What KB System Does](#1-what-kb-system-does)
2. [How It Works — Concepts](#2-how-it-works--concepts)
3. [Prerequisites](#3-prerequisites)
4. [Installation](#4-installation)
5. [Creating Your First Project](#5-creating-your-first-project)
6. [Writing a Project Manifest](#6-writing-a-project-manifest)
7. [Running a Knowledge Base Review](#7-running-a-knowledge-base-review)
8. [Understanding the Output](#8-understanding-the-output)
9. [Running Individual Phases](#9-running-individual-phases)
10. [Working with Multiple Projects](#10-working-with-multiple-projects)
11. [Configuring External Services](#11-configuring-external-services)
12. [Maintenance and Health Checks](#12-maintenance-and-health-checks)
13. [Moving or Reorganizing Repos](#13-moving-or-reorganizing-repos)
14. [Upgrading KB System](#14-upgrading-kb-system)
15. [Troubleshooting](#15-troubleshooting)
16. [Reference: All Commands and Flags](#16-reference-all-commands-and-flags)

---

## 1. What KB System Does

KB System is a set of AI agent skills that build and maintain a **persistent
knowledge base** grounded in published research and expert content. It gives
your AI coding agent a structured, growing memory of papers, videos, blog
posts, and social media threads so it can review your work against real
domain knowledge — not just its training data.

**Without KB System:** Every AI conversation starts from scratch. The agent
uses whatever it learned during training, which may be outdated, incomplete,
or wrong for your specific domain. Insights from one session are lost in the
next.

**With KB System:** Your agent accumulates structured knowledge over time.
It knows which papers agree with each other, which contradict, what the
consensus view is, and where the gaps are. It can compare your actual project
artifacts (code, plans, decisions) against this knowledge and produce
specific, citation-backed findings.

### Who is this for?

- **Software developers** building systems that should align with published
  algorithms, protocols, or research. Example: "Does our covariance estimator
  match what Ledoit & Wolf (2004) actually recommends?"

- **Technical consultants** who accumulate domain expertise across
  engagements. The knowledge base carries forward between projects so each
  engagement doesn't start from zero.

- **Researchers and analysts** synthesizing information from many sources.
  The system tracks agreements, contradictions, and gaps automatically.

- **Team leads** who want institutional knowledge that doesn't disappear
  when people context-switch or move on.

---

## 2. How It Works — Concepts

### The Five Skills

KB System is made up of five skills that work together. You usually don't
call them individually — the orchestrator (`/kb-review`) decides what needs
to run and invokes them in the right order.

| Skill | What it does |
|-------|-------------|
| **kb-review** | The orchestrator. Checks what's stale, decides which phases to run, invokes the other skills in sequence, and produces the final report. This is the one you call. |
| **kb-discover** | Searches for new sources — papers, videos, blog posts, tweets. Uses multiple search rounds to find cited works and fill gaps. Deduplicates against what's already in the KB. |
| **kb-absorb** | Reads each new source deeply. Extracts specific claims, assumptions, limitations. Detects contradictions with existing sources. Builds cross-references. Writes structured notes. |
| **kb-assess** | Reviews your project's artifacts (code files, design docs, plans) against the knowledge base. Produces severity-rated findings with literature citations. |
| **kb-refresh** | Maintenance. Checks staleness of each domain, runs lint across the knowledge base (orphan sources, dead references, unresolved contradictions, etc.), and flushes any buffered data. |

### The Project Manifest

All project-specific configuration lives in a single YAML file called the
**project manifest**. It defines:

- **Domains** — the topics you want to build knowledge about (e.g.,
  "covariance-estimation", "authentication-protocols", "data-pipeline-design")
- **Search queries** — what to search for when discovering new sources
- **Code paths** — which files in your project to review against the literature
- **Review checklist** — specific questions the assessment should answer
- **Source adapters** — how to discover and extract each content type
- **Staleness thresholds** — how often to re-scan for new content

The manifest lives in your project at `.claude/kb-projects/{name}.yaml` and
is version-controlled with your project code.

### Where Knowledge Is Stored

The knowledge base is stored in **Fast.io**, a cloud workspace platform with
built-in AI capabilities. Fast.io provides:

- Markdown notes with automatic RAG (Retrieval-Augmented Generation) indexing
- Semantic search across all notes
- Scoped AI chat that can answer questions about your knowledge base
- Work logging for audit trails

Each project gets its own folder in Fast.io with this structure:

```
{project-name}/
├── hot.md              — Session context (what happened last time)
├── INDEX.md            — Master index of all sources
├── sources/            — One note per absorbed source
│   ├── LW2004-shrinkage-estimator.md
│   ├── youtube-channel-video-title.md
│   └── ...
├── domains/            — One synthesis note per domain
│   ├── covariance-estimation.md
│   └── ...
└── assessments/        — Dated assessment reports
    └── 2026-04-12-initial-review.md
```

Optionally, **mem0** provides semantic working memory — a fast-recall layer
for cross-cutting insights and decisions that span multiple sources. mem0 is
not required; the system works without it.

### Assessment Modes

The manifest's `assessment_mode` field determines how the assessment skill
reviews your work:

| Mode | What it reviews | When to use |
|------|----------------|-------------|
| `code_vs_literature` | Source code files against published best practices | Default for code projects. "Does our implementation match the literature?" |
| `knowledge_synthesis` | The knowledge base itself (no project artifacts) | Building understanding of a domain. "What does the literature say?" |
| `decision_audit` | Design docs and decision records against domain knowledge | Checking past decisions. "Is decision X supported by the literature?" |
| `plan_review` | Project plans and roadmaps against literature recommendations | Planning phase. "Does our plan align with what experts recommend?" |

---

## 3. Prerequisites

### Required

| Dependency | Version | How to verify | How to install |
|-----------|---------|---------------|----------------|
| **Claude Code** | Latest | `claude --version` | See [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code). Available as CLI (`npm install -g @anthropic-ai/claude-code`), desktop app, or IDE extension. |
| **Python 3** | 3.6+ | `python3 --version` | Pre-installed on macOS. On Linux: `sudo apt install python3` (Debian/Ubuntu) or `sudo dnf install python3` (Fedora). |
| **Git** | 2.0+ | `git --version` | Pre-installed on macOS (via Xcode CLI tools). On Linux: `sudo apt install git` or `sudo dnf install git`. |
| **Fast.io account** | Free tier | Sign up at [fast.io](https://fast.io) | Free plan provides 50 GB storage and 5,000 monthly credits. |

### Optional (improve quality but not required)

| Service | What it improves | Without it |
|---------|-----------------|------------|
| mem0 account | Cross-session semantic memory | System works, just no fast insight recall between sessions |
| YouTube Data API key | Video discovery quality | Falls back to web search (less precise) |
| YouTube Transcript MCP | Video content extraction | Falls back to web page scraping (partial) |
| Twitter/X API key | Thread discovery and unrolling | Falls back to web search |
| NotebookLM MCP | YouTube pre-processing with cross-source synthesis | Skipped; uses raw transcripts |
| Scholar Gateway | Academic paper discovery | Falls back to web search |

You can start with zero optional credentials and add them incrementally
as you see value. The system degrades gracefully at every level.

---

## 4. Installation

### Step 1: Clone the KB System repo

Choose a directory alongside your projects. The KB System repo should be a
sibling to the projects it serves, though it can live anywhere on your
filesystem.

```bash
# Typical layout: ~/github/kb-system alongside ~/github/your-project
cd ~/github
git clone https://github.com/plytostrading/kb-system.git
```

### Step 2: Install into your project

From the KB System directory, run the install script pointing at your
project:

```bash
cd kb-system
./install.sh ../your-project
```

You should see output like:

```
KB System Install
  KB repo:  /home/you/github/kb-system
  Target:   /home/you/github/your-project
  Relative: ../kb-system

  ✓ .kb-link written (../kb-system)
  ✓ .claude/skills/kb-review.md → ../../kb-system/skills/kb-review.md
  ✓ .claude/skills/kb-discover.md → ../../kb-system/skills/kb-discover.md
  ✓ .claude/skills/kb-absorb.md → ../../kb-system/skills/kb-absorb.md
  ✓ .claude/skills/kb-assess.md → ../../kb-system/skills/kb-assess.md
  ✓ .claude/skills/kb-refresh.md → ../../kb-system/skills/kb-refresh.md
  ✓ .claude/kb-docs/ARCHITECTURE.md → ../../kb-system/docs/ARCHITECTURE.md
  ✓ scripts/kb-sync.sh created

Done! 5 skills + architecture doc linked.
```

**What this creates in your project:**

| File | Purpose |
|------|---------|
| `.kb-link` | Config file storing the relative path from your project root to the KB System repo. Used by the sync script. |
| `.claude/skills/kb-*.md` | Symlinks to the five skill files. Claude Code picks these up automatically. |
| `.claude/kb-docs/ARCHITECTURE.md` | Symlink to the architecture reference document. |
| `scripts/kb-sync.sh` | Convenience script to refresh all symlinks if you move the KB System repo. |

### Step 3: Update .gitignore

The symlinks and config file are machine-local (they depend on where the
KB System repo lives on your filesystem). Add these lines to your project's
`.gitignore`:

```gitignore
# KB System — symlinks from external kb-system repo (machine-local)
.kb-link
.claude/skills/kb-*.md
.claude/kb-docs/
```

### Step 4: Verify the installation

Open Claude Code in your project directory and check that the skills are
visible:

```bash
cd your-project
claude
```

You should see the `kb-review`, `kb-discover`, `kb-absorb`, `kb-assess`, and
`kb-refresh` skills available. You can verify by typing `/kb-review` — Claude
Code should recognize it as a skill.

### Step 5: Set up Fast.io

1. Go to [fast.io](https://fast.io) and create a free account.
2. Create a workspace named `shared-kb` (or any name you prefer).
3. In your workspace settings, **enable intelligence** — this turns on
   automatic RAG indexing for all notes.
4. Get your API token from the dashboard (or run `fastio auth login` if you
   have the CLI installed).
5. Add the token to your environment:

**Linux (bash/zsh):**
```bash
# Add to ~/.bashrc or ~/.zshrc:
export FASTIO_TOKEN="your-token-here"

# Then reload:
source ~/.bashrc  # or source ~/.zshrc
```

**macOS (zsh):**
```bash
# Add to ~/.zshrc:
export FASTIO_TOKEN="your-token-here"

# Then reload:
source ~/.zshrc
```

Alternatively, store credentials in a `.env` file in your project root (make
sure `.env` is in `.gitignore`):

```bash
# .env
FASTIO_TOKEN=your-token-here
```

---

## 5. Creating Your First Project

### Step 1: Copy the manifest template

```bash
mkdir -p .claude/kb-projects
cp /path/to/kb-system/templates/manifest-template.yaml \
   .claude/kb-projects/my-project.yaml
```

Replace `my-project` with a descriptive kebab-case name for your project
(e.g., `auth-system`, `data-pipeline`, `portfolio-optimization`).

### Step 2: Edit the manifest

Open `.claude/kb-projects/my-project.yaml` in your editor. The key sections
to fill in are covered in detail in Section 6 below.

### Step 3: Run your first review

```
/kb-review --project my-project
```

On the first run, the system will:
1. Detect this is a new project (no existing Fast.io folder structure)
2. Offer to create the scaffold (folders, INDEX.md, hot.md)
3. Check service connectivity and report status
4. Run discovery to find initial sources
5. Absorb discovered sources into structured notes
6. If assessment mode is `code_vs_literature`: review your code against the
   new knowledge base

The first run takes longer because there's nothing in the KB yet. Subsequent
runs are incremental — they only discover new content and re-assess when
domains go stale.

---

## 6. Writing a Project Manifest

The project manifest is the single most important file in the system. It
defines everything project-specific: what topics to research, what to search
for, what files to review, and how often to refresh.

### Minimal Working Example

Here's the smallest manifest that works:

```yaml
manifest_version: 1
content_hash: ""

project:
  name: my-api
  description: >
    REST API for user management. Knowledge base covers authentication
    best practices, rate limiting strategies, and input validation.
  workspace: shared-kb
  project_folder: my-api
  assessment_mode: code_vs_literature

domains:
  - name: authentication
    description: Token-based auth, session management, password hashing
    search_queries:
      - "best practices for JWT authentication in REST APIs"
      - "secure session management server-side"
    code_paths:
      - src/auth/
    review_checklist:
      - "Does our token handling follow OWASP recommendations?"

source_adapters:
  paper:
    discovery:
      preferred: scholar_gateway
      fallback: web_search
    extraction:
      preferred: web_fetch

  blog:
    discovery:
      preferred: web_search
    extraction:
      preferred: web_fetch

mcp_servers:
  fast_io:
    required: true
    check_tool: "workspace/read-note"
    credentials:
      - env: FASTIO_TOKEN

staleness:
  stale_days: 30
  aging_days: 7
  unreviewed_days: 30
```

### Full Manifest Reference

#### `project` section

```yaml
project:
  name: my-project           # Unique identifier (kebab-case). Used in:
                              #   - Fast.io folder naming
                              #   - mem0 tagging ([my-project] prefix)
                              #   - Work log entries
  description: >
    A paragraph describing what this knowledge base covers. Be specific
    about the domain — this helps the discovery skill write better search
    queries and helps the assessment skill understand context.
  workspace: shared-kb        # Fast.io workspace name
  project_folder: my-project  # Folder within the workspace (usually same as name)
  assessment_mode: code_vs_literature  # See Section 2 for all modes
```

#### `domains` section

Domains are the knowledge taxonomy for your project. Each domain is a topic
area that gets its own search queries, source notes, synthesis document, and
(optionally) code paths for assessment.

```yaml
domains:
  - name: authentication          # kebab-case identifier
    description: >
      What this domain covers. Be specific — this description is used by
      the discovery skill to understand what's relevant.
    search_queries:
      - "best practices for JWT authentication in REST APIs"
      - "OWASP authentication cheat sheet recommendations"
      # Tips for search queries:
      #   - Use natural language, not keyword-only queries
      #   - Include the specific technique or algorithm name
      #   - 2-4 queries per domain is usually enough
      #   - Different angles produce different results
    code_paths:                    # Only for code_vs_literature mode
      - src/auth/middleware.py
      - src/auth/tokens.py
      # Can be directories (all files) or specific files
    review_checklist:
      - "Does our token handling follow OWASP recommendations?"
      - "Is our password hashing algorithm current (not MD5/SHA1)?"
      # These become the questions the assessment skill answers
    foundational_sources:          # Optional: key references to seed the KB
      - "OWASP 2023 — Authentication Cheat Sheet"
      - "RFC 7519 — JSON Web Token (JWT)"
      # The discovery skill ensures these are in the KB
```

**How many domains?** Start with 2-4. You can split or merge later by
reorganizing the Fast.io folder structure and updating the manifest.

#### `source_adapters` section

Source adapters define how to discover and extract each type of content. The
system supports five source types: `paper`, `preprint`, `blog`, `youtube`,
and `twitter`.

```yaml
source_adapters:
  paper:
    discovery:
      preferred: scholar_gateway   # Academic search via Scholar Gateway MCP
      fallback: web_search         # Google search as fallback
    extraction:
      preferred: web_fetch         # Read the paper via URL

  youtube:
    discovery:
      preferred: youtube_api_mcp   # YouTube Data API search
      fallback: web_search_site    # "query site:youtube.com"
    pre_processing:                # Optional enrichment step
      preferred: notebooklm_mcp   # Cross-source synthesis via NotebookLM
      fallback: skip               # No pre-processing; use raw transcript
    extraction:
      preferred: youtube_transcript_mcp  # Full transcript via MCP
      fallback: web_fetch                # Scrape page (partial)
    credentials:
      youtube_api_key: env:YOUTUBE_API_KEY
    quality_threshold: 3           # 1-5 relevance score minimum
    seed_channels:                 # Optional: channels to always scan
      - "@3Blue1Brown"

  twitter:
    discovery:
      preferred: twitter_mcp
      fallback: web_search_site
    extraction:
      preferred: twitter_mcp      # Full thread unrolling
      fallback: web_fetch
    credentials:
      twitterapi_key: env:TWITTERAPI_KEY
    quality_threshold: 4           # Higher bar for tweets (noisier medium)
    seed_accounts:
      - "@expert_handle"
```

You only need to include adapters for content types you actually want. If
your project only needs papers and blog posts, omit `youtube` and `twitter`.

#### `mcp_servers` section

Declares which MCP servers the system needs and how to check them. The
orchestrator checks these on startup and reports a service status table.

```yaml
mcp_servers:
  fast_io:
    description: "Cloud KB storage"
    required: true                  # Must be available — blocks if not
    check_tool: "workspace/read-note"
    credentials:
      - env: FASTIO_TOKEN
        description: "Fast.io API token"
        how_to_get: "https://fast.io/dashboard → API Keys"

  mem0:
    description: "Semantic working memory"
    required: false                 # System works without it
    credentials:
      - env: MEM0_API_KEY
        how_to_get: "https://app.mem0.ai/dashboard → API Keys"
```

**About mem0 authentication:** mem0 uses OAuth with rate-limited auth
attempts. KB System skills **never** call authenticate automatically — they
check the tool registry for mem0 data tools (a zero-cost local check). If
mem0 is authenticated and data tools are available, they're used normally.
If not, all mem0 usage is silently skipped and writes are buffered to
`mem0-pending.md`. Authentication is always user-initiated.

#### `staleness` section

Controls how often the system recommends re-scanning for new content:

```yaml
staleness:
  stale_days: 30     # After 30 days without discovery: domain is STALE
                     # → full cycle: discovery + absorb + assess
  aging_days: 7      # After 7 days: domain is AGING
                     # → discovery scan (absorb + assess only if new sources found)
  unreviewed_days: 30 # After 30 days without assessment: domain is UNREVIEWED
                     # → assessment only (no new discovery)
```

For fast-moving domains, lower these thresholds. For stable fields, raise
them.

---

## 7. Running a Knowledge Base Review

### The basic command

```
/kb-review --project my-project
```

This is the primary entry point. It:

1. **Loads your manifest** and checks it against the cloud copy in Fast.io
2. **Checks service connectivity** — reports which services are available,
   which are using fallbacks, and which are in lazy-auth mode
3. **Evaluates staleness** — determines which domains need attention
4. **Presents a plan** and asks for confirmation before proceeding
5. **Runs sub-skills** in order: refresh → discover → absorb → assess
6. **Updates the hot cache** so the next session knows what happened
7. **Produces a final report** with findings, open questions, and statistics

### What to expect on first run

The first run for a new project will look something like this:

```
KB System — Service Status
Project: my-project

  ✓ Fast.io         — connected (workspace: shared-kb)       [REQUIRED]
  ◌ mem0            — lazy (will try on first use)           [optional, lazy]
  ✓ Scholar Gateway — connected                              [optional]

Services available: 2/3 (1 lazy)

Project: my-project
Domain Status:
  authentication: EMPTY (no sources absorbed) → discovery + absorb + assess

Proceed? [y/n]
```

After confirmation, the system runs through discovery, absorption, and
assessment. This can take several minutes on the first run depending on
how many sources are found.

### What to expect on subsequent runs

Subsequent runs are incremental. The system checks staleness and only runs
phases that are needed:

```
Project: my-project
Domain Status:
  authentication: CURRENT (last discovery: 2026-04-10, assessment: 2026-04-10) → skip
  rate-limiting:  AGING (last discovery: 2026-04-05) → discovery scan
  validation:     STALE (last discovery: 2026-03-01) → full cycle

Proceed? [y/n]
```

---

## 8. Understanding the Output

### The Final Report

After a review completes, you get a report like this:

```
KB Review Complete — 2026-04-12
Project: my-project

Domains reviewed: authentication, rate-limiting
Sources: 18 total in KB, 4 new this session
Findings: 1 critical, 3 important, 5 informational

Top findings:
1. [CRITICAL] authentication: JWT tokens stored in localStorage without
   HttpOnly flag — OWASP recommends HttpOnly cookies to prevent XSS
   token theft
   → src/auth/tokens.ts:42
   → Source: [OWASP2023] Authentication Cheat Sheet §4.2

2. [IMPORTANT] rate-limiting: Fixed-window rate limiter is vulnerable
   to burst attacks at window boundaries — literature recommends
   sliding window or token bucket
   → src/middleware/rateLimiter.ts:18
   → Source: [Cloudflare2022] "Rate limiting best practices"

3. [IMPORTANT] authentication: Password hashing uses bcrypt with
   cost factor 10, which is below the 2024 recommendation of 12+
   → src/auth/passwords.ts:7
   → Source: [OWASP2023] Password Storage Cheat Sheet

Full assessment: my-project/assessments/2026-04-12-review.md

Open questions requiring your input:
- Should we migrate from localStorage to HttpOnly cookies? (affects
  client-side auth flow)
- Rate limiter change requires Redis — is that acceptable?
```

### Severity Levels

| Severity | Meaning | Action needed |
|----------|---------|---------------|
| **Critical** | Your implementation directly contradicts published best practices in a way that could cause real harm (security vulnerabilities, data correctness issues, etc.) | Address promptly |
| **Important** | Your implementation deviates from literature recommendations, but may be intentional or have mitigating factors | Review and decide |
| **Informational** | Literature suggests improvements or alternatives, but current approach isn't wrong | Consider for future work |

### Source Notes

Each absorbed source gets a structured note in Fast.io. Source notes contain:

- **Key Claims** — specific, falsifiable statements from the source (not
  vague summaries). For YouTube sources: includes timestamps.
- **Assumptions & Limitations** — what the source takes for granted
- **Methodology** — how the source arrived at its conclusions
- **Relevance to Our Project** — how specific claims map to your artifacts
- **Actionable Recommendations** — what you should do or check
- **Cross-References** — relationships to other sources (extends, contradicts,
  complements, supersedes, cites)
- **Contradictions** — flagged when this source disagrees with existing sources

### Domain Syntheses

Each domain gets a synthesis note — a living narrative document that
summarizes the current state of knowledge. It includes:

- **Consensus View** — what the literature broadly agrees on
- **Open Debates** — where sources disagree (with citations for both sides)
- **Recommendations for Our Project** — synthesis-level guidance
- **Contradictions** — unresolved disagreements between sources
- **Gap Areas** — topics the KB doesn't cover yet

Domain syntheses are updated automatically after each absorption cycle.

---

## 9. Running Individual Phases

You don't always need a full review. Use the `--phase` flag to run a
specific phase:

### Discovery only

Find new sources without absorbing or assessing:

```
/kb-review --project my-project --phase discovery
```

Useful when you want to see what's out there before committing to a full
review cycle.

### Absorption only

Absorb pending sources that were discovered but not yet processed:

```
/kb-review --project my-project --phase absorb
```

Useful after manually adding source URLs to INDEX.md or after a previous
discovery that you didn't absorb immediately.

### Assessment only

Re-run the assessment against the current knowledge base without new
discovery:

```
/kb-review --project my-project --phase assess
```

Useful after making code changes and wanting to re-check against the
literature.

### Refresh/lint only

Run maintenance checks without discovery or assessment:

```
/kb-review --project my-project --phase refresh
```

### Scoping to specific domains

Combine `--phase` with `--scope` to target a single domain:

```
/kb-review --project my-project --phase assess --scope authentication
```

### Force a full run

Skip staleness checks and run everything regardless of freshness:

```
/kb-review --project my-project --force
```

---

## 10. Working with Multiple Projects

KB System supports multiple independent projects from a single installation.

### Installing into multiple projects

```bash
cd kb-system
./install.sh ../project-alpha
./install.sh ../project-beta
./install.sh ../project-gamma
```

Each project gets its own set of symlinks, its own manifest, and its own
folder in Fast.io.

### Isolation by default

Projects are completely isolated:
- Fast.io searches are scoped to the project's own folder
- mem0 queries include the project name tag, so only that project's
  insights are returned
- No cross-contamination between unrelated projects

### Cross-project knowledge sharing

Sometimes projects share overlapping domains. For example, two different
APIs might both need to know about authentication best practices.

Enable cross-project sharing with the `--cross-project` flag:

```
/kb-review --project project-alpha --cross-project
```

When enabled:
- Fast.io searches expand to the entire workspace (all projects)
- mem0 queries omit the project tag, surfacing insights from all projects
- The assessment report notes any relevant findings from other projects

This is opt-in per invocation — you choose when cross-pollination is useful.

---

## 11. Configuring External Services

### Fast.io (required)

Fast.io is the only required service. Without it, nothing works.

**Setup:**
1. Create a free account at [fast.io](https://fast.io)
2. Create a workspace (e.g., `shared-kb`)
3. Enable intelligence on the workspace (Settings → Intelligence → On)
4. Get your API token: Dashboard → API Keys

**Environment variable:** `FASTIO_TOKEN`

**Free tier limits:** 50 GB storage, 5,000 monthly credits. The KB System
is designed to be credit-conscious — it prefers free operations
(`workspace/read-note`) over credit-consuming ones (`ai/chat-create`).

### mem0 (optional — semantic memory)

mem0 provides fast semantic recall of cross-cutting insights between sessions.
Without it, the system still works — it just doesn't have a quick-recall
layer for "what did we learn about X across all sources?"

**Setup:**
1. Create an account at [app.mem0.ai](https://app.mem0.ai)
2. Go to Dashboard → API Keys
3. Create a new key

**Environment variable:** `MEM0_API_KEY`

**Note on authentication:** mem0 uses OAuth with rate-limited auth
attempts. KB System skills **never** attempt to authenticate automatically
— they check the tool registry for data tools (a zero-cost local check).
If mem0 hasn't been authenticated by the user, all mem0 usage is silently
skipped and writes are buffered to Fast.io (`mem0-pending.md`). To
authenticate, use the mem0 MCP server's authenticate flow manually. Once
authenticated, skills will detect the data tools and use mem0 normally.

### Scholar Gateway (optional — academic papers)

Scholar Gateway provides semantic search over academic literature. It's
available as a Claude.ai integration — no API key needed.

**Setup:**
1. In Claude.ai settings, connect the Scholar Gateway integration
2. Complete the OAuth flow once

The Scholar Gateway MCP tools become available automatically in Claude Code
after connecting.

### YouTube Data API (optional — video discovery)

Improves video discovery quality compared to web search fallback.

**Setup:**
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a project (or use an existing one)
3. Enable "YouTube Data API v3"
4. Create Credentials → API Key

**Environment variable:** `YOUTUBE_API_KEY`

**Free tier:** 10,000 units/day (a search costs ~100 units, so ~100
searches/day).

### YouTube Transcript MCP (optional — video extraction)

Extracts full transcripts from YouTube videos for deep absorption.

**Setup:** Install the YouTube Transcript MCP server in your Claude Code
configuration. No API key required — it uses `yt-dlp` locally.

### NotebookLM (optional — YouTube pre-processing)

Provides citation-backed cross-source synthesis for YouTube content. Most
valuable for long-form content (>15 min) and multi-video domain batches.

**Setup options:**

- **Community MCP (via Google Cookies):** Export your Google account cookies
  using a browser extension. Set the `GOOGLE_COOKIES` environment variable.
  See the [notebooklm-mcp README](https://github.com/PleasePrompto/notebooklm-mcp)
  for format details.

- **Enterprise API (via gcloud):** Run `gcloud auth login` with an Enterprise
  tier subscription. Uses OAuth, not env vars.

### Twitter/X API (optional — tweet discovery and threads)

Enables searching for tweets and unrolling full threads.

**Setup:**
1. Go to [twitterapi.io](https://twitterapi.io)
2. Sign up and go to Dashboard → API Key

**Environment variable:** `TWITTERAPI_KEY`

**Cost:** ~$0.15 per 1,000 API calls (separate from Fast.io credits).

---

## 12. Maintenance and Health Checks

### Automatic maintenance

The `kb-refresh` skill runs automatically at the start of every
`/kb-review` invocation. It checks:

1. **Staleness** — which domains need new discovery
2. **Lint** — 9 categories of knowledge base health issues

### Lint categories

| # | Category | What it catches | Severity |
|---|----------|----------------|----------|
| 1 | Orphan sources | Source notes with zero cross-references | Warning |
| 2 | Dead references | Cross-references to non-existent source IDs | Error |
| 3 | Unresolved contradictions | Flagged contradictions awaiting human decision | Warning |
| 4 | Missing sources | Domain syntheses citing sources not in the KB | Error |
| 5 | Incomplete metadata | Source notes missing required fields | Warning |
| 6 | Empty sections | Source notes with placeholder content | Warning |
| 7 | Stale index | INDEX.md out of sync with actual files | Error |
| 8 | Stale syntheses | Domain synthesis not updated after new sources | Warning |
| 9 | Pending mem0 queue | Buffered mem0 writes awaiting flush | Info/Warning |

### Running lint manually

```
/kb-review --project my-project --phase refresh
```

### Auto-fixing lint issues

Some issues can be fixed automatically:

```
/kb-refresh --project my-project --fix
```

Auto-fixable issues include: dead references (adds missing sources to INDEX
as pending), incomplete metadata (fills from note content), and stale index
entries (syncs INDEX with actual files).

Issues that require human judgment (orphan sources, unresolved contradictions,
empty sections) are reported but not auto-fixed.

### Flushing the mem0 pending queue

If mem0 was unavailable during previous sessions, insights are buffered in
Fast.io. To flush them:

```
/kb-refresh --project my-project --flush-mem0
```

This attempts to reconnect to mem0 and push all buffered entries. If mem0 is
still unavailable, it reports the queue size and skips.

---

## 13. Moving or Reorganizing Repos

### Moving the KB System repo

If you move the KB System repo to a different directory:

**Option A — Re-run install from the new location:**

```bash
cd /new/path/to/kb-system
./install.sh /path/to/your-project
```

**Option B — Edit the config and sync:**

```bash
cd your-project
# Update .kb-link with the new relative path
echo "../new/path/to/kb-system" > .kb-link
# Refresh all symlinks
./scripts/kb-sync.sh
```

### Moving your project

If you move your project directory, the symlinks will break (they use
relative paths). Re-run the install script:

```bash
cd kb-system
./install.sh /new/path/to/your-project
```

### Verifying symlinks

To check that symlinks are pointing to the right place:

```bash
ls -la .claude/skills/kb-*.md
ls -la .claude/kb-docs/ARCHITECTURE.md
```

Each symlink should show a valid relative path that resolves to a file in
the KB System repo. If any show as broken (red on most terminals), re-run
install or sync.

---

## 14. Upgrading KB System

KB System uses symlinks, so upgrading is just a `git pull`:

```bash
cd kb-system
git pull origin main
```

Because your project's `.claude/skills/kb-*.md` files are symlinks pointing
into the KB System repo, they automatically pick up the new versions. No
re-install needed.

If a new version adds files that didn't exist before (e.g., a new skill),
re-run the install script to create the new symlinks:

```bash
./install.sh ../your-project
```

---

## 15. Troubleshooting

### "Skills not found" in Claude Code

**Symptom:** `/kb-review` isn't recognized as a skill.

**Check:**
```bash
ls -la .claude/skills/kb-*.md
```

If the symlinks are broken or missing, re-run the install:
```bash
cd /path/to/kb-system
./install.sh /path/to/your-project
```

### "Fast.io not connected"

**Symptom:** The service status shows Fast.io as unavailable.

**Check:**
1. Is `FASTIO_TOKEN` set? `echo $FASTIO_TOKEN`
2. Is the token valid? Try `fastio auth check` if you have the CLI
3. Does the workspace exist? Check at [fast.io](https://fast.io)

### "mem0 not authenticated" on every run

**Symptom:** mem0 always shows as "not authenticated" in the service status.

**Cause:** mem0 uses OAuth. The skills check for mem0 data tools in the
tool registry — if only `authenticate`/`complete_authentication` tools
exist, mem0 hasn't completed its OAuth flow.

**Fix:** Authenticate mem0 manually. Ask Claude Code to run the mem0
authentication flow, then complete it in your browser. Once done, mem0
data tools will appear and skills will use them automatically.

**Note:** Skills never call authenticate automatically — this prevents the
account lockouts that occur with rate-limited OAuth. Authentication is
always user-initiated.

### Symlinks break after git pull

**Symptom:** After pulling changes in your project, the KB skill symlinks
break.

**Cause:** Git doesn't follow symlinks. If someone else committed the
symlinks (which shouldn't happen — they should be gitignored), pulling
can overwrite them.

**Fix:**
```bash
./scripts/kb-sync.sh
```

### Discovery finds nothing

**Symptom:** `/kb-review --phase discovery` reports zero new sources.

**Check:**
1. Are your search queries specific enough? Vague queries produce irrelevant
   results that get filtered out.
2. Is the quality threshold too high? Check `quality_threshold` in
   your source adapters (default: 3, range: 1-5).
3. Are you using the right adapters? If Scholar Gateway isn't connected,
   paper discovery falls back to web search, which may miss academic papers.

### Assessment produces no findings

**Symptom:** The assessment says everything is fine, but you expected findings.

**Check:**
1. Are `code_paths` correct in the manifest? The assessment can only review
   files it can find.
2. Are there enough sources in the KB? Assessment compares your code against
   the knowledge base — if the KB is thin, there's less to compare against.
3. Is the assessment mode correct? `knowledge_synthesis` mode doesn't review
   code at all.

### Install script fails with "python3 not found"

**Fix (Linux):**
```bash
sudo apt install python3    # Debian/Ubuntu
sudo dnf install python3    # Fedora/RHEL
```

**Fix (macOS):**
```bash
# Python 3 comes with Xcode command line tools
xcode-select --install

# Or install via Homebrew
brew install python3
```

---

## 16. Reference: All Commands and Flags

### `/kb-review` — The main command

```
/kb-review --project <name> [options]
```

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--project` | manifest name | *(auto if only one)* | Which project to review |
| `--scope` | `all`, domain name(s) | `all` | Limit to specific domains (comma-separated) |
| `--phase` | `all`, `discovery`, `absorb`, `assess`, `refresh` | `all` | Run only a specific phase |
| `--force` | *(flag)* | off | Skip staleness checks, run everything |
| `--cross-project` | *(flag)* | off | Enable cross-project knowledge sharing |

**Examples:**

```bash
# Full review of all domains
/kb-review --project my-api

# Discovery only, single domain
/kb-review --project my-api --phase discovery --scope authentication

# Force full re-assessment
/kb-review --project my-api --phase assess --force

# Cross-project knowledge sharing
/kb-review --project my-api --cross-project
```

### `/kb-refresh` — Maintenance

```
/kb-refresh --project <name> [options]
```

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--project` | manifest name | required | Which project |
| `--scope` | `all`, domain name(s) | `all` | Limit to specific domains |
| `--fix` | *(flag)* | off | Auto-fix issues where possible |
| `--lint-only` | *(flag)* | off | Skip staleness check, run lint only |
| `--flush-mem0` | *(flag)* | off | Attempt to flush pending mem0 writes |

### `/kb-discover` — Discovery

```
/kb-discover --project <name> [options]
```

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--project` | manifest name | required | Which project |
| `--scope` | `all`, domain name(s) | `all` | Limit to specific domains |
| `--cross-project` | *(flag)* | off | Deduplicate across all projects |

### `/kb-absorb` — Absorption

```
/kb-absorb --project <name> [options]
```

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--project` | manifest name | required | Which project |
| `--scope` | `all`, domain name(s) | `all` | Limit to specific domains |
| `--source` | source ID | *(none)* | Absorb a specific source by ID |

### `/kb-assess` — Assessment

```
/kb-assess --project <name> [options]
```

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--project` | manifest name | required | Which project |
| `--scope` | `all`, domain name(s) | `all` | Limit to specific domains |
| `--cross-project` | *(flag)* | off | Surface insights from other projects |
