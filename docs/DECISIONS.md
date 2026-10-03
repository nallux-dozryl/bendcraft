# Decisions

## 2026-10-03: pinned reference and compiler

Use Java 26.3 regardless of later releases. Use Bend 2.0.35 at the verified source revision. The user supplied this pin and broad implementation authority. Reference assets stay outside tracked files.

## 2026-10-03: shared authority

Use one owned simulation for singleplayer and server. Live/API/MCP actions enter the same typed dispatcher; control transport cannot bypass permissions or state validity. Tick scheduling must preserve vanilla timings. Stable numeric block-state IDs are generated from reference reports, with version metadata retained.

## 2026-10-03: evidence is layered

Registry/data coverage, implemented behavior and independently verified behavior are separate. Full completion requires all three plus non-data mechanics and actual interface demonstrations. Foundation tests are never reported as game parity.

## 2026-10-03: concrete owned section map

The ordinary checker accepted a generic Base Map owning Section arrays, but native emission rejected it with `an open Array element type`. Use a concrete Bend 32-bit trie and full-key collision buckets for owned sections. An independent FNV collision (`costarring` / `liquid`, hash 1582148253) verifies key isolation. No native gameplay fallback or compiler change was introduced.

## 2026-10-03: independent proof kernel

The installed Bend compiler lacked Lean on PATH. Fetch Lean 4.34.0's official Apple Silicon archive into ignored project-local .runtime, verify release SHA-256, and build Bend's supplied small kernel. tools/proof_kernel.py reproduces this without changing global toolchain configuration. Root laws pass both checkers; JSON serialization has a recorded termination-translation mismatch, and is not included in these proof claims.

## 2026-10-03: local Git checkpoints

The root repository was unborn; create codex/minecraft-26-3 and stage only owned minecraft paths. User Git signing attempted interactive pinentry and failed in the noninteractive runner. Per-command `git -c commit.gpgsign=false commit` permits local checkpoints without changing the user's global Git configuration. No remote publication.

## 2026-10-03: live transport ownership

One Bend actor owns the world; connection computations exchange typed requests/replies through bounded Base channels. OS-driven accept/read/timer/actor lifetimes use explicit @unsafe recursion and remain outside root laws; gameplay transitions remain pure checked Bend. Local NDJSON transport uses byte-preserving receive/framing so Unicode split across packets cannot corrupt requests. Developer access requires a configured nonempty local token; player functionality is only exposed when actual abilities/observations are implemented.
