---
skill: orchestration
description: Configure, launch, and operate multi-agent task orchestration in a repository.
triggers:
  - new repo setup needing orchestration installed
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

---

## Decision Order

Follow this sequence on every invocation:

1. **Detect** — Determine whether orchestration is absent, partial, or fully
   installed in the target repository. Look for `orchestration-state.env` (or
   `.claude/orchestration-state.env`), `scripts/orchestrate-loop.sh`, and a
   `tasks.md` with pending `[ ]` items.

2. **Capabilities** — Check for required and optional tooling:
   - Required: `git` (must be present)
   - Native subagents: determine whether the host runtime supports bounded
     subtask delegation without external processes (Claude built-in agent
     execution; Codex native subagents or equivalent)
   - Optional: `tmux` (enables multi-session mode with separate CLI processes)

3. **Route** — Based on detection:
   - Absent or partial → follow the bootstrap flow (`references/bootstrap-flow.md`)
   - Fully installed → follow the operate flow (validate, launch, or resume)

4. **Runtime** — Recommend the appropriate execution model:
   - **Native subagents** (primary): use when the host supports bounded subtask
     delegation (Claude Task tool, Codex native subagents). No tmux required.
     This is the default recommendation.
   - **tmux compatibility mode**: offer when the user prefers multi-session pane
     orchestration, when Codex CLI is the intended implementer, or when native
     subagents are unavailable. Requires `tmux` and the CLI tools.
   - **Single-session**: use when running interactively in Claude Code without
     native subagent delegation. The orchestrator acts as implementer using the
     Task tool for context isolation.

5. **Output** — Produce artifacts and next-step commands matching the detected
   state (see Outputs section below).

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
