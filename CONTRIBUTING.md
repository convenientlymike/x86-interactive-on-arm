# Contributing

PRs are welcome. A few ground rules:

## Before submitting

1. **Lint the shell script:** `shellcheck scripts/*.sh` — must pass clean.
2. **Validate the compose file:** `docker compose config` — must parse without errors.
3. **Keep the worked example generic.** The compose template and `up.sh` must stay
   applicable to *any* x86-only interactive-console binary, not a specific application.

## Scope

This repo documents one focused technique: running x86-only interactive-console binaries
on Apple Silicon via Colima + Docker Compose. Changes that clarify, improve, or extend the
diagnosis (new symptoms, edge cases, alternative runtimes) are in scope. Unrelated tooling
additions are out of scope — keep it tight.

## Code style

- Shell: POSIX-compatible where possible; `set -euo pipefail` required.
- YAML: 2-space indent; inline comments for every non-obvious field.
