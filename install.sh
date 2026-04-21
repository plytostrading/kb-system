#!/bin/bash
# =============================================================================
# KB System — Install into a consuming project
# =============================================================================
# Creates symlinks from the target project's .claude/skills/ and .claude/kb-docs/
# back to this KB system repo. Writes a .kb-link config file so the target
# project knows where the KB repo is.
#
# Usage:
#   ./install.sh /path/to/target-project
#   ./install.sh ../my-project
#
# What it creates in the target project:
#   .kb-link                              — relative path to this KB repo (from project root)
#   .claude/skills/kb-review.md           — symlink → kb-system/skills/kb-review.md
#   .claude/skills/kb-discover.md         — symlink
#   .claude/skills/kb-absorb.md           — symlink
#   .claude/skills/kb-assess.md           — symlink
#   .claude/skills/kb-refresh.md          — symlink
#   .claude/kb-docs/ARCHITECTURE.md       — symlink → kb-system/docs/ARCHITECTURE.md
#
# To refresh symlinks after moving the KB repo:
#   1. Edit .kb-link in the target project with the new relative path
#   2. Run: {kb-repo}/install.sh {target-project}
#      OR: cd {target-project} && ./scripts/kb-sync.sh
# =============================================================================

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <target-project-path>"
    echo "Example: $0 ../algobrute-engine"
    exit 1
fi

TARGET="$(realpath "$1")"
KB_ROOT="$(realpath "$(dirname "$0")")"

if [ ! -d "$TARGET" ]; then
    echo "Error: Target directory does not exist: $TARGET"
    exit 1
fi

# Relative path from project root to KB repo (stored in .kb-link)
REL_FROM_ROOT="$(python3 -c "import os; print(os.path.relpath('$KB_ROOT', '$TARGET'))")"

echo "KB System Install"
echo "  KB repo:  $KB_ROOT"
echo "  Target:   $TARGET"
echo "  Relative: $REL_FROM_ROOT"
echo ""

# Write .kb-link config file (relative from project root)
echo "$REL_FROM_ROOT" > "$TARGET/.kb-link"
echo "  ✓ .kb-link written ($REL_FROM_ROOT)"

# Create directories
mkdir -p "$TARGET/.claude/skills"
mkdir -p "$TARGET/.claude/kb-docs"

# Symlink skill files
# Claude Code's agent-skill discovery expects directory-form skills:
#   .claude/skills/<skill-name>/SKILL.md
# (NOT flat .md files directly under .claude/skills/, which are silently
# ignored by the registry.) We therefore create a subdirectory per skill
# and symlink SKILL.md inside it to the authoritative source file in the
# kb-system repo. Symlink targets are relative to the SYMLINK's parent,
# which is now one directory deeper than the flat-form layout.
SKILL_DIR="$TARGET/.claude/skills"

# Clean up legacy flat-file kb-* symlinks from older install versions.
# These files are invisible to Claude Code's skill loader but would confuse
# anyone inspecting the layout; removing them makes the migration explicit.
for legacy in "$SKILL_DIR"/kb-*.md; do
    if [ -L "$legacy" ]; then
        rm -f "$legacy"
        echo "  · removed legacy flat-form symlink: $(basename "$legacy")"
    fi
done

SKILL_COUNT=0
for skill in "$KB_ROOT"/skills/kb-*.md; do
    BASENAME="$(basename "$skill")"            # e.g. kb-capture.md
    SKILL_NAME="$(basename "$skill" .md)"      # e.g. kb-capture
    SKILL_SUBDIR="$SKILL_DIR/$SKILL_NAME"
    mkdir -p "$SKILL_SUBDIR"
    LINK="$SKILL_SUBDIR/SKILL.md"
    REL_FROM_SUBDIR="$(python3 -c "import os; print(os.path.relpath('$KB_ROOT/skills/$BASENAME', '$SKILL_SUBDIR'))")"
    rm -f "$LINK"
    ln -s "$REL_FROM_SUBDIR" "$LINK"
    SKILL_COUNT=$((SKILL_COUNT + 1))
    echo "  ✓ .claude/skills/$SKILL_NAME/SKILL.md → $REL_FROM_SUBDIR"
done

# Symlink architecture doc
DOCS_DIR="$TARGET/.claude/kb-docs"
REL_DOCS="$(python3 -c "import os; print(os.path.relpath('$KB_ROOT/docs', '$DOCS_DIR'))")"

ARCH_LINK="$DOCS_DIR/ARCHITECTURE.md"
rm -f "$ARCH_LINK"
ln -s "$REL_DOCS/ARCHITECTURE.md" "$ARCH_LINK"
echo "  ✓ .claude/kb-docs/ARCHITECTURE.md → $REL_DOCS/ARCHITECTURE.md"

# Install (or refresh) sync script. We always overwrite because its logic
# must track install.sh — if the directory-form convention ever changes
# again, stale sync scripts would silently re-create the wrong layout.
SYNC_DIR="$TARGET/scripts"
SYNC_SCRIPT="$SYNC_DIR/kb-sync.sh"
mkdir -p "$SYNC_DIR"
if [ -f "$SYNC_SCRIPT" ]; then
    echo "  · scripts/kb-sync.sh exists — overwriting with current template"
fi
cat > "$SYNC_SCRIPT" << 'SYNCEOF'
#!/bin/bash
# =============================================================================
# KB System — Refresh symlinks from .kb-link config
# =============================================================================
# Run this after editing .kb-link (e.g., after moving the KB repo).
# Reads the KB repo path from .kb-link and recreates all symlinks.
# =============================================================================

set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KB_LINK="$PROJ_ROOT/.kb-link"

if [ ! -f "$KB_LINK" ]; then
    echo "Error: .kb-link not found in $PROJ_ROOT"
    echo "Run install.sh from the KB system repo first."
    exit 1
fi

KB_REL="$(cat "$KB_LINK")"
KB_ABS="$(cd "$PROJ_ROOT" && realpath "$KB_REL" 2>/dev/null || echo "")"

if [ ! -d "$KB_ABS" ]; then
    echo "Error: KB repo not found at $KB_REL (resolved: $KB_ABS)"
    echo "Edit .kb-link with the correct relative path, then re-run."
    exit 1
fi

echo "Refreshing KB symlinks from: $KB_REL (resolved: $KB_ABS)"

# Compute relative paths from symlink locations (not project root)
SKILL_DIR="$PROJ_ROOT/.claude/skills"
DOCS_DIR="$PROJ_ROOT/.claude/kb-docs"
mkdir -p "$SKILL_DIR" "$DOCS_DIR"

REL_SKILLS="$(python3 -c "import os; print(os.path.relpath('$KB_ABS/skills', '$SKILL_DIR'))")"
REL_DOCS="$(python3 -c "import os; print(os.path.relpath('$KB_ABS/docs', '$DOCS_DIR'))")"

# Clean up any legacy flat-form symlinks from older installs.
for legacy in "$SKILL_DIR"/kb-*.md; do
    if [ -L "$legacy" ]; then
        rm -f "$legacy"
        echo "  · removed legacy flat-form symlink: $(basename "$legacy")"
    fi
done

# Re-symlink skills in directory-form (Claude Code's agent-skill convention).
for skill in "$KB_ABS"/skills/kb-*.md; do
    BASENAME="$(basename "$skill")"
    SKILL_NAME="$(basename "$skill" .md)"
    SKILL_SUBDIR="$SKILL_DIR/$SKILL_NAME"
    mkdir -p "$SKILL_SUBDIR"
    LINK="$SKILL_SUBDIR/SKILL.md"
    REL_FROM_SUBDIR="$(python3 -c "import os; print(os.path.relpath('$KB_ABS/skills/$BASENAME', '$SKILL_SUBDIR'))")"
    rm -f "$LINK"
    ln -s "$REL_FROM_SUBDIR" "$LINK"
    echo "  ✓ .claude/skills/$SKILL_NAME/SKILL.md"
done

# Re-symlink docs
rm -f "$DOCS_DIR/ARCHITECTURE.md"
ln -s "$REL_DOCS/ARCHITECTURE.md" "$DOCS_DIR/ARCHITECTURE.md"
echo "  ✓ .claude/kb-docs/ARCHITECTURE.md"

echo "Done. All symlinks refreshed."
SYNCEOF
chmod +x "$SYNC_SCRIPT"
echo "  ✓ scripts/kb-sync.sh installed"

echo ""
echo "Add these to your .gitignore if not already present:"
echo "  .kb-link"
echo "  .claude/skills/kb-*/"
echo "  .claude/kb-docs/"

echo ""
echo "Done! $SKILL_COUNT skills + architecture doc linked."
echo ""
echo "Next steps:"
echo "  1. Add the .gitignore entries above"
echo "  2. Create a project manifest: .claude/kb-projects/{name}.yaml"
echo "     (copy from $KB_ROOT/templates/manifest-template.yaml)"
echo "  3. Run: /kb-review --project {name}"
