# Market Trajectory & Business Models

18-month forward view of the AI-enabled knowledge work landscape (through
October 2027) and four business models that monetize the accumulated
knowledge asset rather than tool access.

Date: April 2026

---

## 1. The AI Landscape in October 2027

Six trends that will compound from the current state:

### 1.1 Agents Become Persistent Actors

Today an agent starts fresh each session. Within 18 months, platforms will
ship first-class persistent agent state — scheduled tasks, background
monitoring, long-running workflows. The pattern of "agent wakes up, checks
what changed, acts, goes back to sleep" becomes standard. This is exactly
what the refresh/staleness cycle in KB System already models.

### 1.2 Multi-Agent Composition Becomes Normal

Today a user talks to one agent. By late 2027, your primary agent routinely
delegates to specialized sub-agents for specific capabilities. "Review my
code" triggers your agent to call a security review agent, an evidence
review agent, a performance review agent — each returning structured findings
that your primary agent synthesizes. The MCP protocol is the wire format.
KB System's MCP server becomes one node in a mesh of specialized agents.

### 1.3 Model Inference Costs Drop 5-10x

Sonnet-class inference that costs $3/$15 per million tokens today will be
well under $1/$5 by late 2027. Critical implication: **compute becomes
commodity; structured knowledge becomes the differentiator.** Running an LLM
against raw text is cheap. Having a curated, cited, contradiction-mapped,
continuously-updated body of domain knowledge to run it against — that's
the scarce resource.

### 1.4 "Agent as Buyer" Emerges

Agents will have budgets and the ability to procure services autonomously.
Your coding agent encounters an unfamiliar domain, checks if there's a
knowledge base available, purchases access, runs a review, and reports
back — without human intervention at the procurement step. MCP servers with
standardized billing become the "APIs that agents buy from other agents."

### 1.5 Generic Knowledge Is Worthless; Domain-Specific Knowledge Is Gold

Base models know everything and nothing. They have broad coverage and shallow
depth. The value gap is: "What does the relevant evidence specifically say
about this specific technical decision in this specific domain?" That's
structured, curated, continuously-validated domain knowledge. That's what
KB System accumulates.

### 1.6 The Compliance and Audit Trail Becomes Mandatory

As AI-generated code and AI-influenced decisions proliferate, organizations
need to demonstrate that decisions were grounded in evidence, not
hallucination. A dated, cited evidence trail — "on this date, we reviewed
this code against these sources, and the literature supports/contradicts
this approach" — becomes a regulatory and liability asset.

## 2. Implications for the Product

The previous assessment framed KB System as a tool: "pay us to review your
code." That's v1 revenue, but the wrong long-term framing. Tools get
commoditized.

The real asset is **the structured knowledge that accumulates as a byproduct
of usage.**

Every user who runs KB System contributes to a growing body of:

- Structured source notes (claims, assumptions, limitations extracted from
  thousands of sources)
- Domain syntheses (consensus views, open debates, gap areas)
- Contradiction maps (where experts disagree, on what, and which evidence
  supports each side)
- Cross-reference graphs (how sources relate to each other)
- Assessment patterns (which findings recur across different codebases)
- Domain velocity signals (how quickly knowledge changes in each domain)

No user creates this data intentionally. It's a byproduct of them getting
their reviews. But in aggregate, it's an intelligence layer that gets more
valuable with every user, every source, and every review.

## 3. Business Model 1: Domain Knowledge Marketplace

**What it is:** Package curated, continuously-updated domain knowledge bases
as purchasable assets. Not "subscribe to a tool" — "subscribe to a domain."

**Example:** "The Web Authentication Knowledge Base" — 200+ structured source
notes, synthesis documents covering JWT, OAuth, session management, password
storage, MFA. Continuously updated. New sources absorbed as they're
published. Contradictions tracked. Available as an MCP resource that any
agent can query.

**How it works:**

- Users who build private KBs do so for their own projects (private by
  default)
- KB System offers **community domain packs** — curated by a combination of
  algorithmic synthesis across users (anonymized, aggregated) and editorial
  review
- Other users (or their agents) subscribe to domain packs for instant access
  to grounded domain knowledge without building it themselves
- Domain pack subscribers get: pre-built synthesis, source inventory,
  contradiction maps, and the ability to run assessments against the curated
  KB immediately

**Revenue:** Per-domain subscription ($3-5/domain/month) or bundled into
tiers. Network effect: more users in a domain = richer KB for that domain =
more subscribers.

**Why this works in 2027:** When agents autonomously procure knowledge,
they'll buy the domain pack, not the tool subscription. The agent's
reasoning: "I need to review this auth implementation. Is there a curated
auth knowledge base I can buy access to? Yes — $5/month, 200+ sources,
continuously updated. Cheaper and faster than building my own."

## 4. Business Model 2: Evidence Oracle API

**What it is:** A query API where agents ask domain-grounded questions and
get cited answers back. Not a chatbot — a structured evidence retrieval
service.

**Example query from an agent:**

```
kb_query(
  domain: "rate-limiting",
  question: "Is fixed-window rate limiting considered secure for API
             endpoints?",
  context: "We're using a fixed 60-second window with 100
            requests/window"
)
```

**Response:**

```json
{
  "answer": "Fixed-window rate limiting has a known vulnerability at
             window boundaries...",
  "confidence": "high",
  "supporting_sources": [
    "cloudflare-2022-rate-limiting",
    "nginx-2023-best-practices"
  ],
  "contradicting_sources": [],
  "consensus": "settled - sliding window or token bucket recommended",
  "citations": [
    {
      "source": "cloudflare-2022",
      "claim": "Fixed windows allow burst attacks at boundary..."
    },
    {
      "source": "nginx-2023",
      "claim": "Token bucket provides smoother rate enforcement..."
    }
  ]
}
```

**Revenue:** Per-query pricing. Free tier for basic queries. Paid tier for
deep queries with full citations. This is the "Clearbit for technical
evidence" model — embed it into CI/CD pipelines, code review tools, planning
tools.

**Why this works in 2027:** Multi-agent systems need specialized knowledge
services. The orchestrating agent doesn't want to run a 30-minute review
cycle for a quick factual question. It wants a fast, cited answer. The Oracle
API serves that need — the knowledge equivalent of a DNS lookup.

## 5. Business Model 3: Assessment Intelligence

**What it is:** Anonymized, aggregated data about what the evidence says
across all users and domains. Not individual user data — statistical
patterns.

**Products:**

### Domain Health Index

"The authentication domain has had 3 consensus shifts in 12 months. The
cryptography domain has been stable for 4 years."

**Buyers:** Framework maintainers, security companies, technical due
diligence firms, developer education platforms.

### Common Deviation Reports

"68% of JWT implementations we've reviewed store tokens in localStorage. The
literature consensus is HttpOnly cookies."

**Buyers:** OWASP, security tool vendors, framework teams (to prioritize
default-secure configurations), insurance underwriters assessing technical
debt risk.

### Contradiction Radar

"There is active disagreement in the literature about whether
microservice-to-microservice auth should use mTLS or service mesh identity.
Here are the arguments on each side, with sources."

**Buyers:** Technical publishers (O'Reilly, InfoQ), conference organizers,
standards bodies.

### Emerging Domain Signal

"Review activity in 'LLM evaluation' increased 340% this quarter. 12 new
sources absorbed. No consensus exists yet."

**Buyers:** VCs doing technical due diligence, R&D leads deciding where to
invest.

**Revenue:** Data licensing. Annual contracts with enterprise buyers. Or a
public "State of Technical Evidence" report (like Stack Overflow's developer
survey) that drives brand authority and attracts users to the platform.

## 6. Business Model 4: Compliance Evidence Trail

**What it is:** For regulated industries (finance, healthcare, defense,
automotive), the KB System's dated assessment reports become compliance
artifacts. "On 2027-03-15, our authentication implementation was reviewed
against 47 sources, including OWASP 2027, NIST 800-63, and 12 peer-reviewed
papers. 0 critical findings, 2 important findings addressed on 2027-03-18."

**Revenue:** Enterprise licensing. Per-seat or per-project pricing. Much
higher price point ($50-200/user/month) because the buyer is
compliance/legal, not engineering.

**Why this works in 2027:** As AI-authored code becomes the norm, regulators
will require evidence that AI output was validated against authoritative
sources. The EU AI Act and similar regulations are already moving in this
direction. A continuously-maintained evidence trail is exactly what auditors
will ask for.

## 7. Revised Product Architecture

```
+-----------------------------------------------------------+
|                    Knowledge Layer                          |
|                                                            |
|  Community Domain KBs    Private User KBs    Aggregate     |
|  (curated, purchasable)  (per-user, private)  Intelligence |
|                                                            |
|  Sources -> Claims -> Syntheses -> Contradictions -> Graphs|
|                                                            |
|  This is the asset. Everything below serves it.            |
+--------------------+-------------------------+-------------+
                     |                         |
          +----------v----------+   +----------v-----------+
          |  MCP Server          |   |  Oracle API           |
          |  (Agent-to-Agent)    |   |  (Query endpoint)     |
          |                      |   |                       |
          |  kb_review           |   |  kb_query             |
          |  kb_add_source       |   |  domain_status        |
          |  kb_get_findings     |   |  contradiction_map    |
          |  kb_get_synthesis    |   |                       |
          +----------+-----------+   +----------+------------+
                     |                          |
          +----------v--------------------------v------------+
          |  Orchestration (Agent SDK)                        |
          |                                                   |
          |  Skill prompts -> Agent instructions              |
          |  Deterministic pipeline for mechanical work       |
          |  Agent reasoning for judgment work                |
          +----------+---------------------------------------+
                     |
          +----------v---------------------------------------+
          |  Storage                                          |
          |                                                   |
          |  Structured note store (Postgres + pgvector)      |
          |  Source documents (S3/R2)                          |
          |  Graph relationships (source cross-refs)           |
          |  Aggregate indices (anonymized)                    |
          +--------------------------------------------------+
```

Note the storage shift: at scale with a data-monetization model, Fast.io
is fine for v0/v1 validation, but the knowledge asset needs to live in
infrastructure you control — Postgres with pgvector for structured notes +
semantic search, S3/R2 for source documents, and a graph model for
cross-references and contradictions.

## 8. Revenue Timeline

| Phase | Time | Revenue Model | What drives it |
|-------|------|--------------|----------------|
| **v0** (validation) | Month 1-3 | Free — open MCP server | Prove the output resonates. 50-100 users. |
| **v1** (tool revenue) | Month 3-8 | Subscription + credits ($5-10/mo) | Individual users paying for private KB review |
| **v2** (knowledge marketplace) | Month 8-14 | Domain pack subscriptions ($3-5/domain/mo) | Community KBs become purchasable. Agent-to-agent commerce. |
| **v3** (intelligence products) | Month 12-18 | Data licensing + Oracle API (usage-based) | Aggregated insights sold to enterprises, tools, publishers |
| **v4** (compliance) | Month 18+ | Enterprise contracts ($50-200/user/mo) | Regulated industries buying evidence trails |

The key insight: **v1 subscription revenue is the loss leader.** It
subsidizes the data accumulation that makes v2-v4 possible. The real business
isn't "pay us $10/month to review your code." It's "we have the most
comprehensive, continuously-validated, structured body of technical domain
knowledge in the world — and agents, enterprises, and data buyers all want
access to it."

## 9. Defensibility

In 18 months, anyone can stand up an MCP server that calls Claude to review
code. The LLM is commodity. The prompt engineering is replicable. The tool
itself is not the moat.

The moat is **the accumulated knowledge graph:**

- Thousands of structured source notes with extracted claims,
  cross-references, and contradiction maps
- Hundreds of domain syntheses representing continuously-updated consensus
  views
- Assessment patterns derived from thousands of real-world reviews
- Domain velocity data that nobody else tracks
- A flywheel where every user improves the knowledge base for every other
  user in that domain

This compounds. It gets harder to replicate with every passing month. And
it gets more valuable to agents, who in 2027 will be the primary consumers
of structured knowledge.

## 10. Build Priorities

**Phase 0 (weeks 1-4):** Validate the core output. MCP server with
`kb_review` backed by Agent SDK. No billing. Open access. Goal: do 50
people use it twice?

**Phase 1 (weeks 5-12):** Tool revenue + knowledge accumulation. Add auth,
billing, private KBs. Critically: **design the storage schema for the
aggregate knowledge layer from day one.** Even if you don't monetize it yet,
every source note, every synthesis, every contradiction should be stored in
a format that supports future aggregation, anonymization, and querying.

**Phase 2 (weeks 12-20):** Domain marketplace. Curate the first 5-10
community domain packs from aggregated user data. Make them purchasable.
Test whether agents will buy domain knowledge autonomously.

**Phase 3 (weeks 20-30):** Intelligence products. Build the Oracle API.
Publish the first "Domain Health Index." Approach enterprise buyers with
compliance evidence trail packaging.

The subscription business pays the bills. The knowledge business builds the
company.
