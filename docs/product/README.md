# KB System — Product Strategy

Product strategy, architecture, and business model documentation for the
commercialization of KB System as an MCP-native evidence review platform.

Produced during product strategy sessions, April 2026.

## Documents

| # | Document | Summary |
|---|----------|---------|
| 1 | [Gap Analysis](01-gap-analysis.md) | Current state audit of the repo, PRD requirements mapping, 7 work areas with effort estimates, and the critical architecture decision |
| 2 | [MCP-Native Architecture](02-architecture.md) | Agent-to-agent product model, hosted MCP server design with tool/resource definitions, revised effort estimates, and credit model |
| 3 | [Market Trajectory & Business Models](03-market-trajectory-and-business-models.md) | 18-month forward view of the AI knowledge-work landscape, 4 data-monetization business models beyond subscription |
| 4 | [Monetization & Graph Maturity](04-monetization-and-graph-maturity.md) | Knowledge graph maturity phases with computable triggers, 6 premium agent features, and the freemium model design |

## Reading Order

Read in numerical order. Each document builds on the previous:

1. **Gap Analysis** establishes the baseline — what exists, what's needed, how much work
2. **Architecture** revises the delivery model — MCP-native, not web app — and collapses the build surface
3. **Market Trajectory** extends the time horizon and pivots from tool-revenue to data-revenue
4. **Monetization & Graph Maturity** provides the specific mechanisms for the data-revenue model

## Key Conclusions

- The repo contains zero application code — it is 4,026 lines of skill prompts, architecture docs, and configuration templates. The value is in the domain model and judgment logic, not code.
- The product is a **hosted MCP server**, not a web application. Distribution happens through the MCP ecosystem. The user's existing AI agent is the UI.
- The subscription business (tool access) pays the bills. The **knowledge business** (aggregated domain intelligence, contradiction maps, evidence oracles) builds the company.
- Knowledge graph maturity phases provide computable, honest monetization triggers — you charge when the graph has demonstrably earned it.
