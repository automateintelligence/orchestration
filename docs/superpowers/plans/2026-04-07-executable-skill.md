# Executable Orchestration Skill Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the orchestration skill execute install and bootstrap inline — zero handoffs, zero copy-pasting markdown files.

**Architecture:** SKILL.md becomes an executable instruction set with Bash commands and inline question flow. `bootstrap-prompt.md` and `install.sh` stay as standalone fallbacks. The skill references `install-paths.md` for the file manifest and `bootstrap-prompt.md` for the question catalog (via pointer, not duplication).

**Tech Stack:** Markdown skill instructions, Bash commands

**Spec:** `docs/superpowers/specs/2026-04-07-executable-skill.md`

---

## Chunk 1: Executable Skill

### Task 1: Rewrite `skills/orchestration/SKILL.md` to execute instead of describe

**Files:**
- Modify: `skills/orchestration/SKILL.md` (99 lines currently)

The current SKILL.md describes what to do but tells the user to go do it. The new version gives the AI executable instructions — Bash commands to run, questions to ask, files to write.

- [ ] **Step 1: Read the current SKILL.md in full**

Read the entire file to understand the current structure.

- [ ] **Step 2: Rewrite SKILL.md**

The file keeps the same frontmatter and section structure but the Decision Order and Outputs sections become executable. The new content must cover three entry points.

**Frontmatter** — keep as-is but add entry point metadata:

```yaml
---
skill: orchestration
description: Install, configure, and operate multi-agent task orchestration in a repository.
entry_points:
  - orchestration        # full auto: detect → install → bootstrap → operate
  - orchestration:install  # install runtime files only
  - orchestration:init     # bootstrap only (assumes files installed)
triggers:
  - new repo setup needing orchestration
  - existing orchestration needing validation or troubleshooting
  - guidance on launching or resuming an orchestration run
---
```

**When to Use** — keep the two scenarios (Bootstrapping, Operating) but add a third: "Installing only" for users who want to install without configuring.

**Entry Points** — new section after When to Use. Three entry points:

1. **`/orchestration`** — Full auto. Detect → install if needed → bootstrap if unconfigured → operate if ready.
2. **`/orchestration:install`** — Install runtime files only. No bootstrap. For manual configuration.
3. **`/orchestration:init`** — Bootstrap only. Requires files already installed. Errors with a concrete message if they're not.

**Decision Order** — rewrite to be executable instructions, not descriptions. The AI reading this should be able to act on each step without interpretation.

Step 1 — **Detect**. Run these Bash commands:

```bash
# Check vendored install
ls .claude/orchestration/scripts/orchestrate-loop.sh 2>/dev/null && echo "INSTALLED" || echo "NOT_INSTALLED"
# Check for state file
ls .claude/orchestration-state.env orchestration-state.env 2>/dev/null && echo "HAS_STATE" || echo "NO_STATE"
# Check for tasks
find . -name "tasks.md" -path "*/specs/*" 2>/dev/null | head -1
```

Route based on results:
- `NOT_INSTALLED` → install flow (Step 2)
- `INSTALLED` + `NO_STATE` → bootstrap flow (Step 3)
- `INSTALLED` + `HAS_STATE` → operate flow (Step 5)
- If entry point is `/orchestration:install` → skip to Step 2 only, stop after install
- If entry point is `/orchestration:init` → verify installed (if NOT_INSTALLED, error: "Orchestration files not found. Run `/orchestration:install` first."), then skip to Step 3

Step 2 — **Install**. Locate the source repo and copy runtime files:

```bash
# Find source repo (check common locations)
for SRC in "$HOME/.claude/orchestration" "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/orchestration"; do
  [ -f "$SRC/install.sh" ] && break
  SRC=""
done
```

If `$SRC` is empty, ask the user: "Where is the orchestration source repo? (e.g., `~/code/orchestration`)"

Then run:
```bash
"$SRC/install.sh" .claude/orchestration
```

If `install.sh` is not found at the source path, fall back to copying files directly per the manifest in `references/install-paths.md` (mkdir + cp each file individually).

Verify the layout matches `references/install-paths.md`. If verification fails, show what's missing and stop.

If entry point is `/orchestration:install`, stop here with: "Installed. Run `/orchestration:init` to configure, or paste `bootstrap-prompt.md` into a session."

Otherwise flow directly into Step 3.

Step 3 — **Bootstrap: Capability Detection**. Run these checks automatically (do not ask the user):

```bash
# git
git rev-parse --git-dir 2>/dev/null && echo "GIT: yes" || echo "GIT: no"
# tmux
command -v tmux >/dev/null 2>&1 && echo "TMUX: yes" || echo "TMUX: no"
# Codex CLI
command -v codex >/dev/null 2>&1 && echo "CODEX: yes" || echo "CODEX: no"
# Claude CLI
command -v claude >/dev/null 2>&1 && echo "CLAUDE_CLI: yes" || echo "CLAUDE_CLI: no"
```

Native subagent support: if you (the AI) can dispatch subagents (Task tool, Agent tool), you have native subagent support. This is a self-check, not a Bash check.

Based on results, pre-fill the runtime recommendation. Do not ask the user to choose — recommend and let them override.

Step 4 — **Bootstrap: Context Gathering and Artifact Generation**. Read `bootstrap-prompt.md` for the full question catalog and artifact templates. Run the bootstrap flow inline:

1. **Auto-detect what you can** via Bash before asking questions:
   ```bash
   # Project root
   git rev-parse --show-toplevel 2>/dev/null
   # Git remote
   git remote get-url github 2>/dev/null || git remote get-url origin 2>/dev/null
   # Current branch
   git branch --show-current 2>/dev/null
   # Language detection
   ls package.json Gemfile requirements.txt pyproject.toml go.mod Cargo.toml 2>/dev/null
   ```

2. **Ask only what you can't detect.** Present auto-detected values and let the user confirm or correct. Group questions from `bootstrap-prompt.md` Groups A-D, skipping any already answered.

3. **Generate artifacts** per `bootstrap-prompt.md` Step 2 templates:
   - Write `orchestration-state.env` directly to the project (use the template from `bootstrap-prompt.md`, fill with gathered values)
   - Generate the agent bootstrap context block (show in output)
   - Generate the launch command for the recommended runtime mode
   - Generate the quick reference card

4. **Run validation checklist** automatically (the 7-point checklist from `bootstrap-prompt.md` Step 3). Report pass/fail for each item.

5. **Output** — Show the file layout, the generated state file contents, and the exact next command.

Step 5 — **Operate**. When orchestration is already installed and configured:

1. Validate: scripts present, state file readable, tasks.md exists with pending items.
2. Show status: how many tasks pending, how many complete, current branch.
3. Present launch/resume command for the configured runtime mode.
4. Point to `references/troubleshooting.md` for any issues.

**Outputs** section — keep as-is. The outputs haven't changed, only the mechanism for producing them.

**References** table — keep as-is.

**Platform Notes** — keep as-is.

**Constraints:**
- Target length: 150-200 lines. The old SKILL.md was 99 lines of description. The new one has executable instructions and Bash blocks, so it will be longer.
- The skill must not duplicate `bootstrap-prompt.md` content — it references the question catalog and templates by pointer.
- Bash commands must work in both Claude Code and Codex environments.
- Every Bash block must handle missing tools gracefully (check before using).

**Key context for the implementing agent:**
- Read the current `skills/orchestration/SKILL.md` (99 lines) for the structure to preserve.
- Read `bootstrap-prompt.md` (212 lines) for the question catalog (Groups A-D) and artifact templates (Step 2) that the skill will reference and run inline.
- Read `install.sh` to understand what the skill will invoke.
- Read `references/install-paths.md` for the file layout verification.
- The spec is at `docs/superpowers/specs/2026-04-07-executable-skill.md`.

- [ ] **Step 3: Commit**

```bash
git add skills/orchestration/SKILL.md
git commit -m "skills/orchestration/SKILL.md -- rewrite to execute install and bootstrap inline"
```

---

### Task 2: Update `references/bootstrap-flow.md` to reflect skill-driven flow

**Files:**
- Modify: `skills/orchestration/references/bootstrap-flow.md` (77 lines currently)

The bootstrap-flow.md currently describes a user-driven process. Update it to reflect that the skill executes the flow, with `bootstrap-prompt.md` as a fallback.

- [ ] **Step 1: Read the current file**

Read the entire file.

- [ ] **Step 2: Update bootstrap-flow.md**

Changes needed:

1. **Purpose statement** (line 3) — change from "Maps the bootstrap workflow. The executable prompt lives at `bootstrap-prompt.md`" to: "Maps the bootstrap workflow. The `/orchestration` skill executes this flow automatically. For manual setup without the skill, see `bootstrap-prompt.md` in the repository root."

2. **Decision tree step 5** (line 27-28) — the install path recommendation currently says "vendored copy of orchestration suite." Update to: "The skill runs `install.sh` directly. For manual install without the skill, use `install.sh` from the source repo."

3. **Decision tree step 6** (line 30-34) — context gathering currently says "see `bootstrap-prompt.md` Step 1 for full catalog." Add: "The skill auto-detects project root, git remote, branch, and language before asking. It only prompts for values it cannot detect."

4. **Canonical Reference** section (lines 70-77) — update the pointer text to: "The skill reads `bootstrap-prompt.md` for the full question catalog, artifact templates, and validation checklist. Users without the skill can paste `bootstrap-prompt.md` directly into a session as a fallback."

Do not change the decision tree structure, error exits, or see-also links.

**Constraints:**
- Stay under 80 lines.
- Do not duplicate SKILL.md content — just update the framing from "user does this" to "skill does this, user can do it manually."

- [ ] **Step 3: Commit**

```bash
git add skills/orchestration/references/bootstrap-flow.md
git commit -m "skills/orchestration/references/bootstrap-flow.md:3,27-28,30-34,70-77 -- update to reflect skill-driven flow"
```

---

### Task 3: Add fallback note to `bootstrap-prompt.md`

**Files:**
- Modify: `bootstrap-prompt.md` (212 lines currently)

Add a brief note that the skill runs this automatically. This is a minimal change — the file stays fully functional as a standalone prompt.

- [ ] **Step 1: Read lines 1-10 of the current file**

Read the header comment.

- [ ] **Step 2: Add a fallback note after the header comment**

After line 8 (end of the header block), insert:

```markdown
# NOTE: The /orchestration skill runs this bootstrap flow automatically with
# auto-detection and inline questions. Use this file directly only if the skill
# is unavailable. See skills/orchestration/SKILL.md for the skill-driven flow.
```

Do not change anything else in the file.

- [ ] **Step 3: Commit**

```bash
git add bootstrap-prompt.md
git commit -m "bootstrap-prompt.md:9-11 -- add skill-driven fallback note"
```

---

### Task 4: Update README Getting Started section

**Files:**
- Modify: `README.md` (lines 5-24 currently)

The Getting Started section currently shows `bootstrap-prompt.md` paste as the primary path. Update to show skill invocation as primary, paste as fallback.

- [ ] **Step 1: Read lines 1-30 of the current README**

Read the Getting Started section.

- [ ] **Step 2: Rewrite the Getting Started section**

Replace lines 5-24 with:

**Getting Started** section structure:

1. **Skill invocation (primary)** — If you have the orchestration skill installed in Claude or Codex:
   - `/orchestration` — detects your repo state, installs runtime files if needed, runs bootstrap questions inline, generates all config.
   - `/orchestration:install` — install only, configure later.
   - `/orchestration:init` — configure only (files already installed).

2. **Manual bootstrap (fallback)** — Without the skill, paste `bootstrap-prompt.md` into a Claude or Codex session:
   ```bash
   cat ~/.claude/orchestration/bootstrap-prompt.md
   ```
   Or invoke directly:
   ```bash
   claude -p "$(cat ~/.claude/orchestration/bootstrap-prompt.md)

   My project: [describe your project here]"
   ```

Keep the existing pointer to `bootstrap-prompt.md` for the full template.

**Constraints:**
- The skill invocation must be first, paste-based second.
- Keep the section concise — under 25 lines.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "README.md:5-24 -- skill invocation as primary getting started path"
```

---

## Chunk 2: Verification

### Task 5: Verify all changes

**Files:**
- Read: All files modified in Tasks 1-4

- [ ] **Step 1: Run regression tests**

```bash
bash tests/runtime-regressions.sh
```

Expected: All tests pass.

- [ ] **Step 2: Verify SKILL.md is executable**

Read `skills/orchestration/SKILL.md` and verify:
- Every decision step has concrete Bash commands (not just descriptions).
- The install flow references `install.sh` by path.
- The bootstrap flow references `bootstrap-prompt.md` for question catalog and templates.
- All three entry points (`/orchestration`, `/orchestration:install`, `/orchestration:init`) have clear routing logic.
- Bash commands handle missing tools gracefully (all use `2>/dev/null` or `command -v` checks).

- [ ] **Step 3: Verify bootstrap-prompt.md still works standalone**

Read `bootstrap-prompt.md` and verify:
- The fallback note is present but does not break the prompt flow.
- The rest of the file is unchanged and functional as a paste-and-go prompt.

- [ ] **Step 4: Verify README flow**

Read `README.md` lines 1-30 and verify:
- Skill invocation is the first getting started option.
- Paste-based bootstrap is the second (fallback) option.
- Both paths are clearly distinguished.

- [ ] **Step 5: Trace entry point routing**

For each of the three entry points, trace the execution path through SKILL.md and confirm correct stop/continue behavior:

- `/orchestration` in an empty repo → should hit: detect (NOT_INSTALLED) → install → bootstrap → output. Should NOT stop after install.
- `/orchestration:install` → should hit: install → stop with "Run /orchestration:init to configure." Should NOT run bootstrap.
- `/orchestration:init` with files present → should hit: detect (INSTALLED + NO_STATE) → bootstrap → output. Should NOT run install.
- `/orchestration:init` without files → should error: "Orchestration files not found. Run /orchestration:install first."

- [ ] **Step 6: Cross-reference consistency**

Verify:
- SKILL.md decision step 2 (install) references `install.sh` — confirm `install.sh` exists and is executable.
- SKILL.md decision step 4 references `bootstrap-prompt.md` — confirm the file exists.
- `bootstrap-flow.md` says "skill runs this flow automatically" — confirm SKILL.md actually does.
- README says `/orchestration` as primary path — confirm SKILL.md handles this entry point.

- [ ] **Step 7: Commit any fixes**

If any issues were found in steps 2-5, commit each fix atomically. If no fixes needed, skip.
