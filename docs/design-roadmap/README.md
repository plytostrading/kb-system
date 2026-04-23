# Design Roadmap

This directory holds design documents for kb-system extensions that
are approved but not yet implemented. Each document describes a
planned change in enough detail that implementation can proceed
without re-deriving the design, but without committing to the
final prose/code until the work is scheduled.

## Current roadmap

| # | Title | Status | Design doc |
|---|-------|--------|-----------|
| 3 | Terminal-capture reader for kb-capture | Designed 2026-04-23 | [phase-3-terminal-capture-reader.md](phase-3-terminal-capture-reader.md) |
| 4 | Weighted-trust retrieval in kb-assess | Designed 2026-04-23 | [phase-4-weighted-trust-retrieval.md](phase-4-weighted-trust-retrieval.md) |

## Convention

- **Designed**: a design doc exists; implementation hasn't started.
- **In progress**: implementation branch is live.
- **Shipped**: merged; design doc becomes reference material pointing
  at the implementation.
- **Deferred**: designed but intentionally not scheduled. Reason noted.
- **Abandoned**: removed from roadmap. Reason noted.

When a phase ships, the design doc stays in this folder — it's the
archaeology record for why the shipped feature looks the way it does.
Think of it as the Design section of a commit message, but extracted
into a dedicated file when the design is complex enough to warrant
more than a commit message's body.
