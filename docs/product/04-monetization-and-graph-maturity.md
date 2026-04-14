# Monetization & Knowledge Graph Maturity

Specific monetization mechanisms tied to computable properties of the
knowledge graph. Defines the 5 maturity phases, 6 premium agent features
that operate over the graph, and the freemium model design.

Date: April 2026

---

## 1. Knowledge Graph Maturity as a Monetization Trigger

A knowledge base isn't equally valuable at every stage. It goes through
distinct phases, and each phase unlocks a different kind of value. The
properties that mark these transitions are computable from the graph's
structure — you don't need a human to decide "this KB is ready."

### Phase 1: Collection (no charge)

**What it looks like:** The user has added some sources. Each source is a
standalone note. There are few or no cross-references. No contradictions
have been detected because there aren't enough sources to disagree with
each other. The domain synthesis is thin — it's basically a summary of
the few sources present.

**Graph properties:**

- Source count per domain: < 8-10
- Average cross-references per source: < 1.5
- Contradiction count: 0
- Synthesis stability: never updated (only one absorption cycle)
- Connected components: multiple disconnected clusters (sources don't
  reference each other)

**Value to user:** Low. The KB is a reading list with some extracted notes.
The user could get this from a notebook.

**Charging rationale:** None. This is the free tier. You want maximum
adoption here. Every user in this phase is depositing data into the system
that feeds the aggregate intelligence layer later. Charging here kills the
flywheel before it starts.

### Phase 2: Interconnection (the KB becomes a graph)

**What it looks like:** Enough sources have been absorbed that
cross-references form naturally. Sources cite each other, extend each
other, complement each other. The graph transitions from a collection of
isolated notes to a connected structure. You can traverse from one source
to a related source to a third source and learn something you wouldn't
have learned from any individual note.

**Graph properties:**

- Source count per domain: 8-15
- Average cross-references per source: ≥ 2.5
- The graph forms a single connected component (or close to it — ≥80%
  of sources reachable from any other source)
- Average path length between any two sources: ≤ 3 hops
- Domain synthesis has been updated through ≥ 2 absorption cycles

**What's new:** The KB can now answer traversal questions. "What are the
assumptions underlying our approach, and which sources validate or
challenge each assumption?" requires walking the graph. This is
qualitatively different from reading individual notes.

**Charging rationale:** This is where a soft gate makes sense — not on the
KB itself, but on agent features that leverage the interconnected structure
(covered in §2).

### Phase 3: Contradiction Emergence (the KB becomes an oracle)

**What it looks like:** With enough sources, the system detects genuine
disagreements between authorities. Source A recommends approach X, Source B
recommends approach Y, and both are credible. The contradiction map
becomes populated. The domain synthesis now has an "Open Debates" section
that reflects real expert disagreement.

This is the single highest-value phase transition. A KB without
contradictions is a reference library. A KB with mapped contradictions is a
**decision-support system** — it tells you not just what the evidence says,
but where the evidence is contested and where your decisions carry genuine
epistemic risk.

**Graph properties:**

- Contradiction count per domain: ≥ 2
- At least one contradiction involves sources with high authority scores
  (peer-reviewed, well-cited)
- Contradictions have high betweenness centrality in the graph (they
  connect otherwise separate clusters of evidence — meaning they sit at
  decision points)
- Domain synthesis "Open Debates" section is non-empty and has been stable
  across ≥ 1 refresh cycle

**What's new:** The user can now see where expert disagreement exists and
make an informed choice rather than unknowingly picking one side. This is
the moment the KB prevents a bad decision — which is the core value
proposition.

**Charging rationale:** Strong. This is the natural "aha moment." The user
can see that the evidence is contested in a way that affects their project,
and the KB is the thing showing them that. "Your knowledge base has
identified 3 active contradictions in the authentication domain that affect
your implementation. Keep your evidence base current → [upgrade]."

### Phase 4: Synthesis Stability (the KB becomes trustworthy)

**What it looks like:** The domain synthesis has been updated through
multiple cycles. Each new source refines the synthesis slightly but doesn't
rewrite it. The consensus view has "settled" — new evidence confirms rather
than contradicts the existing understanding (or the contradictions are
mapped and stable).

**Graph properties:**

- Synthesis delta per refresh: decreasing over time (measured as edit
  distance between successive synthesis versions)
- "Consensus View" section has been stable for ≥ 2 refresh cycles
- Source coverage per sub-topic: ≥ 2 sources per sub-topic identified
  in the domain
- Gap areas are shrinking or stable (not growing)

**What's new:** The synthesis is now reliable enough to make decisions
against with confidence. It's not just "here's what a few papers say" —
it's "here's what the field broadly agrees on, here's where it disagrees,
and here's how that maps to your project." The assessment findings from
this phase carry real weight.

**Charging rationale:** Very strong. The KB is now a functioning evidence
oracle for this domain. Maintaining it (freshness, gap filling,
contradiction tracking) requires ongoing work. This is where ongoing
subscription is most natural.

### Phase 5: Temporal Depth (the KB becomes a historical record)

**What it looks like:** The KB has sources spanning multiple years. It can
show how the domain's consensus has evolved. "In 2020, the recommendation
was X. By 2023, it shifted to Y due to papers A, B, C. The current
consensus is Z."

**Graph properties:**

- Source date range spans ≥ 3 years
- At least one "supersedes" cross-reference exists (Source B obsoletes
  Source A's recommendations)
- The synthesis includes temporal markers ("as of 2024...",
  "prior to 2022...")

**What's new:** The KB can now answer "why did the best practice change?"
and "is our approach based on outdated evidence?" — questions that no
static analysis or single-shot LLM query can answer.

## 2. Premium Agent Features Over the Graph

These are capabilities that only become possible (or only become valuable)
once the KB reaches certain maturity phases. They're the natural premium
tier — you charge for intelligence over the graph, not for the graph
itself.

### Sentinel (requires Phase 2+)

**What it does:** A background agent monitors the domains in your KB for
new evidence. When it finds a new paper, blog post, or video that's
relevant to your domains, it flags it. When the new evidence contradicts
something in your synthesis, it alerts you proactively.

**Why it requires Phase 2+:** Without an interconnected graph, there's
nothing to monitor *against*. The sentinel needs existing cross-references
and synthesis to evaluate whether new evidence is relevant, confirmatory,
or contradictory.

**How it works:** Scheduled agent (daily or weekly) runs a lightweight
discovery cycle. New candidates are scored against the existing KB.
Anything that scores as "potentially contradicts existing synthesis" gets
flagged immediately rather than waiting for the next manual review.

**Monetization:** This is the clearest premium feature. Free users run
reviews manually. Paid users get continuous background monitoring. The
value proposition is: "Your KB watches for you."

### Decision Confidence Scoring (requires Phase 3+)

**What it does:** For any technical decision in your project, the system
computes a confidence score based on the state of evidence. Not "how
confident is the LLM?" — "how strong is the evidence supporting this
specific approach?"

**Inputs (all derivable from the graph):**

- Number of supporting sources for the approach
- Recency of supporting evidence (weighted by freshness)
- Authority of supporting sources (peer-reviewed > blog > tweet)
- Number and severity of contradicting sources
- Whether the domain's consensus is settled or contested
- Whether the user's specific implementation has been assessed

**Output:**

```
Decision: Use bcrypt with cost factor 12 for password hashing
Confidence: HIGH (0.87)

Supporting evidence: 4 sources (2 peer-reviewed, 1 OWASP, 1 practitioner)
Contradicting evidence: 0 sources
Consensus status: Settled (since 2021)
Recency: Most recent source is 2025
Risk factor: Low — no active debate in this sub-domain

Compare: Your previous decision (cost factor 10) scored MEDIUM (0.61)
due to 2 sources recommending ≥12 after 2023 hardware benchmarks.
```

**Why it requires Phase 3+:** The confidence score is meaningless without
contradiction data. A score that only counts supporting evidence gives
false confidence. You need to know what disagrees, not just what agrees.

**Monetization:** Per-query or included in paid tier. This is high-value
for compliance-oriented users who need to document the evidentiary basis
for decisions.

### Automatic Gap Filling (requires Phase 2+)

**What it does:** The agent analyzes the KB's structure, identifies coverage
gaps (sub-topics within a domain that have zero or insufficient sources),
and autonomously discovers and absorbs sources to fill them. The KB
improves itself without user intervention.

**How it detects gaps:**

- The domain synthesis has "Gap Areas" section entries
- Cross-references mention sources not in the KB (a source cites
  "Chen 2010" but Chen 2010 isn't absorbed)
- Sub-topics identified by the LLM in existing syntheses have < 2
  supporting sources
- The user's review checklist includes questions the KB can't answer

**Why it requires Phase 2+:** Gap detection requires enough existing
structure to define what's missing. With 3 sources, everything is a gap.
With 15 interconnected sources, the gaps are specific and fillable.

**Monetization:** Credit-consuming operation (discovery + absorption). Free
tier: gaps are identified and reported. Paid tier: gaps are automatically
filled. The user's KB grows while they sleep.

### Regression Detection (requires Phase 4+)

**What it does:** When new evidence is published that undermines the basis
for a finding the user previously acted on, the agent detects this and
re-opens the finding.

**Example:** In March, the KB recommended approach X for session management,
citing 3 papers. In July, a new paper demonstrates a vulnerability in
approach X. The agent detects that this new paper contradicts the evidence
supporting a previously-accepted finding and flags it as a regression.

**Why it requires Phase 4+:** Regression detection requires temporal
depth — the system needs to know what was recommended *when*, what the user
acted on, and what has changed since. This requires synthesis version
history and a mapping from findings to code changes.

**Monetization:** Premium feature. This is the "insurance policy" — it
protects the user from evidence decay. "Your KB is actively monitoring for
evidence that might invalidate your past decisions."

### Cross-Domain Insight Surfacing (requires Phase 2+ across multiple domains)

**What it does:** Identifies non-obvious connections between domains. "Your
rate-limiting domain and your authentication domain both reference the same
OWASP guidelines, but your implementations handle token expiry differently
in each context."

**How it works:** Graph traversal across domain boundaries, looking for
shared sources, shared claims, or contradictory implementations of the same
principle.

**Monetization:** Builder tier and above (multiple domains required).

### What-If Analysis (requires Phase 3+)

**What it does:** The user proposes a change ("what if we switched from JWT
to session tokens?") and the agent traverses the graph to synthesize what
the evidence says about the tradeoffs — pulling from multiple domains,
multiple sources, accounting for known contradictions.

**Monetization:** Credit-consuming (requires agent reasoning over the
graph). High-value for architectural decisions.

## 3. The Freemium Model

Putting this together, the monetization structure aligns naturally with
graph maturity:

| KB Phase | What's free | What's paid | Trigger |
|----------|------------|-------------|---------|
| **Phase 1** (Collection) | Everything. Build the KB, run manual reviews, see findings. | Nothing. | — |
| **Phase 2** (Interconnection) | Manual reviews, findings, synthesis reading | Sentinel, gap identification, cross-domain insights | Graph becomes connected (avg cross-refs ≥ 2.5) |
| **Phase 3** (Contradiction) | Manual reviews, contradiction viewing | Decision confidence scoring, automatic gap filling, what-if analysis | First contradictions detected with high betweenness |
| **Phase 4** (Stability) | Manual reviews | Regression detection, evidence decay alerts, compliance evidence trail | Synthesis stability across ≥ 2 cycles |

## 4. The Conversion Moment

The system can detect when a KB reaches Phase 3 — the first time it
surfaces a genuine contradiction that affects the user's project. That's
the moment the product has proven its value. The upgrade prompt writes
itself:

> *"Your evidence base just identified that two authoritative sources
> disagree about an approach your project relies on. Upgrade to track how
> this contradiction evolves and get alerted if new evidence tips the
> balance."*

This is honest monetization. You're not charging for storage or access.
You're charging for intelligence that only becomes possible once the
knowledge graph is rich enough to produce it.

## 5. The Data Flywheel Across All Users

Every free-tier user building a Phase 1-2 KB is depositing structured
source notes into the system. Across thousands of users:

- The same paper gets absorbed by hundreds of users in the same
  domain → cross-user source notes for the same paper can be compared
  to improve extraction quality
- Contradictions detected across many users' KBs in the same domain can
  be aggregated into the community contradiction map
- Gap areas that appear in many users' KBs signal what the market doesn't
  know yet
- Assessment patterns across many users reveal which best practices are
  most commonly violated

**Free users build private KBs. The aggregate of all private KBs
(anonymized) becomes the community knowledge layer. The community knowledge
layer is the data product.**

The user never pays for their own KB. They pay for the intelligence
features over it, and for access to the community knowledge layer that
their usage helped build. This is the same model as Waze: every user's
driving data is free to contribute, and the aggregate traffic map benefits
everyone.
