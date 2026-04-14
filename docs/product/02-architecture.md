# MCP-Native Product Architecture

Revised architecture based on three insights: speed to market requires Agent
SDK, the product should be MCP-native (not a web app), and the distribution
model is agent-to-agent (not agent-to-human).

Date: April 2026

---

## 1. Why MCP-Native, Not Web App

The initial assessment defaulted to "build a SaaS web app" because that's
the conventional path to a commercial product. But the target user — a solo
technical builder, consultant, researcher, quant — is already sitting inside
an AI agent environment (Claude Code, Cursor, Windsurf, Claude Desktop).
They don't want to context-switch to a web app to manage their evidence
review. They want to say "review my auth implementation against the
literature" from wherever they already are.

The product isn't a web app that users visit. **The product is a hosted MCP
server that their existing agent connects to.** The "frontend" is whatever
AI interface the user already uses. The distribution channel is the MCP
ecosystem itself.

This is the API-first model. Stripe didn't start as a dashboard — it started
as an API that developers could drop into their existing workflow. The
dashboard came later to support what the API already did.

## 2. Why Not iOS

An iOS app for this product does not make sense at v1 for three reasons:

1. **Wrong interaction point.** The core action is "review my
   codebase/docs/plan against the evidence." That requires proximity to the
   artifact. You run reviews from your development environment, not your
   phone.

2. **Redundant.** Claude's iOS app already exists and supports MCP servers.
   If a user wants to check findings from their phone, they open Claude
   mobile, which is already connected to the KB System MCP server, and ask
   "what were the critical findings from my last review?" The MCP server
   returns the answer.

3. **Wrong use of build time.** iOS means Swift/React Native, App Store
   review, device testing, a separate codebase. That's months of work to
   reach users who are already reachable via the MCP protocol.

The correct answer for "mobile access" is: the MCP server is accessible from
Claude mobile (or any MCP-compatible mobile client). Mobile is free.

## 3. Product Definition

The product is three things:

### 3.1 A Hosted MCP Server

Exposes knowledge base operations as tools that any MCP-compatible client can
call.

### 3.2 Agent SDK Orchestration

When the user's agent calls `kb_review`, the MCP server spins up an Agent
SDK agent that executes the review pipeline. The five skill files become the
system prompts for these agents. The manifest becomes the agent's
configuration context.

### 3.3 A Thin Billing + Account Layer

API key provisioning, Stripe subscription, credit metering. This is the only
part that needs a web surface — and it's a single-page account dashboard, not
a full application.

## 4. MCP Server Tool Definitions

```
Tools (what the user's agent can call):

  kb_create_project    — Set up a new project with domains and queries
  kb_review            — Run a full or partial review cycle
  kb_add_source        — Add a URL/document to the evidence base
  kb_get_findings      — Retrieve assessment findings by severity
  kb_get_synthesis     — Retrieve the current domain synthesis
  kb_get_status        — Project health, staleness, pending work
  kb_refresh           — Run maintenance / flush pending data
  kb_query             — Ask an evidence-grounded question about a domain
```

## 5. MCP Server Resource Definitions

```
Resources (what the user's agent can read):

  kb://projects                          — List of projects
  kb://projects/{name}/findings          — Latest findings
  kb://projects/{name}/domains/{domain}  — Domain synthesis
  kb://projects/{name}/sources           — Source inventory
  kb://projects/{name}/contradictions    — Unresolved contradictions
```

## 6. Architecture Diagram

```
User's AI agent (Claude Code / Cursor / Claude Desktop / Claude Mobile)
    |
    |  MCP protocol (Streamable HTTP)
    v
+----------------------------------------------+
|  KB System MCP Server (hosted)               |
|                                              |
|  Tools:  kb_review, kb_add_source,           |
|          kb_get_findings, etc.               |
|                                              |
|  Auth:   API key in MCP config               |
|  Meter:  Credit deduction per tool           |
+----------------------------------------------+
|  Orchestration (Agent SDK)                   |
|                                              |
|  Skill prompts -> Agent instructions         |
|  Manifest -> Agent context                   |
|  Hybrid: deterministic pipeline for          |
|    discover/refresh, agent for               |
|    absorb/assess                             |
+----------------------------------------------+
|  Storage                                     |
|                                              |
|  Fast.io (per-user workspace)                |
|  -- or --                                    |
|  Own storage (Postgres + S3 + pgvector)      |
+----------------------------------------------+
```

## 7. User Setup

The user's entire setup is adding one entry to their MCP configuration:

```json
{
  "mcpServers": {
    "kb-system": {
      "url": "https://api.kb-system.com/mcp",
      "headers": {
        "Authorization": "Bearer kb_live_abc123..."
      }
    }
  }
}
```

No install. No CLI. No app. Their agent now has evidence review capabilities.

## 8. Revised Effort Estimate

| Work Area | What it is | Weeks (2-person) |
|-----------|-----------|-----------------|
| MCP server | Express/Fastify implementing MCP protocol, tool definitions, resource definitions | 2-3 |
| Agent SDK orchestration | Wrap skill prompts as Agent SDK agents, wire tool execution to the pipeline | 3-4 |
| Storage integration | Per-user Fast.io workspace provisioning (or own Postgres + vector store) | 2-3 |
| Auth + billing | API key management, Stripe subscriptions, credit metering per tool call | 2-3 |
| Account dashboard | Single-page web: sign up, get API key, view usage, manage billing | 1-2 |
| Landing page | Marketing site: what it does, pricing, setup instructions | 1 |
| Source ingestion | URL/PDF/document upload endpoint, YouTube transcript, Scholar search | 2-3 |
| **Total** | | **13-19 weeks** |

**3-5 months with two people.** The MCP-native model cuts roughly 40% of the
work by eliminating the web frontend, the dashboard UX, the onboarding flow,
and the report viewer — all of which the user's existing AI agent handles
natively.

## 9. Tradeoffs

### What Gets Harder

1. **Onboarding friction.** A web app can hand-hold with wizards and progress
   bars. An MCP server requires the user to know how to add an MCP server to
   their config. This limits the addressable market to people already using
   MCP-compatible tools — but that's the target user anyway.

2. **"Seeing" the product.** There's no screenshot, no dashboard, no demo
   GIF. The product is invisible — it lives inside the user's agent.
   Marketing has to sell the output (findings, contradictions, syntheses),
   not the interface.

### What Gets Easier

1. **Distribution.** MCP server registries become a free distribution
   channel. One listing = discoverable by every MCP-compatible client.

2. **Platform breadth.** Day one: works in Claude Code, Claude Desktop,
   Claude iOS, Cursor, Windsurf, and any MCP-compatible agent. One server,
   all clients.

3. **Retention.** The knowledge base compounds in the background. Switching
   cost increases naturally without lock-in tactics.

4. **Margin.** No frontend infrastructure to maintain. The user's client
   handles rendering. The server just serves data and runs agents.

## 10. Launch Sequence

**Phase 0 — Proof of signal (weeks 1-4):**
Build a minimal MCP server with `kb_review` and `kb_get_findings` backed by
Agent SDK. No billing, no auth — just an open endpoint. Give it to 10-20
people. Does the output make them want to use it again?

**Phase 1 — Starter tier (weeks 5-9):**
Add auth (API keys), billing (Stripe, $5/mo + credits), per-user storage,
`kb_add_source` for document/URL ingestion, and `kb_get_synthesis` /
`kb_get_status`. Ship to MCP directories.

**Phase 2 — Builder tier (weeks 10-14):**
Multiple projects, scheduled refresh, all assessment modes, richer source
types (YouTube, Twitter), cross-project sharing. $10/mo.

**Phase 3 — Compound (weeks 15+):**
Domain templates, community source packs, team sharing, the web dashboard
for people who want to browse their KB visually.

## 11. Credit Model per MCP Tool

| Tool | Credit cost | Why |
|------|------------|-----|
| `kb_get_findings`, `kb_get_status`, `kb_get_synthesis` | Free | Read-only, encourages engagement |
| `kb_add_source` | 1-2 credits | Ingestion + extraction |
| `kb_refresh` | 1 credit | Mostly deterministic |
| `kb_review --phase discovery` | 3-5 credits | Multi-round search |
| `kb_review --phase absorb` | 2-5 credits per source | LLM extraction |
| `kb_review --phase assess` | 5-10 credits | Full agent assessment |
| `kb_review` (full cycle) | 15-30 credits | Everything |

Starter: 50 credits/month included. Builder: 200 credits/month included.
Additional credits purchasable.
