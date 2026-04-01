# Orchestration Protocol

> **Authority**: This protocol governs multi-agent development orchestration.
> **Primary Orchestrator**: Claude (via Claude.ai + Desktop Commander WSL access)
> **Execution Agent (Code Implementation)**: Codex CLI (default implementer)
> **Review Agent**: Claude Code CLI
> **Architect**: Project lead -- owns specifications, direction, and final acceptance
> **Orchestrator Authority**: Claude -- owns execution planning, clarification, dispatch, review cycles, and cross-agent coordination

---

## 1. Command Hierarchy

### Project Lead (Architect)
- Owns all specifications and architectural decisions
- Provides goals (loose or detailed) and approves plans before execution
- Drives brainstorming sessions (often via `/superpowers:brainstorm`)
- Manually tests major features at completion milestones
- Configures external services (API keys, etc.)

### Claude -- Orchestrator (this agent)
- Reads codebase and specs via Desktop Commander + WSL
- Drives SpecKit or SuperPowers to produce executable plans
- Dispatches tasks to Codex and Claude Code CLI
- Monitors completion via git (branch commits)
- Performs final review after cross-agent review cycles
- Escalates to project lead per Section 5
- May create git worktrees for parallel execution
- **Can run autonomously** via `orchestrate-loop.sh` (see Section 10)

### Codex CLI -- Execution Agent
- Implements plans, writes code, runs tests, commits
- Utilize expert agents when appropriate.
- Receives structured task descriptions pointing to plan files
- Operates in `--full-auto` mode (model selection is configurable)

### Claude Code CLI -- Reviewer
- Utilize expert agents when appropriate.
- Performs code review of Codex commits
- Operates with `--dangerously-skip-permissions`
- Uses `-p` (print mode) for non-interactive dispatch

---

## 2. Planning Frameworks

### SpecKit (`/speckit` family)
**Use when**: Big sprints, new features with many complex pieces, greenfield development
**Output**: `specs/<feature>/` containing spec.md, plan.md, research.md, data-model.md, contracts/, tasks.md
**Active spec**: Set via `ORCH_SPECS` env var or `--specs` flag (e.g., `specs/<active-spec>/`)

### SuperPowers (`/superpowers` family)
**Use when**: Individual features, experimentation, complex features within a SpecKit plan
**Workflow**: `/superpowers:brainstorm` -> `/superpowers:write-plan` -> `/superpowers:execute-plan`

### Selection criteria
- If scope touches 3+ user stories or requires new data models -> SpecKit
- If scope is a single feature, bugfix, or refinement -> SuperPowers
- Project lead may override: "this is a SpecKit job" or "SuperPowers is fine"

---

## 3. Dispatch Commands

### Codex -- Implementation
```bash
cd "$PROJECT_ROOT" && codex exec \
  "Read and implement the plan at <plan-file-path>. \
   Work on the assigned branch or worktree branch for this task. \
   Follow .codex/ prompts and <specs-path> specifications. \
   Commit locally immediately after every completed task (one task per commit; no batching) with descriptive messages. \
   Do NOT push unless the operator explicitly asks. \
   Do NOT edit tasks.md; the orchestrator owns task-state mutation." \
  --full-auto
```

### Codex -- Code Review
```bash
cd "$PROJECT_ROOT" && codex exec review \
  "Review the latest commits on branch <branch-name>. \
   Perform code review as you would for a PR, regardless if there is a PR or not.  \
   Check against the plan at <plan-file-path> and <specs-path>/spec.md. \
   Focus on: correctness, edge cases, security, test coverage. \
   Do NOT run tests -- only review code. \
   Write findings to planning/reviews/<branch-name>-review.md." \
  --full-auto
```

### Claude Code -- Code Review
```bash
cd "$PROJECT_ROOT" && env -u CLAUDECODE claude -p \
  "Review the latest commits on branch <branch-name> using: git log --oneline -10 && git diff <compare-range>. \
   Perform code review as you would for a PR, regardless if there is a PR or not.  \
   Check against the plan at <plan-file-path> and <specs-path>/spec.md. \
   Focus on: correctness, edge cases, security, test coverage, \
   and suggest improvements or better patterns where applicable. \
   Do NOT run tests -- only review code. \
   Write findings to planning/reviews/<branch-name>-review.md." \
  --dangerously-skip-permissions
```

---

## 4. Execution Cycle

```
+---------------------------------------------------------+
|  PROJECT LEAD: Provides goal / specification / TODO list |
+------------------------+--------------------------------+
                         v
+---------------------------------------------------------+
|  ORCHESTRATOR (Claude): Plans                           |
|  - Reads codebase, specs, current state                 |
|  - Drives SpecKit or SuperPowers to produce plan        |
|  - Creates feature branch or worktree                   |
|  - Checks in with project lead if any ambiguity         |
+------------------------+--------------------------------+
                         v
+---------------------------------------------------------+
|  EXECUTION: Codex implements                            |
|  - Receives plan file path + branch name                |
|  - Implements, tests, commits after every task          |
|  - Leaves task-state mutation to the orchestrator       |
+------------------------+--------------------------------+
                         v
+---------------------------------------------------------+
|  CROSS-REVIEW: Claude Code reviews                      |
|  - Codex implements -> Claude Code reviews              |
|  - Writes review to planning/reviews/                   |
+------------------------+--------------------------------+
                         v
+------------------------+--------------------------------+
|  Issues found?                                          |
|  YES -> Send back to implementer with review file       |
|         (autonomous cycle, up to 3 iterations)          |
|  NO  -> Continue to orchestrator final check            |
+------------------------+--------------------------------+
                         v
+---------------------------------------------------------+
|  ORCHESTRATOR: Final review                             |
|  - Reads diff against plan and specs                    |
|  - Verifies cross-review issues are resolved            |
|  - Checks project conventions compliance                |
|  - If clean -> mark phase complete, start next phase    |
|  - If escalation needed -> notify project lead (Sec 5)  |
+---------------------------------------------------------+
```

### Parallel Execution
- Tasks marked `[P]` in tasks.md may be dispatched to separate agents simultaneously
- Use git worktrees to avoid branch conflicts: `git worktree add ../proj-<task-id> <branch>`
- Each parallel agent gets its own worktree and sub-branch
- Orchestrator reviews each worktree branch against the parent branch before any merge
- Only review `PASS` results are merged back to the parent branch
- `ORCH_PARALLEL_GROUP_HOOK` can force a `[P]` batch back to sequential execution when the consuming repo declares a conflict

### Completion Detection
- **Loop mode** (Section 10): Polls tmux pane exit status + `.exit` files on a configurable cadence (`30s` for code by default)
- **Document mode** (Section 11): Uses the same tmux polling pattern with a `15s` default cadence
- **Manual mode**: Check git log on feature branch for new commits
- **Fallback**: Read process output from agent PIDs
- **Verification gate**: Before marking a task complete, run configured test/lint commands directly (not delegated). See `verify_task()` in `orchestrate-loop.sh`.

### Git-Based Progress Monitoring

The orchestrator MUST use git as an active progress signal -- not just passively wait for exit files. During polling:

1. **Track commits**: Before dispatching an agent, snapshot `git rev-parse HEAD`. On each poll cycle, run `git log --oneline {snapshot}..HEAD` to see new commits.
2. **Spot-check diffs**: Run `git diff --stat HEAD~1..HEAD` on the latest commit to see what files changed and how much.
3. **Detect drift**: Run `git diff --name-only {snapshot}..HEAD` and flag files outside the expected scope (e.g., agent editing unrelated modules, touching configuration files, or modifying locked documents).
4. **Detect stalls**: If no new commits appear after 2+ poll cycles for an implementation task, log a warning -- the agent may be stuck or spinning.
5. **Post-completion audit**: After an agent finishes, check `git diff --stat` for uncommitted changes (agent forgot to commit) and `git log --oneline -3` to verify commit messages follow conventions.
6. **Code review the diff**: For critical tasks, the orchestrator should read `git diff {snapshot}..HEAD` to verify the changes are on-track before proceeding to the formal review step. Flag obviously wrong patterns: deleted test files, hardcoded credentials, massive file additions, or changes to locked documents.

These checks are implemented in `check_git_progress()` and the post-implementation audit in `process_task()` in `orchestrate-loop.sh`.

### Error Recovery

When a dispatched agent fails (non-zero exit, timeout, or partial output):

1. **Capture diagnostics**: Read the last 30-50 lines of tmux pane output
2. **Check output**: Verify if the expected output file exists and has content
3. **Classify failure**:
   - **Import/dependency error** -> Fix environment, re-dispatch
   - **Context overflow** -> Split task into smaller pieces, re-dispatch
   - **Timeout** -> Increase `--timeout` or simplify task scope
   - **Unknown** -> Escalate to project lead (Section 5)
4. **Preserve partial progress**: If the agent wrote code before failing, commit it before re-dispatching
5. **Re-dispatch limit**: Maximum 2 re-dispatches per failure. After that, escalate.

---

## 5. Escalation Rules -- STOP and Check In With Project Lead

The orchestrator MUST stop and consult the project lead when:

**(a)** A specification needs to change or is ambiguous
**(b)** An architectural decision isn't covered by existing specs
**(c)** Tests fail in a way suggesting the plan is wrong, not just the implementation
**(d)** Changes touch deployment or infrastructure configuration
**(e)** Manual configuration is needed (external services, API keys not in env files)
**(f)** Major features reach testable state -- project lead manually verifies
**(g)** Cross-review cycle exceeds 3 iterations without resolution

---

## 6. Review Standards

### Review prompt templates
Reviews use structured prompt templates that enforce concise, actionable output:
- **Codex reviewer**: `scripts/review-prompt-codex.md`
- **Claude Code reviewer**: `scripts/review-prompt-claude.md`

Templates are rendered by `dispatch.sh` with placeholders (`{BRANCH}`, `{PLAN_FILE}`, `{SPECS}`, `{REVIEW_FILE}`, `{COMPARE_RANGE}`, `{COMMIT_RANGE}`) filled at dispatch time.

### Core rules enforced by templates
1. ONLY report items that require action -- no observations, no praise, no summaries
2. Every item MUST have exact file path + line number(s) and a concrete fix instruction
3. Empty sections are omitted entirely
4. Zero issues = verdict line only

### Review output format
```markdown
# Review: <branch-name>
**Reviewer**: Codex|Claude Code
**Commits**: <commit-range>

## MUST FIX
- `path/file.py:42` -- Description. Fix: [exact instruction]

## SHOULD FIX
- `path/file.py:87-93` -- Description. Fix: [exact instruction]

## IMPROVE (Claude Code only -- better pattern available)
- `path/file.py:120-135` -- Current approach works but [better pattern]. Refactor: [exact instruction]

## Verdict: PASS | NEEDS_FIXES | ESCALATE
```

### Verdict rules
- **PASS**: No MUST FIX items. SHOULD FIX and IMPROVE do not block.
- **NEEDS_FIXES**: One or more MUST FIX items. Sent back to implementer.
- **ESCALATE**: Architectural issue beyond code fixes. Routed to project lead (Section 5).

---

## 7. Frontend-Specific Rules (Recommended)

When working on frontend code:
- Codex is the default for frontend implementation
- Claude Code preferred for frontend code review (stronger at suggesting improvements)
- **MCP servers recommended**: Magic MCP and Context7 for pre-built components
- Do NOT write components from scratch when a quality pre-built component exists
- Code review SHOULD check: "Could this component have been retrieved from MCP instead of written from scratch?"

### MCP Integration
- Context7: Use for library documentation and code examples
- Magic MCP: Use for UI component patterns and design system components
- Reviewers flag any hand-written component that duplicates MCP-available functionality

---

## 8. Git Conventions

### Branch naming
- Feature branches: `<spec-number>-<feature-name>` (e.g., `003-auth-system`)
- Sub-branches for parallel work: `<parent>/<task-ids>` (e.g., `003-auth-system/T018-T021`)
- Worktrees: `../proj-<task-id>` directory, branched from parent feature branch

### Commit messages
- Format: `<files-changed> -- <description>`
- Git remote: configurable via `GIT_REMOTE` env var (default: `github`) for prompts, review context, and operator-facing commands
- Pushes are operator-controlled; workers commit locally unless explicitly told to push
- Current convention per git log (maintain consistency)

### Commit cadence (mandatory)
- Code loop (Section 10): commit immediately after every completed task (one task per commit; no batching across tasks)
- Document loop (Section 11): commit immediately after every phase-writing step (initial draft and each implement round; no batching across rounds/phases)

### Task marking in tasks.md
- `[ ]` -- Not started
- `[o]` -- In progress (claimed by an agent)
- `[x]` -- Completed

---

## 9. File Locations

| Purpose | Location |
|---------|----------|
| Orchestration protocol (this file) | `orchestration-protocol.md` |
| Active specs | `specs/<active-spec>/` (set via `ORCH_SPECS`) |
| Planning docs | `planning/` |
| Review artifacts | `planning/reviews/` |
| Orchestration log | `planning/orchestration-log.md` |
| Escalation files | `planning/reviews/ESCALATION-*.md` |
| Secrets | `~/.secrets/<project>.env` |
| Review prompt templates | `scripts/review-prompt-*.md` |
| Dispatch script (single task) | `scripts/dispatch.sh` |
| Shared runtime helpers | `scripts/lib/orch-agent-runtime.sh` |
| Orchestration loop script | `scripts/orchestrate-loop.sh` |
| Doc orchestration script | `scripts/orchestrate-doc.sh` |
| Vendored state file | `.claude/orchestration-state.env` |
| Standalone code state file | `orchestration-state.env` |
| Standalone doc state file | `orchestration-doc-state.env` |
| Makefile orchestration targets | `makefile-targets.mk` |
| JSON state file (code loop) | `orchestration-state.json` |
| JSON state file (doc loop) | `{output-dir}/phase-{N}-state.json` |

---

## 10. Autonomous Orchestration Loop

### Overview

The orchestration loop (`orchestrate-loop.sh`) is the canonical execution path. It is a persistent bash script that runs inside a tmux session and replaces the manual dispatch workflow by autonomously:

1. Parsing `tasks.md` for pending tasks
2. Dispatching Codex or Claude Code to implement each task
3. Dispatching Claude Code for cross-review
4. Parsing review verdicts and iterating on failures (up to 3 cycles)
5. Escalating to the project lead when Section 5 rules are triggered
6. Logging everything to `planning/orchestration-log.md`

### State Machine

```
                    +----------------------+
                    |  Parse tasks.md      |
                    |  Find next [ ] task   |
                    +----------+-----------+
                               v
                    +----------------------+
                    |  Select fixed agents |
                    |  (Codex implements,  |
                    |   Claude reviews)    |
                    +----------+-----------+
                               v
              +--------------------------------+
              |  DISPATCH: Implementer          |
              |  (codex in tmux pane)           |
              +----------------+---------------+
                               v
              +--------------------------------+
              |  POLL: Wait for completion      |
              |  (configurable cadence)         |
              +----------------+---------------+
                               v
              +--------------------------------+
              |  DISPATCH: Reviewer             |
              |  (claude reviewer)              |
              +----------------+---------------+
                               v
              +--------------------------------+
              |  POLL: Wait for review          |
              +----------------+---------------+
                               v
              +--------------------------------+
              |  PARSE VERDICT                  |
              |  (grep review file, or          |
              |   claude -p fallback)           |
              +----------------+---------------+
                               v
                    +---------------------+
                    |  Verdict?           |
                    +--+------+-------+---+
            PASS       |      |       |  ESCALATE
              v        |      |       v
       +----------+    |      |  +-------------+
       | Mark [x]  |   |      |  | Write        |
       | Next task |   |      |  | escalation   |
       +----------+    |      |  | file -> HALT  |
                       |      |  +-------------+
              NEEDS_FIXES     |
              (iteration < 3) |
                       v      |
              +----------+    |  (iteration >= 3)
              | Re-dispatch   |         v
              | implementer   |  +-------------+
              | with review   |  | ESCALATE:   |
              | feedback  |   |  | max retries |
              +-----------+   |  +-------------+
```

### Default Agent Assignment

Implementation defaults:
- All tasks: Codex implements by default
- All tasks: Claude Code reviews

`[claude]` task tags can override the default implementer selection when explicitly needed.

### Task Selection & Filtering

By default, all pending `[ ]` tasks are processed. Use these flags to narrow scope:

```bash
# Process only Phase 2 tasks
--phase 2
--phase "Foundational"     # matches phase name substring (case-insensitive)

# Process specific tasks
--tasks T018,T019,T020

# Process a range of tasks
--from T018 --to T025      # inclusive on both ends

# Combine: Phase 2 starting from T020
--phase 2 --from T020
```

### Break Marker

Insert `[BREAK]` in tasks.md to halt the orchestrator at that point:

```markdown
- [ ] T018 [US1] Implement search endpoint
- [ ] T019 [US1] Implement subgraph endpoint
[BREAK]
- [ ] T020 [US1] Integrate both endpoints    <-- not processed
```

`[BREAK]` can also appear inline in a task line:
```markdown
- [ ] T019 [US1] [BREAK] Implement subgraph endpoint  <-- stops here, T019 not processed
```

This is useful for limiting a session's scope without modifying CLI flags.

### Sequential Execution Guarantee

Tasks without `[P]` markers are **always** executed sequentially -- each task completes its full implement->review->iterate cycle before the next task begins. The orchestrator logs this explicitly:

```
SEQUENTIAL: T019 runs after T018 completes
```

Use `--sequential-only` to force ALL tasks to run sequentially, even those marked `[P]`:

```bash
--sequential-only    # ignores [P] markers, all tasks run one at a time
```

### Parallel Execution

Tasks marked `[P]` that are consecutive in tasks.md are grouped for parallel execution:

```
- [ ] T018 [P] [US1] Implement search endpoint
- [ ] T019 [P] [US1] Implement subgraph endpoint
- [ ] T020 [US1] Integrate both endpoints       <-- sequential, waits for above
```

**Parallel workflow**:
1. Create a git worktree per task: `../proj-T018`, `../proj-T019`
2. Each worktree gets a sub-branch: `<feature-branch>/T018`
3. Dispatch agents simultaneously (one per worktree)
4. Wait for all to complete
5. Review each sub-branch against the parent feature branch while it is still isolated
6. Merge only `PASS` worktree branches back to the feature branch
7. Clean up unmerged worktrees and reset `NEEDS_FIXES` tasks to `[ ]` for the sequential loop to retry
8. Optionally gate the whole batch through `ORCH_PARALLEL_GROUP_HOOK` when the consuming repo needs custom conflict rules

### Starting the Orchestrator

```bash
# Basic: process all pending tasks in tasks.md
tmux new-session -s orchestrator \
  '.claude/orchestration/scripts/orchestrate-loop.sh $ORCH_SPECS/tasks.md $BRANCH'

# With options
tmux new-session -s orchestrator \
  '.claude/orchestration/scripts/orchestrate-loop.sh $ORCH_SPECS/tasks.md $BRANCH \
   --specs $ORCH_SPECS \
   --plan $ORCH_SPECS/plan.md \
   --poll-interval 30 \
   --max-iterations 3 \
   --timeout 3600 \
   --env ~/.secrets/<project>.env'

# Process only Phase 2
tmux new-session -s orchestrator \
  '.claude/orchestration/scripts/orchestrate-loop.sh $ORCH_SPECS/tasks.md $BRANCH \
   --phase 2 --env ~/.secrets/<project>.env'

# Process specific tasks, sequentially
tmux new-session -s orchestrator \
  '.claude/orchestration/scripts/orchestrate-loop.sh $ORCH_SPECS/tasks.md $BRANCH \
   --tasks T018,T019,T020 --sequential-only --env ~/.secrets/<project>.env'

# Process a range
tmux new-session -s orchestrator \
  '.claude/orchestration/scripts/orchestrate-loop.sh $ORCH_SPECS/tasks.md $BRANCH \
   --from T018 --to T025 --env ~/.secrets/<project>.env'

# Dry run (prints commands without executing)
.claude/orchestration/scripts/orchestrate-loop.sh $ORCH_SPECS/tasks.md $BRANCH --dry-run
```

### Monitoring

```bash
# Attach to watch live output
tmux attach -t orchestrator

# Watch the log file
tail -f planning/orchestration-log.md

# Check task progress
grep -cE '^\- \[([ xo])\]' $ORCH_SPECS/tasks.md

# View agent windows (each agent gets a tmux window)
tmux list-windows -t orchestrator

# Peek at an agent's output
tmux capture-pane -t orchestrator:impl-T018-i1 -p | tail -20
```

### Stopping & Pausing

```bash
# Graceful: let current task finish, then stop
# (Send SIGINT -- the script traps EXIT for cleanup)
tmux send-keys -t orchestrator C-c

# Force stop (kills all agent windows too)
tmux kill-session -t orchestrator

# State is preserved at the resolved state-file path (`.claude/orchestration-state.env` for vendored installs)
```

### Resuming After Escalation

When the orchestrator halts for escalation:
1. An `ESCALATION-*.md` file is written to `planning/reviews/`
2. The orchestrator state is saved to the resolved state-file path
3. Project lead reviews the escalation, resolves the issue, and resumes:

```bash
# Resume from saved state (skips completed tasks)
tmux new-session -s orchestrator \
  '.claude/orchestration/scripts/orchestrate-loop.sh $ORCH_SPECS/tasks.md $BRANCH --resume'
```

### Configuration Reference

| Option | Default | Description |
|--------|---------|-------------|
| `--specs <path>` | `$ORCH_SPECS` env var | Specs directory |
| `--plan <path>` | `<specs>/plan.md` | Plan file for agent prompts |
| `--poll-interval <sec>` | `30` | Seconds between code-loop completion checks |
| `--max-iterations <n>` | `3` | Max implement->review cycles per task |
| `--timeout <sec>` | `3600` | Max seconds per agent dispatch |
| `--env <path>` | *(none)* | Environment file to source |
| `--dry-run` | `false` | Print commands without executing |
| `--resume` | `false` | Resume from `orchestration-state.env` |
| `--phase <n\|name>` | *(all)* | Filter to a specific phase (number or name substring) |
| `--tasks <ids>` | *(all)* | Comma-separated task IDs to process |
| `--from <task-id>` | *(start)* | Start processing from this task (inclusive) |
| `--to <task-id>` | *(end)* | Stop processing after this task (inclusive) |
| `--sequential-only` | `false` | Force all tasks sequential (ignore `[P]`) |
| `--test-cmd <cmd>` | *(none)* | Test command to run for verification |
| `--lint-cmd <cmd>` | *(none)* | Lint command to run for verification |
| `--bootstrap-reads <files>` | *(none)* | Comma-separated files agents must read first |
| `--git-remote <name>` | `github` | Git remote name shown in prompts and review context |

Environment overrides:

| Variable | Default | Description |
|----------|---------|-------------|
| `ORCH_POLL_INTERVAL` | `30` code / `15` doc | Shared poll interval override for tmux-based modes |
| `ORCH_CODE_POLL_INTERVAL` | inherits shared or `30` | Code-loop-specific poll interval |
| `ORCH_DOC_POLL_INTERVAL` | inherits shared or `15` | Document-loop-specific poll interval |
| `ORCH_PARALLEL_GROUP_HOOK` | *(none)* | Command run before dispatching a `[P]` batch; non-zero forces sequential fallback |
| `ORCH_EXPECTED_DIRS` | `src/|tests/|specs/|planning/|docs/|\.claude/|deploy/|tools/|Makefile` | Expected path regex for git drift checks |

When `ORCH_PARALLEL_GROUP_HOOK` runs, it receives `ORCH_PARALLEL_TASK_IDS`, `ORCH_PARALLEL_TASK_PHASES`, `ORCH_PARALLEL_TASK_DESCRIPTIONS`, `ORCH_TASKS_FILE`, `ORCH_PROJECT_ROOT`, and `ORCH_BRANCH`.

### Integration with Manual Dispatch

The loop script and `dispatch.sh` are complementary:
- **`orchestrate-loop.sh`**: Autonomous, processes all pending tasks end-to-end
- **`dispatch.sh`**: Manual, dispatches a single agent for a specific task

The project lead can always stop the loop and use `dispatch.sh` for manual control, then resume the loop later.

### Artifacts Produced

| Artifact | Location | Purpose |
|----------|----------|---------|
| Orchestration log | `planning/orchestration-log.md` | Complete execution history |
| Review files | `planning/reviews/<branch>-<task>-i<n>-<reviewer>-review.md` | Per-task, per-iteration reviews |
| Escalation files | `planning/reviews/ESCALATION-<task>-<timestamp>.md` | Issues requiring project lead |
| State file | resolved from install layout | Resume state |
| JSON state file | `orchestration-state.json` | Machine-parseable state |

## 11. Document Orchestration Mode

### Overview

The document orchestration mode extends the protocol for iterative **document drafting** workflows -- producing planning documents, landing page copy, design specs, etc. -- as opposed to the code task loop in Section 10.

The key difference: instead of iterating through a `tasks.md` task list, this mode runs a **draft -> review -> implement -> review -> implement** loop on a single document.

### Why Separate Mode?

| Concern | Code Loop (Section 10) | Document Loop (Section 11) |
|---------|----------------------|---------------------------|
| Input | `tasks.md` with T001-T999 | A single prompt from a prompt sequence file |
| Output | Code across many files | One `.md` document |
| Review scope | Git diff of code changes | Document completeness vs. prompt requirements |
| Review output location | `planning/reviews/` | **Same directory as the draft** (context permanence) |
| Iteration | Per-task: implement -> review -> fix | Per-round: draft -> review -> implement suggestions |
| Commit cadence | Commit after every completed task | Commit after every draft/implement round step |

### Architecture: Orchestrator Never Implements

```
+-------------------------------------------------------------+
|  ORCHESTRATOR (Claude CLI instance #1)                       |
|  - Reads protocol and dispatch scripts                       |
|  - Launches worker agents in tmux windows                    |
|  - Polls for completion (.exit files)                        |
|  - Reads review verdicts and decides next step               |
|  - Updates orchestration tracker                             |
|  - NEVER writes document content                             |
|  - NEVER implements review suggestions                       |
+------------+--------------------------+----------------------+
             |                          |
    +--------v---------+    +----------v-----------+
    | Claude CLI #2     |    | Codex CLI             |
    | (tmux window)     |    | (tmux window)         |
    |                   |    |                       |
    | Drafts document   |    | Reviews document      |
    | Implements fixes  |    | Writes review .md     |
    +-------------------+    +-----------------------+
```

**Why this matters:**
1. **Context load distribution** -- The orchestrator's context stays small (dispatch commands + review verdicts). Workers get the full document context but only for their step.
2. **Reliability** -- Running everything in WSL tmux avoids Desktop Commander cross-OS issues.
3. **Context permanence** -- Reviews written alongside the draft survive compactions and session restarts.

### Dispatch Script

`orchestrate-doc.sh` provides four commands:

```bash
# Initial draft
.claude/orchestration/scripts/orchestrate-doc.sh draft \
  --phase 6 \
  --prompt-source "planning/prompts/consolidated_prompt_sequence.md" \
  --output "planning/phases/phase-6-output.md" \
  --locked-phases "Phases 0-5" \
  --design-system "planning/phases/phase-5-design-system.md"

# Review (launches Codex by default, or --reviewer claude)
.claude/orchestration/scripts/orchestrate-doc.sh review \
  --phase 6 \
  --draft "planning/phases/phase-6-output.md" \
  --prompt-source "planning/prompts/consolidated_prompt_sequence.md" \
  --round 1 \
  --reviewer codex

# Implement review suggestions
.claude/orchestration/scripts/orchestrate-doc.sh implement \
  --phase 6 \
  --draft "planning/phases/phase-6-output.md" \
  --review "planning/phases/phase-6-review-r1-codex.md" \
  --round 1

# Verify (run tests/lint)
.claude/orchestration/scripts/orchestrate-doc.sh verify \
  --phase 6 \
  --test-cmd "pytest tests/ -x -q" \
  --lint-cmd "ruff check ."
```

### Review Output Location

**Critical difference from code reviews**: Document reviews are written to the **same directory as the draft**, not `planning/reviews/`. This ensures:
- Reviews are visible to subsequent worker agents without path confusion
- Context survives session compactions (the orchestrator can re-read them)
- The entire phase folder is self-contained

Naming convention:
```
{output-dir}/phase-{N}-review-r{round}-{reviewer}.md
```

Example directory after 2 rounds:
```
planning/phases/
  phase-6-output.md                            <-- the draft (updated in-place)
  phase-6-review-r1-codex.md                   <-- round 1 review
  phase-6-review-r2-codex.md                   <-- round 2 review
  phase-6-orchestration-tracker.md             <-- state tracker
  phase-6-state.json                           <-- machine-parseable state
```

### Orchestration Tracker

The orchestrator creates a tracker file alongside the draft to maintain state across compactions:

```markdown
# Phase 6 Orchestration Tracker
## Status: IN PROGRESS

| Step | Agent | Status | Timestamp | Notes |
|------|-------|--------|-----------|-------|
| Draft | Claude CLI | Done | 2025-02-12 14:30 | 654 lines |
| Review R1 | Codex CLI | Done | 2025-02-12 15:15 | 8 MUST FIX, 4 SHOULD FIX |
| Implement R1 | Claude CLI | Done | 2025-02-12 16:00 | All MUST FIX addressed |
| Review R2 | Codex CLI | Running | | |
| Implement R2 | Claude CLI | Pending | | |
| Final | Project Lead | Pending | | |
```

### State Machine

```
  +----------------------------------+
  | Step 0: Setup                     |
  | - Create tracker                  |
  | - Clean stale .exit files         |
  +-------------+--------------------+
                v
  +----------------------------------+
  | Step 1: Dispatch Claude CLI       |
  |         to write initial draft    |
  | (tmux window: "draft")            |
  +-------------+--------------------+
                v
  +----------------------------------+
  | Poll: /tmp/phase{N}-draft.exit    |
  +-------------+--------------------+
                v
  +------------------------------------------------------+
  | Step 2: Dispatch Codex CLI to review         <------+|
  | (tmux window: "review-r{N}")                        ||
  +-------------+--------------------------------------+|
                v                                        |
  +----------------------------------+                   |
  | Poll: review .exit file           |                   |
  +-------------+--------------------+                   |
                v                                        |
  +----------------------------------+                   |
  | Read verdict                      |                   |
  | PASS -> Done                      |                   |
  | ESCALATE -> Halt, notify lead     |                   |
  | NEEDS_FIXES -> continue ----------+-----------+      |
  +----------------------------------+            |      |
                                                   v      |
                                  +---------------------+|
                                  | Step 3: Dispatch     ||
                                  | Claude CLI to        ||
                                  | implement fixes      ||
                                  | (tmux: "impl-r{N}") ||
                                  +----------+----------+|
                                             v           |
                                  +---------------------+|
                                  | Poll: impl .exit     ||
                                  +----------+----------+|
                                             v           |
                                        round++ ---------+
                                    (up to max rounds)
```

### Prompt Template

The orchestrator is launched with a prompt from `orchestrate-doc-prompt-template.md`. Fill in the placeholders and either:
- Paste the rendered prompt directly into a `claude -p` invocation
- Reference it via a slash command

```bash
# Example: Launch orchestrator for Phase 6, 2 review rounds
claude -p \
  "You are the orchestrator. Read orchestrate-doc-prompt-template.md for your full instructions.

   Phase: 6
   Phase name: Landing Page Copy & Conversion
   Prompt source: planning/prompts/consolidated_prompt_sequence.md
   Output: planning/phases/phase-6-output.md
   Locked: Phases 0-5 and planning/phases/phase-5-design-system.md
   Review rounds: 2

   Begin." \
  --dangerously-skip-permissions
```

### Integration with Section 10

Sections 10 and 11 are the primary tmux-based execution surfaces:
- **Section 10** (`orchestrate-loop.sh`): Canonical path for code tasks from `tasks.md`
- **Section 11** (`orchestrate-doc.sh`): Canonical path for document draft-review-implement cycles

Both use the same tmux dispatch pattern, .exit file polling, and review verdict parsing. The orchestrator can invoke either based on the nature of the work.

### File Locations (additions to Section 9)

| Purpose | Location |
|---------|----------|
| Doc orchestration dispatch | `scripts/orchestrate-doc.sh` |
| Doc orchestration prompt template | `orchestrate-doc-prompt-template.md` |
| Doc review template (Codex) | `scripts/review-prompt-doc-codex.md` |
| Doc review template (Claude) | `scripts/review-prompt-doc-claude.md` |
| Phase orchestration tracker | `{output-dir}/phase-{N}-orchestration-tracker.md` |
| Phase review artifacts | `{output-dir}/phase-{N}-review-r{round}-{reviewer}.md` |

## 12. Single-Session Fallback

### Overview

Single-session mode is a fallback execution model for when the canonical tmux-based path is unavailable or not worth its overhead. In this mode, the orchestrator runs inside Claude Code's interactive session, acts as the implementer, and uses internal subagents (Task tool) for context isolation and parallelism.

### When to Use

- No tmux session available
- No Codex CLI installed
- Running inside Claude Code interactive session
- Quick orchestration where tmux overhead isn't justified

### How It Differs

| Aspect | Multi-Session (Sections 10-11) | Single-Session |
|--------|-------------------------------|----------------|
| Dispatch | tmux windows + CLI processes | Task tool subagents |
| Polling | Configurable `.exit` file checks (`30s` code / `15s` doc defaults) | Task tool returns synchronously |
| Tracking | Markdown tracker + `orchestration-state.env` | TodoWrite + JSON state file |
| Verification | Orchestrator runs directly | Same -- orchestrator runs directly |
| Context isolation | Separate CLI processes | Subagent context boundaries |
| Parallelism | Multiple tmux windows | Multiple Task tool calls |

### Execution Pattern

```
+---------------------------------------------------------+
|  ORCHESTRATOR (Claude Code main session)                 |
|  - Reads plan/spec, creates TodoWrite items              |
|  - Dispatches Task tool agents for implementation        |
|  - Runs verification (test/lint) directly                |
|  - Dispatches Task tool agents for code review           |
|  - Reads review output and decides next step             |
+------------------------+--------------------------------+
                         v
         +-----------------------------+
         |  Task: backend-architect     | <-- Implementation
         |  Task: code-reviewer         | <-- Review
         |  (run in parallel when       |
         |   independent)               |
         +-----------------------------+
```

### Dispatch Examples

```python
# Implementation dispatch (replaces codex exec or claude -p)
Task(
    subagent_type="backend-architect",
    prompt="""Read the plan at $ORCH_SPECS/plan.md.
    Implement task T018: [description].
    Work on branch <feature-branch>.
    Read AGENTS.md and .claude/CLAUDE.md for project conventions when present.
    Git remote is '$GIT_REMOTE' (NOT origin).
    Do NOT push unless explicitly asked.
    Commit format: <files-changed> -- <description>
    """,
    description="Implement T018"
)

# Review dispatch (replaces claude -p review)
Task(
    subagent_type="code-reviewer",
    prompt="""Review the latest commits on branch <feature-branch>.
    Check against $ORCH_SPECS/plan.md and spec.md.
    Focus on: correctness, edge cases, security, test coverage.
    """,
    description="Review T018"
)
```

### Verification

Verification runs directly in the orchestrator session, not delegated:

```bash
# Orchestrator runs these directly
pytest tests/ -x -q
ruff check .
```

If verification fails, the orchestrator creates a synthetic review with the failure output and dispatches a fix agent.

### Git-Based Progress Monitoring (applies to all modes)

Even in single-session mode, git remains the primary progress signal. The orchestrator MUST:

1. **Snapshot HEAD** before dispatching any subagent: `git rev-parse HEAD`
2. **After subagent returns**: run `git log --oneline {snapshot}..HEAD` to see what the agent committed
3. **Spot-check the diff**: run `git diff --stat {snapshot}..HEAD` -- flag if the agent touched too many files, changed unexpected modules, or deleted test files
4. **Detect drift**: any changes to locked documents or unrelated modules are red flags -- abort and investigate before proceeding to review
5. **Audit uncommitted changes**: run `git diff --stat` -- if the agent left uncommitted work, either commit it or discard it before the next step
6. **Verify commit messages**: check that commit messages follow `<files-changed> -- <description>` format and reference the correct task ID

In single-session mode, the orchestrator can read the actual diff content (not just stat) to confirm implementation quality before dispatching a reviewer. This is faster than a full review cycle and catches obvious problems early.

### Agent Bootstrap

Every dispatched subagent must receive the Agent Bootstrap Context block (see `build_agent_bootstrap()` in `orchestrate-loop.sh`). This includes:
- `AGENTS.md` plus `.claude/CLAUDE.md` when present
- Git remote name
- Test/lint commands
- Bootstrap reads file list
- Project directory map

### File Locations (additions to Section 9)

| Purpose | Location |
|---------|----------|
| JSON state file (code loop) | `orchestration-state.json` |
| JSON state file (doc loop) | `{output-dir}/phase-{N}-state.json` |
