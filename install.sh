#!/usr/bin/env bash
# install.sh — install the orchestration suite into a target repository.
# Usage: ./install.sh [TARGET_DIR]
#   TARGET_DIR defaults to .claude/orchestration in the current directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-.claude/orchestration}"

mkdir -p "$TARGET/scripts/lib"

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

echo "Installed orchestration suite to $TARGET"
echo "Next: paste $TARGET/bootstrap-prompt.md into a Claude or Codex session to configure."
