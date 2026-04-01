#!/bin/bash
# =============================================================================
# Orchestration Dispatch Helper
# Used by Claude (orchestrator) to dispatch tasks to Codex and Claude Code
# See .claude/orchestration/orchestration-protocol.md for full protocol
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/orch-agent-runtime.sh"
orch_resolve_paths "$SCRIPT_DIR"
PROJECT_ROOT="$ORCH_PROJECT_ROOT"
REVIEWS_DIR="$PROJECT_ROOT/planning/reviews"
TEMPLATES_DIR="$SCRIPT_DIR"
DEFAULT_SPECS="${ORCH_SPECS:-specs}"
CODEX_MODEL="${CODEX_MODEL:-}"
GIT_REMOTE="${GIT_REMOTE:-github}"
STATE_DIR="/tmp/orch-dispatch-$$"

cleanup_dispatch() {
    rm -rf "$STATE_DIR" 2>/dev/null || true
}
trap cleanup_dispatch EXIT

mkdir -p "$REVIEWS_DIR"

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  codex-implement   <plan-file> <branch> [specs-path]  Dispatch Codex to implement
  codex-review      <branch> [plan-file] [specs-path]  Dispatch Codex to review
  implement         <plan-file> <branch> [specs-path] [agent]  Default implementer dispatch (agent: codex|claude, default codex)
  claude-implement  <plan-file> <branch> [specs-path]  Dispatch Claude Code to implement (override)
  claude-review     <branch> [plan-file] [specs-path]  Dispatch Claude Code to review
  check-branch      <branch>                           Check latest commits
  status                                               Show state

Environment:
  ORCH_SPECS    Default specs directory (default: specs)
  GIT_REMOTE    Git remote name (default: github)
  CODEX_MODEL   Model override for Codex CLI

EOF
    exit 1
}

# --- TEMPLATE RENDERING ---

render_review_prompt() {
    local template_file="$1"
    local branch="$2"
    local plan_file="$3"
    local specs="$4"
    local review_file="$5"

    if [ ! -f "$template_file" ]; then
        echo "ERROR: Review template not found: $template_file" >&2
        exit 1
    fi

    # Get commit range for the review
    local commit_range
    commit_range=$(cd "$PROJECT_ROOT" && git log --oneline -10 "$branch" 2>/dev/null | head -1 | cut -d' ' -f1)
    commit_range="main..${branch} (latest: ${commit_range})"

    local prompt
    prompt=$(cat "$template_file")
    prompt="${prompt//\{BRANCH\}/$branch}"
    prompt="${prompt//\{PLAN_FILE\}/$plan_file}"
    prompt="${prompt//\{SPECS\}/$specs}"
    prompt="${prompt//\{REVIEW_FILE\}/$review_file}"
    prompt="${prompt//\{COMMIT_RANGE\}/$commit_range}"

    echo "$prompt"
}

# --- AGENT BOOTSTRAP ---

build_agent_bootstrap() {
    local branch="${1:-}"
    local specs="${2:-$DEFAULT_SPECS}"

    cat <<BOOTSTRAP

## Agent Bootstrap Context
- **Project root**: $PROJECT_ROOT
- **Suite layout**: \`$ORCH_SUITE_LAYOUT\`
- **Guidelines**: Read \`AGENTS.md\` and \`.claude/CLAUDE.md\` when present
- **Git remote**: \`${GIT_REMOTE}\` (NOT origin)
- **Git branch**: \`${branch}\`
- **Commit format**: \`<files-changed> -- <description>\`

### Project Map
- \`.claude/\` -- Claude Code configuration and orchestration scripts
- \`src/\` -- Source code
- \`tests/\` -- Test suites
- \`docs/\` -- Documentation
- \`specs/\` -- Specifications and plans
- \`planning/\` -- Planning documents and reviews
BOOTSTRAP
}

# --- DISPATCH FUNCTIONS ---

codex_implement() {
    local plan_file="$1"
    local branch="$2"
    local specs="${3:-$DEFAULT_SPECS}"
    cd "$PROJECT_ROOT"

    local model_flag=""
    [[ -n "$CODEX_MODEL" ]] && model_flag="-m $CODEX_MODEL"

    local bootstrap
    bootstrap=$(build_agent_bootstrap "$branch" "$specs")

    local prompt_file="$STATE_DIR/codex-impl-prompt.md"
    mkdir -p "$STATE_DIR"
    cat > "$prompt_file" <<PROMPT
${bootstrap}

## Task
Read and implement the plan at $plan_file.
Work on branch $branch.
Follow .codex/ prompts and $specs specifications.
Commit locally using: git add <specific-files> && git commit -m '<files-changed> -- <description>'
Do NOT push unless the operator explicitly asks for it.
One task per commit; do not batch tasks.
Do NOT edit tasks.md; the orchestrator owns task-state mutation.
PROMPT

    orch_run_agent_direct codex "$prompt_file" "$PROJECT_ROOT"
}

codex_review() {
    local branch="$1"
    local plan_file="${2:-$DEFAULT_SPECS/plan.md}"
    local specs="${3:-$DEFAULT_SPECS}"
    local review_file="$REVIEWS_DIR/${branch//\//-}-codex-review-$(date +%Y%m%d-%H%M%S).md"

    cd "$PROJECT_ROOT"

    local prompt
    prompt=$(render_review_prompt "$TEMPLATES_DIR/review-prompt-codex.md" "$branch" "$plan_file" "$specs" "$review_file")

    local model_flag=""
    [[ -n "$CODEX_MODEL" ]] && model_flag="-m $CODEX_MODEL"
    codex exec review "$prompt" --full-auto $model_flag
}

claude_implement() {
    local plan_file="$1"
    local branch="$2"
    local specs="${3:-$DEFAULT_SPECS}"
    local model="${4:-}"

    cd "$PROJECT_ROOT"
    local model_flag=""
    [[ -n "$model" ]] && model_flag="--model $model"

    local bootstrap
    bootstrap=$(build_agent_bootstrap "$branch" "$specs")

    local prompt_file="$STATE_DIR/claude-impl-prompt.md"
    mkdir -p "$STATE_DIR"
    cat > "$prompt_file" <<PROMPT
${bootstrap}

## Task
Read and implement the plan at $plan_file.
Work on branch $branch.
Follow .claude/CLAUDE.md guidelines and $specs specifications.
Commit locally using: git add <specific-files> && git commit -m '<files-changed> -- <description>'
Do NOT push unless the operator explicitly asks for it.
One task per commit; do not batch tasks.
Do NOT edit tasks.md; the orchestrator owns task-state mutation.
PROMPT

    orch_run_agent_direct claude "$prompt_file" "$PROJECT_ROOT"
}

claude_review() {
    local branch="$1"
    local plan_file="${2:-$DEFAULT_SPECS/plan.md}"
    local specs="${3:-$DEFAULT_SPECS}"
    local review_file="$REVIEWS_DIR/${branch//\//-}-claude-review-$(date +%Y%m%d-%H%M%S).md"

    cd "$PROJECT_ROOT"

    local prompt
    prompt=$(render_review_prompt "$TEMPLATES_DIR/review-prompt-claude.md" "$branch" "$plan_file" "$specs" "$review_file")

    local prompt_file="$STATE_DIR/claude-review-prompt.md"
    mkdir -p "$STATE_DIR"
    orch_write_prompt_file "$prompt_file" "$prompt"
    orch_run_agent_direct claude "$prompt_file" "$PROJECT_ROOT"
}

implement_default() {
    local plan_file="$1"
    local branch="$2"
    local specs="${3:-$DEFAULT_SPECS}"
    local agent="${4:-codex}"

    case "$agent" in
        codex)  codex_implement "$plan_file" "$branch" "$specs" ;;
        claude) claude_implement "$plan_file" "$branch" "$specs" ;;
        *)
            echo "Error: implement agent must be 'codex' or 'claude' (got: $agent)" >&2
            return 1
            ;;
    esac
}

check_branch() {
    local branch="$1"
    cd "$PROJECT_ROOT"
    echo "=== Latest commits on $branch ==="
    git log --oneline -10 "$branch" 2>/dev/null || echo "Branch $branch not found"
    echo ""
    echo "=== Uncommitted changes ==="
    git status --short
}

show_status() {
    cd "$PROJECT_ROOT"
    echo "=== Current branch ==="
    git branch --show-current
    echo ""
    echo "=== Recent commits ==="
    git log --oneline -5
    echo ""
    echo "=== Task progress ==="
    if [ -f "$DEFAULT_SPECS/tasks.md" ]; then
        local total
        total=$(grep -cE '^\- \[[ xXo]\]' "$DEFAULT_SPECS/tasks.md" 2>/dev/null || echo 0)
        local done
        done=$(grep -cE '^\- \[[xX]\]' "$DEFAULT_SPECS/tasks.md" 2>/dev/null || echo 0)
        local wip
        wip=$(grep -cE '^\- \[o\]' "$DEFAULT_SPECS/tasks.md" 2>/dev/null || echo 0)
        local todo=$((total - done - wip))
        echo "  Total: $total | Done: $done | WIP: $wip | TODO: $todo"
    else
        echo "  No tasks.md found at $DEFAULT_SPECS/tasks.md"
    fi
    echo ""
    echo "=== Active worktrees ==="
    git worktree list
    echo ""
    echo "=== Recent reviews ==="
    ls -lt "$REVIEWS_DIR"/*.md 2>/dev/null | head -5 || echo "  No reviews yet"
}

# --- MAIN ---

[[ $# -lt 1 ]] && usage

COMMAND="$1"
shift

case "$COMMAND" in
    codex-implement)
        [[ $# -lt 2 ]] && { echo "Error: codex-implement requires <plan-file> <branch>"; exit 1; }
        codex_implement "$1" "$2" "${3:-}" "${4:-}"
        ;;
    codex-review)
        [[ $# -lt 1 ]] && { echo "Error: codex-review requires <branch>"; exit 1; }
        codex_review "$1" "${2:-}" "${3:-}"
        ;;
    implement)
        [[ $# -lt 2 ]] && { echo "Error: implement requires <plan-file> <branch>"; exit 1; }
        implement_default "$1" "$2" "${3:-}" "${4:-codex}"
        ;;
    claude-implement)
        [[ $# -lt 2 ]] && { echo "Error: claude-implement requires <plan-file> <branch>"; exit 1; }
        claude_implement "$1" "$2" "${3:-}" "${4:-}"
        ;;
    claude-review)
        [[ $# -lt 1 ]] && { echo "Error: claude-review requires <branch>"; exit 1; }
        claude_review "$1" "${2:-}" "${3:-}"
        ;;
    check-branch)
        [[ $# -lt 1 ]] && { echo "Error: check-branch requires <branch>"; exit 1; }
        check_branch "$1"
        ;;
    status)
        show_status
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        ;;
esac
