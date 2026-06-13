#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/up.sh
# Convenience wrapper: idempotently start the x86_64 Colima VM with the full
# CPU flag set (--cpu-type max), then `compose up`.
#
#   --cpu-type max → the emulated CPU advertises host-derived flags (POPCNT /
#                    SSE4.2 / x86-64-v2) so an x86 binary doesn't SIGILL at startup.
#   stdin_open     → lives in docker-compose.yml (keeps the interactive console
#                    from hitting EOF → the phantom exit 139).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROFILE="${COLIMA_PROFILE:-x86}"
CPUS="${COLIMA_CPUS:-4}"
MEM="${COLIMA_MEMORY:-8}"
DISK="${COLIMA_DISK:-60}"

command -v colima >/dev/null 2>&1 || {
  echo "✗ colima not installed — run: brew install colima qemu docker docker-compose" >&2
  exit 1
}

# Start the VM only if it isn't already running (idempotent).
if ! colima status -p "$PROFILE" >/dev/null 2>&1; then
  echo "▸ starting Colima x86_64 VM '$PROFILE' (--cpu-type max; first boot may take a few minutes)…"
  colima start -p "$PROFILE" \
    --vm-type qemu --arch x86_64 --cpu-type max \
    --cpu "$CPUS" --memory "$MEM" --disk "$DISK"
fi

# Point the docker CLI at the Colima VM, then bring the stack up.
export DOCKER_CONTEXT="colima-${PROFILE}"
exec docker compose up --build "$@"
