# Orchestration Protocol Suite

A cross-platform orchestration skill for multi-agent development workflows. Drop it into any repository to get autonomous implement → review → iterate cycles driven by a `tasks.md` file. Designed for developers using Claude or Codex for coordinated development; the runtime dispatches bounded subtasks to subagents, tracks progress via git, and manages the full review-fix cycle without manual intervention.

## Getting Started: Bootstrap

The fastest way to configure orchestration for a new project is to paste `bootstrap-prompt.md` into a Claude or Codex session:

```bash
# Print the prompt, then paste it into a new Claude or Codex session
cat ~/.claude/orchestration/bootstrap-prompt.md
```

Or invoke it directly:

```bash
claude -p "$(cat ~/.claude/orchestration/bootstrap-prompt.md)

My project: [describe your project here]"
```

Claude will ask targeted questions about your project structure, runtime preferences, and toolchain, then generate all configuration artifacts: state file, agent bootstrap block, launch command, and monitoring reference.

See [bootstrap-prompt.md](bootstrap-prompt.md) for the full template.

## Installation

### Canonical: Vendored Copy (recommended)

Copy the suite into your project's `.claude/orchestration/` directory:

```bash
cp -r ~/.claude/orchestration/ .claude/orchestration/
```

Or add as a git submodule:

```bash
git submodule add <repo-url> .claude/orchestration
```

The runtime treats the consuming repository root as the project root. State files live at `.claude/orchestration-state.env`.

### Convenience: Prompt-Driven

Use `bootstrap-prompt.md` to generate the installation steps for your specific setup. The bootstrap prompt will produce a ready-to-run install command based on your answers.

See [skills/orchestration/references/install-paths.md](skills/orchestration/references/install-paths.md) for the full expected file layout and path resolution rules.

## Runtime Modes

Three execution models are supported. Choose based on your platform.

### Primary: Native Subagent Orchestration

The orchestrator dispatches bounded subtasks using the host platform's built-in agent/subagent capabilities (Claude agent execution or Codex native subagents). No external process management required. **Recommended for most users.**

Use when: running inside Claude Code or Codex with native subagent support.

### Compatibility: tmux Multi-Session

The orchestrator launches separate CLI processes in tmux panes/windows, using `scripts/orchestrate-loop.sh` for code tasks and `scripts/orchestrate-doc.sh` for document tasks. Polls for completion via `.exit` files.

Use when: Codex is the implementer, pane-based monitoring is preferred, or native subagents are unavailable.

### Single-Session Fallback

The orchestrator runs inside an interactive Claude Code session using the Task tool for context isolation. No tmux or polling overhead.

Use when: running inside Claude Code with multi-session overhead not justified, or tmux unavailable.

See [skills/orchestration/references/runtime-modes.md](skills/orchestration/references/runtime-modes.md) for capability detection and selection logic.

## Quick Start

### Native Subagent Mode (primary)

Invoke the orchestration skill directly from Claude Code:

```
/sc:task Implement all tasks in specs/my-feature/tasks.md on branch my-feature-branch
```

Or use the Task tool directly:

```
Use the orchestration protocol to implement tasks in specs/my-feature/tasks.md.
Branch: my-feature-branch
Specs: specs/my-feature
```

### tmux Multi-Session Mode

```bash
# Basic run
tmux new-session -s orchestrator \
  '.claude/orchestration/scripts/orchestrate-loop.sh specs/my-feature/tasks.md my-feature-branch \
   --specs specs/my-feature --env ~/.secrets/my-project.env'

# With verification
tmux new-session -s orchestrator \
  '.claude/orchestration/scripts/orchestrate-loop.sh specs/my-feature/tasks.md my-feature-branch \
   --specs specs/my-feature \
   --test-cmd "pytest tests/ -x -q" \
   --lint-cmd "ruff check ." \
   --bootstrap-reads ".claude/CLAUDE.md,specs/my-feature/spec.md" \
   --git-remote github'
```

### Single-Session Fallback

Use the TodoWrite-based pattern from Section 12 of the protocol:

```
Implement the tasks in specs/my-feature/tasks.md.
For each task: use the Task tool to dispatch to a subagent.
Validate after each task before proceeding.
```

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ORCH_SPECS` | `specs` | Default specs directory |
| `GIT_REMOTE` | `github` | Git remote name |
| `CODEX_MODEL` | *(none)* | Model override for Codex CLI |
| `CLAUDE_MODEL` | *(none)* | Model override for Claude Code CLI |
| `ORCH_POLL_INTERVAL` | `30` code / `15` doc | Shared poll interval override (tmux modes) |
| `ORCH_CODE_POLL_INTERVAL` | inherits shared or `30` | Code-loop-specific poll interval override |
| `ORCH_DOC_POLL_INTERVAL` | inherits shared or `15` | Document-loop-specific poll interval override |
| `ORCH_PARALLEL_GROUP_HOOK` | *(none)* | Optional hook to screen parallel `[P]` batches |
| `ORCH_EXPECTED_DIRS` | `src/\|tests/\|specs/\|...` | Pipe-separated regex for drift detection |

### CLI Options (orchestrate-loop.sh)

| Option | Default | Description |
|--------|---------|-------------|
| `--specs <path>` | `$ORCH_SPECS` | Specs directory |
| `--plan <path>` | `<specs>/plan.md` | Plan file |
| `--poll-interval <sec>` | `30` | Code-loop poll frequency |
| `--max-iterations <n>` | `3` | Max review-fix cycles |
| `--timeout <sec>` | `3600` | Max seconds per agent |
| `--test-cmd <cmd>` | *(none)* | Verification test command |
| `--lint-cmd <cmd>` | *(none)* | Verification lint command |
| `--bootstrap-reads <files>` | *(none)* | Files agents must read first |
| `--git-remote <name>` | `github` | Git remote name |
| `--phase <n\|name>` | *(all)* | Phase filter |
| `--tasks <ids>` | *(all)* | Task ID filter |
| `--from <task-id>` | *(start)* | Start from this task (inclusive) |
| `--to <task-id>` | *(end)* | Stop after this task (inclusive) |
| `--sequential-only` | `false` | Ignore `[P]` markers |
| `--dry-run` | `false` | Print without executing |
| `--resume` | `false` | Resume from state file |
| `--env <path>` | *(none)* | Environment file to source |

See [orchestration-protocol.md](orchestration-protocol.md) for the full configuration reference.

## Makefile Integration (optional)

`makefile-targets.mk` is an optional integration aid for Make-based projects. It provides `orch-*` targets that wrap the shell scripts.

```makefile
# In your root Makefile
PLAN   ?= specs/my-feature/plan.md
BRANCH ?= my-feature-branch
SPECS  ?= specs/my-feature
include .claude/orchestration/makefile-targets.mk
```

This is not required. The shell scripts and skill invocation patterns work without it.

## Using as a Skill

The `skills/orchestration/` directory is the canonical skill source.

**Claude:** Zip the directory and upload it as a custom skill in Claude.ai. The zip is a release artifact built from `skills/orchestration/` — it is not checked in.

```bash
cd skills && zip -r ../dist/orchestration-skill.zip orchestration/
```

**Codex:** Use the directory directly as a skill source by pointing Codex at `skills/orchestration/`.

The skill entry point is [skills/orchestration/SKILL.md](skills/orchestration/SKILL.md).

## File Inventory

| Path | Role |
|------|------|
| `README.md` | Primary public entry point |
| `bootstrap-prompt.md` | User-facing bootstrap prompt; convenience install path |
| `orchestration-protocol.md` | Full protocol reference (Sections 1-12) |
| `orchestrate-doc-prompt-template.md` | Prompt template for document orchestration |
| `orchestration-state.env.example` | State schema reference |
| `makefile-targets.mk` | Optional Make targets integration |
| `skills/orchestration/SKILL.md` | Canonical skill entry point |
| `skills/orchestration/references/install-paths.md` | File layout and path resolution reference |
| `skills/orchestration/references/runtime-modes.md` | Runtime mode selection and capability detection |
| `skills/orchestration/references/bootstrap-flow.md` | Bootstrap flow reference |
| `skills/orchestration/references/troubleshooting.md` | Common issues and remediation |
| `dist/orchestration-skill.zip` | Claude upload artifact (generated only, not checked in) |
| `scripts/orchestrate-loop.sh` | Autonomous code task loop (tmux mode) |
| `scripts/orchestrate-doc.sh` | Document draft/review/implement dispatch (tmux mode) |
| `scripts/dispatch.sh` | Single-task dispatch helper |
| `scripts/lib/orch-agent-runtime.sh` | Shared path resolution, polling defaults, dispatch helpers |
| `scripts/review-prompt-claude.md` | Code review template (Claude Code) |
| `scripts/review-prompt-codex.md` | Code review template (Codex) |
| `scripts/review-prompt-doc-claude.md` | Document review template (Claude Code) |
| `scripts/review-prompt-doc-codex.md` | Document review template (Codex) |
| `tests/runtime-regressions.sh` | Regression baseline for path resolution and runtime behavior |

## Documentation

- [orchestration-protocol.md](orchestration-protocol.md) — Full protocol including agent roles, dispatch commands, execution cycle, git monitoring, error recovery, escalation rules, review standards, autonomous loop, document orchestration, and single-session fallback.
- [orchestrate-doc-prompt-template.md](orchestrate-doc-prompt-template.md) — Prompt template for orchestrating document drafts and revisions.
- [skills/orchestration/references/](skills/orchestration/references/) — Skill reference files: install paths, runtime modes, bootstrap flow, and troubleshooting.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Community

- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)

## License

This project is available under the [MIT License](LICENSE).
