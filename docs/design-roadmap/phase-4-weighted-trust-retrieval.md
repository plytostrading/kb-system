# Phase 4 — Weighted-Trust Retrieval in kb-assess

**Status:** Designed 2026-04-23. Not yet implemented. Depends on Phase 3 shipping because of the `fidelity: partial` enum value addition.
**Related skill:** `skills/kb-assess.md`, `skills/kb-capture.md`
**Related ADR:** `docs/ARCHITECTURE.md` §3.4, §3.5, §4.3 (assessment framework), §8 (orchestration flow).

---

## Executive Summary

kb-assess reads hot.md's "Recent Decisions" section as Layer 1 Context but treats every journal entry with equal weight regardless of how it was captured or whether the session succeeded. This doc designs a provenance-aware trust layer that scores journal entries against their front-matter and integrates those scores into kb-assess's retrieval pipeline, finding format, and mem0 promotion path.

---

## 1. Weighting Scheme

Trust score is a **product** of three independent factors, not a sum. Multiplication is correct because a failed session with full fidelity should remain low-trust, and a degraded-fidelity session that succeeded should also be penalized — neither factor should rescue the other.

```
trust(entry) = source_factor(entry) * outcome_factor(entry) * compaction_factor(entry)
```

**source_factor:**

| distillation_source | fidelity | source_factor |
|---|---|---|
| active | full | 1.00 |
| working_memory+jsonl | full | 0.90 |
| jsonl | full | 0.75 |
| jsonl | degraded | 0.40 |
| (any) | degraded | 0.40 (cap) |

Rationale: active notes were written at decision-time from live in-context reasoning; reflexive distillation reconstructs from working memory post-hoc (~0.10 gap). 0.75 for jsonl/full better reflects the reconstruction-from-transcript value gap than the initial proposal of 0.80.

**Note on `active_notes_count`:** should NOT be a direct factor in the session-level trust score. A high count raises confidence that the retrospective summary is well-anchored, but the active notes themselves already carry their own `active/full` score. Using it as a multiplier would double-count. Use instead as a soft signal during context assembly (§2).

**outcome_factor:**

| outcome | outcome_factor |
|---|---|
| success | 1.00 |
| unspecified | 0.85 |
| partial | 0.70 |
| failed | 0.30 |

`unspecified` is usually "the user didn't pass --outcome" — routine success is the prior. Setting 0.85 rather than 0.8 calibrates this better. Failed floor at 0.30 (not 0.0) acknowledges that failed-session diagnostics encode real signal about the problem space.

**compaction_factor:**

```
compaction_factor = max(0.5, 1.0 - 0.08 * max(0, compaction_events - 2))
```

Changes from initial proposal: floor raised from 0.3 to 0.5, per-event penalty lowered from 0.10 to 0.08. Even maximally compacted sessions produce successful code and decisions; 0.5 floor says "still half-weight." 0.08 per event reaches floor at ~8 events beyond threshold.

**Composite range:** 0.40 × 0.30 × 0.50 = 0.06 (minimum) to 1.00 (maximum). Working range: 0.30–1.00.

**Is this over-engineered?** Slightly, for v1. The source_factor alone captures ~80% of the signal. Ship all three but make the compaction threshold manifest-tunable (`journal.compaction_trust_threshold`, default 2).

---

## 2. Retrieval Surface Changes

**Recommended: score-annotated with budget-aware truncation.**

Four options are not mutually exclusive — correct answer combines them:

1. Score all entries at read time (not pre-computed — sub-second over 10 entries).
2. Sort by trust descending.
3. Include entries above minimum threshold (0.25), annotated with trust score.
4. Budget-aware truncation:
   - Trust ≥ 0.70 → full text
   - Trust 0.40–0.70 → title + one-line rationale only
   - Trust < 0.40 → title only, flagged as low-trust

**Why not score-then-filter?** A `failed`-outcome session with `active`/`full` scores 0.30. Dropping loses diagnostic content — which is what failed sessions produce at high fidelity.

**Why not score-then-sort alone?** Without annotation, agent has no basis to weight during reasoning.

**hot.md format change (kb-capture side):** "Recent Decisions" entries should embed trust fields inline:

```markdown
- [active|retro|retro-missed] D{N} ({date}/{sid}): {title} — {rationale}
  [trust-fields: source=active fidelity=full outcome=success compaction=0]
```

Keeps score computable from hot.md alone, preserving zero-extra-read Layer 1 design.

---

## 3. Surfacing in Findings

**Lightweight inline citation, not a standalone field.**

When a finding is substantially informed by journal context:

```
DEVIATION [Important]: {description}
Our approach: {description} — {artifact reference}
Literature recommends: {description} — [SOURCE_ID]
Journal basis: D{N} ({date}/{sid}, trust=0.85) — [active, success]
Impact: ...
```

Only emit `Journal basis` when the finding directly depends on a specific journal entry. Format: one line, trust score as bare decimal + two provenance tags.

**mem0 integration:** add `journal:trust={score}` to mem0 entries when finding has journal basis. Enables future mem0 queries to filter by trust.

---

## 4. Decision Lineage Queries

**Class A — active-note-backed:**

```
Artifact reference: {code:line or doc}
Decision lineage: journal/notes/{YYYY-MM-DD}-{sid8}-{seq:03d}-{slug}.md [active, trust=1.00]
```

**Class B — retrospective-summary-backed:**

```
Decision lineage: journal/{YYYY-MM-DD}-{sid}-distilled.md#D{N} [retro, trust={score}]
[INFERRED from retrospective distillation — reasoning may be incomplete]
```

The `[INFERRED]` flag tells reviewers: "this rests on reconstructed reasoning, not real-time." They decide whether to validate by reading the raw note or the artifact.

**Implementation:** kb-assess post-Layer-1 checks `active_notes_referenced` field (or `[active]` tag in hot.md entry). Active → `journal/notes/{filename}`. Retro → distilled-note URL with section anchor.

---

## 5. Edge Cases

**Failed-session insights: read, downweight, do NOT auto-promote to mem0.**

Modify kb-capture's insight promotion rule: exclude `failed`-outcome sessions from auto-promotion. Manual kb-note promotion remains possible. Failed entries stay in journal + hot.md with visibly low trust.

**Two entries disagreeing on a decision, active vs retrospective.**

Active wins, unconditionally. Architecture rule + trust scores reinforce. Retrospective should have been suppressed by kb-capture's coverage rule; if it wasn't, that's a kb-capture bug. kb-assess detects same-session same-decision-content conflicts → emit GAP finding: "Conflicting journal entries for session {sid}; retrospective may not have honored coverage rule."

**High missed_decisions_count — retrospective downgrade?**

No direct score penalty. `missed_decisions_count` is a quality signal for the active-journaling discipline, not for the fidelity of what the retrospective summary DID capture. Instead, feed a separate meta-signal: when count is high, kb-assess notes "journal coverage for this session is sparse; findings based on session {sid} have higher uncertainty than trust score alone implies."

**mem0-promoted insights without full front-matter.**

mem0 entries carry project tag + insight text only. Two responses:

1. At promotion time, kb-capture embeds trust in entry text: `[trust:0.85, source:active, outcome:success]`.
2. At retrieval time, mem0 entries without embedded trust get default weight 0.70 (midpoint between full and degraded). Conservative but not penalizing: promoted insight already passed selection.

---

## 6. Implementation Sketch

**New block: "Journal Trust Scoring" (after Step 0, before Layer 1):**

```
## Journal Trust Scoring

For each "Recent Decisions" entry read from hot.md, compute:
  trust = source_factor * outcome_factor * compaction_factor

source_factor: active → 1.0; working_memory+jsonl → 0.9;
               jsonl/full → 0.75; any/degraded → 0.40

outcome_factor: success → 1.0; unspecified → 0.85;
                partial → 0.70; failed → 0.30

compaction_factor: max(0.5, 1.0 - 0.08 * max(0, compaction_events - 2))

Entry rendering by trust band:
  trust >= 0.70 → full text + [trust={score}] annotation
  trust 0.40–0.70 → title + one-line rationale + [trust={score}]
  trust < 0.40 → title only + [low-trust: {source}/{outcome}]
  trust < 0.25 → exclude from context
```

**Modified Layer 1 step:** After reading hot.md, apply Journal Trust Scoring to each Recent Decisions entry. Sort descending by trust. Render into context using band rules. Replaces raw Recent Decisions section for the assessment.

**Modified Assessment Framework — Deviations format:** optional `Journal basis` field (§3). `[INFERRED]` annotation rule for retro-backed (§4).

**Modified mem0 store block:** if finding has journal basis with trust < 0.50, append `[low-trust-journal]`.

**No new Layer required.** Scoring + annotation is post-processing on already-read content. Layer 1 token budget increases ~5-10 tokens per entry (trust annotation) — negligible vs 500-token budget.

---

## Risks & Open Questions

**Risk 1 — hot.md format migration.** Inline `trust-fields` annotation doesn't exist yet. Until kb-capture is updated to write them, kb-assess falls back to default scoring (unspecified/jsonl/no-compaction → 0.75 × 0.85 × 1.0 ≈ 0.64). Safe but weighting is inert until kb-capture ships its half. Both changes must ship together OR fallback must be clearly spec'd.

**Risk 2 — score gaming.** Agents always passing `--outcome success` inflate scores. No automated defense. Mitigation: make `--outcome` visible in journal index so reviewers can spot systematic optimism.

**Risk 3 — active note fidelity assumption.** 1.00 trust for active notes assumes faithful authoring. Malformed/rushed active notes still get 1.00 if they pass write validation. kb-note's quality check (template + artifact reference) is the only backstop.

**Open 1 — cross-session trust coherence.** Same decision referenced in two sessions with different trust scores. Proposed: cite highest-trust instance with a note. Not designed here.

**Open 2 — trust decay over time.** 6-month-old high-trust entry vs yesterday's low-trust entry. Time implicitly handled by hot.md's 10-most-recent cap; not composed with trust. Future extension could multiply by recency factor.

**Open 3 — `decision_audit` mode journal weighting.** In this mode the journal IS the artifact being audited. Low-trust entries should be flagged, not downweighted. Mode-specific behavior not designed here; address when `decision_audit` is exercised against a real corpus.
