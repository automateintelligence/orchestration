# Installation Paths

## Canonical Path: Vendored Copy

The primary installation method is to **vendor the orchestration repository** into `.claude/orchestration/` within your consuming repository.

**Steps:**
1. Copy or clone the orchestration repository
2. Place its contents into `.claude/orchestration/` in your project
3. Verify the directory structure matches the layout below
4. Reference scripts and prompts via absolute paths: `./.claude/orchestration/scripts/`, etc.

This is the most auditable path — all orchestration code is local and under version control.

## Convenience Path: Prompt-Driven Install

For faster setup, paste the contents of `bootstrap-prompt.md` into an AI conversation and let it generate installation steps. This is quicker but less auditable.

**Note:** Always verify the resulting file layout matches the expected structure before using.

## Expected File Layout

After a successful vendored install, your project should contain:

```
.claude/
  orchestration/
    scripts/
      orchestrate-loop.sh
      orchestrate-doc.sh
      dispatch.sh
      lib/
        orch-agent-runtime.sh
      review-prompt-claude.md
      review-prompt-codex.md
      review-prompt-doc-claude.md
      review-prompt-doc-codex.md
    orchestration-protocol.md
    bootstrap-prompt.md
    orchestrate-doc-prompt-template.md
    orchestration-state.env.example
    makefile-targets.mk
```

## Makefile Integration

The `makefile-targets.mk` file provides optional Make targets for common orchestration tasks. Projects using Make can include it in their Makefile; it is not required.

## Standalone Checkout

Developers working on the orchestration suite itself use a standalone checkout of the repository. This is the internal development path, not an installation method for consumers.

---

For how to run orchestration after installation, see `runtime-modes.md` and `orchestration-protocol.md`.
