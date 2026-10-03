# Decisions

## 2026-10-03: pinned reference and compiler

Use Java 26.3 regardless of later releases. Use Bend 2.0.35 at the verified source revision. The user supplied this pin and broad implementation authority. Reference assets stay outside tracked files.

## 2026-10-03: shared authority

Use one owned simulation for singleplayer and server. Live/API/MCP actions enter the same typed dispatcher; control transport cannot bypass permissions or state validity. Tick scheduling must preserve vanilla timings. Stable numeric block-state IDs are generated from reference reports, with version metadata retained.

## 2026-10-03: evidence is layered

Registry/data coverage, implemented behavior and independently verified behavior are separate. Full completion requires all three plus non-data mechanics and actual interface demonstrations. Foundation tests are never reported as game parity.
