# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial recipe for running x86-only interactive-console server binaries on Apple
  Silicon (arm64) via Colima + Docker Compose.
- Documents two independent, deterministic failure modes hiding behind a single exit 139:
  (1) startup SIGILL/SIGSEGV from a conservative baseline CPU missing POPCNT/SSE4.2,
  fixed with `colima start --cpu-type max`; and (2) teardown fault from an interactive
  console immediately hitting EOF on a closed stdin, fixed with `stdin_open: true` in
  the compose service definition.
- `docker-compose.yml` template with the two load-bearing fields annotated inline.
- `scripts/up.sh` convenience wrapper: idempotently starts the Colima x86_64 VM with
  `--cpu-type max`, then runs `docker compose up --build`.
- Symptom table to help identify which of the two root causes is active in the wild.
- Diagnosis explanation: consistency of exit 139 (deterministic) vs. genuine emulation
  jitter (non-deterministic) as the distinguishing signal.
