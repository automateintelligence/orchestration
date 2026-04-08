---
skill: orchestration
description: Install, configure, and operate multi-agent task orchestration in a repository.
entry_points:
  - orchestration
  - orchestration:install
  - orchestration:init
triggers:
  - new repo setup needing orchestration
  - existing orchestration needing validation or troubleshooting
  - guidance on launching or resuming an orchestration run
---

## When to Use

**Bootstrapping**: The target repository has no orchestration configuration or is
partially configured (missing `orchestration-state.env`, missing scripts, or an
incomplete bootstrap). Use this path to generate all launch artifacts from scratch.

**Operating**: The target repository already has orchestration installed and a
`tasks.md` ready. Use this path to validate the install, launch or resume a run,
or diagnose a stalled or failed orchestration session.

**Installing only**: The user wants to copy runtime files into the target repository
without running the full bootstrap. Use `/orchestration:install` for this.

---

## Entry Points

1. **`/orchestration`** — Full auto. Detect → install if needed → bootstrap if
   unconfigured → operate if ready.
2. **`/orchestration:install`** — Install runtime files only. Stop after install;
   do not bootstrap.
3. **`/orchestration:init`** — Bootstrap only. Requires runtime files already
   installed. Error if not: "Orchestration files not found. Run
   `/orchestration:install` first."

---

## Decision Order

### Step 1 — Detect

Run these commands:

```bash
# Check vendored install
ls .claude/orchestration/scripts/orchestrate-loop.sh 2>/dev/null && echo "INSTALLED" || echo "NOT_INSTALLED"
# Check for state file
ls .claude/orchestration-state.env orchestration-state.env 2>/dev/null && echo "HAS_STATE" || echo "NO_STATE"
# Check for tasks file
find . -name "tasks.md" -path "*/specs/*" 2>/dev/null | head -1
```

Route based on results:

- `NOT_INSTALLED` → Step 2 (install)
- `INSTALLED` + `NO_STATE` → Step 3 (bootstrap)
- `INSTALLED` + `HAS_STATE` → Step 5 (operate)
- Entry point `/orchestration:install` → go to Step 2, stop after install
- Entry point `/orchestration:init` → verify `INSTALLED` first; if `NOT_INSTALLED`,
  stop with error: "Orchestration files not found. Run `/orchestration:install`
  first." Otherwise go to Step 3.

---

### Step 2 — Install

Ask the user: "Where is the orchestration source repo? (e.g., `~/code/orchestration`,
or a git URL to clone from)"

If the user provides a local path, verify it contains `install.sh`:

```bash
[ -f "$SRC/install.sh" ] && echo "SOURCE_OK" || echo "NO_INSTALL_SCRIPT"
```

If `NO_INSTALL_SCRIPT`, fall back to copying files individually per the manifest in
`references/install-paths.md` (mkdir + cp each file).

Run the installer from the target repository root:

```bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
"$SRC/install.sh" .claude/orchestration
```

Verify the directory layout matches `references/install-paths.md`. If any file is
missing, list what is absent and stop.

If entry point is `/orchestration:install`, stop here and show:
"Installed. Run `/orchestration:init` to configure, or paste
`.claude/orchestration/bootstrap-prompt.md` into a session."

Otherwise continue to Step 3.

---

### Step 3 — Bootstrap: Capability Detection

Run automatically — do not ask the user:

```bash
git rev-parse --git-dir 2>/dev/null && echo "GIT: yes" || echo "GIT: no"
command -v tmux >/dev/null 2>&1 && echo "TMUX: yes" || echo "TMUX: no"
command -v codex >/dev/null 2>&1 && echo "CODEX: yes" || echo "CODEX: no"
command -v claude >/dev/null 2>&1 && echo "CLAUDE_CLI: yes" || echo "CLAUDE_CLI: no"
```

Native subagent support is a self-check, not a Bash check: if you (the AI reading
this) can dispatch subagents via Task tool or Agent tool, native subagent support
is available.

Pre-fill the runtime recommendation based on detected capabilities. Do not ask the
user to choose — recommend a mode and let them override:

- Native subagents available → recommend native subagent mode
- No native subagents + TMUX + (CODEX or CLAUDE_CLI) → recommend tmux mode
- Otherwise → recommend single-session mode

---

### Step 4 — Bootstrap: Context Gathering and Artifact Generation

Read `.claude/orchestration/bootstrap-prompt.md` for the full question catalog and
artifact templates. Execute the bootstrap inline:

**4a. Auto-detect before asking:**

```bash
git rev-parse --show-toplevel 2>/dev/null
git remote get-url github 2>/dev/null || git remote get-url origin 2>/dev/null
git branch --show-current 2>/dev/null
for f in package.json Gemfile requirements.txt pyproject.toml go.mod Cargo.toml; do [ -f "$f" ] && echo "$f"; done
```

**4b. Ask only what cannot be detected.** Present auto-detected values for
confirmation. Group remaining questions per `bootstrap-prompt.md` Groups A–D,
skipping already-answered items.

**4c. Generate artifacts** per `bootstrap-prompt.md` Step 2 templates:

- Write `.claude/orchestration-state.env` (canonical path, co-located with scripts).
- Generate the agent bootstrap context block (include in output).
- Generate the launch command for the recommended runtime mode.
- Generate the quick reference card.

**4d. Run validation checklist automatically** (the checklist from
`bootstrap-prompt.md` Step 3). Report pass/fail for each item.

**4e. Show:** file layout, generated state file contents, and exact next command.

---

### Step 5 — Operate

When orchestration is installed and `orchestration-state.env` is present:

1. Validate: confirm scripts are present, state file is readable, and `tasks.md`
   exists with at least one `- [ ]` item.
2. Show status: count of pending and completed tasks, current branch.
3. Present the launch or resume command for the configured runtime mode.
4. Point to `references/troubleshooting.md` for any issues.

---

## Outputs

### Bootstrap path produces

- `orchestration-state.env` — populated env file with project-specific values
- Agent bootstrap context block — ready-to-paste context for the first agent session
- Launch command or next-step guidance — either a tmux command (multi-session) or
  a native subagent invocation plan (single-session)
- Expected file layout — directory map showing where scripts, specs, and state
  files should live relative to the project root

### Operate path produces

- Validation report — confirms scripts are present, env vars are set, tasks.md is
  readable, and test/lint commands execute without error
- Launch or resume instructions — the exact command to start or continue the
  orchestration run from the current task state
- Relevant doc pointers — links to sections of `orchestration-protocol.md` or
  reference files that apply to the current issue or question

---

## References

| File | Purpose |
|------|---------|
| `references/bootstrap-flow.md` | Bootstrap decision tree: detection, capability check, install path, artifact generation |
| `references/install-paths.md` | Installation options: vendored vs standalone, directory layouts |
| `references/runtime-modes.md` | Runtime model detail: native subagents, tmux multi-session, capability detection |
| `references/troubleshooting.md` | Common issues: bootstrap errors, dispatch failures, regression test failures |

---

## Platform Notes

This skill runs in both Claude and Codex.

- **Claude**: package as a zip of the `skills/orchestration/` directory with the
  skill folder as the archive root. This zip is a release artifact generated
  during packaging — it is not checked into the repository.
- **Codex**: use the `skills/orchestration/` directory directly from the checked-out
  source tree. No separate copy or divergent implementation is needed.
