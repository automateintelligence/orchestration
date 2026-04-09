#!/usr/bin/env bash
# install.sh — install the orchestration suite into a target repository.
# Usage: ./install.sh [TARGET_DIR]
#   TARGET_DIR defaults to .claude/orchestration in the current directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-.claude/orchestration}"

mkdir -p "$TARGET/scripts/lib"
TARGET_PARENT_DIR="$(cd "$(dirname "$TARGET")" && pwd)"

cp "$SCRIPT_DIR"/scripts/orchestrate-loop.sh "$TARGET/scripts/"
cp "$SCRIPT_DIR"/scripts/orchestrate-doc.sh  "$TARGET/scripts/"
cp "$SCRIPT_DIR"/scripts/dispatch.sh         "$TARGET/scripts/"
cp "$SCRIPT_DIR"/scripts/lib/orch-agent-runtime.sh "$TARGET/scripts/lib/"
cp "$SCRIPT_DIR"/scripts/review-prompt-claude.md     "$TARGET/scripts/"
cp "$SCRIPT_DIR"/scripts/review-prompt-codex.md      "$TARGET/scripts/"
cp "$SCRIPT_DIR"/scripts/review-prompt-doc-claude.md "$TARGET/scripts/"
cp "$SCRIPT_DIR"/scripts/review-prompt-doc-codex.md  "$TARGET/scripts/"

cp "$SCRIPT_DIR"/orchestration-protocol.md         "$TARGET/"
cp "$SCRIPT_DIR"/bootstrap-prompt.md               "$TARGET/"
cp "$SCRIPT_DIR"/orchestrate-doc-prompt-template.md "$TARGET/"
cp "$SCRIPT_DIR"/orchestration-state.env.example   "$TARGET/"
cp "$SCRIPT_DIR"/makefile-targets.mk               "$TARGET/"

# Register the /orchestration skill for project-local Claude Code and Codex use.
PROJECT_ROOT="$(dirname "$TARGET_PARENT_DIR")"
COMMANDS_DIR="$PROJECT_ROOT/.claude/commands"
CODEX_SKILL_DIR="$PROJECT_ROOT/.codex/skills/orchestration"
if [ -d "$SCRIPT_DIR/skills/orchestration" ]; then
  mkdir -p "$COMMANDS_DIR" "$CODEX_SKILL_DIR"
  cp "$SCRIPT_DIR"/skills/orchestration/SKILL.md "$COMMANDS_DIR/orchestration.md"
  cp -R "$SCRIPT_DIR"/skills/orchestration/. "$CODEX_SKILL_DIR/"
  echo "Registered /orchestration skill at $COMMANDS_DIR/orchestration.md"
  echo "Registered Codex orchestration skill at $CODEX_SKILL_DIR"
fi

echo "Installed orchestration suite to $TARGET"
echo "Next: run /orchestration in Claude Code or Codex to configure."
