# Bootstrap Decision Tree

Maps the bootstrap workflow. The executable prompt lives at `bootstrap-prompt.md` in the repository root.

## Entry Conditions

Bootstrap runs when orchestration is absent or partially installed in the target repository, or the user explicitly requests setup.

## Decision Tree

1. **Inspect target repo** for existing orchestration assets:
   - `orchestration-state.env` or `.claude/orchestration-state.env`
   - `scripts/orchestrate-loop.sh`
   - `tasks.md` with pending items
   - `.claude/orchestration/` directory

2. **Classify state**: Absent → fully install. Partial → warn and reconcile. Already installed → proceed to step 3.

3. **If already installed** → exit bootstrap, route to operate flow.

4. **Check capabilities**:
   - Is `git` present? (required)
   - Does the host support native subagent delegation? (primary runtime)
   - Is `tmux` available? (optional compatibility mode)

5. **Recommend install path**:
   - **Canonical**: vendored copy of orchestration suite in `.claude/orchestration/` (see `install-paths.md`)
   - **Convenience**: prompt-driven configuration in this session (still produces the same files)

6. **Gather project context** via question groups A-D (see `bootstrap-prompt.md` Step 1 for full catalog):
   - A: Project identity (name, root, git remote, branch)
   - B: Specifications (spec directory, tasks.md location, plan file)
   - C: Tech stack and quality (languages, test/lint commands, bootstrap reads)
   - D: Execution mode (vendored vs standalone, multi-session vs single-session, polling defaults)

7. **Recommend runtime mode** based on capabilities (see `runtime-modes.md`):
   - Native subagents (primary: Claude built-in agent, Codex native delegation)
   - tmux multi-session (optional: shell-based orchestration with separate panes)

8. **Generate artifacts** (see `bootstrap-prompt.md` Step 2):
   - `orchestration-state.env` with project-specific values
   - Agent bootstrap context block (ready-to-paste for first session)
   - Launch command or next-step guidance
   - Quick reference card for monitoring

9. **Run validation checklist** (see `bootstrap-prompt.md` Step 3):
   - tasks.md exists with `- [ ]` formatted items
   - plan.md exists and is referenced correctly
   - Test and lint commands run successfully
   - Git branch exists and is checked out
   - `.claude/orchestration/` scripts are present
   - Bootstrap reads files all exist

10. **Present expected file layout and next-step commands** — show where scripts, specs, and state files should live relative to the project root, then provide either a tmux session launch or a native subagent execution plan with specific task numbers to start.

## Error Exits

Bootstrap stops clearly in these cases:

1. **Target is not a git repository** → Bootstrap can continue in degraded state, but orchestration will be limited until git is initialized. Recommend `git init`.

2. **Canonical orchestration files missing** → Stop and list which files are missing from the orchestration repository. Bootstrap cannot improvise; the reference files must be present.

3. **Conflicting orchestration material exists** → Describe the conflict. Recommend reconcile, overwrite, or copy to a new branch instead of silent replacement.

4. **Prompt-driven install path chosen** → Still show the resulting expected file layout so the install remains auditable and transparent.

5. **No viable runtime available** → Neither native subagents nor tmux are viable. Stop with a concrete explanation instead of pretending setup succeeded.

## Canonical Reference

For the full question catalog, artifact templates, validation checklist, and prompt engineering principles, see `bootstrap-prompt.md` in the repository root.

See also:
- `install-paths.md` — Installation options (vendored vs standalone, directory layouts)
- `runtime-modes.md` — Runtime model detail (native subagents, tmux multi-session, capability detection)
- `troubleshooting.md` — Common bootstrap issues and resolution paths
