# Minecraft 26.3 implementation contract

The persistent goal in chat 01a101ff-32b6-7910-a9af-96488bfb0c2f is authoritative. This project is a full Minecraft Java **26.3** reimplementation, not a voxel demonstration. A milestone never establishes completion. Preserve ../tetris, ../inker, and ../bend user changes. Never stage the entire parent repository.

## Language and ownership

- Baseline compiler: /Users/chuah/.bend/bin/bend 2.0.35; source ../bend at 79df8d9c40722ee9507a1e253f283b51025f9d6c. Read `bend guide`, `bend guide shaders`, and `bend guide effects` before corresponding work.
- Simulation, rendering, UI, mod semantics, resource/data-pack processing, persistence formats and live-operation semantics belong in Bend wherever practical. Host adapters require measured capability gaps and a recorded boundary. Python may orchestrate tests and extract reference data; it must not quietly become the game implementation.
- Do not edit ../bend/bend2/bend.ts. Avoid toolchain edits unless evidence requires one. No axioms, placeholder proofs, or foreign/unsafe dependencies presented as proof.
- Proofs establish only their stated laws. Behavioral parity requires independent Java-reference fixtures or observations.
- Use affine ownership explicitly. Arrays have one owner. Shared simulation runs at vanilla's tick cadence; rendering and API polling cannot redefine simulation time.

## Evidence and fidelity

- Pin 26.3 even when newer releases appear. Authority: explicit user scope, observed pinned-game behavior, versioned official source/data, project contracts, then engineering judgment. Record discrepancies.
- Keep implementation and verification status separate. No registry entry or coverage row counts as implemented. Mark approximations and unknowns explicitly.
- Reference inputs are the installed 26.3 jar/data and official version metadata. Do not read, copy, print or commit account credentials. Assets may be referenced from the local installation; do not check them into Git.
- Protect valid simulation state; player API permissions derive from player abilities/observations, developer permissions are explicit. Interfaces bind loopback by default.
- Save writes require interruption/corruption recovery evidence. Multiplayer requires external multi-client integration tests. MCP tests must use the actual transport.
- Full client acceptance requires recorded visible native end-to-end inspection using computer use or demonstrably equivalent real OS input/presentation automation. Verify actual presentation, keyboard/mouse capture/release, continuous movement/jump/collision, relevant UI/inventory/settings, world edit/save/reload and multiplayer; compare representative pinned-vanilla scenes/modes/settings. Start bounded visible smoke checks when controls are stable, expand alongside features and recheck the packaged client. Hidden pixels and synthetic internal events remain necessary but cannot substitute for this evidence.
- Visible sessions must preserve the user's focus constraint: use an actually available isolated controllable desktop, or coordinate unavoidable foreground testing with the user when ready. Do not start unsolicited foreground sessions or silently waive acceptance. Record build/scenario/settings, observations/artifacts/defects; a few scenes never establish whole parity. Audio and latency require their own appropriate evidence, not screenshot inference.
- Benchmarks compare equivalent workloads/settings/quality on this machine. Do not infer a speedup from a partial game or fewer simulated features.

## Work and verification

- Lead owns root documentation, build orchestration, src/json.bend, src/core.bend, src/live.bend, entry points, root LAWS.bend/PROOF.bend, and integration.
- Subagents receive bounded, disjoint file ownership. Do not edit another agent's files or root contracts without coordination. Read existing files first. Report exact commands and evidence paths.
- Use scoped local commits, no external publication. Generated assets/binaries/caches are ignored. Evidence should contain summaries and reproducible commands, not huge raw dumps.
- Maintain docs/STATUS.md, docs/DECISIONS.md, and coverage inventory so a resumed run can continue without repeating completed work.
- Tests must probe real failure modes and independent expected outcomes. Check Bend code, native builds, relevant CPU/GPU execution, and independent behavioral evidence where applicable.
- Routine automated client launches must avoid focus changes and Spaces switching. Human launches use normal input/focus behavior. Required visible OS-input sessions follow the coordinated/isolated acceptance policy in docs/VISUAL_ACCEPTANCE.md.

The user explicitly authorizes useful parallel subagents, all gpt-6.1-sol with xhigh reasoning, and autonomous engineering decisions within this scope. Never request routine milestone approval.
