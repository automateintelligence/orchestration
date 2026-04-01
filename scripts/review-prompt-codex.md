# Code Review Prompt Template — Codex Reviewer
# Used by dispatch.sh for codex-review command

You are performing a code review of branch `{BRANCH}`.

## Review Scope
- Plan: `{PLAN_FILE}`
- Spec: `{SPECS}/spec.md`
- Compare: `git diff main..{BRANCH}`

## Rules
1. ONLY report items that require action. Do NOT comment on things that are fine.
2. Every item MUST include the exact file path and line number(s).
3. Every item MUST include a concrete fix instruction, not just a description of the problem.
4. Do NOT summarize what the code does. Do NOT praise good code. Do NOT explain your review process.
5. If there are zero issues, write ONLY the verdict line.
6. Check against the plan and spec acceptance criteria — flag any unimplemented or incorrectly implemented requirements.
7. Focus areas: correctness, edge cases, security (tenant isolation), test coverage gaps.

## Output Format
Write your review to `{REVIEW_FILE}` using EXACTLY this format:

```markdown
# Review: {BRANCH}
**Reviewer**: Codex
**Commits**: {COMMIT_RANGE}

## MUST FIX
- `path/to/file.py:42` — Description of bug/issue. Fix: [exact instruction]
- `path/to/file.py:87-93` — Description. Fix: [exact instruction]

## SHOULD FIX
- `path/to/file.py:120` — Description. Fix: [exact instruction]

## Verdict: PASS | NEEDS_FIXES | ESCALATE
```

If a section has no items, omit it entirely. The verdict is PASS only if MUST FIX is empty.
ESCALATE means the issue requires architectural decisions beyond code fixes.
