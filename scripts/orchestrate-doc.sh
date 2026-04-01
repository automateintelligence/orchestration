#!/bin/bash
# =============================================================================
# Document Orchestration Dispatch Helper
# Dispatches Claude CLI and Codex CLI for document draft/review/implement cycles
# See .claude/orchestration/orchestration-protocol.md Section 11
# =============================================================================
#
# Usage:
#   orchestrate-doc.sh draft     --phase N --prompt-source <file> --output <file> [options]
#   orchestrate-doc.sh review    --phase N --draft <file> --prompt-source <file> --round N --reviewer <agent>
#   orchestrate-doc.sh implement --phase N --draft <file> --review <file> --round N
#   orchestrate-doc.sh verify    --phase N [--test-cmd <cmd>] [--lint-cmd <cmd>]
#   orchestrate-doc.sh status    --phase N --output-dir <dir>
#
# This script is called BY the orchestrator (Claude acting as coordinator).
# It launches worker agents in tmux windows and writes .exit files on completion.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/orch-agent-runtime.sh
source "$SCRIPT_DIR/lib/orch-agent-runtime.sh"
orch_resolve_paths "$SCRIPT_DIR"
PROJECT_ROOT="$ORCH_PROJECT_ROOT"
TMUX_SESSION=""  # Auto-detected from current session or --session flag
CODEX_MODEL="${CODEX_MODEL:-}"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"
DOC_POLL_INTERVAL="$(orch_default_poll_interval doc)"

# =============================================================================
# Argument Parsing
# =============================================================================

COMMAND=""
PHASE_NUM=""
PROMPT_SOURCE=""
OUTPUT_FILE=""
OUTPUT_DIR=""
DRAFT_FILE=""
REVIEW_FILE=""
ROUND=""
REVIEWER=""
LOCKED_PHASES=""
DESIGN_SYSTEM=""
EXTRA_CONTEXT=""
TEST_CMD=""
LINT_CMD=""
BOOTSTRAP_READS=""
GIT_REMOTE="${GIT_REMOTE:-github}"
GIT_BRANCH=""

usage() {
    cat <<'EOF'
Usage: orchestrate-doc.sh <command> [options]

Commands:
  draft      Launch Claude CLI to write initial draft
  review     Launch Codex/Claude CLI to review a draft
  implement  Launch Claude CLI to implement review suggestions
  verify     Run test and lint commands directly (Step 7.5)
  status     Show current orchestration state

Options:
  --phase <N>              Phase number (required)
  --prompt-source <file>   File containing the phase prompt (required for draft/review)
  --output <file>          Output file path for draft (required for draft)
  --draft <file>           Draft file to review/revise (required for review/implement)
  --review <file>          Review file with suggestions (required for implement)
  --round <N>              Review round number (required for review/implement)
  --reviewer <agent>       Reviewer agent: codex or claude (default: codex)
  --locked-phases <desc>   Description of locked phases for context
  --design-system <file>   Design system file path for context
  --extra-context <file>   Additional context file to include
  --session <name>         tmux session name (default: auto-detect or phase{N}-orch)
  --output-dir <dir>       Output directory (inferred from --output if not set)
  --test-cmd <cmd>         Test command (e.g., "pytest tests/ -x -q")
  --lint-cmd <cmd>         Lint command (e.g., "ruff check .")
  --bootstrap-reads <f>    Comma-separated list of files agents should read first
  --git-remote <name>      Git remote name (default: "github")
  --git-branch <name>      Git branch (default: auto-detect from git branch --show-current)

Environment:
  GIT_REMOTE    Git remote name (default: github)
  CODEX_MODEL   Model override for Codex CLI
  CLAUDE_MODEL  Model override for Claude Code CLI
EOF
    exit 1
}

[[ $# -lt 1 ]] && usage
COMMAND="$1"; shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)            PHASE_NUM="$2"; shift 2 ;;
        --prompt-source)    PROMPT_SOURCE="$2"; shift 2 ;;
        --output)           OUTPUT_FILE="$2"; shift 2 ;;
        --draft)            DRAFT_FILE="$2"; shift 2 ;;
        --review)           REVIEW_FILE="$2"; shift 2 ;;
        --round)            ROUND="$2"; shift 2 ;;
        --reviewer)         REVIEWER="$2"; shift 2 ;;
        --locked-phases)    LOCKED_PHASES="$2"; shift 2 ;;
        --design-system)    DESIGN_SYSTEM="$2"; shift 2 ;;
        --extra-context)    EXTRA_CONTEXT="$2"; shift 2 ;;
        --session)          TMUX_SESSION="$2"; shift 2 ;;
        --output-dir)       OUTPUT_DIR="$2"; shift 2 ;;
        --test-cmd)         TEST_CMD="$2"; shift 2 ;;
        --lint-cmd)         LINT_CMD="$2"; shift 2 ;;
        --bootstrap-reads)  BOOTSTRAP_READS="$2"; shift 2 ;;
        --git-remote)       GIT_REMOTE="$2"; shift 2 ;;
        --git-branch)       GIT_BRANCH="$2"; shift 2 ;;
        *)                  echo "Unknown option: $1"; usage ;;
    esac
done

# Derive defaults
[[ -z "$PHASE_NUM" ]] && { echo "Error: --phase is required"; exit 1; }
[[ -z "$TMUX_SESSION" ]] && TMUX_SESSION="phase${PHASE_NUM}-orch"
[[ -z "$OUTPUT_DIR" && -n "$OUTPUT_FILE" ]] && OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
[[ -z "$OUTPUT_DIR" && -n "$DRAFT_FILE" ]] && OUTPUT_DIR="$(dirname "$DRAFT_FILE")"
REVIEWER="${REVIEWER:-codex}"

# Auto-detect git branch if not provided
if [[ -z "$GIT_BRANCH" ]]; then
    GIT_BRANCH="$(cd "$PROJECT_ROOT" && git branch --show-current 2>/dev/null || echo "unknown")"
fi

# =============================================================================
# Helpers
# =============================================================================

log() {
    echo "[orchestrate-doc] $(date '+%H:%M:%S') $*"
}

ensure_tmux_session() {
    if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        log "Creating tmux session: $TMUX_SESSION"
        tmux new-session -d -s "$TMUX_SESSION" -n orch "echo 'Orchestrator session ready'; bash"
    fi
}

dispatch_in_window() {
    local window_name="$1"
    local agent="$2"
    local prompt_file="$3"
    local exit_file="/tmp/phase${PHASE_NUM}-${window_name}.exit"

    ensure_tmux_session

    orch_dispatch_tmux_window "$TMUX_SESSION" "$window_name" "$agent" "$prompt_file" "$PROJECT_ROOT" "$exit_file"
    while IFS= read -r line; do
        log "$line"
    done < <(orch_dispatch_summary "$TMUX_SESSION" "$window_name" "$agent" "$exit_file")
    log "Suggested poll cadence: ${DOC_POLL_INTERVAL}s"
    log "Monitor:   tmux capture-pane -t ${TMUX_SESSION}:${window_name} -p | tail -20"
}

write_prompt() {
    local name="$1"
    local prompt="$2"
    local prompt_file="/tmp/phase${PHASE_NUM}-${name}.prompt"
    orch_write_prompt_file "$prompt_file" "$prompt"
    echo "$prompt_file"
}

# Build a context preamble that workers should read
build_context_preamble() {
    local parts=""
    if [[ -n "$LOCKED_PHASES" ]]; then
        parts+="LOCKED CONTEXT: $LOCKED_PHASES are locked and must not be modified.\n"
    fi
    if [[ -n "$DESIGN_SYSTEM" ]]; then
        parts+="Read the design system at $DESIGN_SYSTEM for styling/token references.\n"
    fi
    if [[ -n "$EXTRA_CONTEXT" ]]; then
        parts+="Read additional context from $EXTRA_CONTEXT.\n"
    fi
    echo -e "$parts"
}

# Build structured bootstrap context block for agent orientation.
# Includes project root, git info, test/lint commands, bootstrap reads, and project map.
build_agent_bootstrap() {
    local bootstrap=""

    bootstrap+="## Agent Bootstrap Context\n"
    bootstrap+="- **Project root**: ${PROJECT_ROOT}\n"
    bootstrap+="- **Suite layout**: \`${ORCH_SUITE_LAYOUT}\`\n"
    bootstrap+="- **Guidelines**: Read \`AGENTS.md\` and \`.claude/CLAUDE.md\` when present\n"
    bootstrap+="- **Git remote**: \`${GIT_REMOTE}\` (NOT origin)\n"
    bootstrap+="- **Git branch**: \`${GIT_BRANCH}\`\n"

    if [[ -n "$TEST_CMD" ]]; then
        bootstrap+="- **Test command**: \`${TEST_CMD}\` (run before committing)\n"
    fi
    if [[ -n "$LINT_CMD" ]]; then
        bootstrap+="- **Lint command**: \`${LINT_CMD}\` (run before committing)\n"
    fi

    bootstrap+="- **Commit format**: \`<files-changed> -- <description>\`\n"
    bootstrap+="\n"

    # Bootstrap reads -- files the agent MUST read before starting
    if [[ -n "$BOOTSTRAP_READS" ]]; then
        bootstrap+="### Files to read FIRST (before starting work)\n"
        IFS=',' read -ra reads_array <<< "$BOOTSTRAP_READS"
        for f in "${reads_array[@]}"; do
            # Trim whitespace
            f="$(echo "$f" | xargs)"
            bootstrap+="- \`${f}\`\n"
        done
        bootstrap+="\n"
    fi

    # Project map -- fixed overview of key directories
    bootstrap+="### Project Map\n"
    bootstrap+="- \`.claude/\` -- Claude Code configuration and orchestration scripts\n"
    bootstrap+="- \`src/\` -- Source code\n"
    bootstrap+="- \`tests/\` -- Test suites\n"
    bootstrap+="- \`docs/\` -- Documentation\n"
    bootstrap+="- \`specs/\` -- Specifications and plans\n"
    bootstrap+="- \`planning/\` -- Planning documents and reviews\n"
    bootstrap+="\n"

    echo -e "$bootstrap"
}

# Check the result of a dispatched agent and capture diagnostics on failure.
# Call after polling detects the exit file exists.
check_agent_result() {
    local window_name="$1"
    local exit_file="/tmp/phase${PHASE_NUM}-${window_name}.exit"
    local diag_file="/tmp/phase${PHASE_NUM}-${window_name}.diag"

    if [[ ! -f "$exit_file" ]]; then
        log "WARNING: Exit file not found: $exit_file"
        return 1
    fi

    local exit_code
    exit_code="$(cat "$exit_file")"

    if [[ "$exit_code" != "0" ]]; then
        log "ERROR: Agent '${window_name}' exited with code ${exit_code}"

        # Capture last 50 lines of tmux pane output for diagnostics
        local pane_output=""
        if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
            pane_output="$(tmux capture-pane -t "${TMUX_SESSION}:${window_name}" -p -S -50 2>/dev/null || echo "(tmux pane not available)")"
        else
            pane_output="(tmux session ${TMUX_SESSION} not available)"
        fi

        # Check if any output file was produced
        local output_exists="false"
        if [[ -n "$OUTPUT_FILE" && -s "$OUTPUT_FILE" ]]; then
            output_exists="true ($(wc -l < "$OUTPUT_FILE") lines)"
        elif [[ -n "$DRAFT_FILE" && -s "$DRAFT_FILE" ]]; then
            output_exists="true ($(wc -l < "$DRAFT_FILE") lines)"
        fi

        # Write diagnostic file
        cat > "$diag_file" <<DIAG_EOF
# Agent Failure Diagnostic
- **Window**: ${window_name}
- **Exit code**: ${exit_code}
- **Timestamp**: $(date -Iseconds)
- **Output file exists**: ${output_exists}

## Last 50 lines of tmux pane
\`\`\`
${pane_output}
\`\`\`
DIAG_EOF

        log "Diagnostic written to: $diag_file"
        log "Decision needed: re-dispatch or escalate"
        return 1
    fi

    log "Agent '${window_name}' completed successfully (exit 0)"
    return 0
}

# Write machine-parseable JSON state file alongside the markdown tracker.
write_state_json() {
    local phase="$1"
    local current_step="$2"
    local json_file="${OUTPUT_DIR:-/tmp}/phase-${phase}-state.json"

    # Collect completed steps and exit codes from exit files
    local steps_completed="[]"
    local exit_codes="{}"
    local step_list=""
    local code_list=""

    for f in /tmp/phase"${phase}"-*.exit; do
        [[ -f "$f" ]] || continue
        local step_name
        step_name="$(basename "$f" .exit | sed "s/phase${phase}-//")"
        local code
        code="$(cat "$f")"
        if [[ -n "$step_list" ]]; then
            step_list+=","
            code_list+=","
        fi
        step_list+="\"${step_name}\""
        code_list+="\"${step_name}\":${code}"
    done
    steps_completed="[${step_list}]"
    exit_codes="{${code_list}}"

    cat > "$json_file" <<JSON_EOF
{
  "phase": ${phase},
  "current_step": "${current_step}",
  "git_branch": "${GIT_BRANCH}",
  "git_remote": "${GIT_REMOTE}",
  "timestamp": "$(date -Iseconds)",
  "steps_completed": ${steps_completed},
  "exit_codes": ${exit_codes},
  "test_cmd": "${TEST_CMD}",
  "lint_cmd": "${LINT_CMD}"
}
JSON_EOF

    log "State JSON written to: $json_file"
}

# =============================================================================
# Commands
# =============================================================================

do_draft() {
    [[ -z "$PROMPT_SOURCE" ]] && { echo "Error: --prompt-source required for draft"; exit 1; }
    [[ -z "$OUTPUT_FILE" ]] && { echo "Error: --output required for draft"; exit 1; }

    local bootstrap
    bootstrap="$(build_agent_bootstrap)"

    local context
    context="$(build_context_preamble)"

    local prompt="${bootstrap}
${context}
You are writing Phase ${PHASE_NUM} as a document draft.

INSTRUCTIONS:
1. Read the Phase ${PHASE_NUM} prompt from: ${PROMPT_SOURCE}
   - Find the section for Phase ${PHASE_NUM} and follow its instructions precisely.
2. Read all locked phase documents referenced in the prompt for context.
3. Write the complete Phase ${PHASE_NUM} document to: ${OUTPUT_FILE}
4. The document must be comprehensive and production-ready -- no placeholders, no TODOs for core content.
5. Follow all formatting conventions from prior phases.
6. Commit using: git add <files> && git commit -m '<files-changed> -- <description>'
   - Do NOT push unless the operator explicitly asks.
   - One phase-step per commit; do not batch across phases/rounds.
7. When complete, ensure the file is saved, committed locally, and exit."

    local prompt_file
    prompt_file="$(write_prompt "draft" "$prompt")"
    dispatch_in_window "draft" "claude" "$prompt_file"
    write_state_json "$PHASE_NUM" "draft"
}

do_review() {
    [[ -z "$DRAFT_FILE" ]] && { echo "Error: --draft required for review"; exit 1; }
    [[ -z "$ROUND" ]] && { echo "Error: --round required for review"; exit 1; }

    local review_output="${OUTPUT_DIR}/phase-${PHASE_NUM}-review-r${ROUND}-${REVIEWER}.md"

    local bootstrap
    bootstrap="$(build_agent_bootstrap)"

    # Use the doc-specific review template if available, fall back to standard
    local template_file="${SCRIPT_DIR}/review-prompt-doc-${REVIEWER}.md"
    if [[ ! -f "$template_file" ]]; then
        template_file="${SCRIPT_DIR}/review-prompt-${REVIEWER}.md"
    fi

    local prompt
    if [[ -f "$template_file" ]]; then
        prompt="$(cat "$template_file")"
        prompt="${prompt//\{DRAFT_FILE\}/$DRAFT_FILE}"
        prompt="${prompt//\{PROMPT_SOURCE\}/${PROMPT_SOURCE:-unknown}}"
        prompt="${prompt//\{PHASE_NUM\}/$PHASE_NUM}"
        prompt="${prompt//\{REVIEW_FILE\}/$review_output}"
        prompt="${prompt//\{ROUND\}/$ROUND}"
        prompt="${prompt//\{GIT_REMOTE\}/$GIT_REMOTE}"
        prompt="${prompt//\{GIT_BRANCH\}/$GIT_BRANCH}"
        # Prepend bootstrap to template-rendered prompt
        prompt="${bootstrap}
${prompt}"
    else
        # Inline fallback prompt
        prompt="${bootstrap}
You are reviewing the Phase ${PHASE_NUM} draft document.

DRAFT: ${DRAFT_FILE}
ORIGINAL PROMPT: ${PROMPT_SOURCE:-see draft header for requirements}
ROUND: ${ROUND}

INSTRUCTIONS:
1. Read the draft at ${DRAFT_FILE}.
2. Read the original Phase ${PHASE_NUM} prompt from ${PROMPT_SOURCE:-the draft header} to understand requirements.
3. Review for: completeness against prompt requirements, accuracy, consistency with locked phases, copy quality, structural issues.
4. Write your review to: ${review_output}

OUTPUT FORMAT:
# Review: Phase ${PHASE_NUM} -- Round ${ROUND}
**Reviewer**: ${REVIEWER^}

## MUST FIX
- Description of critical issue. Fix: [exact instruction]

## SHOULD FIX
- Description of improvement. Fix: [exact instruction]

## Verdict: PASS | NEEDS_FIXES | ESCALATE

If a section has no items, omit it. Verdict is PASS only if MUST FIX is empty."
    fi

    local window_name="review-r${ROUND}"
    local prompt_file
    prompt_file="$(write_prompt "$window_name" "$prompt")"
    dispatch_in_window "$window_name" "$REVIEWER" "$prompt_file"
    write_state_json "$PHASE_NUM" "review-r${ROUND}"

    log "Review will be written to: $review_output"
}

do_implement() {
    [[ -z "$DRAFT_FILE" ]] && { echo "Error: --draft required for implement"; exit 1; }
    [[ -z "$REVIEW_FILE" ]] && { echo "Error: --review required for implement"; exit 1; }
    [[ -z "$ROUND" ]] && { echo "Error: --round required for implement"; exit 1; }

    local bootstrap
    bootstrap="$(build_agent_bootstrap)"

    local context
    context="$(build_context_preamble)"

    local prompt="${bootstrap}
${context}
You are implementing review suggestions for Phase ${PHASE_NUM}, Round ${ROUND}.

INSTRUCTIONS:
1. Read the review at: ${REVIEW_FILE}
2. Read the current draft at: ${DRAFT_FILE}
3. Implement ALL items in MUST FIX.
4. Implement items in SHOULD FIX where they improve quality.
5. Update the draft IN PLACE at: ${DRAFT_FILE}
6. Do NOT remove or restructure content that was not flagged in the review.
7. Commit using: git add <files> && git commit -m '<files-changed> -- <description>'
   - Do NOT push unless the operator explicitly asks.
   - One phase-step per commit; do not batch across phases/rounds.
8. When complete, ensure the file is saved, committed locally, and exit.

IMPORTANT: You are updating an existing document. Preserve all content that is not flagged for changes."

    local window_name="implement-r${ROUND}"
    local prompt_file
    prompt_file="$(write_prompt "$window_name" "$prompt")"
    dispatch_in_window "$window_name" "claude" "$prompt_file"
    write_state_json "$PHASE_NUM" "implement-r${ROUND}"
}

do_verify() {
    local exit_code=0

    if [[ -n "$TEST_CMD" ]]; then
        log "Running tests: $TEST_CMD"
        cd "$PROJECT_ROOT"
        if ! eval "$TEST_CMD"; then
            log "VERIFICATION FAILED: Tests did not pass"
            exit_code=1
        fi
    else
        log "No test command configured (use --test-cmd to set one)"
    fi

    if [[ -n "$LINT_CMD" ]]; then
        log "Running lint: $LINT_CMD"
        cd "$PROJECT_ROOT"
        if ! eval "$LINT_CMD"; then
            log "VERIFICATION FAILED: Lint did not pass"
            exit_code=1
        fi
    else
        log "No lint command configured (use --lint-cmd to set one)"
    fi

    if [[ $exit_code -eq 0 ]]; then
        log "VERIFICATION PASSED"
    fi

    # Write verify exit status for state tracking
    echo "$exit_code" > "/tmp/phase${PHASE_NUM}-verify.exit"
    write_state_json "$PHASE_NUM" "verify"

    return $exit_code
}

do_status() {
    echo "=== Phase $PHASE_NUM Orchestration Status ==="
    echo ""

    # Check tmux session
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        echo "tmux session: $TMUX_SESSION (active)"
        tmux list-windows -t "$TMUX_SESSION" 2>/dev/null | sed 's/^/  /'
    else
        echo "tmux session: $TMUX_SESSION (not running)"
    fi
    echo ""

    # Check exit files
    echo "=== Completion status ==="
    for f in /tmp/phase"${PHASE_NUM}"-*.exit; do
        [[ -f "$f" ]] || continue
        local step
        step=$(basename "$f" .exit | sed "s/phase${PHASE_NUM}-//")
        echo "  $step: exit $(cat "$f")"
        # Show diagnostic if present
        local diag="/tmp/phase${PHASE_NUM}-${step}.diag"
        if [[ -f "$diag" ]]; then
            echo "    (diagnostic available: $diag)"
        fi
    done
    echo ""

    # Check output files
    if [[ -n "$OUTPUT_DIR" ]]; then
        echo "=== Files in $OUTPUT_DIR ==="
        find "$OUTPUT_DIR" -maxdepth 1 -type f -name "phase-${PHASE_NUM}*" -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr \
            | head -10 \
            | cut -d' ' -f2- \
            || echo "  No phase files found"
    fi

    # Check tracker
    local tracker="${OUTPUT_DIR:-${PROJECT_ROOT}}/phase-${PHASE_NUM}-orchestration-tracker.md"
    if [[ -f "$tracker" ]]; then
        echo ""
        echo "=== Tracker ==="
        cat "$tracker"
    fi

    # Check JSON state
    local state_json="${OUTPUT_DIR:-/tmp}/phase-${PHASE_NUM}-state.json"
    if [[ -f "$state_json" ]]; then
        echo ""
        echo "=== JSON State ==="
        cat "$state_json"
    fi
}

# =============================================================================
# Main
# =============================================================================

case "$COMMAND" in
    draft)     do_draft ;;
    review)    do_review ;;
    implement) do_implement ;;
    verify)    do_verify ;;
    status)    do_status ;;
    *)         echo "Unknown command: $COMMAND"; usage ;;
esac
