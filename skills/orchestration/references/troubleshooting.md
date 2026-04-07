# Troubleshooting Reference

Covers both bootstrap error scenarios and ongoing operational issues. Each entry lists symptom, cause, and resolution.

---

### Issue: Target Repository Is Not a Git Repository

**Symptom**: Bootstrap detects no `.git/` directory; git commands fail; no ability to track branches or monitor commits.

**Cause**: Target repository was not initialized with `git init` or is a subdirectory of a git repository without its own `.git/`.

**Resolution**: Initialize git with `git init`, configure remote (`git remote add`), and ensure a default branch exists (`git checkout -b main`). Bootstrap can continue in degraded mode, but orchestration features requiring git (branch tracking, worktree creation, commit monitoring) will be unavailable. Reinitialize and re-run bootstrap.

---

### Issue: Canonical Orchestration Files Missing from Source

**Symptom**: Bootstrap fails while copying or validating orchestration scripts; specific files listed as missing (e.g., `scripts/orchestrate-loop.sh`, `bootstrap-prompt.md`).

**Cause**: The orchestration repository itself is incomplete; vendored copy path does not contain required reference files.

**Resolution**: Do not improvise replacements. Stop bootstrap and identify all missing files. Verify the source repository checkout is complete (`git status`, `git log`). If confirmed incomplete, contact the orchestration maintainer or sync the source. Re-run bootstrap after source is complete.

---

### Issue: Conflicting Orchestration Material in Target Repository

**Symptom**: Bootstrap detects existing `orchestration-state.env`, `scripts/orchestrate-loop.sh`, or `.claude/orchestration/` directory with conflicting or incomplete content; unclear whether to overwrite.

**Cause**: Target repository has partial orchestration setup from a previous attempt, different orchestration version, or manual configuration that may conflict.

**Resolution**: Do not silently overwrite. Describe the conflict: which files exist, which are outdated, and what configuration differs. Recommend in order of preference: (1) reconcile — merge old and new configs, keeping what's still valid; (2) overwrite — replace existing files entirely and validate after; (3) copy to a new branch — preserve old state and test new setup independently. Run validation checklist after reconciliation.

---

### Issue: Prompt-Driven Install Produced Unexpected Layout

**Symptom**: After a prompt-driven install session, files are missing or misplaced; actual directory structure does not match expected layout documented in `references/install-paths.md`.

**Cause**: Prompt session was interrupted, or responses to configuration questions resulted in non-standard paths or missing script generation.

**Resolution**: Compare actual file layout against the expected map in `references/install-paths.md`. Identify missing or misplaced files. Re-run bootstrap with vendored copy path (canonical mode) to force standard layout. If bootstrap still produces errors, see "Canonical Orchestration Files Missing" above.

---

### Issue: No Viable Runtime Available

**Symptom**: Bootstrap cannot find native subagent support and `tmux` is not installed; no viable execution model exists for orchestration.

**Cause**: Host platform does not support native subagent delegation, `tmux` is missing, and fallback modes are not available.

**Resolution**: Install `tmux` (recommended for shell-based multi-session mode), switch to a platform that supports native subagents (Claude built-in agent delegation), or use single-session fallback if running in Claude Code interactive mode. Stop bootstrap and address prerequisites before retry. Do not proceed with a degraded runtime that cannot dispatch tasks.

---

### Issue: Agent Dispatch Failures

**Symptom**: Tasks fail to dispatch or agent windows never appear; tmux window creation errors or agent session hangs with no progress.

**Cause**: Common tmux-mode issues: tmux session not running, agent window creation failed, agent CLI is not installed, or script paths are incorrect.

**Resolution**: (1) Verify tmux session exists: `tmux list-sessions`. (2) Check agent CLI installation: `which claude` or equivalent. (3) Verify script paths in `orchestration-state.env` match actual locations. (4) Review agent logs: `tmux capture-pane -p -S -30` in the target window. (5) Manually create a test window: `tmux new-window -t SESSION_NAME` to confirm tmux is responsive. (6) Re-run orchestration loop after fix.

---

### Issue: Regression Test Failures After Documentation Changes

**Symptom**: After renaming, moving, or updating orchestration reference files, tests in `tests/runtime-regressions.sh` fail with path resolution errors or missing file warnings.

**Cause**: File renames or moves were not reflected in test expectations or hardcoded path references in bootstrap scripts.

**Resolution**: Run regression test suite: `bash tests/runtime-regressions.sh`. Review failure messages for specific file or path mismatches. Update test expectations to match new paths. If failures relate to hardcoded path constants in `scripts/orchestrate-loop.sh` or `scripts/lib/orch-agent-runtime.sh`, update those constants. Re-run tests and confirm all pass before committing changes.

---

## See Also

- `bootstrap-flow.md` — Bootstrap decision tree and error exits
- `install-paths.md` — Standard file layout and installation options
- `runtime-modes.md` — Native subagent vs tmux multi-session execution models
