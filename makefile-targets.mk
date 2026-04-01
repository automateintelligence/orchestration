# =============================================================================
# Orchestration targets (see orchestration-protocol.md)
# Include this from root Makefile: include path/to/makefile-targets.mk
#
# Required variables (set in your Makefile or environment before including):
#   PLAN   — path to plan.md (e.g., specs/my-feature/plan.md)
#   BRANCH — git branch name (e.g., my-feature-branch)
#   SPECS  — specs directory (e.g., specs/my-feature)
# =============================================================================

DISPATCH := .claude/scripts/dispatch.sh
PLAN ?=
BRANCH ?=
SPECS ?=

.PHONY: orch-status orch-codex-implement orch-codex-review orch-claude-implement orch-claude-review orch-check orch-help orch-validate

orch-validate:
	@if [ -z "$(PLAN)" ]; then echo "Error: PLAN is not set. Set it in your Makefile or pass PLAN=<path>"; exit 1; fi
	@if [ -z "$(BRANCH)" ]; then echo "Error: BRANCH is not set. Set it in your Makefile or pass BRANCH=<name>"; exit 1; fi
	@if [ -z "$(SPECS)" ]; then echo "Error: SPECS is not set. Set it in your Makefile or pass SPECS=<path>"; exit 1; fi

orch-help:
	@echo "Orchestration targets (see orchestration-protocol.md):"
	@echo ""
	@echo "  make orch-status                              Show branch, task progress, reviews"
	@echo "  make orch-codex-implement PLAN=<f> BRANCH=<b> Dispatch Codex to implement"
	@echo "  make orch-codex-review BRANCH=<b>             Dispatch Codex to review"
	@echo "  make orch-claude-implement PLAN=<f> BRANCH=<b> Dispatch Claude Code to implement"
	@echo "  make orch-claude-review BRANCH=<b>            Dispatch Claude Code to review"
	@echo "  make orch-check BRANCH=<b>                    Check latest commits on branch"
	@echo "  make orch-validate                            Verify PLAN, BRANCH, SPECS are set"
	@echo ""
	@echo "Current: PLAN=$(PLAN) BRANCH=$(BRANCH) SPECS=$(SPECS)"
	@echo ""
	@echo "Set these variables in your Makefile before including makefile-targets.mk:"
	@echo "  PLAN   ?= specs/my-feature/plan.md"
	@echo "  BRANCH ?= my-feature-branch"
	@echo "  SPECS  ?= specs/my-feature"

orch-status:
	@$(DISPATCH) status

orch-codex-implement: orch-validate
	$(DISPATCH) codex-implement $(PLAN) $(BRANCH) $(SPECS)

orch-codex-review: orch-validate
	$(DISPATCH) codex-review $(BRANCH) $(PLAN) $(SPECS)

orch-claude-implement: orch-validate
	$(DISPATCH) claude-implement $(PLAN) $(BRANCH) $(SPECS)

orch-claude-review: orch-validate
	$(DISPATCH) claude-review $(BRANCH) $(PLAN) $(SPECS)

orch-check: orch-validate
	@$(DISPATCH) check-branch $(BRANCH)
