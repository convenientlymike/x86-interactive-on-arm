<div align="center">

# 🖥️ x86-interactive-on-arm

### Run x86-only **interactive-console** server binaries on Apple Silicon — without the phantom SIGSEGV.

A two-field fix for a bug that *looks* like an emulation limit and isn't: an x86_64
server binary that opens an interactive console quits the instant it goes interactive,
faults on teardown, and reports a consistent **exit 139** — masquerading as a Rosetta/QEMU
segfault. The real causes are a **missing CPU-flag set** and a **closed stdin**. Fix both
and it boots clean.

<br/>

[![Supported OS](https://img.shields.io/badge/host-macOS%20Apple%20Silicon%20(arm64)-8B5CF6?style=flat-square&logo=apple&logoColor=white)](#-supported-os)
&nbsp;
[![Colima](https://img.shields.io/badge/Colima-x86__64%20VM-6366F1?style=flat-square&logo=docker&logoColor=white)](https://github.com/abiosoft/colima)
&nbsp;
[![Docker Compose](https://img.shields.io/badge/Docker-Compose-22D3EE?style=flat-square&logo=docker&logoColor=white)](https://docs.docker.com/compose/)
&nbsp;
[![License: MIT](https://img.shields.io/badge/License-MIT-8B5CF6?style=flat-square)](LICENSE)

</div>

---

## The problem & why it faults

You have an x86-only server binary that runs an **interactive console** (a REPL, a command
prompt, anything that reads stdin). You run it on an Apple Silicon Mac in Docker with
`platform: linux/amd64`. It crashes **every single run with exit 139 (SIGSEGV)** — often
inside a managed runtime (mono / .NET / a JIT) with a message like *"Stack overflow in
unmanaged code."* The obvious diagnosis is *"arm64 emulation just can't run this."*

**That diagnosis is wrong — and the consistency is the tell.** A genuine emulation fault is
*non-deterministic*: it crashes at random instruction boundaries. A fault that lands at
**exit 139 on 6 of 6 runs** isn't the emulator giving out; it's a **deterministic cause**
firing at the same point every boot. There are actually **two** independent deterministic
causes hiding behind that one exit code — a **missing CPU-flag set** at startup and a
**closed stdin** at teardown — and you need to fix **both**.

This repo is the distilled fix: **two configuration fields** (one Colima VM flag, one compose
field), plus the diagnosis so you recognize the failure mode the next time you see it.

> **Worked example:** the binary I first hit this with is an **x86-only interactive
> multiplayer game-server binary** running on a managed (mono/.NET) runtime. But nothing here
> is specific to it — the recipe applies to *any* x86-only interactive-console server binary
> (a database in console mode, a legacy daemon with a REPL, a .NET/mono console host).

---

## ✨ The fix, in two fields

Two independent problems; you need **both** fixes — either alone still fails.

### 1 · `--cpu-type max` on the Colima VM — fixes SIGILL / SIGSEGV at *startup*

A default x86_64 emulation VM advertises a **conservative baseline CPU** to its guest — it
omits flags like **POPCNT / SSE4.2** (the **x86-64-v2** feature level). Many mono/.NET and
modern-C++ x86 binaries emit those instructions unconditionally and **SIGILL (illegal
instruction) → SIGSEGV** the moment they execute one — *before the app even initializes*.
Starting Colima with **`--cpu-type max`** makes the emulated CPU advertise the **full
host-derived flag set**, so those instructions are valid.

### 2 · `stdin_open: true` on the service — fixes exit 139 at *teardown*

An interactive-console binary starts **reading stdin the instant it goes interactive** (right
after the last init step). Under `docker compose up` **without an open stdin**, that read
returns **EOF immediately**. The binary interprets EOF as *"console closed → shut down,"*
prints something like *"Ctrl-C pressed in console,"* and quits — and the **managed runtime
then faults on the forced teardown**, surfacing as **exit 139**. It looks *exactly* like an
emulation segfault. Set **`stdin_open: true`** (the compose equivalent of `docker run -i`)
and the console **blocks on the open pipe** instead of hitting EOF, so the process stays up.

---

## ▶️ Quickstart

> **Prerequisites:** an Apple Silicon Mac, [Homebrew](https://brew.sh).

```bash
# 1 · Install Colima + QEMU (the x86_64 emulation backend) and the docker CLI.
brew install colima qemu docker docker-compose

# 2 · Start a dedicated x86_64 Colima VM with the FULL CPU flag set.
#     --arch x86_64  → the VM (and its containers) are amd64
#     --cpu-type max → advertise host-derived CPU flags (POPCNT / SSE4.2 / x86-64-v2)
#                      so the binary doesn't SIGILL on an unsupported instruction.
colima start -p x86 \
  --vm-type qemu --arch x86_64 --cpu-type max \
  --cpu 4 --memory 8 --disk 60

# 3 · Point the docker CLI at that VM, then bring the stack up.
export DOCKER_CONTEXT=colima-x86
docker compose up --build
```

The two load-bearing lines are **`--cpu-type max`** (step 2) and **`stdin_open: true`** in the
compose file (below).

---

## 🧩 The compose recipe

The minimal service. The load-bearing fields are flagged inline:

```yaml
# docker-compose.yml
services:
  app:
    image: your/x86-only-interactive-server:latest

    # (a) FORCE amd64. The binary is x86_64-only; on Apple Silicon this routes it
    #     through the Colima x86_64 VM's emulation (a no-op on a native x86_64 host).
    platform: linux/amd64

    # (b) KEEP STDIN OPEN. An interactive-console binary reads stdin the moment it
    #     goes interactive. Without an open stdin it hits EOF, "thinks" the console
    #     closed, quits, and the runtime faults on teardown → a phantom exit 139.
    #     This is the `docker run -i` equivalent. (Do NOT also add `tty: true` when
    #     you drive compose from a non-TTY pipe — it errors "the input device is not
    #     a TTY".)
    stdin_open: true

    # ...your ports / volumes / env as normal.
```

> **Note on `--cpu-type max`:** it's a **Colima VM-start flag**, not a compose field — it
> configures the emulated CPU at the VM level (step 2 above), so every container on that VM
> inherits the full flag set. You can't set it per-service in compose.

---

## 🔬 How it works / why it faults without this

Walk the boot and the two failure modes line up exactly:

```
  ┌──────────────────────────────────────────────────────────────────────┐
  │  Apple Silicon (arm64) host                                           │
  │                                                                        │
  │   colima  ──start──▶  QEMU x86_64 VM                                    │
  │                         │   without --cpu-type max:                     │
  │                         │   guest CPU omits POPCNT / SSE4.2             │
  │                         ▼                                               │
  │                     docker (linux/amd64 container)                      │
  │                         │                                               │
  │                         ▼                                               │
  │                     x86-only interactive server binary                  │
  │                         │                                               │
  │   ① startup ───────────▶│  emits POPCNT/SSE4.2 ─▶ SIGILL ─▶ SIGSEGV    │
  │      (no --cpu-type max) │  ✗ crashes before it even initializes        │
  │                         │                                               │
  │   ② goes interactive ──▶│  reads stdin                                  │
  │      (no stdin_open)     │  ─▶ EOF instantly ─▶ "console closed" ─▶     │
  │                         │     quit ─▶ runtime faults on teardown ─▶     │
  │                         │     exit 139 (LOOKS like an emulation segv)   │
  └──────────────────────────────────────────────────────────────────────┘
```

**The diagnosis that cracked it:** the crash was **exit 139 on every single run**. A real
emulation fault is *non-deterministic*; a deterministic exit code means a deterministic
*cause*. Once you separate the two problems (startup SIGILL vs. teardown EOF) and fix each
with its own field, the boot is clean.

### Recognizing it in the wild

| Symptom | Likely cause | Fix |
|---|---|---|
| Crash **immediately at startup**, "illegal instruction" / SIGILL, or SIGSEGV before any app output | VM CPU missing POPCNT / SSE4.2 | `colima start … --cpu-type max` |
| Crashes **right after it prints "console ready" / goes interactive**, consistent **exit 139**, "Ctrl-C / console closed" in the log | interactive console hits EOF on a closed stdin | `stdin_open: true` |
| **Non-deterministic** crashes at varying points, varying exit codes | genuine emulation jitter (residual) | retry; or run on a native x86_64 host for ground truth |

That last row is the honest caveat: **emulation has residual jitter.** Even with both fixes, a
heavy managed runtime under QEMU-TCG can hiccup occasionally. Treat a clean boot on the Mac as
a **reliable local dev/verification check**, and a **native x86_64 host as the ground-truth
backstop** — see [Honesty & limits](#️-honesty--limits).

---

## 🛠️ Helper script (optional)

A convenience wrapper that ensures the VM exists with the right flags, then brings the stack
up — see [`scripts/up.sh`](scripts/up.sh).

```bash
./scripts/up.sh        # idempotent: starts the x86 VM if needed, then `compose up`
```

---

## 🍎 Supported OS

| Host | Status |
|---|---|
| **macOS · Apple Silicon (arm64 — M-series)** | ✅ This is what the recipe is *for*. |
| macOS · Intel (x86_64) | ➖ N/A — runs natively; you don't need any of this. |
| Linux · x86_64 | ➖ N/A — runs natively. (The fields are harmless if left in.) |
| Linux · arm64 | ❓ Untested — the same *principle* applies, but verify the Colima/QEMU path yourself. |
| Windows | ❓ Out of scope — use WSL2 / native virtualization; the `stdin_open` insight still holds. |

The recipe specifically targets **emulating x86_64 on an Apple-Silicon Mac**. The `stdin_open`
half is OS-independent and applies to any interactive-console container.

---

## ⚖️ Honesty & limits

- **This is a recipe + a diagnosis, not a guarantee of zero crashes.** Emulating a heavy
  managed-runtime x86 binary on arm64 has residual non-determinism; the two fixes here
  eliminate the *deterministic* failure modes (startup SIGILL, teardown EOF-139), which in
  practice is what turns "fails every time" into "boots reliably."
- **Native x86_64 is the ground truth.** If you need a hard guarantee, run the binary on a real
  x86_64 host (a CI runner, a cloud box). The Mac path is the fast local loop.
- **The exact resource sizes** (`--cpu 4 --memory 8 --disk 60`) are starting points — tune to
  your binary.

## 📜 License

MIT — see [LICENSE](LICENSE).

<div align="center">
<sub>Built because "it's just emulation" was the wrong answer. The consistent exit code was the clue.</sub>
</div>
