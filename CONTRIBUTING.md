# Contributing

Thanks for your interest in improving the Orchestration Protocol Suite.

## Before you start

- Read the project [README](README.md)
- Review the protocol docs in [orchestration-protocol.md](orchestration-protocol.md)
- Keep changes focused and easy to review

## Development guidelines

1. Create a branch for your work
2. Make the smallest change that solves the problem
3. Update docs when behavior or workflows change
4. Preserve executable permissions on shell scripts in `scripts/`
5. Run lightweight verification before opening a PR

## Suggested verification

For documentation-only changes:

```bash
git diff --check
```

For shell script changes:

```bash
bash -n scripts/*.sh
git diff --check
```

## Pull requests

Please include:

- what changed
- why it changed
- how you validated it

Small, well-scoped pull requests are preferred.
