# Cross-Platform Orchestration Skill Design

- Date: 2026-04-06
- Status: Approved for planning
- Scope: Turn the orchestration repository into a reusable skill source for Claude and Codex, with bootstrap as the default first-run workflow.

## Summary

This repository should become the canonical source for a cross-platform orchestration skill that works in both Claude and Codex. The skill's default job is to bootstrap orchestration into a target repository. Its secondary job is to guide day-to-day orchestration use after installation.

The design is guidance-first. The skill should inspect the target repository, identify missing or conflicting orchestration pieces, recommend the right install path, and generate the launch artifacts and next commands. It should not assume `tmux` is mandatory. Native subagent orchestration is the primary runtime model. The existing `tmux` loop remains an optional compatibility path.

## Goals

1. Make the repository understandable as an installable skill from both GitHub and in-tool usage.
2. Expose `bootstrap-prompt.md` as a first-class entry point instead of a hidden extra.
3. Support both Claude and Codex from one canonical source of truth.
4. Make bootstrap the default workflow for a new repository.
5. Make native subagents the primary runtime story and demote `tmux` to an optional compatibility mode.
6. Keep the documentation, skill instructions, and bootstrap artifacts aligned.

## Non-Goals

1. Replace the existing orchestration shell scripts in this sprint.
2. Remove `tmux` support entirely.
3. Introduce new package-manager dependencies.
4. Build separate feature-complete skills for Claude and Codex with divergent behavior.

## Current Context

The repository already has the core orchestration assets:

- `README.md` describes the orchestration suite and current execution model.
- `bootstrap-prompt.md` contains a strong guided setup flow but is under-emphasized in the public docs.
- `orchestration-protocol.md` documents the operating model and currently centers the `tmux` workflow.
- `scripts/` contains the shell implementation for the current orchestration loop.
- `tests/runtime-regressions.sh` provides a lightweight regression baseline.

The current gap is not missing orchestration logic. The gap is productization. The repo needs a coherent skill surface, a clearer install story, and a modern runtime story that recognizes native subagents.

## Primary Product Decision

Use one canonical skill source tree with thin platform adapters.

The repository should define orchestration behavior once, then expose it in platform-native ways:

- Claude-compatible custom skill packaging for upload/use in Claude.
- Codex-compatible `SKILL.md` workflow for local use in Codex and OMX.

Behavior should not fork by platform unless the platform actually requires different installation or invocation mechanics.

## Canonical Skill Structure

Add a dedicated skill directory that becomes the source of truth for the orchestration workflow.

Proposed shape:

```text
skills/
  orchestration/
    SKILL.md
    references/
      bootstrap-flow.md
      install-paths.md
      runtime-modes.md
      troubleshooting.md
```

Design rules for this structure:

1. `SKILL.md` stays short and focused. It should describe when to use the skill, the decision order, and the outputs it must produce.
2. Supporting detail lives in one-hop reference files instead of expanding `SKILL.md` into a giant protocol dump.
3. The reference files point back to existing canonical artifacts in the repo where appropriate instead of duplicating them.
4. The skill package should be portable enough to ship to Claude while still being understandable to Codex.

## User Flows

### Flow 1: Bootstrap a New Repository

1. User invokes the orchestration skill from Claude or Codex.
2. The skill inspects the target repository and determines whether orchestration is absent, partial, or already installed.
3. The skill checks core capabilities: `git`, native subagent support, and optional `tmux`.
4. The skill recommends the canonical install path from this repository.
5. The skill asks targeted setup questions and generates the expected orchestration artifacts and launch guidance.
6. The skill clearly states which runtime mode will be used:
   - native subagent orchestration when supported
   - `tmux` compatibility mode when explicitly desired or needed
7. The skill produces exact next steps and expected file layout.

### Flow 2: Operate an Already-Installed Repository

1. User invokes the skill in a repository that already contains orchestration assets.
2. The skill validates that expected files are present and not obviously inconsistent.
3. The skill explains how to launch or resume orchestration in the preferred runtime mode.
4. The skill surfaces the relevant docs and troubleshooting guidance for the user's context.

## Installation Model

The repository remains the canonical source of the orchestration payload. The design should document two installation paths:

### Canonical Path: Vendored Copy

The public docs should continue to support copying or vendoring this repository into `.claude/orchestration/` inside a consuming repository. This is the simplest auditable path and matches how similar skill-driven toolchains are commonly installed.

### Convenience Path: Prompt-Driven Install

The docs should also support a prompt-driven install flow for users who prefer to paste or invoke a setup prompt and let Claude generate the installation steps. `bootstrap-prompt.md` becomes the main artifact for this path, not a buried appendix.

The README must state which path is canonical and which path is convenience.

## Runtime Model

Native subagents are the primary orchestration model.

Implications:

1. README and skill docs should describe subagent-first orchestration before mentioning `tmux`.
2. `tmux` becomes an optional compatibility path for users who prefer pane-based orchestration or rely on the existing shell loop.
3. Capability detection happens during bootstrap so the user gets a runtime recommendation early, not after setup is complete.
4. The protocol docs must stop implying that `tmux` is required for orchestration to work.

## Documentation Changes

### README

`README.md` should be rewritten to make the public story obvious:

1. What the repo is.
2. Who it is for.
3. How to install it.
4. How the bootstrap flow works.
5. How runtime mode is selected.
6. Where `bootstrap-prompt.md` fits.
7. How to use the repo from Claude and Codex.

### Bootstrap Prompt

`bootstrap-prompt.md` should be updated so it:

1. Treats bootstrap as the primary new-repo workflow.
2. Detects or asks about runtime capabilities.
3. Branches between native subagent orchestration and optional `tmux`.
4. Produces output that matches the revised README.

### Protocol Doc

`orchestration-protocol.md` should be updated so it:

1. Presents native subagents as the default execution model.
2. Preserves the current shell and `tmux` loop as a compatibility path.
3. Aligns terminology with the skill and README.

## Error Handling

The skill should fail clearly and early:

1. If the target repository is not a git repository, say bootstrap can continue in a degraded state but orchestration will be limited until git exists.
2. If the canonical orchestration files are missing from this repository, stop and identify the missing files instead of improvising.
3. If the target repository already contains conflicting orchestration material, describe the conflict and recommend reconcile-overwrite-copy rather than silent replacement.
4. If the user chooses a prompt-driven install path, the skill should still show the resulting expected file layout so the install remains auditable.
5. If neither native subagents nor `tmux` are viable, the skill should stop with a concrete explanation instead of pretending setup succeeded.

## Verification Strategy

The sprint should verify both documentation and workflow coherence:

1. A new GitHub visitor can discover bootstrap-first setup without already knowing `bootstrap-prompt.md` exists.
2. The Claude-facing skill package and the Codex-facing skill entry both route to the same core references.
3. The documented bootstrap path produces the expected orchestration footprint and launch guidance in a sample repository.
4. README, skill docs, bootstrap prompt, and protocol docs do not contradict each other on install path or runtime selection.
5. Existing regression coverage continues to pass after documentation and skill-structure changes.

## Proposed Implementation Boundaries

This design is intentionally narrow for the sprint:

1. Add the canonical skill directory and supporting references.
2. Rewrite the public docs around bootstrap-first usage.
3. Modernize the runtime narrative to be subagent-first.
4. Keep the current script layer intact unless a doc change requires a small compatibility edit.

This keeps the sprint reviewable and avoids coupling a documentation and productization pass to a deeper runtime rewrite.

## Success Criteria

The sprint is successful when all of the following are true:

1. A GitHub user can understand how to install and bootstrap orchestration from the README alone.
2. A Claude user can use the skill without a separate undocumented setup story.
3. A Codex user can use the same core skill without maintaining a second divergent workflow.
4. The repository no longer implies that `tmux` is mandatory.
5. `bootstrap-prompt.md` is clearly presented as a primary setup artifact.
6. The repo has a clear canonical skill source tree that future work can extend without duplicating instructions.
