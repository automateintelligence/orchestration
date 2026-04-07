# Cross-Platform Orchestration Skill Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the orchestration repository into a reusable, cross-platform skill with bootstrap as the default first-run workflow and native subagents as the primary runtime model.

**Architecture:** One canonical skill source tree at `skills/orchestration/` with thin platform adapters. `SKILL.md` is the short entry point; detail lives in one-hop `references/` files that point back to existing repo artifacts rather than duplicating them. Documentation rewrites make the README bootstrap-first, the protocol subagent-first, and the bootstrap prompt runtime-aware.

**Tech Stack:** Markdown, shell (existing scripts unchanged)

**Spec:** `docs/superpowers/specs/2026-04-06-orchestration-skill-design.md`

---

## Chunk 1: Canonical Skill Directory

### Task 1: Create `skills/orchestration/SKILL.md`

**Files:**
- Create: `skills/orchestration/SKILL.md`

This is the short entry point for both Claude and Codex. It must describe when to use the skill, the decision order, and the outputs it produces. It should NOT duplicate the full protocol — it points to references.

- [ ] **Step 1: Create the directory structure**

```bash
mkdir -p skills/orchestration/references
```

- [ ] **Step 2: Write `SKILL.md`**

The file must contain these sections in this order. Write the content directly — do not leave placeholders.

**Required sections:**

1. **Frontmatter block** — skill name (`orchestration`), one-line description, trigger conditions (new repo setup, existing orchestration validation, orchestration launch guidance).

2. **When to Use** — Two scenarios: (a) bootstrapping orchestration into a new or partially-configured repository, (b) operating or troubleshooting an already-installed repository.

3. **Decision Order** — A numbered sequence the skill follows on every invocation:
   1. Detect: Is orchestration absent, partial, or fully installed in the target repo?
   2. Capabilities: Check for `git`, native subagent support, optional `tmux`.
   3. Route: If absent/partial → bootstrap flow. If installed → operate flow.
   4. Runtime: Recommend native subagents when supported; offer `tmux` compatibility mode when explicitly desired or when subagents are unavailable.
   5. Output: Produce artifacts and next-step commands appropriate to the detected state.

4. **Outputs** — What the skill produces:
   - For bootstrap: `orchestration-state.env`, agent bootstrap context block, launch command or next-step guidance, expected file layout.
   - For operate: validation report, launch/resume instructions, relevant doc pointers.

5. **References** — Short list pointing to each reference file:
   - `references/bootstrap-flow.md` — Bootstrap decision tree
   - `references/install-paths.md` — Installation options
   - `references/runtime-modes.md` — Runtime model and capability detection
   - `references/troubleshooting.md` — Common issues

6. **Platform Notes** — State that this skill works in both Claude and Codex. Claude packaging is a zip of the `skills/orchestration/` directory (generated as a release artifact, not checked in). Codex uses the directory directly.

**Constraints:**
- Keep SKILL.md under 120 lines.
- Use imperative voice ("Detect whether orchestration is installed", not "The skill detects").
- Do not duplicate content from the reference files — summarize and point.

**Key context for the implementing agent:**
- Read `bootstrap-prompt.md` to understand the question catalog and artifact templates the bootstrap flow uses.
- Read Sections 1 (lines 10-43), 10 (starts around line 350, title "Autonomous Code Task Loop" or similar), and 12 (starts around line 810, title "Single-Session Fallback") of `orchestration-protocol.md` to understand the command hierarchy and execution models.
- The skill structure is defined in the spec at lines 58-67.
- "Native subagent support" means the host can delegate bounded subtasks inside its own agent runtime without external tmux panes. In Claude: built-in agent/skill execution. In Codex: native subagents or equivalent delegation.

- [ ] **Step 3: Commit**

```bash
git add skills/orchestration/SKILL.md
git commit -m "skills/orchestration/SKILL.md -- add canonical skill entry point"
```

---

### Task 2: Create `references/bootstrap-flow.md`

**Files:**
- Create: `skills/orchestration/references/bootstrap-flow.md`

This is a short map of the bootstrap decision tree for skill authors and implementers. It summarizes the flow and points to `bootstrap-prompt.md` as the executable artifact. It must NOT duplicate the full question catalog or artifact templates from `bootstrap-prompt.md`.

- [ ] **Step 1: Write `bootstrap-flow.md`**

**Required content:**

1. **Purpose statement** — This file maps the bootstrap decision tree. The executable bootstrap prompt lives at `bootstrap-prompt.md` in the repo root.

2. **Entry conditions** — When bootstrap runs: orchestration is absent or partially installed in the target repository.

3. **Decision tree** — A concise representation (numbered list or simple text diagram) of the bootstrap flow:
   1. Inspect target repo for existing orchestration assets (`.claude/orchestration/`, `orchestration-state.env`, etc.)
   2. Classify state: absent, partial (some files present), or already installed.
   3. If already installed → exit bootstrap, route to operate flow.
   4. Check capabilities: `git` present? Native subagent support? `tmux` available?
   5. Recommend install path: vendored copy (canonical) or prompt-driven (convenience). See `references/install-paths.md`.
   6. Gather project context via question groups A-D (see `bootstrap-prompt.md` for the full catalog).
   7. Recommend runtime mode based on capabilities. See `references/runtime-modes.md`.
   8. Generate artifacts: `orchestration-state.env`, agent bootstrap block, launch command, quick reference card.
   9. Run validation checklist (see `bootstrap-prompt.md` Step 3).
   10. Present expected file layout and next-step commands.

4. **Error exits** — Reference the five error cases from the spec (not a git repo, missing canonical files, conflicting orchestration material, prompt-driven audit trail, no viable runtime).

5. **Canonical reference** — Point to `bootstrap-prompt.md` for the full question catalog, artifact templates, and validation checklist.

**Constraints:**
- Under 80 lines.
- Do not reproduce the question groups or artifact templates — just reference them.

- [ ] **Step 2: Commit**

```bash
git add skills/orchestration/references/bootstrap-flow.md
git commit -m "skills/orchestration/references/bootstrap-flow.md -- add bootstrap decision tree map"
```

---

### Task 3: Create `references/install-paths.md`

**Files:**
- Create: `skills/orchestration/references/install-paths.md`

- [ ] **Step 1: Verify scripts directory contents**

Run `ls scripts/` to confirm the file list matches the layout tree below before writing it. If any files are missing or renamed, update the layout accordingly.

- [ ] **Step 2: Write `install-paths.md`**

**Required content:**

1. **Two installation paths:**

   **Canonical: Vendored Copy** — Copy or vendor the orchestration repository into `.claude/orchestration/` inside the consuming repository. This is the simplest auditable path. The README documents this as the primary method.

   **Convenience: Prompt-Driven Install** — Paste or invoke `bootstrap-prompt.md` and let the AI generate installation steps. This is faster but less auditable. The user should still verify the resulting file layout.

2. **Which is canonical** — State clearly that vendored copy is canonical. Prompt-driven is a convenience alternative.

3. **Expected file layout after install** — Show the directory tree the consuming repository should have after a successful vendored install:
   ```
   .claude/
     orchestration/
       scripts/
         orchestrate-loop.sh
         orchestrate-doc.sh
         dispatch.sh
         lib/orch-agent-runtime.sh
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

4. **Makefile integration** — Note that `makefile-targets.mk` is an optional integration aid. Projects using Make can include it; it is not required.

5. **Standalone checkout** — Briefly note that developers working on the orchestration suite itself can use a standalone checkout. This is not an install path for consumers.

**Constraints:**
- Under 80 lines.
- Do not explain how to run orchestration — that belongs in `runtime-modes.md` and the protocol doc.

- [ ] **Step 3: Commit**

```bash
git add skills/orchestration/references/install-paths.md
git commit -m "skills/orchestration/references/install-paths.md -- add installation paths reference"
```

---

### Task 4: Create `references/runtime-modes.md`

**Files:**
- Create: `skills/orchestration/references/runtime-modes.md`

- [ ] **Step 1: Write `runtime-modes.md`**

**Required content:**

1. **Primary mode: Native Subagent Orchestration** — The orchestrator dispatches bounded subtasks using the host platform's built-in agent/subagent capabilities. No external process management required.
   - In Claude: built-in agent and skill execution (Task tool, subagent spawning).
   - In Codex: native subagents or equivalent built-in delegation.
   - This is the recommended mode for most users.

2. **Compatibility mode: tmux Multi-Session** — The orchestrator launches separate CLI processes in tmux panes/windows. Uses `orchestrate-loop.sh` for code tasks and `orchestrate-doc.sh` for document tasks. Polls for completion via `.exit` files.
   - Use when: user prefers pane-based orchestration, needs the existing shell loop, or native subagents are unavailable.
   - Reference: Section 10 of `orchestration-protocol.md` for the full code loop, Section 11 for document orchestration.

3. **Fallback mode: Single-Session** — The orchestrator runs inside an interactive Claude Code session, using the Task tool for context isolation. This is the simplest mode but lacks the process separation of tmux.
   - Reference: Section 12 of `orchestration-protocol.md`.
   - Note: The spec describes two runtime tiers (native subagents vs. tmux). This reference adds single-session as a third tier based on Section 12 of the protocol doc, which predates the spec.

4. **Capability detection** — During bootstrap, the skill should detect or ask:
   - Is `git` available? (Required for all modes.)
   - Does the host support native subagent dispatch? (Determines primary vs. compatibility recommendation.)
   - Is `tmux` available? (Determines whether compatibility mode is offered.)
   - Is Codex CLI installed? (Relevant for tmux multi-session mode.)

5. **Selection logic** — Simple decision: if native subagents are supported → recommend primary mode. If not and tmux + CLI are available → recommend compatibility mode. If only an interactive session → recommend single-session fallback. Always let the user override.

6. **Important note** — `tmux` is not required for orchestration. The protocol docs and README have been updated to reflect this.

**Constraints:**
- Under 90 lines.
- Do not reproduce the full protocol sections — summarize and point.

- [ ] **Step 2: Commit**

```bash
git add skills/orchestration/references/runtime-modes.md
git commit -m "skills/orchestration/references/runtime-modes.md -- add runtime modes reference"
```

---

### Task 5: Create `references/troubleshooting.md`

**Files:**
- Create: `skills/orchestration/references/troubleshooting.md`

- [ ] **Step 1: Write `troubleshooting.md`**

**Required content:**

Cover the five error scenarios from the spec (Section: Error Handling) plus common operational issues. For each, state: symptom, cause, resolution.

1. **Target repository is not a git repository** — Bootstrap can continue in degraded mode but orchestration features requiring git (branch tracking, commit monitoring, worktrees) will be unavailable.

2. **Canonical orchestration files missing from source** — If the orchestration repository itself is incomplete (e.g., missing scripts), stop and identify the missing files. Do not improvise replacements.

3. **Conflicting orchestration material in target repo** — If the target already has partial or different orchestration files, describe the conflict and recommend reconcile → overwrite → copy (in that preference order) rather than silent replacement.

4. **Prompt-driven install produced unexpected layout** — After a prompt-driven install, the user should compare the actual file layout against the expected layout in `references/install-paths.md`. If files are missing or misplaced, re-run bootstrap with vendored copy path.

5. **No viable runtime available** — If neither native subagents nor `tmux` are available, stop with a concrete explanation. Suggest: install tmux, switch to a platform that supports subagents, or use single-session fallback if running in Claude Code interactive mode.

6. **Agent dispatch failures** — Common tmux-mode issues: tmux not running, window creation fails, `.exit` file not appearing. Resolution: check tmux session exists, verify script paths, check agent CLI installation.

7. **Regression test failures after documentation changes** — Run `tests/runtime-regressions.sh` to verify. If failures relate to path resolution, check that any renamed or moved files are reflected in the test expectations.

**Constraints:**
- Under 100 lines.
- Use a consistent format: `### Issue: <title>` with **Symptom**, **Cause**, **Resolution** subheadings.

- [ ] **Step 2: Commit**

```bash
git add skills/orchestration/references/troubleshooting.md
git commit -m "skills/orchestration/references/troubleshooting.md -- add troubleshooting reference"
```

---

## Chunk 2: Documentation Modernization

### Task 6: Rewrite `README.md`

**Files:**
- Modify: `README.md` (complete rewrite, 191 lines currently)

The README is the primary public entry point. It must be rewritten around bootstrap-first usage and subagent-first runtime.

- [ ] **Step 1: Read the current `README.md` in full**

Read the entire file to understand every section that exists today.

- [ ] **Step 2: Write the new README**

**Required sections in this order:**

1. **Title and one-paragraph summary** — What this repo is (a cross-platform orchestration skill for multi-agent development), who it's for (developers using Claude or Codex for coordinated implement→review→iterate workflows), and the key value prop (drop it into any repo to get autonomous orchestration).

2. **Getting Started: Bootstrap** — Present `bootstrap-prompt.md` as the primary entry point for new users. Explain: paste the prompt into a Claude or Codex session, answer the questions, get your orchestration config. This is the first thing a new user should see.

3. **Installation** — Two paths:
   - **Canonical: Vendored Copy** — `cp -r` or git submodule into `.claude/orchestration/`. Mark this as the recommended path.
   - **Convenience: Prompt-Driven** — Use `bootstrap-prompt.md` to generate the install. Mark this as the alternative.
   - Point to `skills/orchestration/references/install-paths.md` for the expected file layout.

4. **Runtime Modes** — Three modes, presented in this order:
   - **Native Subagent Orchestration** (primary) — Brief description, when it applies.
   - **tmux Multi-Session** (compatibility) — Brief description, when to choose it.
   - **Single-Session Fallback** — Brief description, when to use it.
   - Point to `skills/orchestration/references/runtime-modes.md` for details.
   - **Critical:** Do NOT present tmux as required. The old README centered the tmux workflow; the new one must not.

5. **Quick Start** — A concise example for each runtime mode. For tmux mode, preserve the existing `tmux new-session` command pattern. For native subagent mode, show the skill invocation pattern. For single-session, show the TodoWrite-based pattern from Section 12 of the protocol.

6. **Configuration** — Brief reference to environment variables and CLI flags. Keep the existing configuration table but trim to essentials. Point to `orchestration-protocol.md` for the full reference.

7. **Makefile Integration** — Note that `makefile-targets.mk` is an optional integration aid for Make-based projects. Show the include pattern. Mark as optional, not required.

8. **Using as a Skill** — Explain that the `skills/orchestration/` directory is the canonical skill source:
   - **Claude:** The directory can be zipped and uploaded as a custom skill. The zip is a release artifact, not checked in.
   - **Codex:** Use the directory directly as a skill source.

9. **File Inventory** — Table of all suite components with one-line descriptions. Use the artifact disposition table from the spec as the source of truth. Include the new `skills/orchestration/` entries.

10. **Documentation** — Point to `orchestration-protocol.md` (full protocol reference), `orchestrate-doc-prompt-template.md` (document orchestration), `skills/orchestration/references/` (skill reference files).

11. **Community and License footer** — Preserve links to `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, and `LICENSE`. These files are unchanged by this sprint (see artifact disposition table in the spec). The current README has these links — carry them forward.

**Constraints:**
- Target length: 150-200 lines.
- The first thing a GitHub visitor reads after the title should make bootstrap discoverable.
- Never imply tmux is required.
- Preserve the existing `tmux new-session` command examples for users who choose that path — just don't make them the default.

**Key context for the implementing agent:**
- The current README (191 lines) centers the tmux workflow in Quick Start and presents bootstrap as an afterthought under "New Project Setup."
- The spec says: "A new GitHub visitor can discover bootstrap-first setup without already knowing `bootstrap-prompt.md` exists."
- The artifact disposition table in the spec (lines 136-162) maps every file's post-sprint status.

- [ ] **Step 3: Run regression tests**

```bash
bash tests/runtime-regressions.sh
```

Expected: All tests pass. The regression tests validate path resolution and runtime behavior in the scripts, which are unchanged. If any test references README content or paths that changed, investigate and fix the test expectation only if the old expectation is genuinely stale.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "README.md -- rewrite around bootstrap-first usage and subagent-first runtime"
```

---

### Task 7: Revise `bootstrap-prompt.md`

**Files:**
- Modify: `bootstrap-prompt.md` (158 lines currently)

The bootstrap prompt needs runtime capability detection and subagent branching. The existing question catalog and artifact templates are strong — this is a targeted revision, not a rewrite.

- [ ] **Step 1: Read the current `bootstrap-prompt.md` in full**

Read the entire file to understand the existing flow.

- [ ] **Step 2: Add runtime capability detection to Group D**

In "Step 1: Context Gathering → Group D — Execution Mode", the current questions assume tmux as the primary path. Revise Group D so that:

1. The first question asks about platform capabilities: "Does your environment support native subagent dispatch (e.g., Claude Task tool, Codex native subagents)?"
2. The tmux question becomes conditional: "If you prefer tmux-based orchestration or native subagents are unavailable: Is tmux available? Is Codex CLI installed?"
3. The runtime recommendation flows from capability detection, not from a user choice between named modes.

Do NOT remove existing questions — augment them. The existing questions about review rounds, off-limits directories, parallel conflict boundaries, and polling intervals remain valid for both runtime paths.

- [ ] **Step 3: Add subagent-mode artifact branch to Step 2**

In "Step 2: Generate Configuration", the current artifacts assume tmux. Add a branch:

- **If native subagent mode:** The launch command artifact should show skill invocation or a subagent dispatch pattern instead of a tmux command. The quick reference card should show subagent-relevant monitoring (not tmux attach).
- **If tmux mode:** Keep the existing tmux artifacts exactly as they are.
- **If single-session mode:** Keep the existing TodoWrite-based fallback pattern.

The `orchestration-state.env` artifact and agent bootstrap block are runtime-independent and need no changes.

- [ ] **Step 4: Update the header comment**

The header comment (lines 1-8) says "Claude will ask clarifying questions, then generate the launch artifacts." Update it to mention that the prompt works in both Claude and Codex and covers multiple runtime modes.

- [ ] **Step 5: Run regression tests**

```bash
bash tests/runtime-regressions.sh
```

Expected: All tests pass. If any test references bootstrap-prompt.md content that changed, investigate whether the test expectation is stale.

- [ ] **Step 6: Commit**

```bash
git add bootstrap-prompt.md
git commit -m "bootstrap-prompt.md:22-51,53-118,1-8 -- add runtime capability detection and subagent branching"
```

---

### Task 8: Revise `orchestration-protocol.md`

**Files:**
- Modify: `orchestration-protocol.md` (921 lines currently)

This is a targeted revision to make the runtime narrative subagent-first. The protocol doc is large (921 lines) — do NOT rewrite it. Make surgical changes.

- [ ] **Step 1: Read the protocol doc preamble and Section 1**

Read lines 1-43. The preamble and Section 1 (Command Hierarchy) currently center "Claude (via Claude.ai + Desktop Commander WSL access)" as orchestrator and assume tmux-based dispatch.

- [ ] **Step 2: Revise the preamble (lines 1-8)**

Update the authority block to:
- Present the protocol as runtime-agnostic (not tmux-specific).
- List native subagent orchestration as the primary execution model.
- List tmux multi-session as a compatibility path.
- Keep the role assignments (orchestrator, execution agent, review agent, architect) but decouple them from specific CLIs where possible.

Keep changes minimal — this is a framing adjustment, not a rewrite.

- [ ] **Step 3: Revise Section 1 — Command Hierarchy (lines 10-43)**

The "Claude -- Orchestrator" entry (lines 21-29) currently says "Can run autonomously via `orchestrate-loop.sh` (see Section 10)." Add a note that native subagent dispatch (Section 12) is the primary execution model, with the shell loop as a compatibility path.

Do not change the role definitions for Codex CLI or Claude Code CLI — they apply to both runtime models.

- [ ] **Step 4: Read and revise the Section 10 introduction**

Read the beginning of Section 10 (the autonomous loop section). Add a brief note at the top of Section 10 stating that this section documents the tmux-based compatibility mode. Point to Section 12 for the primary native subagent model.

Do NOT modify the rest of Section 10 — the tmux loop documentation is complete and correct for its mode.

- [ ] **Step 5: Read and revise the Section 12 introduction**

Read the beginning of Section 12 (Single-Session Fallback). Currently titled "Single-Session Fallback" with "fallback" framing throughout. Revise:

1. Retitle to "Native Subagent Orchestration" or "Single-Session / Native Subagent Mode" — something that does not frame it as a fallback.
2. Update the "When to Use" section (currently lines 817-822) to present this as the primary mode, not a fallback. Remove or invert the "when tmux is unavailable" framing.
3. Update the "How It Differs" comparison table (currently line 825). The current column headers are "Multi-Session (Sections 10-11)" and "Single-Session". Rename them to reflect the new framing (e.g., "Native Subagent (Primary)" and "tmux Multi-Session (Compatibility)") and swap column order so the primary mode is listed first.
4. Keep all existing content (dispatch examples, verification, git monitoring, agent bootstrap, file locations) — just adjust the framing language.

- [ ] **Step 6: Run regression tests**

```bash
bash tests/runtime-regressions.sh
```

Expected: All tests pass. The script content is unchanged; only the surrounding documentation framing changed.

- [ ] **Step 7: Commit**

```bash
git add orchestration-protocol.md
git commit -m "orchestration-protocol.md:1-8,10-43,Section10-intro,Section12 -- subagent-first runtime framing"
```

---

## Chunk 3: Verification

### Task 9: Cross-Document Consistency Check and Smoke Test

**Files:**
- Read: All files modified in Tasks 1-8
- Read: `tests/runtime-regressions.sh`

This task verifies the sprint's success criteria from the spec.

- [ ] **Step 1: Run the full regression suite**

```bash
bash tests/runtime-regressions.sh
```

Expected: All tests pass.

- [ ] **Step 2: Verify success criterion 1 — GitHub visitor discoverability**

Read `README.md` and verify:
- The first substantive section after the title introduces bootstrap.
- `bootstrap-prompt.md` is mentioned by name within the first 30 lines.
- A new user can find and follow the bootstrap flow without prior knowledge.

- [ ] **Step 3: Verify success criterion 2 — Claude skill usability**

Read `skills/orchestration/SKILL.md` and verify:
- It describes when to use, decision order, and outputs.
- All four reference files are linked and exist.
- The skill is self-contained enough for Claude packaging (no broken internal references).

- [ ] **Step 4: Verify success criterion 3 — Codex skill usability**

Verify that `skills/orchestration/SKILL.md` works as a Codex entry point:
- The file uses no Claude-specific syntax that would break in Codex.
- References point to files within the skill directory or the repo root (both accessible from Codex).

- [ ] **Step 5: Verify success criterion 4 — tmux not presented as mandatory**

Grep across all modified files:
```bash
grep -rn "tmux" README.md bootstrap-prompt.md orchestration-protocol.md skills/orchestration/
```

For each occurrence, verify it appears in context as optional/compatibility, not as a requirement.

- [ ] **Step 6: Verify success criterion 5 — bootstrap-prompt.md is a primary artifact**

Check README.md for `bootstrap-prompt.md` mentions. It should appear in:
- The Getting Started / Bootstrap section
- The Installation section (convenience path)
- The File Inventory table

- [ ] **Step 7: Verify success criterion 6 — canonical skill source tree**

```bash
find skills/orchestration/ -type f
```

Expected output:
```
skills/orchestration/SKILL.md
skills/orchestration/references/bootstrap-flow.md
skills/orchestration/references/install-paths.md
skills/orchestration/references/runtime-modes.md
skills/orchestration/references/troubleshooting.md
```

- [ ] **Step 8: Cross-document consistency check**

Read the following files and verify no contradictions on install path or runtime selection:
- `README.md` (installation section, runtime section)
- `skills/orchestration/SKILL.md` (decision order)
- `skills/orchestration/references/install-paths.md` (canonical vs convenience)
- `skills/orchestration/references/runtime-modes.md` (primary vs compatibility)
- `bootstrap-prompt.md` (Group D questions, artifact generation)
- `orchestration-protocol.md` (preamble, Section 1, Section 10 intro, Section 12 intro)

Specific things to check:
- All docs agree that vendored copy is the canonical install path.
- All docs agree that native subagents are the primary runtime.
- All docs agree that tmux is optional/compatibility.
- No doc implies tmux is required.
- Reference file cross-links are valid (file exists at the referenced path).
- The `skills/orchestration/` directory is self-contained for Claude zip packaging: no references to files outside the skill directory or repo root that would break when the directory is zipped in isolation.

- [ ] **Step 9: Manual bootstrap smoke test**

Create a temporary sample git repo and run through the documented bootstrap flow:

```bash
cd /tmp
mkdir orchestration-smoke-test && cd orchestration-smoke-test
git init
```

Then verify:
1. The README's bootstrap instructions are followable from this empty repo.
2. The vendored copy install path produces the expected file layout from `references/install-paths.md`.
3. The runtime mode recommendation logic in `references/runtime-modes.md` makes sense given this environment's capabilities.

Record the evidence:
- The command used to drive bootstrap.
- The resulting file layout.
- The runtime recommendation produced.
- The next-step command the user would run.

Clean up after:
```bash
rm -rf /tmp/orchestration-smoke-test
```

- [ ] **Step 10: Commit any fixes from verification**

If any issues were found and fixed during verification steps 2-9, commit each fix atomically:

```bash
git add <fixed-files>
git commit -m "<fixed-files>:<lines> -- fix <what was inconsistent>"
```

If no fixes needed, skip this step.
