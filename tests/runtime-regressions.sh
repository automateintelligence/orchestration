#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/orch-agent-runtime.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message (expected: $expected, got: $actual)"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    [[ "$haystack" == *"$needle"* ]] || fail "$message (missing: $needle)"
}

assert_gt() {
    local left="$1"
    local right="$2"
    local message="$3"
    (( left > right )) || fail "$message (left: $left, right: $right)"
}

test_path_resolution() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    mkdir -p "$tmpdir/project/.claude/orchestration/scripts"
    orch_resolve_paths "$tmpdir/project/.claude/orchestration/scripts"
    assert_eq "vendored" "$ORCH_SUITE_LAYOUT" "vendored layout should be detected"
    assert_eq "$tmpdir/project" "$ORCH_PROJECT_ROOT" "vendored project root should resolve to consuming repo"
    assert_eq "$tmpdir/project/.claude/orchestration-state.env" "$(orch_default_state_file code)" "vendored code state file should live under .claude"
    assert_eq "$tmpdir/project/.claude/orchestration-state.env" "$(orch_default_state_file doc)" "vendored doc state file should live under .claude"

    mkdir -p "$tmpdir/orchestration/scripts"
    orch_resolve_paths "$tmpdir/orchestration/scripts"
    assert_eq "standalone" "$ORCH_SUITE_LAYOUT" "standalone layout should be detected"
    assert_eq "$tmpdir/orchestration" "$ORCH_PROJECT_ROOT" "standalone project root should resolve to suite root"
    assert_eq "$tmpdir/orchestration/orchestration-state.env" "$(orch_default_state_file code)" "standalone code state file should live in suite root"
    assert_eq "$tmpdir/orchestration/orchestration-doc-state.env" "$(orch_default_state_file doc)" "standalone doc state file should live in suite root"

    trap - RETURN
    rm -rf "$tmpdir"
}

test_poll_defaults() {
    unset ORCH_POLL_INTERVAL ORCH_CODE_POLL_INTERVAL ORCH_DOC_POLL_INTERVAL
    assert_eq "30" "$(orch_default_poll_interval code)" "default code poll interval should be 30"
    assert_eq "15" "$(orch_default_poll_interval doc)" "default doc poll interval should be 15"

    ORCH_POLL_INTERVAL=22
    unset ORCH_CODE_POLL_INTERVAL ORCH_DOC_POLL_INTERVAL
    assert_eq "22" "$(orch_default_poll_interval code)" "shared poll interval should apply to code mode"
    assert_eq "22" "$(orch_default_poll_interval doc)" "shared poll interval should apply to doc mode"

    ORCH_CODE_POLL_INTERVAL=11
    ORCH_DOC_POLL_INTERVAL=7
    assert_eq "11" "$(orch_default_poll_interval code)" "code-specific poll interval should override shared value"
    assert_eq "7" "$(orch_default_poll_interval doc)" "doc-specific poll interval should override shared value"
}

test_parallel_review_gate() {
    local file="$REPO_ROOT/scripts/orchestrate-loop.sh"
    local review_line
    local merge_line
    local cleanup_line

    review_line="$(rg -n 'build_review_prompt "\$sub_branch"' "$file" | head -1 | cut -d: -f1)"
    merge_line="$(rg -n 'if merge_worktree "\$task_id" "\$BRANCH"' "$file" | head -1 | cut -d: -f1)"
    cleanup_line="$(rg -n 'cleanup_worktree "\$task_id" "\$BRANCH"' "$file" | head -1 | cut -d: -f1)"

    [[ -n "$review_line" && -n "$merge_line" && -n "$cleanup_line" ]] || fail "parallel review-gate markers should be present"
    assert_gt "$merge_line" "$review_line" "parallel merge should happen after review setup"
    assert_gt "$cleanup_line" "$review_line" "parallel cleanup should happen after review setup"
}

test_hardened_claude_launches() {
    assert_contains "$(cat "$REPO_ROOT/scripts/lib/orch-agent-runtime.sh")" 'env -u CLAUDECODE claude -p' "runtime helper should harden Claude launches"
    assert_contains "$(cat "$REPO_ROOT/scripts/orchestrate-loop.sh")" 'env -u CLAUDECODE claude -p' "verdict parser fallback should harden Claude launches"
}

test_vendored_dispatch_target() {
    assert_contains "$(cat "$REPO_ROOT/makefile-targets.mk")" '.claude/orchestration/scripts/dispatch.sh' "makefile should point to vendored dispatch path"
}

test_install_registers_project_skills() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    mkdir -p "$tmpdir/project"
    (
        cd "$tmpdir/project"
        "$REPO_ROOT/install.sh" .claude/orchestration >/dev/null
    )

    [[ -f "$tmpdir/project/.claude/commands/orchestration.md" ]] || fail "install.sh should register the Claude Code /orchestration command"
    [[ -f "$tmpdir/project/.codex/skills/orchestration/SKILL.md" ]] || fail "install.sh should register the Codex orchestration skill"
    [[ -f "$tmpdir/project/.codex/skills/orchestration/references/install-paths.md" ]] || fail "Codex orchestration skill should include its references"

    assert_contains "$(cat "$tmpdir/project/.codex/skills/orchestration/SKILL.md")" "skill: orchestration" "installed Codex skill should expose the orchestration entry point"

    trap - RETURN
    rm -rf "$tmpdir"
}

main() {
    test_path_resolution
    test_poll_defaults
    test_parallel_review_gate
    test_hardened_claude_launches
    test_vendored_dispatch_target
    test_install_registers_project_skills
    echo "runtime regressions: PASS"
}

main "$@"
