# Code Review Prompt Template — Claude Code Reviewer
# Used by dispatch.sh for claude-review command

You are performing a code review of branch `{BRANCH}`.

## Review Scope
- Plan: `{PLAN_FILE}`
- Spec: `{SPECS}/spec.md`
- Run: `git log --oneline -10` and `git diff {COMPARE_RANGE}`

## Rules
1. ONLY report items that require action. Do NOT comment on things that are fine.
2. Every item MUST include the exact file path and line number(s).
3. Every item MUST include a concrete fix instruction, not just a description of the problem.
4. Do NOT summarize what the code does. Do NOT praise good code. Do NOT explain your review process.
5. If there are zero issues, write ONLY the verdict line.
6. Check against the plan and spec acceptance criteria — flag any unimplemented or incorrectly implemented requirements.
7. Focus areas: correctness, edge cases, security (tenant isolation), test coverage gaps.
8. Additionally: suggest better patterns or abstractions where a meaningful improvement exists. Do NOT suggest stylistic preferences.

## Output Format
Write your review to `{REVIEW_FILE}` using EXACTLY this format:

```markdown
# Review: {BRANCH}
**Reviewer**: Claude Code
**Commits**: {COMMIT_RANGE}

## MUST FIX
- `path/to/file.py:42` — Description of bug/issue. Fix: [exact instruction]

## SHOULD FIX
- `path/to/file.py:87-93` — Description. Fix: [exact instruction]

## IMPROVE (better pattern available)
- `path/to/file.py:120-135` — Current approach works but [better pattern]. Refactor: [exact instruction]

## Verdict: PASS | NEEDS_FIXES | ESCALATE
```

If a section has no items, omit it entirely. The verdict is PASS only if MUST FIX is empty.
IMPROVE items do not affect the verdict. They are suggestions for the next iteration.
ESCALATE means the issue requires architectural decisions beyond code fixes.
