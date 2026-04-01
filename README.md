# Orchestration Protocol Suite

A multi-agent development workflow for coordinating Claude.ai (orchestrator), Codex CLI (implementer), and Claude Code CLI (reviewer). Drop this into any repo to get autonomous implement -> review -> iterate cycles driven by a tasks.md file.

## Quick Start

1. **Copy the suite into your project's `.claude/orchestration/` directory:**
   ```bash
   cp -r ~/.claude/orchestration/ .claude/orchestration/
   ```

2. **Set environment variables** (or pass via CLI flags):
   ```bash
   export ORCH_SPECS="specs/my-feature"        # Path to your spec directory
   export GIT_REMOTE="github"                  # Git remote name (default: github)
   ```

3. **Include Makefile targets** (optional):
   ```makefile
   # In your root Makefile
   PLAN   ?= specs/my-feature/plan.md
   BRANCH ?= my-feature-branch
   SPECS  ?= specs/my-feature
   include .claude/orchestration/makefile-targets.mk
   ```

4. **Run the orchestration loop:**
   ```bash
   tmux new-session -s orchestrator \
     '.claude/orchestration/scripts/orchestrate-loop.sh specs/my-feature/tasks.md my-feature-branch \
      --specs specs/my-feature --env ~/.secrets/my-project.env'
   ```

5. **Run with verification:**
   ```bash
   tmux new-session -s orchestrator \
     '.claude/orchestration/scripts/orchestrate-loop.sh specs/my-feature/tasks.md my-feature-branch \
      --specs specs/my-feature \
      --test-cmd "pytest tests/ -x -q" \
      --lint-cmd "ruff check ." \
      --bootstrap-reads ".claude/CLAUDE.md,specs/my-feature/spec.md" \
      --git-remote github'
   ```

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ORCH_SPECS` | `specs` | Default specs directory (used when `--specs` not passed) |
| `GIT_REMOTE` | `github` | Git remote name for push operations |
| `CODEX_MODEL` | *(none)* | Model override for Codex CLI (e.g., `o3`) |
| `CLAUDE_MODEL` | *(none)* | Model override for Claude Code CLI |
| `ORCH_EXPECTED_DIRS` | *(see below)* | Pipe-separated regex for expected file paths (drift detection) |

`ORCH_EXPECTED_DIRS` defaults to `src/|tests/|specs/|planning/|docs/|\.claude/|deploy/|tools/|Makefile` and controls which file paths are considered "expected" during git drift detection. Set this to match your project's directory structure.

### Makefile Variables

| Variable | Purpose |
|----------|---------|
| `PLAN` | Path to plan.md |
| `BRANCH` | Git branch name |
| `SPECS` | Specs directory path |

### CLI Options (orchestrate-loop.sh)

| Option | Default | Description |
|--------|---------|-------------|
| `--specs <path>` | `$ORCH_SPECS` | Specs directory |
| `--plan <path>` | `<specs>/plan.md` | Plan file |
| `--poll-interval <sec>` | `30` | Poll frequency |
| `--max-iterations <n>` | `3` | Max review-fix cycles |
| `--timeout <sec>` | `3600` | Max seconds per agent |
| `--test-cmd <cmd>` | *(none)* | Verification test command |
| `--lint-cmd <cmd>` | *(none)* | Verification lint command |
| `--bootstrap-reads <files>` | *(none)* | Files agents must read first |
| `--git-remote <name>` | `github` | Git remote name |
| `--phase <n\|name>` | *(all)* | Phase filter |
| `--tasks <ids>` | *(all)* | Task ID filter |
| `--from <id>` / `--to <id>` | *(all)* | Task range filter |
| `--sequential-only` | `false` | Ignore `[P]` markers |
| `--dry-run` | `false` | Print without executing |
| `--resume` | `false` | Resume from state file |
| `--env <path>` | *(none)* | Environment file to source |

## New Project Setup

Use the bootstrap prompt to configure orchestration for a new project:

```bash
# Option 1: Paste bootstrap-prompt.md into a new Claude session
cat ~/.claude/orchestration/bootstrap-prompt.md

# Option 2: Reference it directly
claude -p "$(cat ~/.claude/orchestration/bootstrap-prompt.md)

My project: [describe your project here]"
```

The bootstrap prompt will ask you targeted questions about your project, then generate all the configuration artifacts (state file, agent bootstrap block, launch command, monitoring cheat sheet).

See [bootstrap-prompt.md](bootstrap-prompt.md) for the full template.

## File Inventory

| File | Purpose |
|------|---------|
| `bootstrap-prompt.md` | Meta-prompt for configuring orchestration on a new project |
| `orchestration-protocol.md` | Full protocol documentation (Sections 1-12) |
| `orchestration-state.env.example` | Schema for runtime state (auto-populated) |
| `orchestrate-doc-prompt-template.md` | Prompt template for document orchestration |
| `makefile-targets.mk` | Makefile include for `orch-*` targets |
| `scripts/dispatch.sh` | Single-task dispatch helper |
| `scripts/orchestrate-loop.sh` | Autonomous code task loop |
| `scripts/orchestrate-doc.sh` | Document draft/review/implement dispatch |
| `scripts/review-prompt-codex.md` | Code review template (Codex) |
| `scripts/review-prompt-claude.md` | Code review template (Claude Code) |
| `scripts/review-prompt-doc-codex.md` | Document review template (Codex) |
| `scripts/review-prompt-doc-claude.md` | Document review template (Claude Code) |

## Key Features

### Git-Based Progress Monitoring
During polling, the orchestrator tracks agent progress via git commits, spot-checks diffs for scope drift, and audits for uncommitted changes after completion. See Section 4 of the protocol.

### Verification Gate
After a review PASS, the orchestrator runs test/lint commands directly (not delegated to agents) before marking a task complete. Failures generate synthetic reviews and trigger fix iterations.

### JSON State File
In addition to `orchestration-state.env`, the loop produces a machine-parseable `.json` state file for programmatic consumption.

### Single-Session Mode (Section 12)
When tmux or Codex CLI is unavailable, the orchestrator can run inside Claude Code's interactive session using Task tool subagents for context isolation.

### Error Recovery
Agent failures are classified (dependency errors, context overflow, timeout) with diagnostic capture and configurable re-dispatch limits.

## Documentation

See [orchestration-protocol.md](orchestration-protocol.md) for the full protocol including:
- Command hierarchy and agent roles (Section 1)
- Dispatch commands (Section 3)
- Execution cycle with diagrams (Section 4)
- Git-based progress monitoring (Section 4)
- Error recovery (Section 4)
- Escalation rules (Section 5)
- Review standards and verdict rules (Section 6)
- Autonomous loop operation (Section 10)
- Document orchestration mode (Section 11)
- Single-session mode (Section 12)

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Community

- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)

## License

This project is available under the [MIT License](LICENSE).
