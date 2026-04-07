# Executable Orchestration Skill

- Date: 2026-04-07
- Status: Draft
- Scope: Make the orchestration skill execute install and bootstrap inline instead of handing off to the user.

## Problem

The skill currently describes what to do but never does it. The user invokes `/orchestration`, the skill says "orchestration is absent, run install.sh", the user switches to a terminal, runs the script, comes back, and then has to paste `bootstrap-prompt.md` into a session. Three handoffs for what should be zero.

## Goal

Invoking the skill in a project repo should produce a fully configured orchestration setup with no terminal detours and no copy-pasting markdown files.

## Design

### Entry Points

**`/orchestration`** — The main entry point. Detects state and routes:
- Absent → install + bootstrap (full flow)
- Partial → diagnose what's missing, offer to fix, then bootstrap if needed
- Installed but unconfigured → bootstrap only
- Installed and configured → operate flow (validate, launch guidance, troubleshooting)

**`/orchestration:install`** — Install runtime files only. No bootstrap. For users who want to configure manually.

**`/orchestration:init`** — Bootstrap only. Assumes files are already installed. Errors if they're not.

### Install Flow (replaces install.sh handoff)

The skill has Bash access. When orchestration is absent:

1. Locate the source repo. Check these paths in order:
   - `~/.claude/orchestration/` (common local checkout)
   - The skill's own containing repo (if invoked from a vendored skill)
   - Ask the user if neither is found.

2. Run the equivalent of `install.sh` directly via Bash. Copy only the runtime files listed in `references/install-paths.md`.

3. Verify the resulting layout matches the expected tree.

4. If install succeeds, flow directly into bootstrap. No pause, no handoff.

### Bootstrap Flow (replaces bootstrap-prompt.md paste)

The skill runs the bootstrap questions inline in the conversation instead of requiring the user to paste a markdown prompt. The question catalog and artifact templates from `bootstrap-prompt.md` become the skill's internal logic, not a user-facing document.

The flow:

1. **Capability detection** — Check `git`, native subagent support, `tmux` availability via Bash. Pre-fill answers where possible instead of asking.

2. **Context gathering** — Ask Groups A-D from the bootstrap prompt, one group at a time. Skip questions the skill can answer by inspecting the repo (project root, git remote, branch, language detection via file extensions).

3. **Artifact generation** — Write `orchestration-state.env` directly. Generate the agent bootstrap block. Produce the launch command for the detected runtime mode.

4. **Validation** — Run the validation checklist from `bootstrap-prompt.md` Step 3 automatically. Report any failures.

5. **Output** — Show the expected file layout, the generated state file, and the exact next command to start orchestration.

### What Changes

| File | Change |
|------|--------|
| `skills/orchestration/SKILL.md` | Rewrite decision order to execute instead of describe. Add install and bootstrap logic. |
| `skills/orchestration/references/bootstrap-flow.md` | Update to reflect that the skill runs this flow, not the user. |
| `bootstrap-prompt.md` | Keep as fallback reference. Add a note that the skill runs this automatically. |
| `README.md` | Update Getting Started to show skill invocation as primary, `bootstrap-prompt.md` paste as fallback. |

### What Doesn't Change

- `install.sh` — stays as a standalone CLI tool for users without the skill
- `scripts/` — runtime scripts unchanged
- `orchestration-protocol.md` — protocol unchanged
- `references/install-paths.md`, `runtime-modes.md`, `troubleshooting.md` — content unchanged, still accurate

## Non-Goals

1. Auto-detecting project language with high accuracy (ask if uncertain).
2. Auto-launching the orchestration loop after bootstrap (present the command, let the user run it).
3. Changing the orchestration runtime behavior.

## Error Handling

1. Source repo not found → ask the user for the path. If they don't have it, point to the GitHub clone command.
2. Target `.claude/orchestration/` already exists with conflicting files → follow existing troubleshooting guidance (reconcile → overwrite → copy).
3. `git` not available → warn, continue in degraded mode.
4. Validation checklist fails → show failures, offer to fix.

## Success Criteria

1. `/orchestration` in a bare git repo produces a fully configured orchestration setup in one conversation turn (no terminal detours).
2. `/orchestration:install` copies files without bootstrapping.
3. `/orchestration:init` bootstraps without copying files.
4. `bootstrap-prompt.md` still works as a standalone paste-and-go fallback.
5. `install.sh` still works as a standalone CLI tool.
