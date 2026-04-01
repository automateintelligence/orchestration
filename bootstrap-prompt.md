# Orchestration Bootstrap Prompt
# ========================================================================
# USAGE: Paste this into a new Claude session to configure the orchestration
#        protocol for a new project. Claude will ask clarifying questions,
#        then generate the launch artifacts.
#
# This is a meta-prompt — it produces project-specific orchestration config.
# ========================================================================

You are setting up the multi-agent orchestration protocol for a new project.

## Your Task

Guide me through configuring the orchestration protocol, then generate the
launch artifacts. You will:

1. **Gather context** — ask me targeted questions about the project
2. **Generate configuration** — produce the files needed to run orchestration
3. **Produce the launch command** — give me a ready-to-execute tmux command

## Step 1: Context Gathering

Ask me these questions ONE GROUP AT A TIME (don't dump all at once).
Skip any I've already answered in my initial message.

### Group A — Project Identity
- What is the project name and a one-sentence description?
- Where is the project root? (absolute path)
- What git remote name does this project use? (default: `github`)
- What branch should orchestration work on?

### Group B — Specifications
- Where is the spec/plan directory? (e.g., `specs/my-feature/`)
- Does a `tasks.md` exist there already, or do you need me to help create one?
- Where is the plan file? (e.g., `specs/my-feature/plan.md`)

### Group C — Tech Stack & Quality
- What language(s) and frameworks? (determines test/lint commands)
- What is the test command? (e.g., `pytest tests/ -x -q`, `npm test`)
- What is the lint command? (e.g., `ruff check .`, `npm run lint`)
- Are there specific files every agent should read before starting work?
  (e.g., CLAUDE.md, architecture docs, coding standards)

### Group D — Execution Mode
- Is this a vendored `.claude/orchestration/` copy inside the project repo (primary), or a standalone checkout of the suite for local development?
- Multi-session (tmux + Codex CLI + Claude CLI) or single-session (Claude Code with Task tool)?
- If you want single-session mode, is that a deliberate fallback from the canonical tmux workflow?
- How many review rounds per task? (default: 2 for docs, 3 for code)
- Any directories that should be treated as "off-limits" for drift detection?
- Any repo-specific parallel conflict boundaries that should gate `[P]` batches before dispatch?
- Do you want shared polling defaults, or separate code/doc polling intervals?

## Step 2: Generate Configuration

After gathering context, produce these artifacts:

### Artifact 1: orchestration-state.env
```env
LAST_IMPLEMENTER=
TASKS_PROCESSED=0
TASKS_PASSED=0
TASKS_FAILED=0
ESCALATION_COUNT=0
TASKS_FILE={tasks_file}
BRANCH={branch}
SPECS_PATH={specs_path}
PLAN_FILE={plan_file}
GIT_REMOTE={git_remote}
TEST_CMD={test_cmd}
LINT_CMD={lint_cmd}
BOOTSTRAP_READS={bootstrap_reads}
ORCH_POLL_INTERVAL={shared_poll_interval_or_blank}
ORCH_CODE_POLL_INTERVAL={code_poll_interval_or_blank}
ORCH_DOC_POLL_INTERVAL={doc_poll_interval_or_blank}
ORCH_PARALLEL_GROUP_HOOK={parallel_group_hook_or_blank}
TIMESTAMP=
```

### Artifact 2: Agent Bootstrap Block
Generate the `build_agent_bootstrap()` output customized for this project:

```markdown
## Agent Bootstrap Context
- **Project root**: {project_root}
- **Project**: {project_name} — {description}
- **Suite layout**: `{suite_layout}` (`vendored` preferred, `standalone` supported for local suite development)
- **Guidelines**: Read `AGENTS.md` and `{claude_md_path}` when present
- **Git remote**: `{git_remote}` (NOT origin)
- **Git branch**: `{branch}`
- **Test command**: `{test_cmd}` (run before committing)
- **Lint command**: `{lint_cmd}` (run before committing)
- **Commit format**: `<files-changed> — <description>`

### Files to read FIRST (before starting work)
{bootstrap_reads_as_bullet_list}

### Project Map
{project_specific_directory_map}
```

### Artifact 3: Launch Command
For multi-session mode:
```bash
tmux new-session -s orchestrator \
  '{project_root}/.claude/orchestration/scripts/orchestrate-loop.sh \
   {tasks_file} {branch} \
   --specs {specs_path} \
   --plan {plan_file} \
   --test-cmd "{test_cmd}" \
   --lint-cmd "{lint_cmd}" \
   --bootstrap-reads "{bootstrap_reads}" \
   --git-remote {git_remote} \
   --env {env_file}'
```

For standalone suite development, adjust the script path to `{project_root}/scripts/orchestrate-loop.sh`.

For single-session mode, produce a TodoWrite-based execution plan and label it as a fallback to the canonical multi-session path.

### Artifact 4: Quick Reference Card
A 10-line cheat sheet for monitoring the orchestration run:
```
# Monitor
tmux attach -t orchestrator
tail -f planning/orchestration-log.md
# Task progress
grep -cE '^\- \[([ xo])\]' {tasks_file}
# Git progress
git log --oneline -5
# Stop gracefully
tmux send-keys -t orchestrator C-c
# Resume
.claude/orchestration/scripts/orchestrate-loop.sh {tasks_file} {branch} --resume
```

## Step 3: Validation Checklist

Before handing off, verify:
- [ ] tasks.md exists and has `- [ ]` formatted tasks
- [ ] plan.md exists and is referenced correctly
- [ ] Test command runs successfully from project root
- [ ] Lint command runs successfully from project root
- [ ] Git branch exists and is checked out
- [ ] `.claude/orchestration/` directory exists with scripts
- [ ] Bootstrap reads files all exist

## Prompt Engineering Principles Applied

This prompt uses several key patterns:

1. **Progressive disclosure** — Questions in groups, not all at once
2. **Structured output** — Explicit artifact templates with placeholders
3. **Skip logic** — "Skip any I've already answered"
4. **Validation gate** — Checklist before execution
5. **Dual-path** — Different outputs for multi-session vs single-session
6. **Concrete examples** — Every placeholder has an example value
7. **Self-contained** — The prompt includes everything needed, no external lookups
