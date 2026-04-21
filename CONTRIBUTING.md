# Contributing to kb-system

This document covers conventions for contributing changes to kb-system.
Most of it is about **commit messages**, because for a repo whose
primary artifacts are *instructions to AI agents* the commit history
*is* the design record — far more so than for a typical code repo.

## Why commit messages matter here

kb-system is a set of Markdown skill files and documentation. There's
almost no executable code — the "behavior" lives in prose that
instructs Claude Code (or another agent harness) how to run
knowledge-base workflows. Consequences:

1. **The diff rarely tells you why.** Changing "check the tool registry"
   to "check the tool registry for data tools" is a one-line diff that
   might look cosmetic. In this repo it was a fix for an OAuth lockout
   loop with days-long consequences — context that would be lost
   without a rich commit message.
2. **AI agents themselves read this history.** When a future session
   asks "why is mem0 configured this way?" the commit message is one
   of the first things an agent surfaces. Terse messages force the
   agent to guess or re-derive.
3. **Design decisions compound.** A fix to the install layout depends
   on the earlier decision to use symlinks; that depends on the
   decision to make kb-system a standalone repo serving multiple
   consumers. Each decision is cheap to understand *in isolation* if
   written down at the time; expensive to reconstruct later.

For reference, the arc around `feat(journal): add session chain-of-
thought capture` in April 2026 produced four related commits
(`035606b`, `e1dba6a`, `dc2b066`, plus the precursor framing fixes
`c9ed5cd` and `b05eb9e`). Reading the subjects alone wouldn't tell
you what happened; reading the bodies tells the full story of a
multi-hour debugging session. That's the standard.

## The commit message template

The canonical template lives at `.gitmessage.template` in the repo
root. Structure (each section optional — omit what's empty):

```
<type>(<scope>): <subject — under ~70 chars, active voice>

## Context
What situation prompted the work? Prior state, symptoms, motivating
evidence. The "why do anything at all" section.

## Decisions
What choices were made and why? What alternatives were considered and
rejected? The "why this approach, not another" section.

## Chain of reasoning
How did we get from context to decisions? Concrete findings, logic,
evidence. The "how did we know" section.

## Implementation
Prose mirror of the diff, at "what changed where" level. The diff is
source of truth for line-level detail.

## Implications
What does this change enable, prevent, or affect downstream?
First-order (direct), second-order (indirect), third-order (systemic
/ emergent) effects when relevant. Note any required user actions
(rotate a key, restart something, run a migration).

## References
Related commits (short SHA + one-line purpose), docs paths, external
URLs.
```

## Enabling the template for your commits

Run once, in this repo:

```bash
git config commit.template .gitmessage.template
```

After that, `git commit` (without `-m`) opens your editor pre-filled
with the template. Delete sections you don't need; the instructional
comments at the bottom of the template guide when the full form is
appropriate vs when a shorter message suffices.

For one-off rich commits without enabling the template repo-wide:

```bash
git commit --template .gitmessage.template
```

## When to use the full template vs a short form

**Full template:** architectural decisions, cross-cutting fixes,
investigations where the diagnostic path is valuable, changes a
future reader will want to reconstruct. Examples from this repo's
recent history — all of these reward a full body:

- `fix: reframe canonical mem0 path as API-key HTTP MCP`
  (multi-paragraph Context explaining why prior fixes were
  incomplete, alternatives considered, 1st/2nd/3rd-order effects)
- `feat(journal): add session chain-of-thought capture`
  (explicit order-effects analysis; five labelled design decisions;
  credit cost rationale)
- `fix(install): migrate skill layout to directory-form`
  (diagnosis of a silent harness behavior; system-wide convention
  audit; required user action for migration)

**Shorter form** (subject + single-paragraph body): typos, formatting
fixes, lint-only changes, trivial config bumps, incremental commits
within a feature arc whose context is already written down in the
epic's first commit.

The template is a ceiling, not a floor. When empty sections would
outnumber filled ones, write a short paragraph instead.

## Conventional-commit subjects

Subject line follows [Conventional Commits](https://www.conventionalcommits.org):

```
<type>(<scope>): <subject>
```

Types used in this repo (in descending order of frequency):

- `fix` — bug fix or correction of a previously-merged error
- `feat` — new capability (skill, subcommand, flag, artifact class)
- `docs` — documentation-only change
- `chore` — maintenance with no user-visible effect (hash updates,
  dependency bumps)
- `refactor` — structural change without behavior change
- `test` — test-only changes

Scope is the affected subsystem: `mem0`, `install`, `journal`,
`kb-capture`, `kb-refresh`, etc. Omit the scope for cross-cutting
changes.

Subject under ~70 chars, active voice, no trailing period. "Fix
mem0 misconfigured warning" not "Fixed the mem0 misconfigured
warning that appears when…" — put the long form in the body.

## Process notes

- Create **new commits** rather than amending published ones. If
  pre-commit hooks fail, fix the underlying issue and make a fresh
  commit, never `--amend` a commit that's already on `origin`.
- Push to `main` only when the branch is stable; kb-system doesn't
  use feature branches today but may in the future.
- Include the `Co-Authored-By:` line for AI-assisted commits:
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
