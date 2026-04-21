# KB System

**Your AI agent forgets everything between sessions. This fixes that.**

KB System is a persistent knowledge base that gives AI coding agents (Claude Code,
etc.) a structured, growing memory of research — papers, videos, blog posts, Twitter
threads — so they can review your work against actual published knowledge instead of
just their training data.

## The Problem

AI agents are powerful but stateless. Every conversation starts from zero. If you ask
an agent to review your code against best practices, it draws on whatever it absorbed
during training — which may be outdated, incomplete, or flat-out wrong for your domain.

There's no way to say: "Here are the 30 papers, 15 YouTube talks, and 8 blog posts
that define how we think about this problem. Review my work against *those*."

And even if you could feed that context in, it would vanish the moment the conversation
ends. The next session starts from scratch. Insights get lost. Contradictions between
sources go unnoticed. The same questions get re-researched over and over.

This is especially painful for:

- **Developers** building systems that need to align with published algorithms,
  protocols, or academic research. "Does our implementation match what the literature
  actually recommends?"

- **Consultants** who accumulate domain expertise across engagements but can't
  carry that structured knowledge forward. Each project re-derives the same
  foundational understanding.

- **Researchers and analysts** synthesizing information from many sources —
  tracking what agrees, what contradicts, and what's still unknown.

- **Teams** where knowledge lives in people's heads. When someone leaves or
  context-switches, the institutional understanding degrades.

## What KB System Does

KB System gives your AI agent a **persistent, structured, literature-grounded
knowledge base** that compounds over time.

It runs as a set of skills inside Claude Code. You point it at a topic, and it:

1. **Discovers** relevant sources — academic papers, YouTube videos, blog posts,
   Twitter threads — using real APIs with web search fallback
2. **Absorbs** each source into a structured note with specific claims, assumptions,
   limitations, and cross-references to other sources
3. **Detects contradictions** between sources automatically (and never silently
   resolves them — disagreements between experts are the signal, not noise)
4. **Builds domain syntheses** — living narrative documents that summarize the
   current state of knowledge, not just a pile of individual notes
5. **Assesses** your actual project artifacts against the knowledge base —
   "your code does X, but three papers recommend Y"
6. **Persists everything** in the cloud (Fast.io) so nothing is lost between sessions.
   Every conversation picks up where the last one left off.

The knowledge base is topic-agnostic. It works for quantitative finance, machine
learning, infrastructure design, medical research, legal analysis — anything where
decisions should be grounded in published knowledge.

## How It Works

```
You: /kb-review --project my-project

KB System:
  1. Checks what's stale, what's new, what needs attention
  2. Discovers new sources via Scholar Gateway, YouTube API, Twitter API
  3. Absorbs each source → structured notes with cross-references
  4. Flags contradictions between sources
  5. Updates domain synthesis documents
  6. Reviews your project artifacts against the knowledge base
  7. Produces a prioritized findings report

Everything persists in Fast.io. Next session picks up where this one left off.
```

### What a finding looks like

```
[CRITICAL] covariance-estimation: Linear shrinkage uses fixed lambda=0.9,
but Ledoit & Wolf (2004) proves the optimal shrinkage intensity is data-dependent
and can be computed analytically. Fixed lambda ignores sample size and
dimensionality.
  → File: src/strategy/covariance.py:142
  → Source: [LW2004] "A well-conditioned estimator for large-dimensional
    covariance matrices"
  → Recommendation: Replace fixed lambda with the analytical Oracle
    Approximating Shrinkage estimator from LW2004 §3.
```

This is a real finding, grounded in a real paper, pointing at a real line of code.
Not a vague "consider using a different approach."

## Installation

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (CLI, desktop, or IDE extension)
- Python 3 (for path resolution in install script)
- A [Fast.io](https://fast.io) account (free tier: 50 GB, 5,000 credits/month)

### Install into a project

```bash
# Clone this repo alongside your project
git clone https://github.com/plytostrading/kb-system.git

# Install into your project
cd kb-system
./install.sh ../your-project
```

This creates symlinks from your project into this repo — your project gets the
skills without copying files. When KB System updates, your project gets the
changes automatically.

### Create a project manifest

```bash
cp templates/manifest-template.yaml ../your-project/.claude/kb-projects/my-project.yaml
```

Edit the manifest to define your project's **domains** (the topics you want to
build knowledge about), **search queries** (what to look for), and optionally
**code paths** (what project files to review against the literature).

### Add to .gitignore

Add these lines to your project's `.gitignore` — the symlinks are machine-local
and shouldn't be committed:

```
.kb-link
.claude/skills/kb-*/
.claude/kb-docs/
```

### Run your first review

```
/kb-review --project my-project
```

## Multi-Project Support

The system supports multiple independent projects, each with its own knowledge
base and configuration. Install into as many projects as you like:

```bash
./install.sh ../project-alpha
./install.sh ../project-beta
```

Knowledge is isolated by default — project A's sources don't leak into project B's
reviews. Cross-project knowledge sharing is available as an opt-in flag when you
want to surface relevant insights across projects.

## Credentials

The system works out of the box with just a Fast.io token. Every other credential
is optional — without it, the system falls back to web search. Each credential
you add upgrades the quality of a specific source type:

| Service | What it upgrades | Required? |
|---------|-----------------|-----------|
| Fast.io | Cloud storage for the knowledge base | Yes |
| YouTube Data API | Video discovery (search → metadata) | No — falls back to web search |
| YouTube Transcript | Video content extraction | No — falls back to page scraping |
| Twitter/X API | Thread discovery + full unrolling | No — falls back to web search |
| mem0 | Cross-session semantic memory | No — system works without it |
| Scholar Gateway | Academic paper discovery | No — falls back to web search |

## Documentation

- **[User Guide](docs/USER-GUIDE.md)** — Complete installation instructions, manifest
  reference, usage examples, troubleshooting, and command reference (Linux and macOS)
- **[Architecture](docs/ARCHITECTURE.md)** — Full system design: persistence stack,
  skill architecture, source adapter pipeline, note templates, lint categories, and
  design decisions
- **[Product Strategy](docs/product/)** — Market trajectory, MCP-native architecture,
  business models, and knowledge graph monetization design

## Contributing

- **[Contributing guide](CONTRIBUTING.md)** — commit message conventions
  (including the detailed Context / Decisions / Chain-of-reasoning /
  Implications template), when to use the full form vs a shorter form,
  and how to enable the pre-populated commit template
  (`.gitmessage.template`) in your local checkout.

## License

MIT
