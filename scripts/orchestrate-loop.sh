#!/bin/bash
# =============================================================================
# Orchestration Loop — Autonomous Multi-Agent Development Orchestrator
# =============================================================================
# Runs persistently in a tmux session. Dispatches Codex CLI (implementation) and
# Claude Code CLI (review) until the spec is satisfied.
#
# Usage:
#   .claude/orchestration/scripts/orchestrate-loop.sh <tasks-file> <branch> [options]
#
# Options:
#   --specs <path>         Specs directory (default: $ORCH_SPECS env var, or "specs")
#   --plan <path>          Plan file (default: <specs>/plan.md)
#   --poll-interval <sec>  Seconds between status checks (default: 30)
#   --max-iterations <n>   Max review-fix cycles per task (default: 3)
#   --timeout <sec>        Max seconds per agent dispatch (default: 3600)
#   --dry-run              Print commands without executing
#   --resume               Resume from saved state
#   --env <path>           Source environment file before dispatching agents
#   --phase <n|name>       Only process tasks in the given phase (number or name substring)
#   --tasks <T001,T002>    Only process the listed task IDs (comma-separated)
#   --from <task-id>       Start processing from this task ID (inclusive)
#   --to <task-id>         Stop processing after this task ID (inclusive)
#   --test-cmd <cmd>       Run this command to verify tasks after review PASS
#   --lint-cmd <cmd>       Run this lint command to verify tasks after review PASS
#   --bootstrap-reads <f>  Comma-separated files agents should read first
#   --git-remote <name>    Git remote name (default: github)
#   --sequential-only      Force all tasks to run sequentially (ignore [P] markers)
#
# Environment:
#   ORCH_SPECS             Default specs directory (fallback if --specs not passed)
#   GIT_REMOTE             Git remote name (default: github)
#   CODEX_MODEL            Model override for Codex CLI
#   CLAUDE_MODEL           Model override for Claude Code CLI
#
# tasks.md markers:
#   [BREAK]                Insert on its own line or after a task to halt execution at that point
#
# See .claude/orchestration/orchestration-protocol.md Section 10 for full documentation.
# =============================================================================

set -euo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REVIEWS_DIR="$PROJECT_ROOT/planning/reviews"
TEMPLATES_DIR="$SCRIPT_DIR"
LOG_FILE="$PROJECT_ROOT/planning/orchestration-log.md"
STATE_DIR="/tmp/orch-$$"
STATE_FILE="$PROJECT_ROOT/.claude/orchestration-state.env"
CODEX_MODEL="${CODEX_MODEL:-}"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"

# --- Defaults ---
SPECS_PATH="${ORCH_SPECS:-specs}"
PLAN_FILE=""
POLL_INTERVAL=30
MAX_ITERATIONS=3
AGENT_TIMEOUT=3600
DRY_RUN=false
RESUME=false
ENV_FILE=""
FILTER_PHASE=""
FILTER_TASKS=""
FILTER_FROM=""
FILTER_TO=""
SEQUENTIAL_ONLY=false
TEST_CMD=""
LINT_CMD=""
BOOTSTRAP_READS=""
GIT_REMOTE="${GIT_REMOTE:-github}"

# --- Runtime State ---
LAST_IMPLEMENTER=""
TASKS_PROCESSED=0
TASKS_PASSED=0
TASKS_FAILED=0
ESCALATION_COUNT=0

# =============================================================================
# Argument Parsing
# =============================================================================

usage() {
    sed -n '2,/^# ====/{/^# ====/d;s/^# //;p}' "$0"
    exit 1
}

[[ $# -lt 2 ]] && usage

TASKS_FILE="$1"; shift
BRANCH="$1"; shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --specs)        SPECS_PATH="$2"; shift 2 ;;
        --plan)         PLAN_FILE="$2"; shift 2 ;;
        --poll-interval) POLL_INTERVAL="$2"; shift 2 ;;
        --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
        --timeout)      AGENT_TIMEOUT="$2"; shift 2 ;;
        --dry-run)      DRY_RUN=true; shift ;;
        --resume)       RESUME=true; shift ;;
        --env)          ENV_FILE="$2"; shift 2 ;;
        --phase)        FILTER_PHASE="$2"; shift 2 ;;
        --tasks)        FILTER_TASKS="$2"; shift 2 ;;
        --from)         FILTER_FROM="$2"; shift 2 ;;
        --to)           FILTER_TO="$2"; shift 2 ;;
        --sequential-only) SEQUENTIAL_ONLY=true; shift ;;
        --test-cmd)     TEST_CMD="$2"; shift 2 ;;
        --lint-cmd)     LINT_CMD="$2"; shift 2 ;;
        --bootstrap-reads) BOOTSTRAP_READS="$2"; shift 2 ;;
        --git-remote)   GIT_REMOTE="$2"; shift 2 ;;
        *)              echo "Unknown option: $1"; usage ;;
    esac
done

PLAN_FILE="${PLAN_FILE:-$SPECS_PATH/plan.md}"

LAST_IMPLEMENTER="claude"

# =============================================================================
# Setup
# =============================================================================

mkdir -p "$REVIEWS_DIR" "$STATE_DIR"

# Source environment if specified
if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

# =============================================================================
# Logging
# =============================================================================

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local msg="[$timestamp] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log_section() {
    local sep="============================================================"
    log ""
    log "$sep"
    log "$*"
    log "$sep"
}

die() {
    log "FATAL: $*"
    cleanup
    exit 1
}

# =============================================================================
# State Management
# =============================================================================

save_state() {
    cat > "$STATE_FILE" <<EOF
# Orchestration state — auto-generated, do not edit manually
LAST_IMPLEMENTER=$LAST_IMPLEMENTER
TASKS_PROCESSED=$TASKS_PROCESSED
TASKS_PASSED=$TASKS_PASSED
TASKS_FAILED=$TASKS_FAILED
ESCALATION_COUNT=$ESCALATION_COUNT
TASKS_FILE=$TASKS_FILE
BRANCH=$BRANCH
SPECS_PATH=$SPECS_PATH
PLAN_FILE=$PLAN_FILE
TIMESTAMP=$(date -Iseconds)
EOF
    log "  State saved to $STATE_FILE"
    save_state_json
}

save_state_json() {
    local json_file="${STATE_FILE%.env}.json"
    cat > "$json_file" <<EOF
{
  "branch": "$BRANCH",
  "tasks_file": "$TASKS_FILE",
  "specs_path": "$SPECS_PATH",
  "plan_file": "$PLAN_FILE",
  "tasks_processed": $TASKS_PROCESSED,
  "tasks_passed": $TASKS_PASSED,
  "tasks_failed": $TASKS_FAILED,
  "escalation_count": $ESCALATION_COUNT,
  "last_implementer": "$LAST_IMPLEMENTER",
  "git_remote": "$GIT_REMOTE",
  "test_cmd": "$TEST_CMD",
  "lint_cmd": "$LINT_CMD",
  "timestamp": "$(date -Iseconds)"
}
EOF
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        log "  Resumed from state: processed=$TASKS_PROCESSED passed=$TASKS_PASSED failed=$TASKS_FAILED"
        return 0
    fi
    return 1
}

cleanup() {
    # Remove temp files but preserve state for resume
    rm -rf "$STATE_DIR"
    log "Cleanup complete. State preserved at $STATE_FILE"
}

trap cleanup EXIT

# =============================================================================
# Task Parsing
# =============================================================================
# Format: - [ ] T018 [P] [US1] Description [claude]
#   [ ] = pending, [o] = in progress, [x] = completed
#   [P] = parallelizable, [USn] = user story
#   [BREAK] on its own line or in a task line = halt execution here
#
# Phase headers: ## Phase N: Name
# Filters: --phase, --tasks, --from, --to narrow which tasks are included
# =============================================================================

declare -a TASK_IDS=()
declare -a TASK_LINES=()
declare -a TASK_DESCS=()
declare -a TASK_AGENTS=()      # "codex" (default) or "claude" override
declare -a TASK_PARALLEL=()    # "yes" or "no"
declare -a TASK_LINE_NUMS=()
declare -a TASK_PHASES=()      # phase name for each task
BREAK_HIT=false

# Build a lookup set from --tasks filter (comma-separated task IDs)
declare -A FILTER_TASKS_SET=()
_build_task_filter() {
    if [[ -n "$FILTER_TASKS" ]]; then
        IFS=',' read -ra _ids <<< "$FILTER_TASKS"
        for _id in "${_ids[@]}"; do
            FILTER_TASKS_SET["$(echo "$_id" | xargs)"]=1
        done
    fi
}

parse_tasks() {
    local file="$PROJECT_ROOT/$TASKS_FILE"
    [[ -f "$file" ]] || die "Tasks file not found: $file"

    _build_task_filter

    local line_num=0
    local count=0
    local skipped=0
    local current_phase=""
    local current_phase_num=""
    local in_range=true
    local range_started=false

    # If --from is specified, we start out of range until we hit it
    if [[ -n "$FILTER_FROM" ]]; then
        in_range=false
        range_started=false
    fi

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # --- Detect [BREAK] marker ---
        # Standalone line: [BREAK] or just the word BREAK on a line
        if [[ "$line" =~ ^\[BREAK\] ]] || [[ "$line" =~ ^[[:space:]]*\[BREAK\][[:space:]]*$ ]]; then
            log "  [BREAK] marker hit at line $line_num — stopping task collection"
            BREAK_HIT=true
            break
        fi

        # --- Track phase headers ---
        # Match: ## Phase N: Name  or  ## Phase N - Name  or  ## Phase N. Name
        if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([0-9]+)[^a-zA-Z0-9]*(.+)$ ]]; then
            current_phase_num="${BASH_REMATCH[1]}"
            current_phase="${BASH_REMATCH[2]}"
            current_phase=$(echo "$current_phase" | xargs)  # trim
            continue
        fi

        # --- Match pending tasks: - [ ] ... ---
        if [[ "$line" =~ ^-\ \[\ \]\ (.+)$ ]]; then
            local content="${BASH_REMATCH[1]}"

            # Check for inline [BREAK] marker
            if [[ "$content" =~ \[BREAK\] ]]; then
                log "  [BREAK] marker hit inline at line $line_num — stopping task collection"
                BREAK_HIT=true
                break
            fi

            # Extract task ID (T001, T016a, etc.)
            local task_id="TASK-${line_num}"
            if [[ "$content" =~ ^(T[0-9]+[a-z]?) ]]; then
                task_id="${BASH_REMATCH[1]}"
            fi

            # --- Apply --from / --to range filter ---
            if [[ -n "$FILTER_FROM" ]] && [[ "$task_id" == "$FILTER_FROM" ]]; then
                in_range=true
                range_started=true
            fi
            if [[ "$in_range" != true ]]; then
                skipped=$((skipped + 1))
                # Still need to check --to even while skipping
                continue
            fi

            # --- Apply --phase filter ---
            if [[ -n "$FILTER_PHASE" ]]; then
                local phase_match=false
                if [[ "$FILTER_PHASE" =~ ^[0-9]+$ ]]; then
                    # Numeric: match by phase number only
                    [[ "$current_phase_num" == "$FILTER_PHASE" ]] && phase_match=true
                else
                    # Non-numeric: match by phase name substring (case-insensitive)
                    if [[ -n "$current_phase" ]] && echo "$current_phase" | grep -qi "$FILTER_PHASE"; then
                        phase_match=true
                    fi
                fi
                if [[ "$phase_match" != true ]]; then
                    skipped=$((skipped + 1))
                    # Check --to before continuing
                    if [[ -n "$FILTER_TO" ]] && [[ "$task_id" == "$FILTER_TO" ]]; then
                        in_range=false
                    fi
                    continue
                fi
            fi

            # --- Apply --tasks filter ---
            if [[ ${#FILTER_TASKS_SET[@]} -gt 0 ]]; then
                if [[ -z "${FILTER_TASKS_SET[$task_id]:-}" ]]; then
                    skipped=$((skipped + 1))
                    # Check --to before continuing
                    if [[ -n "$FILTER_TO" ]] && [[ "$task_id" == "$FILTER_TO" ]]; then
                        in_range=false
                    fi
                    continue
                fi
            fi

            # Check for implementer override (default codex)
            local agent="codex"
            if [[ "$content" =~ \[claude\] ]]; then
                agent="claude"
            fi

            # Check for parallel marker (respect --sequential-only)
            local parallel="no"
            if [[ "$content" =~ \[P\] ]] && [[ "$SEQUENTIAL_ONLY" != true ]]; then
                parallel="yes"
            fi

            # Clean description: remove markers for the prompt
            local desc="$content"
            desc=$(echo "$desc" | sed -E 's/\[(claude|P|US[0-9]+|BREAK)\]//g' | sed 's/  */ /g' | xargs)

            TASK_IDS+=("$task_id")
            TASK_LINES+=("$line")
            TASK_DESCS+=("$desc")
            TASK_AGENTS+=("$agent")
            TASK_PARALLEL+=("$parallel")
            TASK_LINE_NUMS+=("$line_num")
            TASK_PHASES+=("${current_phase:-unknown}")
            count=$((count + 1))

            # --- Apply --to range filter (after adding the task) ---
            if [[ -n "$FILTER_TO" ]] && [[ "$task_id" == "$FILTER_TO" ]]; then
                log "  Reached --to task $FILTER_TO — stopping task collection"
                in_range=false
                break
            fi
        fi
    done < "$file"

    # Log filter info
    local filter_info=""
    [[ -n "$FILTER_PHASE" ]] && filter_info+=" phase=$FILTER_PHASE"
    [[ -n "$FILTER_TASKS" ]] && filter_info+=" tasks=$FILTER_TASKS"
    [[ -n "$FILTER_FROM" ]] && filter_info+=" from=$FILTER_FROM"
    [[ -n "$FILTER_TO" ]] && filter_info+=" to=$FILTER_TO"
    [[ "$SEQUENTIAL_ONLY" == true ]] && filter_info+=" sequential-only=true"
    [[ "$BREAK_HIT" == true ]] && filter_info+=" (stopped at [BREAK])"

    if [[ -n "$filter_info" ]]; then
        log "Filters:$filter_info"
    fi
    log "Parsed $count pending tasks from $TASKS_FILE (skipped $skipped)"
}

# =============================================================================
# Agent Selection
# =============================================================================

next_implementer() {
    local task_index="$1"
    echo "${TASK_AGENTS[$task_index]:-codex}"
}

get_reviewer() {
    local implementer="$1"
    if [[ "$implementer" == "codex" ]]; then
        echo "claude"
    else
        echo "codex"
    fi
}

# =============================================================================
# Task Marking in tasks.md
# =============================================================================

mark_task() {
    local line_num="$1"
    local new_state="$2"  # "o" for in-progress, "x" for completed
    local file="$PROJECT_ROOT/$TASKS_FILE"

    if [[ "$DRY_RUN" == true ]]; then
        log "  [DRY RUN] Would mark line $line_num as [$new_state]"
        return
    fi

    sed -i "${line_num}s/- \[[ o]\]/- [${new_state}]/" "$file"
    log "  Marked line $line_num as [$new_state] in $TASKS_FILE"
}

# =============================================================================
# Agent Dispatch
# =============================================================================

build_impl_prompt() {
    local task_id="$1"
    local task_desc="$2"
    local agent="$3"
    local work_dir="${4:-$PROJECT_ROOT}"

    # Prepend bootstrap context
    build_agent_bootstrap "$work_dir"
    echo ""

    cat <<EOF
Read the plan at $PLAN_FILE and the spec at $SPECS_PATH/spec.md.

Implement the following task:
  Task ID: $task_id
  Description: $task_desc

Work on branch: $BRANCH
Working directory: $work_dir

Instructions:
1. Read the relevant sections of the plan and spec before coding.
2. Implement the task completely — no stubs, no TODOs for core functionality.
3. Run any relevant tests to verify your work.
4. Commit using git remote '$GIT_REMOTE': git add <specific-files> && git commit -m '<files-changed> — <description>'
   Push: git push $GIT_REMOTE $BRANCH
   One task per commit; do not batch tasks.
5. Mark this task [x] in $TASKS_FILE (line containing "$task_id").

Follow $([ "$agent" == "codex" ] && echo ".codex/ prompts" || echo ".claude/CLAUDE.md guidelines") and project conventions.
EOF
}

build_agent_bootstrap() {
    local work_dir="${1:-$PROJECT_ROOT}"

    cat <<BOOTSTRAP
## Agent Bootstrap Context
- **Project root**: $work_dir
- **Guidelines**: Read \`.claude/CLAUDE.md\` for project conventions
- **Git remote**: \`$GIT_REMOTE\` (NOT origin)
- **Git branch**: \`$BRANCH\`
- **Test command**: \`${TEST_CMD:-none}\`
- **Lint command**: \`${LINT_CMD:-none}\`
- **Commit format**: \`<files-changed> — <description>\`
BOOTSTRAP

    if [[ -n "$BOOTSTRAP_READS" ]]; then
        echo ""
        echo "### Files to read FIRST (before starting work)"
        IFS=',' read -ra _files <<< "$BOOTSTRAP_READS"
        for f in "${_files[@]}"; do
            echo "- \`$(echo "$f" | xargs)\`"
        done
    fi

    echo ""
    echo "### Project Map"
    echo "- \`.claude/\` -- Claude Code configuration and orchestration scripts"
    echo "- \`src/\` -- Source code"
    echo "- \`tests/\` -- Test suites"
    echo "- \`docs/\` -- Documentation"
    echo "- \`specs/\` -- Specifications and plans"
    echo "- \`planning/\` -- Planning documents and reviews"
}

build_review_prompt() {
    local branch="$1"
    local plan_file="$2"
    local specs="$3"
    local review_file="$4"
    local reviewer="$5"

    local template_file="$TEMPLATES_DIR/review-prompt-${reviewer}.md"
    if [[ ! -f "$template_file" ]]; then
        die "Review template not found: $template_file"
    fi

    # Get commit range
    local commit_range
    commit_range=$(cd "$PROJECT_ROOT" && git log --oneline -10 "$branch" 2>/dev/null | head -1 | cut -d' ' -f1)
    commit_range="main..${branch} (latest: ${commit_range:-unknown})"

    local prompt
    prompt=$(cat "$template_file")
    prompt="${prompt//\{BRANCH\}/$branch}"
    prompt="${prompt//\{PLAN_FILE\}/$plan_file}"
    prompt="${prompt//\{SPECS\}/$specs}"
    prompt="${prompt//\{REVIEW_FILE\}/$review_file}"
    prompt="${prompt//\{COMMIT_RANGE\}/$commit_range}"

    echo "$prompt"
}

dispatch_agent() {
    local window_name="$1"
    local agent="$2"   # "codex" or "claude"
    local prompt="$3"
    local work_dir="${4:-$PROJECT_ROOT}"
    local exit_file="$STATE_DIR/${window_name}.exit"

    # Write prompt to temp file to avoid shell escaping issues
    local prompt_file="$STATE_DIR/${window_name}.prompt"
    echo "$prompt" > "$prompt_file"

    local cmd=""
    if [[ "$agent" == "codex" ]]; then
        cmd="cd '$work_dir' && codex exec \"\$(cat '$prompt_file')\" --full-auto ${CODEX_MODEL:+-m $CODEX_MODEL}"
    else
        cmd="cd '$work_dir' && claude -p \"\$(cat '$prompt_file')\" --dangerously-skip-permissions ${CLAUDE_MODEL:+--model $CLAUDE_MODEL}"
    fi

    # Wrap: run command, capture exit code, signal completion
    local full_cmd="$cmd; echo \$? > '$exit_file'"

    if [[ "$DRY_RUN" == true ]]; then
        log "  [DRY RUN] Would dispatch $agent in window '$window_name':"
        log "  [DRY RUN] $cmd"
        echo "0" > "$exit_file"
        return
    fi

    # Launch in a new tmux window within the orchestrator session
    tmux new-window -t orchestrator -n "$window_name" bash -c "$full_cmd"
    log "  Dispatched $agent in tmux window 'orchestrator:$window_name'"
}

# =============================================================================
# Polling & Completion
# =============================================================================

# Record the commit HEAD before dispatching so we can track new commits
snapshot_git_head() {
    cd "$PROJECT_ROOT"
    git rev-parse HEAD 2>/dev/null || echo "unknown"
}

# Check git progress since a given commit — used during polling to see
# whether the agent is making commits and whether those commits look sane.
check_git_progress() {
    local since_commit="$1"
    local task_id="$2"
    cd "$PROJECT_ROOT"

    # New commits since dispatch
    local new_commits
    new_commits=$(git log --oneline "${since_commit}..HEAD" 2>/dev/null)
    local commit_count
    commit_count=$(echo "$new_commits" | grep -c '.' 2>/dev/null || echo 0)

    if [[ $commit_count -gt 0 ]]; then
        log "  GIT PROGRESS ($task_id): $commit_count new commit(s) since dispatch"
        echo "$new_commits" | head -5 | while IFS= read -r line; do
            log "    + $line"
        done

        # Spot-check: show files changed in the latest commit
        local changed_files
        changed_files=$(git diff --stat HEAD~1..HEAD 2>/dev/null | tail -1)
        log "  Latest commit stats: $changed_files"

        # Drift detection: flag if agent is touching files outside expected scope
        # Generic pattern: common project directories. Override ORCH_EXPECTED_DIRS
        # env var if your project has a different structure.
        local expected_dirs="${ORCH_EXPECTED_DIRS:-src/|tests/|specs/|planning/|docs/|\.claude/|deploy/|tools/|Makefile}"
        local unexpected_files
        unexpected_files=$(git diff --name-only "${since_commit}..HEAD" 2>/dev/null \
            | grep -vE "^(${expected_dirs})" || true)
        if [[ -n "$unexpected_files" ]]; then
            log "  WARNING: Agent touched unexpected files (possible drift):"
            echo "$unexpected_files" | head -5 | while IFS= read -r line; do
                log "    ! $line"
            done
        fi
    else
        log "  GIT PROGRESS ($task_id): No new commits yet (${elapsed}s elapsed)"
    fi
}

wait_for_agent() {
    local window_name="$1"
    local task_id="${2:-$window_name}"
    local exit_file="$STATE_DIR/${window_name}.exit"
    local elapsed=0

    # Snapshot HEAD before the agent runs so we can track its commits
    local head_before
    head_before=$(snapshot_git_head)

    while [[ ! -f "$exit_file" ]] && [[ $elapsed -lt $AGENT_TIMEOUT ]]; do
        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))

        # Periodic status log (every 5 polls)
        if (( elapsed % (POLL_INTERVAL * 5) == 0 )); then
            log "  Waiting for $window_name... (${elapsed}s / ${AGENT_TIMEOUT}s)"

            # Git-based progress check
            check_git_progress "$head_before" "$task_id"

            # Check if tmux window still exists
            if ! tmux list-windows -t orchestrator -F '#{window_name}' 2>/dev/null | grep -q "^${window_name}$"; then
                log "  WARNING: tmux window '$window_name' disappeared"
                # Process may have exited — check for exit file one more time
                sleep 2
                [[ -f "$exit_file" ]] && break
                echo "1" > "$exit_file"
                break
            fi
        fi
    done

    if [[ ! -f "$exit_file" ]]; then
        log "  TIMEOUT: $window_name exceeded ${AGENT_TIMEOUT}s"
        # Kill the window
        tmux kill-window -t "orchestrator:$window_name" 2>/dev/null || true
        echo "TIMEOUT" > "$exit_file"
    fi

    local exit_code
    exit_code=$(cat "$exit_file")
    log "  Agent $window_name finished (exit: $exit_code)"

    # Error diagnosis for non-zero exits
    if [[ "$exit_code" != "0" && "$exit_code" != "TIMEOUT" ]]; then
        log "  ERROR DIAGNOSIS for $window_name (exit: $exit_code):"
        # Capture last lines from tmux pane if it still exists
        local pane_output
        pane_output=$(tmux capture-pane -t "orchestrator:$window_name" -p 2>/dev/null | tail -30) || true
        if [[ -n "$pane_output" ]]; then
            log "  Last 30 lines of agent output:"
            echo "$pane_output" | while IFS= read -r line; do
                log "    | $line"
            done
        fi
        # Classify failure type for orchestrator decision
        if echo "$pane_output" | grep -qi "import\|ModuleNotFoundError\|No module named"; then
            log "  FAILURE TYPE: Missing dependency — fix environment before re-dispatch"
        elif echo "$pane_output" | grep -qi "context.*overflow\|context.*limit\|token.*limit"; then
            log "  FAILURE TYPE: Context overflow — split task into smaller pieces"
        else
            log "  FAILURE TYPE: Unknown — consider escalation"
        fi
    fi

    return 0
}

get_exit_code() {
    local window_name="$1"
    local exit_file="$STATE_DIR/${window_name}.exit"
    [[ -f "$exit_file" ]] && cat "$exit_file" || echo "UNKNOWN"
}

# =============================================================================
# Review Verdict Parsing
# =============================================================================

parse_verdict() {
    local review_file="$1"

    if [[ ! -f "$review_file" ]]; then
        log "  WARNING: Review file not found: $review_file"
        echo "MISSING"
        return
    fi

    # Try grep first (fast path)
    local verdict
    verdict=$(grep -oP 'Verdict:\s*\K(PASS|NEEDS_FIXES|ESCALATE)' "$review_file" 2>/dev/null | head -1)

    if [[ -n "$verdict" ]]; then
        echo "$verdict"
        return
    fi

    # Fallback: use claude -p to parse (handles non-standard formatting)
    log "  Verdict not found via grep, using claude -p to parse..."
    verdict=$(claude -p \
        "Read this file and return ONLY one word — the review verdict: PASS, NEEDS_FIXES, or ESCALATE. File contents: $(cat "$review_file")" \
        --dangerously-skip-permissions ${CLAUDE_MODEL:+--model "$CLAUDE_MODEL"} 2>/dev/null | grep -oE '(PASS|NEEDS_FIXES|ESCALATE)' | head -1)

    if [[ -n "$verdict" ]]; then
        echo "$verdict"
    else
        log "  WARNING: Could not parse verdict from $review_file"
        echo "UNKNOWN"
    fi
}

# =============================================================================
# Worktree Management (for parallel tasks)
# =============================================================================

create_worktree() {
    local task_id="$1"
    local parent_branch="$2"
    local sub_branch="${parent_branch}/${task_id}"
    local worktree_dir="$PROJECT_ROOT/../proj-${task_id}"

    cd "$PROJECT_ROOT"
    git branch "$sub_branch" "$parent_branch" 2>/dev/null || true
    git worktree add "$worktree_dir" "$sub_branch" 2>/dev/null || {
        log "  WARNING: Worktree for $task_id already exists at $worktree_dir"
    }

    log "  Created worktree: $worktree_dir on branch $sub_branch"
    echo "$worktree_dir"
}

merge_worktree() {
    local task_id="$1"
    local parent_branch="$2"
    local sub_branch="${parent_branch}/${task_id}"
    local worktree_dir="$PROJECT_ROOT/../proj-${task_id}"

    cd "$PROJECT_ROOT"
    git checkout "$parent_branch"
    git merge --no-ff -m "Merge $sub_branch into $parent_branch" "$sub_branch" || {
        log "  ESCALATION: Merge conflict for $task_id — requires manual resolution"
        ESCALATION_COUNT=$((ESCALATION_COUNT + 1))
        return 1
    }

    git worktree remove "$worktree_dir" 2>/dev/null || true
    git branch -d "$sub_branch" 2>/dev/null || true
    log "  Merged and cleaned up worktree for $task_id"
}

# =============================================================================
# Escalation
# =============================================================================

escalate() {
    local task_id="$1"
    local reason="$2"
    local escalation_file="$PROJECT_ROOT/planning/reviews/ESCALATION-${task_id}-$(date +%Y%m%d-%H%M%S).md"

    cat > "$escalation_file" <<EOF
# ESCALATION: $task_id
**Time**: $(date -Iseconds)
**Branch**: $BRANCH
**Reason**: $reason

## Context
- Task: ${TASK_DESCS[*]:0:1}
- Iterations completed: see orchestration log
- Review files in: $REVIEWS_DIR/

## Action Required
Please review and provide guidance. Resume orchestration with:
\`\`\`bash
.claude/orchestration/scripts/orchestrate-loop.sh $TASKS_FILE $BRANCH --resume
\`\`\`
EOF

    log_section "ESCALATION — $task_id"
    log "Reason: $reason"
    log "Escalation file: $escalation_file"
    log "Orchestrator HALTING. Waiting for project lead."
    ESCALATION_COUNT=$((ESCALATION_COUNT + 1))
    save_state
}

# =============================================================================
# Single Task Cycle: Implement → Review → Iterate
# =============================================================================

process_task() {
    local idx="$1"
    local task_id="${TASK_IDS[$idx]}"
    local task_desc="${TASK_DESCS[$idx]}"
    local line_num="${TASK_LINE_NUMS[$idx]}"

    log_section "Task: $task_id — $task_desc"

    # Select agents
    local implementer
    implementer=$(next_implementer "$idx")
    local reviewer
    reviewer=$(get_reviewer "$implementer")
    LAST_IMPLEMENTER="$implementer"

    log "  Implementer: $implementer | Reviewer: $reviewer"

    # Mark in-progress
    mark_task "$line_num" "o"

    local iteration=0
    local verdict="NEEDS_FIXES"

    while [[ "$verdict" != "PASS" ]] && [[ $iteration -lt $MAX_ITERATIONS ]]; do
        iteration=$((iteration + 1))
        log "  --- Iteration $iteration / $MAX_ITERATIONS ---"

        # --- Implementation phase ---
        local impl_window="impl-${task_id}-i${iteration}"
        local impl_prompt
        impl_prompt=$(build_impl_prompt "$task_id" "$task_desc" "$implementer")

        # If iteration > 1, append the review feedback
        if [[ $iteration -gt 1 ]]; then
            local prev_review="$REVIEWS_DIR/${BRANCH//\//-}-${reviewer}-review-latest.md"
            if [[ -f "$prev_review" ]]; then
                impl_prompt="$impl_prompt

PREVIOUS REVIEW FEEDBACK (iteration $((iteration - 1))):
$(cat "$prev_review")

Address ALL 'MUST FIX' items from the review above."
            fi
        fi

        log "  Dispatching $implementer for implementation..."
        dispatch_agent "$impl_window" "$implementer" "$impl_prompt"
        wait_for_agent "$impl_window" "$task_id"

        local impl_exit
        impl_exit=$(get_exit_code "$impl_window")

        # Post-implementation git sanity check
        log "  Post-implementation git check:"
        local post_impl_diff
        post_impl_diff=$(cd "$PROJECT_ROOT" && git diff --stat 2>/dev/null)
        if [[ -n "$post_impl_diff" ]]; then
            log "  WARNING: Uncommitted changes left by agent:"
            echo "$post_impl_diff" | while IFS= read -r line; do
                log "    ? $line"
            done
        fi
        local recent_commits
        recent_commits=$(cd "$PROJECT_ROOT" && git log --oneline -3 2>/dev/null)
        log "  Recent commits:"
        echo "$recent_commits" | while IFS= read -r line; do
            log "    $line"
        done

        if [[ "$impl_exit" == "TIMEOUT" ]]; then
            escalate "$task_id" "Implementation timed out after ${AGENT_TIMEOUT}s (iteration $iteration)"
            return 1
        fi

        # --- Review phase ---
        local review_file="$REVIEWS_DIR/${BRANCH//\//-}-${reviewer}-review-latest.md"
        local review_window="review-${task_id}-i${iteration}"
        local review_prompt
        review_prompt=$(build_review_prompt "$BRANCH" "$PLAN_FILE" "$SPECS_PATH" "$review_file" "$reviewer")

        log "  Dispatching $reviewer for code review..."
        dispatch_agent "$review_window" "$reviewer" "$review_prompt"
        wait_for_agent "$review_window" "$task_id"

        # --- Verdict ---
        if [[ "$DRY_RUN" == true ]]; then
            verdict="PASS"
            log "  Verdict: PASS [DRY RUN — auto-pass]"
        else
            verdict=$(parse_verdict "$review_file")
            log "  Verdict: $verdict"
        fi

        # Archive the review with iteration number
        if [[ -f "$review_file" ]]; then
            cp "$review_file" "$REVIEWS_DIR/${BRANCH//\//-}-${task_id}-i${iteration}-${reviewer}-review.md"
        fi

        case "$verdict" in
            PASS)
                # Run verification if test/lint commands are configured
                if [[ -n "$TEST_CMD" || -n "$LINT_CMD" ]]; then
                    if ! verify_task "$task_id"; then
                        log "  Verification failed — dispatching fix agent"
                        verdict="NEEDS_FIXES"
                        # Create a synthetic review with verification failures
                        local verify_review="$REVIEWS_DIR/${BRANCH//\//-}-${task_id}-verify-i${iteration}.md"
                        {
                            echo "# Verification Review: $task_id"
                            echo "**Reviewer**: Orchestrator (automated)"
                            echo ""
                            [[ -f "$STATE_DIR/verify-${task_id}-test.log" ]] && {
                                echo "## MUST FIX"
                                echo "- Test failures:"
                                echo '```'
                                tail -30 "$STATE_DIR/verify-${task_id}-test.log"
                                echo '```'
                            }
                            [[ -f "$STATE_DIR/verify-${task_id}-lint.log" ]] && {
                                echo "- Lint failures:"
                                echo '```'
                                tail -30 "$STATE_DIR/verify-${task_id}-lint.log"
                                echo '```'
                            }
                            echo ""
                            echo "## Verdict: NEEDS_FIXES"
                        } > "$verify_review"
                        # Point the review file at the verification output
                        cp "$verify_review" "$REVIEWS_DIR/${BRANCH//\//-}-${reviewer}-review-latest.md"
                        continue  # Back to the while loop for another iteration
                    fi
                fi
                log "  Task $task_id PASSED review"
                ;;
            NEEDS_FIXES)
                if [[ $iteration -ge $MAX_ITERATIONS ]]; then
                    log "  Max iterations ($MAX_ITERATIONS) reached for $task_id"
                    escalate "$task_id" "Max review iterations ($MAX_ITERATIONS) exceeded without PASS verdict"
                    return 1
                fi
                log "  Sending back to $implementer with review feedback..."
                ;;
            ESCALATE)
                escalate "$task_id" "Reviewer ($reviewer) flagged architectural issue requiring project lead's input"
                return 1
                ;;
            MISSING|UNKNOWN)
                log "  WARNING: Could not determine verdict — treating as NEEDS_FIXES"
                verdict="NEEDS_FIXES"
                if [[ $iteration -ge $MAX_ITERATIONS ]]; then
                    escalate "$task_id" "Could not parse review verdict after $MAX_ITERATIONS iterations"
                    return 1
                fi
                ;;
        esac
    done

    # Mark completed
    mark_task "$line_num" "x"
    TASKS_PASSED=$((TASKS_PASSED + 1))
    log "  Task $task_id completed successfully"
    save_state
    return 0
}

# =============================================================================
# Task Verification (tests/lint)
# =============================================================================

verify_task() {
    local task_id="$1"
    local exit_code=0

    if [[ -n "$TEST_CMD" ]]; then
        log "  Verification: running tests ($TEST_CMD)..."
        cd "$PROJECT_ROOT"
        if ! eval "$TEST_CMD" > "$STATE_DIR/verify-${task_id}-test.log" 2>&1; then
            log "  VERIFY FAILED: Tests did not pass"
            log "  See: $STATE_DIR/verify-${task_id}-test.log"
            exit_code=1
        else
            log "  Tests passed"
        fi
    fi

    if [[ -n "$LINT_CMD" ]]; then
        log "  Verification: running lint ($LINT_CMD)..."
        cd "$PROJECT_ROOT"
        if ! eval "$LINT_CMD" > "$STATE_DIR/verify-${task_id}-lint.log" 2>&1; then
            log "  VERIFY FAILED: Lint did not pass"
            log "  See: $STATE_DIR/verify-${task_id}-lint.log"
            exit_code=1
        else
            log "  Lint passed"
        fi
    fi

    return $exit_code
}

# =============================================================================
# Parallel Task Group Processing
# =============================================================================

process_parallel_group() {
    local -a indices=("$@")
    local count=${#indices[@]}

    log_section "Parallel group: $count tasks"

    # Create worktrees and dispatch all implementations
    declare -A worktree_dirs
    declare -A impl_agents

    for idx in "${indices[@]}"; do
        local task_id="${TASK_IDS[$idx]}"
        local task_desc="${TASK_DESCS[$idx]}"
        local line_num="${TASK_LINE_NUMS[$idx]}"

        local implementer
        implementer=$(next_implementer "$idx")
        LAST_IMPLEMENTER="$implementer"
        impl_agents[$idx]="$implementer"

        # Create worktree
        local wt_dir
        wt_dir=$(create_worktree "$task_id" "$BRANCH")
        worktree_dirs[$idx]="$wt_dir"

        # Mark in-progress
        mark_task "$line_num" "o"

        # Build and dispatch
        local impl_prompt
        impl_prompt=$(build_impl_prompt "$task_id" "$task_desc" "$implementer" "$wt_dir")
        local impl_window="impl-${task_id}-p"

        log "  Dispatching $implementer for $task_id (parallel)..."
        dispatch_agent "$impl_window" "$implementer" "$impl_prompt" "$wt_dir"
    done

    # Wait for all implementations
    for idx in "${indices[@]}"; do
        local task_id="${TASK_IDS[$idx]}"
        wait_for_agent "impl-${task_id}-p" "$task_id"
    done

    # Review and merge each (sequentially to avoid merge conflicts)
    for idx in "${indices[@]}"; do
        local task_id="${TASK_IDS[$idx]}"
        local line_num="${TASK_LINE_NUMS[$idx]}"
        local implementer="${impl_agents[$idx]}"
        local reviewer
        reviewer=$(get_reviewer "$implementer")

        # Merge worktree first so reviewer sees the code on the main branch
        merge_worktree "$task_id" "$BRANCH" || continue

        # Single review iteration for parallel tasks (keep it moving)
        local review_file="$REVIEWS_DIR/${BRANCH//\//-}-${reviewer}-review-${task_id}.md"
        local review_prompt
        review_prompt=$(build_review_prompt "$BRANCH" "$PLAN_FILE" "$SPECS_PATH" "$review_file" "$reviewer")
        local review_window="review-${task_id}-p"

        log "  Dispatching $reviewer to review $task_id..."
        dispatch_agent "$review_window" "$reviewer" "$review_prompt"
        wait_for_agent "$review_window" "$task_id"

        local verdict
        verdict=$(parse_verdict "$review_file")
        log "  $task_id verdict: $verdict"

        case "$verdict" in
            PASS)
                mark_task "$line_num" "x"
                TASKS_PASSED=$((TASKS_PASSED + 1))
                ;;
            NEEDS_FIXES|MISSING|UNKNOWN)
                log "  $task_id needs fixes — will be retried as sequential task"
                # Reset to pending so the main loop picks it up
                mark_task "$line_num" " "
                ;;
            ESCALATE)
                escalate "$task_id" "Parallel review escalation by $reviewer"
                ;;
        esac
    done

    save_state
}

# =============================================================================
# Main Orchestration Loop
# =============================================================================

main() {
    log_section "Orchestration Loop Starting"
    log "Tasks file: $TASKS_FILE"
    log "Branch:     $BRANCH"
    log "Specs:      $SPECS_PATH"
    log "Plan:       $PLAN_FILE"
    log "Implementer default: codex${CODEX_MODEL:+ ($CODEX_MODEL)}"
    log "Implementer override: [claude] task tag"
    log "Reviewer: opposite agent of implementer"
    log "Max iterations: $MAX_ITERATIONS"
    log "Poll interval:  ${POLL_INTERVAL}s"
    log "Agent timeout:  ${AGENT_TIMEOUT}s"
    log "Dry run:        $DRY_RUN"
    log "Sequential only: $SEQUENTIAL_ONLY"
    [[ -n "$FILTER_PHASE" ]] && log "Phase filter:   $FILTER_PHASE"
    [[ -n "$FILTER_TASKS" ]] && log "Task filter:    $FILTER_TASKS"
    [[ -n "$FILTER_FROM" ]] && log "From task:      $FILTER_FROM"
    [[ -n "$FILTER_TO" ]] && log "To task:        $FILTER_TO"
    [[ -n "$TEST_CMD" ]] && log "Test command:   $TEST_CMD"
    [[ -n "$LINT_CMD" ]] && log "Lint command:   $LINT_CMD"
    [[ -n "$BOOTSTRAP_READS" ]] && log "Bootstrap reads: $BOOTSTRAP_READS"
    log "Git remote:     $GIT_REMOTE"
    log ""

    # Verify we're in the orchestrator tmux session
    if [[ -z "${TMUX:-}" ]] && [[ "$DRY_RUN" != true ]]; then
        die "Must run inside a tmux session named 'orchestrator'. Start with:
  tmux new-session -s orchestrator '.claude/orchestration/scripts/orchestrate-loop.sh $TASKS_FILE $BRANCH'"
    fi

    # Verify tools
    for tool in git codex claude; do
        if ! command -v "$tool" &>/dev/null; then
            die "$tool not found in PATH"
        fi
    done

    # Resume state if requested
    if [[ "$RESUME" == true ]]; then
        if load_state; then
            log "Resuming from previous state"
        else
            log "No state file found — starting fresh"
        fi
    fi

    # Ensure we're on the right branch
    cd "$PROJECT_ROOT"
    local current_branch
    current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "$BRANCH" ]]; then
        log "Switching to branch $BRANCH (was on $current_branch)"
        git checkout "$BRANCH" || die "Failed to checkout $BRANCH"
    fi

    # Parse tasks
    parse_tasks

    local total_tasks=${#TASK_IDS[@]}
    if [[ $total_tasks -eq 0 ]]; then
        log "No pending tasks found. Nothing to do."
        return 0
    fi

    log "Processing $total_tasks pending tasks..."

    # Process tasks — handle parallel groups and sequential guarantees
    local i=0
    local prev_task_id=""
    while [[ $i -lt $total_tasks ]]; do
        TASKS_PROCESSED=$((TASKS_PROCESSED + 1))
        local current_id="${TASK_IDS[$i]}"

        # Check for parallel group (only if not --sequential-only)
        if [[ "${TASK_PARALLEL[$i]}" == "yes" ]] && [[ "$SEQUENTIAL_ONLY" != true ]]; then
            # Collect consecutive parallel tasks
            local -a parallel_group=("$i")
            local j=$((i + 1))
            while [[ $j -lt $total_tasks ]] && [[ "${TASK_PARALLEL[$j]}" == "yes" ]]; do
                parallel_group+=("$j")
                j=$((j + 1))
            done

            if [[ ${#parallel_group[@]} -gt 1 ]]; then
                process_parallel_group "${parallel_group[@]}"
                prev_task_id="${TASK_IDS[$((j - 1))]}"
                i=$j
                continue
            fi
            # Single [P] task — just process normally
        fi

        # Sequential task — log the dependency guarantee
        if [[ -n "$prev_task_id" ]]; then
            log "  SEQUENTIAL: $current_id runs after $prev_task_id completes"
        fi

        process_task "$i"
        local result=$?

        if [[ $result -ne 0 ]]; then
            # Escalation occurred — halt
            log_section "HALTED — Escalation pending"
            log "Processed: $TASKS_PROCESSED | Passed: $TASKS_PASSED | Failed: $TASKS_FAILED | Escalations: $ESCALATION_COUNT"
            log "Resume with: .claude/orchestration/scripts/orchestrate-loop.sh $TASKS_FILE $BRANCH --resume"
            return 1
        fi

        prev_task_id="$current_id"
        i=$((i + 1))
    done

    # --- Final Report ---
    log_section "Orchestration Complete"
    log "Total tasks:  $total_tasks"
    log "Passed:       $TASKS_PASSED"
    log "Failed:       $TASKS_FAILED"
    log "Escalations:  $ESCALATION_COUNT"
    log ""

    if [[ $TASKS_PASSED -eq $total_tasks ]]; then
        log "ALL TASKS PASSED — Branch $BRANCH ready for project lead review"
    else
        log "Some tasks incomplete — check escalation files in $REVIEWS_DIR/"
    fi

    save_state
}

# =============================================================================
# Entry Point
# =============================================================================
main
