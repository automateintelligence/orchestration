# Runtime Modes

The orchestrator supports three execution models. Choose based on your platform capabilities and preferences.

## Primary Mode: Native Subagent Orchestration

The orchestrator dispatches bounded subtasks using the host platform's built-in agent/subagent capabilities.

**Characteristics:**
- No external process management required
- Tasks execute synchronously via subagent calls (Claude agent execution or Codex native subagents)
- Context isolation and parallelism provided by the subagent runtime
- Recommended for most users

**When to use:**
- Claude Code session with native agent execution
- Codex CLI with native subagent dispatch
- Any host that supports bounded subtask delegation

**Reference:** Section 12 of `orchestration-protocol.md` describes the single-session mode, which typically uses this pattern with the Task tool for context isolation.

---

## Compatibility Mode: tmux Multi-Session

The orchestrator launches separate CLI processes in tmux panes/windows. Uses `orchestrate-loop.sh` for code tasks and `orchestrate-doc.sh` for document tasks. Polls for completion via `.exit` files.

**Characteristics:**
- Process-level isolation: each agent runs in its own tmux window
- Configurable polling (30s for code, 15s for documents)
- Full execution history logged to `planning/orchestration-log.md`
- Support for parallel execution of marked `[P]` tasks

**When to use:**
- User explicitly prefers pane-based orchestration
- Codex CLI is the intended implementer (ships with this pattern)
- Native subagents are unavailable
- `tmux` and CLI tools are installed

**Reference:** Section 10 (`orchestrate-loop.sh`) for code orchestration; Section 11 (`orchestrate-doc.sh`) for document workflows.

---

## Fallback Mode: Single-Session

The orchestrator runs inside an interactive Claude Code session. Uses the Task tool for context isolation and parallelism, dispatching bounded subtasks synchronously.

**Characteristics:**
- Simplest setup: no tmux or separate CLI processes
- Orchestrator and agents coexist in the same session
- Verification (test/lint) runs directly, not delegated
- No polling overhead — tasks return synchronously

**When to use:**
- Running inside Claude Code interactive session
- Quick orchestration where multi-session overhead isn't justified
- tmux unavailable or user prefers interactive mode

**Reference:** Section 12 of `orchestration-protocol.md` for full details.

---

## Capability Detection

During bootstrap, detect or ask:

1. **Is `git` available?** (Required for all modes.)
2. **Does the host support native subagent dispatch?**
   - Claude: yes (native agent execution)
   - Codex: yes (native subagents)
   - Other: check documentation
3. **Is `tmux` available?** (Determines whether compatibility mode is available.)
4. **Is CLI installed?** (Codex, Claude Code, or equivalent — relevant for tmux multi-session mode.)

---

## Selection Logic

**Simple decision tree:**

```
Native subagents supported?
├─ Yes → Recommend primary mode (default)
└─ No
   └─ tmux + CLI available?
      ├─ Yes → Recommend compatibility mode
      └─ No
         └─ Interactive session?
            ├─ Yes → Recommend single-session fallback
            └─ No → BLOCKED (no suitable runtime found)
```

**Always let the user override** the recommendation.

---

## Important Note

`tmux` is **not required** for orchestration. Native subagents or single-session mode both operate without it. The protocol and reference materials have been updated to reflect this — tmux is purely optional for users who prefer multi-session pane-based management.
