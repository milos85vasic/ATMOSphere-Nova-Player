# CLAUDE.md - ATMOSphere Nova Player

Fork of Nova Video Player, customized for ATMOSphere firmware on Orange Pi 5 Max (RK3588). Provides video playback with media library management, network browsing (SMB/UPnP), and subtitle support.

## Project Overview

- **Package**: `atmosphere.nova.player`
- **Language**: Java/Kotlin + C/C++ (FFmpeg native via avos)
- **Build**: Make + Gradle hybrid (see `Makefile`, `core.mk`)
- **Repo**: `git@github.com:ATMOSphere1234321/ATMOSphere-Nova-Player.git`
- **Parent repo path**: `device/rockchip/atmosphere/nova-player`
- **Upstream**: Nova Video Player (courville/nova)

### Key Directories

| Directory | Purpose |
|-----------|---------|
| `Video/` | Main Android app module |
| `FileCoreLibrary/` | File access abstraction (local, SMB, UPnP) |
| `MediaLib/` | Native media library (FFmpeg-based scanner) |
| `native/` | Native codec/player components (avos) |

### ATMOSphere Integration

- Listed in `VIDEO_PACKAGES` in VideoPlaybackDetector for Tier 2 task-move detection
- Uses FFmpeg avos native player (not Android MediaCodec) for most codecs
- MediaCodec.configure() HW codec rejection is guarded by ExoPlayer stack trace check -- Nova is NOT affected by the IllegalArgumentException throw
- DEFLATED native libs injected into system.img via debugfs_static pipeline

## MANDATORY DEVELOPMENT PRINCIPLES

1. **Solutions MUST NOT be error-prone** -- every fix must be robust, not introduce new failure modes
2. **No blocking operations inside synchronized blocks** -- Thread.sleep(), network calls, or long computations inside `synchronized` WILL cause deadlocks
3. **Always consider concurrent callers** -- multiple media sessions can be active simultaneously
4. **Test the fix, not just the symptom** -- verify the fix works AND does not break anything else

## MANDATORY API KEY & SECRETS CONSTRAINTS

1. **NEVER commit `.env` files** -- they contain API keys and credentials
2. **NEVER add API keys to source code** -- use environment variables or `.env` files only
3. **ALWAYS verify `.gitignore` protects `.env`** before committing

## MANDATORY COMMIT & PUSH CONSTRAINTS

1. **ONLY use the official commit script from the PARENT repo**: `bash scripts/commit_all.sh "message"`
2. **NEVER use `git add`, `git commit`, or `git push` directly** in this submodule
3. The parent script handles staging, committing, and pushing to ALL remotes

## MANDATORY SUBMODULE SYNC CONSTRAINTS

1. **ALWAYS fetch and pull latest from upstream** before pushing our committed changes
2. **Analyze all new features/APIs** from upstream and incorporate them properly
3. **Merge conflicts** must be resolved carefully -- never discard upstream changes blindly

## MANDATORY TAGGING CONSTRAINTS

1. **Tags are NEVER created before flashing and validating** on BOTH ATMOSphere devices
2. **Tags MUST be applied to ALL owned submodules** when tagging the main repo
3. **Tag naming**: `<major>.<minor>.<patch>-dev[-<sub-version>]`

## Project Context

- Part of ATMOSphere Android 15 firmware for Orange Pi 5 Max (RK3588)
- Parent repo at `/run/media/milosvasic/DATA4TB/Projects/Android_15/` handles build, flash, and test
- Build via parent: `bash scripts/build.sh --skip-pull --skip-tests --skip-ota`
- Tests via parent: `bash device/rockchip/rk3588/tests/pre_build_verification.sh`

---

## MANDATORY: ATMOSphere Constitution compliance (appended 2026-04-19 — ATMOSphere 1.1.3-dev-0.0.6)

Every change in this submodule MUST comply with the canonical
Constitution at `docs/guides/ATMOSPHERE_CONSTITUTION.md` in the parent
repo. In summary:

1. **Test coverage for every change** — pre-build gate (CM-MC*),
   post-build gate, on-device test, and a mutation entry in
   `scripts/testing/meta_test_false_positive_proof.sh` proving the
   gate catches regressions.
2. **Device validation before any tag** — both D1 and D2 flashed and
   green on every relevant suite.
3. **Commit + push via `bash scripts/commit_all.sh "…"` from the
   parent repo root.** Submodule source changes are committed in the
   submodule itself first, pushed to every remote of that submodule,
   and then the parent's `commit_all.sh` captures the updated
   pointer.
4. **Tags cascade.** Every version tag on the main repo is mirrored
   on this submodule at its current HEAD, across every remote this
   submodule publishes to. Use
   `scripts/testing/release_tag.sh <tag>` from the parent repo.
5. **Changelog discipline.** `docs/changelogs/<tag>.{md,html,json,txt}`
   on the parent repo documents every release; exported via
   `scripts/testing/export_changelog.sh`.
6. **No false-success results.** Tests that are always-PASS are
   immediately rewritten. Meta-test mutations catch bluff gates.
7. **Flock.** `commit_all.sh` and `push_all.sh` are serialised via
   `.git/.commit_all.lock` / `.git/.push_all.lock`. Never bypass.

Non-compliance is a blocker regardless of context.
