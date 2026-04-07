# Runtime Modes

The orchestrator supports three execution models. Choose based on your platform capabilities.

## Primary Mode: Native Subagent Orchestration

The orchestrator dispatches bounded subtasks using the host platform's built-in agent/subagent capabilities (Claude agent execution or Codex native subagents). No external process management required. Recommended for most users.

**Reference:** Section 12 of `orchestration-protocol.md`.

## Compatibility Mode: tmux Multi-Session

The orchestrator launches separate CLI processes in tmux panes/windows. Uses `orchestrate-loop.sh` for code tasks and `orchestrate-doc.sh` for document tasks. Polls for completion via `.exit` files. Process-level isolation with configurable polling (30s code, 15s docs).

**Use when:** User prefers pane-based orchestration, Codex is the implementer, native subagents unavailable, or `tmux` + CLI tools installed.

**Reference:** Sections 10-11 of `orchestration-protocol.md`.

## Single-Session Mode

The orchestrator runs inside an interactive Claude Code session. Uses the Task tool for context isolation, dispatching bounded subtasks synchronously. Simplest setup with no tmux or polling overhead.

**Use when:** Running inside Claude Code, multi-session overhead not justified, or tmux unavailable.

**Reference:** Section 12 of `orchestration-protocol.md`.

## Capability Detection

During bootstrap, detect or ask:

1. **Is `git` available?** (Required for all modes.)
2. **Does the host support native subagent dispatch?** (Claude/Codex: yes)
3. **Is `tmux` available?** (Enables compatibility mode)
4. **Is CLI installed?** (Enables tmux multi-session mode)

## Selection Logic

```
Native subagents supported?
├─ Yes → Primary mode
└─ No → tmux + CLI?
   ├─ Yes → Compatibility mode
   └─ No → Single-session mode
```

Always let the user override.

---

## Important Note

`tmux` is **not required** for orchestration. Both native subagents and single-session modes operate without it. The protocol reflects this — tmux is optional for users preferring pane-based management.
