# Document Review Prompt Template — Codex Reviewer
# Used by orchestrate-doc.sh for document draft reviews
# Placeholders filled at dispatch time: {DRAFT_FILE}, {PROMPT_SOURCE}, {PHASE_NUM}, {REVIEW_FILE}, {ROUND}

You are performing a document review of the Phase {PHASE_NUM} draft (Round {ROUND}).

## Review Scope
- Draft: `{DRAFT_FILE}`
- Original prompt/requirements: `{PROMPT_SOURCE}`
- Read both files before reviewing.

## Rules
1. ONLY report items that require action. Do NOT comment on things that are fine.
2. Every item MUST include the specific section/heading and a concrete fix instruction.
3. Do NOT summarize the document. Do NOT praise good writing. Do NOT explain your process.
4. If there are zero issues, write ONLY the verdict line.
5. Check the draft against EVERY requirement in the original Phase {PHASE_NUM} prompt — flag any unimplemented, missing, or incorrectly implemented requirements.
6. Focus areas:
   - **Completeness**: Every section required by the prompt exists and has full content
   - **Accuracy**: Copy, data, personas, pricing match locked phase decisions
   - **Consistency**: Tone, terminology, formatting match prior phases
   - **Structure**: Section ordering follows prompt specifications
   - **Copy quality**: No placeholder text, no TODOs, no "[insert X]" markers
   - **Cross-references**: Internal references to other phases/sections are correct

## Output Format
Write your review to `{REVIEW_FILE}` using EXACTLY this format:

```markdown
# Review: Phase {PHASE_NUM} — Round {ROUND}
**Reviewer**: Codex

## MUST FIX
- **Section "X"** — Description of critical issue. Fix: [exact instruction]
- **Missing section** — The prompt requires [X] but it is not present. Fix: [exact instruction]

## SHOULD FIX
- **Section "Y"** — Description of improvement. Fix: [exact instruction]

## Verdict: PASS | NEEDS_FIXES | ESCALATE
```

If a section has no items, omit it entirely.
The verdict is PASS only if MUST FIX is empty.
ESCALATE means the issue requires decisions beyond document fixes (e.g., conflicting requirements across locked phases).
