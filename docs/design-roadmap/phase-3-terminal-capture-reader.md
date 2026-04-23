# Phase 3 — Terminal-Capture Reader for kb-capture

**Status:** Designed 2026-04-23. Not yet implemented.
**Related skill:** `skills/kb-capture.md`
**Related ADR:** `docs/ARCHITECTURE.md` §3.4 (Session Journaling), §3.5 (Active Journaling), and the 2026-04-23 decisions-log entry on thinking-token redaction.

---

## Executive Summary

This extension adds a second distillation-source path to kb-capture: alongside the existing JSONL reader, a terminal-capture reader ingests `.typescript` (script(1)) and `.cast` (asciinema) files to recover thinking content that Claude Code 2.1.116+ silently strips from JSONL at write-time. When a terminal capture substantively fills the redaction gap, the distilled note is upgraded from `fidelity: degraded` to `fidelity: full`. The design is additive — no existing JSONL logic changes; the terminal reader runs after JSONL parsing and contributes to the same distillation prompt context.

---

## 1. Detection

**Primary convention: `~/.claude-captures/`**

The existing ARCHITECTURE.md §3.4 already recommends `~/.claude-captures/` as the capture directory and documents the filename convention `$(date +%F-%H%M%S).{typescript|cast}`. This is the canonical location.

**Why `~/.claude-captures/` beats alternatives.** A per-project directory (e.g. `.claude/captures/`) requires the user to configure capture before they know which project they will work in. A per-session directory keyed on session_id is impossible at launch time because session_id is not known until the first JSONL event is written (the session is assigned its UUID by Claude Code's runtime, not by the wrapper alias). `~/.claude-captures/` is writable without project context, which is the correct constraint at capture time.

**Session matching via timestamp overlap.** Terminal captures have no embedded session_id. Matching is purely temporal:

1. Extract the JSONL session window: `session_start = first-message timestamp`, `session_end = last-message timestamp`.
2. For each capture file in `~/.claude-captures/`:
   - `start_hint = parse timestamp from filename` (`%F-%H%M%S` pattern, e.g. `2026-04-23-143012`). This is when the `claude` binary was launched, which is always slightly before the first JSONL event.
   - `end_hint = file mtime` (when the terminal session closed).
3. A capture matches a JSONL session if: `capture_start_hint` is within a configurable tolerance (default 30 seconds) before `session_start`, AND `end_hint` is within tolerance (default 60 seconds) after `session_end`.

The "before session_start" constraint comes from the observed ordering: `script` or `asciinema` wraps the process launch, so the capture begins before the first JSONL write. The tolerances are tunable via manifest field `journal.capture_match_tolerance_sec` (default 30/60 for start/end).

**No reliable alternative heuristic is available.** Terminal captures have no structured metadata embedding session_id, cwd, or model version. mtime + filename timestamp is the only cross-reference. This is acknowledged as fragile; see Risks.

**Manifest override.** The manifest may specify `journal.capture_dir` to override the default `~/.claude-captures/`. This supports multi-user or non-standard setups without skill changes.

---

## 2. Parsing

**`.typescript` files (script(1)).** Raw byte streams: terminal output including ANSI escape codes, carriage returns (`\r`), and backspace sequences. No timestamp metadata per character.

Extraction pipeline:
1. Read file as bytes; decode as UTF-8 with replacement for malformed sequences.
2. Strip ANSI escape codes: apply the regex `\x1b\[[0-9;]*[A-Za-z]` plus OSC sequences (`\x1b\][^\x07]*\x07`).
3. Apply carriage-return / overwrite normalization: process the byte stream left-to-right, treating `\r` as "reset column to 0" and `\x08` (backspace) as "decrement column." This collapses spinner noise and progress bars.
4. After normalization, split on `\n` to produce a clean line array.
5. Apply terminal-width unwrapping: if the terminal width is detectable (from `stty size` output that sometimes appears in captures, or defaulting to 220), lines that are exactly W characters and continue semantically on the next line are concatenated.

**`.cast` files (asciinema v2).** Structured JSONL: first line is a header object (`{"version":2,"width":N,"height":M,...}`); subsequent lines are event records `[timestamp_float, event_type, data_string]` where `event_type` is `"o"` (output), `"i"` (input), or `"r"` (resize). Per-character timestamps are available.

Extraction pipeline:
1. Parse header; extract `width` for unwrapping.
2. Collect all `"o"` events in order; concatenate `data_string` values into a single byte stream.
3. Apply the same ANSI stripping, carriage-return normalization, and line splitting as `.typescript`.
4. Per-character timestamps allow approximate attribution of thinking blocks to clock time — use this to correlate with JSONL tool-call timestamps.

**Extractable signal classes, in priority order:**

| Signal class | On-screen marker | Extraction approach |
|---|---|---|
| Thinking blocks | Verbose mode italic/dim styling; "·" bullet prefix (Claude Code convention) | Lines between verbose-mode thinking delimiters; strip style codes |
| Assistant text output | Flush-left prose after a thinking block ends | Lines not matching user/tool prefixes |
| Tool calls | `Tool: {name}` prefix (verbose-mode render) | Prefix match; extract tool name + inline args |
| Tool results | Indented block following tool call | Collect until next non-indented line |
| User turns | `>` prefix or distinct color (cyan/green) | Prefix match primary; color fallback |
| Spinner / progress noise | Lines ending in `\r` before normalization | Eliminated by step 3 of CR normalization |

**On-screen markers are version-dependent.** The exact thinking delimiter is an undocumented implementation detail. Parser treats as heuristic; must report how many thinking blocks it detected and handle the zero-blocks-despite-redacted-JSONL case as ambiguous (verbose-off vs no-thinking).

---

## 3. Merge Semantics

**JSONL is authoritative for structure; terminal capture is authoritative for thinking content.**

When both sources exist:

1. **JSONL provides:** session_id, precise timestamps, tool call argument payloads (full — on-screen may truncate), tool result content, user message text, assistant text output, session metadata counts.
2. **Terminal capture provides:** thinking block text (the gap JSONL leaves), approximate ordering (using `.cast` timestamps or sequential position in `.typescript`), sanity check on assistant text.

**Cross-referencing.** Thinking blocks from terminal capture are correlated to JSONL positions by **sequence**: the Nth thinking block in the terminal corresponds to the Nth redacted thinking block in the JSONL. This ordinal correlation is reliable because both sources are strictly sequential records of the same session.

**Conflict handling.** If the terminal capture's assistant text differs from JSONL text blocks (terminal wrapping artifacts), prefer JSONL for text content. Terminal capture takes precedence only for thinking blocks.

**Merge output.** The distillation prompt context gets a new `Terminal Capture (Thinking Blocks)` section inserted between the existing empty `Thinking Blocks` section and `Tool Calls`. Each recovered thinking block is formatted identically to how JSONL thinking blocks were previously formatted — no structural change to the prompt.

---

## 4. Fidelity Tagging

**Fidelity assignment logic (precedence order):**

1. `fidelity: full` — reflexive distillation (working memory; unaffected by this extension).
2. `fidelity: full` — retrospective, pre-2.1.116 session (cleartext thinking in JSONL).
3. `fidelity: full` — retrospective, post-2.1.116 session, terminal capture present AND recovered thinking blocks ≥ 0.8 × redacted blocks.
4. `fidelity: partial` — NEW tag. Retrospective, post-2.1.116, terminal capture present, recovered count is 0 < x < 0.8 × redacted.
5. `fidelity: degraded` — retrospective, post-2.1.116, no terminal capture OR capture present but zero thinking blocks recovered.

**New front-matter fields:**

```yaml
terminal_capture_file: {filename or null}
terminal_capture_format: {typescript|cast|none}
terminal_capture_thinking_recovered: {N}
jsonl_thinking_redacted: {N}
capture_fidelity_fill_ratio: {0.0-1.0}
```

---

## 5. Edge Cases

- **Truncated captures.** Terminal killed mid-session. Detected by: `end_hint` is more than tolerance before `session_end`. Result: `fidelity: partial` regardless of fill ratio + metadata note.
- **Multiple terminals per session.** Rare but possible. Handled by: select longest file (by byte count) as primary; log others as alternates. If two overlap with non-zero thinking, higher-count wins.
- **Verbose mode off.** Zero recovered blocks is indistinguishable from genuinely-no-thinking. Tag `fidelity: degraded` with Session Metadata Note explaining.
- **Capture older than JSONL counterpart.** Clock skew. Ordinal-correlation check (N blocks vs N redacted) reveals mismatch.
- **Orphan captures.** No matching JSONL. Logged; not deleted.

---

## 6. Implementation Sketch

**Changes to `kb-capture.md`:**

- Description: add "terminal captures" to sources.
- New argument `--capture-dir` (optional path override).
- **Step 0**: extract new manifest fields `journal.capture_dir`, `journal.capture_match_tolerance_sec`, `journal.capture_fidelity_threshold`.
- **New Step 2.5: Locate Terminal Captures** (between Step 2 and Step 3). Scan-and-match algorithm from §§1-2. Produce `matched_capture` and `capture_format` per session.
- **Step 3a**: new subsection "3a.2: Parse Terminal Capture (if matched)" after JSONL parsing. Extraction pipeline from §2. Produce `terminal_thinking_blocks[]` parallel to (empty) `thinking_blocks[]`. Store parse warnings.
- **Step 3a distillation-source classification**: add 5th case "post-2.1.116 with terminal capture." Fidelity logic from §4. New front-matter fields from §4.
- **Step 3b**: front-matter template gains new fields. `fidelity: partial` as valid value.
- **Step 3d (raw dump)**: add "Terminal Capture Thinking Blocks" section to raw format.
- **Step 7 (Report)**: "Terminal captures used: {N} sessions ({M} full, {K} partial, {J} none/degraded). Orphan captures: {list}."

---

## Risks & Open Questions

**Heuristic matching brittleness.** Timestamp-window match is the sole cross-reference. Clock skew can produce false positives/negatives. 30/60s tolerances need empirical tuning; manifest override is the escape valve.

**ANSI parsing completeness.** Extraction handles common sequences but terminal output is open-ended. New Claude Code UI patterns could produce garbage. CR normalization handles current spinner case; new animations may not parse cleanly.

**Verbose-mode marker stability.** Visual format of verbose thinking is an undocumented UI detail. If Claude Code changes it, extractor silently produces zero blocks. The zero-blocks-despite-redacted handling is graceful but ambiguous.

**`fidelity: partial` is a new enum value.** Adding it is a breaking change for any downstream consumer pattern-matching on `{full|degraded}`. Phase 4 (weighted-trust retrieval) needs to handle three values when shipped.

**Open: short-circuit for reflexive distillation.** When kb-capture runs reflexively on the current session, terminal capture lookup is redundant. Should explicitly short-circuit before Step 2.5.

**Open: minimum viable verbose-mode instruction.** Terminal capture is only useful if verbose mode was on at launch. Could the shell alias inject Ctrl+O? Outside kb-capture scope; note in Scheduling Guidance.
