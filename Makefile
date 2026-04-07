# Top-level Makefile for orchestration suite development.
# Consumers include makefile-targets.mk in their own Makefile instead.

.PHONY: install dist dist-skill clean test help

TARGET ?= .claude/orchestration

help:
	@echo "Development targets:"
	@echo "  make install TARGET=<dir>  Install runtime files (default: .claude/orchestration)"
	@echo "  make dist                  Build dist/orchestration.tar.gz and dist/orchestration-skill.zip"
	@echo "  make dist-skill            Build dist/orchestration-skill.zip only (Claude upload)"
	@echo "  make test                  Run regression tests"
	@echo "  make clean                 Remove dist/"

install:
	./install.sh $(TARGET)

dist: dist/orchestration.tar.gz dist/orchestration-skill.zip
	@echo "Built:"
	@ls -lh dist/orchestration.tar.gz dist/orchestration-skill.* 2>/dev/null || true

dist/orchestration.tar.gz:
	@mkdir -p dist
	git archive --format=tar.gz --prefix=orchestration/ -o dist/orchestration.tar.gz HEAD

dist/orchestration-skill.zip:
	@mkdir -p dist
	@if command -v zip >/dev/null 2>&1; then \
		cd skills && zip -r ../dist/orchestration-skill.zip orchestration/; \
	else \
		echo "zip not found — building with tar+gzip instead"; \
		cd skills && tar czf ../dist/orchestration-skill.tar.gz orchestration/; \
		echo "Built dist/orchestration-skill.tar.gz (rename to .zip or install zip)"; \
	fi

dist-skill: dist/orchestration-skill.zip
	@echo "Built: dist/orchestration-skill.zip"

test:
	bash tests/runtime-regressions.sh

clean:
	rm -rf dist/
