#!/bin/bash

# Shared runtime helpers for orchestration dispatch scripts.

orch_resolve_paths() {
    local script_dir="$1"
    local suite_root
    suite_root="$(cd "$script_dir/.." && pwd)"

    ORCH_SUITE_ROOT="$suite_root"
    if [[ "$(basename "$suite_root")" == "orchestration" ]] && [[ "$(basename "$(dirname "$suite_root")")" == ".claude" ]]; then
        ORCH_SUITE_LAYOUT="vendored"
        ORCH_PROJECT_ROOT="$(cd "$suite_root/../.." && pwd)"
    else
        ORCH_SUITE_LAYOUT="standalone"
        ORCH_PROJECT_ROOT="$suite_root"
    fi
}

orch_default_state_file() {
    local mode="${1:-code}"
    if [[ "$ORCH_SUITE_LAYOUT" == "vendored" ]]; then
        echo "$ORCH_PROJECT_ROOT/.claude/orchestration-state.env"
    else
        case "$mode" in
            code) echo "$ORCH_SUITE_ROOT/orchestration-state.env" ;;
            doc) echo "$ORCH_SUITE_ROOT/orchestration-doc-state.env" ;;
            *) echo "$ORCH_SUITE_ROOT/orchestration-state.env" ;;
        esac
    fi
}

orch_default_poll_interval() {
    local mode="${1:-code}"
    local shared="${ORCH_POLL_INTERVAL:-}"

    case "$mode" in
        code)
            echo "${ORCH_CODE_POLL_INTERVAL:-${shared:-30}}"
            ;;
        doc)
            echo "${ORCH_DOC_POLL_INTERVAL:-${shared:-15}}"
            ;;
        *)
            echo "${shared:-30}"
            ;;
    esac
}

orch_write_prompt_file() {
    local prompt_file="$1"
    local prompt="$2"
    printf '%s' "$prompt" > "$prompt_file"
}

orch_build_agent_command() {
    local agent="$1"
    local prompt_file="$2"
    local work_dir="$3"
    local work_dir_q
    local prompt_file_q

    work_dir_q=$(printf '%q' "$work_dir")
    prompt_file_q=$(printf '%q' "$prompt_file")

    if [[ "$agent" == "codex" ]]; then
        printf 'cd %s && codex exec "$(cat %s)" --full-auto' "$work_dir_q" "$prompt_file_q"
        if [[ -n "${CODEX_MODEL:-}" ]]; then
            printf ' -m %q' "$CODEX_MODEL"
        fi
    else
        printf 'cd %s && env -u CLAUDECODE claude -p "$(cat %s)" --dangerously-skip-permissions' "$work_dir_q" "$prompt_file_q"
        if [[ -n "${CLAUDE_MODEL:-}" ]]; then
            printf ' --model %q' "$CLAUDE_MODEL"
        fi
    fi
}

orch_wrap_command_with_exit_capture() {
    local command="$1"
    local exit_file="$2"
    local exit_file_q
    exit_file_q=$(printf '%q' "$exit_file")
    printf '%s; status=$?; printf "%%s" "$status" > %s; exit "$status"' "$command" "$exit_file_q"
}

orch_write_agent_script() {
    local script_file="$1"
    local agent="$2"
    local prompt_file="$3"
    local work_dir="$4"
    local exit_file="$5"
    local command
    local wrapped_command

    command="$(orch_build_agent_command "$agent" "$prompt_file" "$work_dir")"
    wrapped_command="$(orch_wrap_command_with_exit_capture "$command" "$exit_file")"

    cat > "$script_file" <<EOF
#!/bin/bash
set -euo pipefail
$wrapped_command
EOF
    chmod +x "$script_file"
}

orch_dispatch_tmux_window() {
    local session_name="$1"
    local window_name="$2"
    local agent="$3"
    local prompt_file="$4"
    local work_dir="$5"
    local exit_file="$6"
    local replace_existing="${7:-true}"
    local command
    local wrapped_command

    command="$(orch_build_agent_command "$agent" "$prompt_file" "$work_dir")"
    wrapped_command="$(orch_wrap_command_with_exit_capture "$command" "$exit_file")"

    if [[ "$replace_existing" == "true" ]]; then
        tmux kill-window -t "${session_name}:${window_name}" 2>/dev/null || true
    fi
    rm -f "$exit_file"

    tmux new-window -t "$session_name" -n "$window_name" bash -lc "$wrapped_command"
}

orch_run_agent_direct() {
    local agent="$1"
    local prompt_file="$2"
    local work_dir="${3:-$ORCH_PROJECT_ROOT}"
    local command

    command="$(orch_build_agent_command "$agent" "$prompt_file" "$work_dir")"
    eval "$command"
}
