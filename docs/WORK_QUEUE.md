# Dependency queue and integration ownership

This queue supports the full 26.3 objective. A finite scene, renderer, or save
fixture is a verification instrument; none satisfies a gameplay completion gate.

## Current critical path

1. Actual Level collision/move, locomotion, neutral Player.travel, Player.aiStep
   and logical keyboard sampling are checked. Next: actual supporting-block
   cache/context resolution → owned Player tick bridge → authoritative 20 Hz
   held-input controls and typed player saves. The discrete debug controller is
   an integration instrument, not vanilla walking.
2. Registry identity → leased save-owning server → durable publication → actual
   restart/queued-action/MCP tests and the same save-owning state in a client are
   checked. Typed atomic extension saves also pass. Next: player metadata/body/
   support codec and shared runtime composition, then full player/mod state,
   recovery policy and vanilla-format compatibility.
3. Official ZIP/DEFLATE/PNG decoding and bounded texture pixels are checked.
   Typed model parsing/inheritance, the actual first-value resource reader and
   actual-quad mesh rendering are checked. Next: Bend model bake, blockstate
   selection, resource closure loading and world quad production → actual native
   client frames → atlas, world lighting and complete presentation.
4. Exact signed-cell snapshot caching and camera-relative F64 subtraction before
   F32 narrowing and verified far-coordinate views are checked in the shared
   persistent client. Visible OS input/presentation acceptance is mandatory and
   unverified; begin its bounded smoke once held controls are stable, with
   verified isolation or a coordinated foreground session.

Contextual block shapes, player input/pose rules and complete resource semantics
remain required, as do all other full-goal systems. Ready work stays bounded by
declared interfaces; integration evidence determines subsequent work.

## Owners and interfaces

| Owner | Exclusive working files or subsystem | Stable integration interface |
| --- | --- | --- |
| Lead | `player_runtime.bend`, new client/actor/save integration and root contracts | One W body plus metadata, Tables, support and held buttons; Core step before player physics |
| World bridge | New `player_tick_world.bend`, then `support_world.bend` | PW checked rollback and body admission; future actual owned support/context reads |
| Client/render | New `block_resources.bend` | Bounded model/parent/texture closure, explicit static normalized sprite policy, owned Assets |
| Player motion | New `support.bend` and direct Java oracle/tests | Cached support slab/tie/fallback history and exact movement/jump sampling positions |
| Model interpretation | New `blockstate_model.bend` | Actual selector/multipart/weighted semantics and ordered-state instantiation |
| Model bake | New `block_bake.bend` | Typed resolved models and explicit sprites → verified exact CPU quads |
| World mesh | New `world_mesh.bend` | Relative snapshot plus explicit state/bake bindings → bounded mesh Scene |
| Player codec | New `player_codec.bend` | Exact neutral player/body/support/view snapshot with strict bounded NBT |
| Float parsing | Completed, stable source | Separate strict RFC and Java-string binary32 parsers |
| Persistence | Completed core and extension foundations, stable sources | Effectful sole-engine/lease State; closed owned codec and catalog |
| Build reuse | Ordinary cache complete; separate Window cache final handoff | `ensure_native`; opt-in `ensure_platform` CPU-only policy with unchanged transform |

Owners integrate through these interfaces; they do not concurrently modify
another owner's source. Changes to an interface are announced before dependent
work. Finished source and matching evidence are checkpointed with scoped Git
paths. Checks run once on the final changed dependency set, then the relevant
integration suite runs. Repeated broad tests require a new failure, source change,
or unresolved concern.

Limit heavy native emission/full kernel jobs to two concurrently. Eight observed
Bend jobs on 2026-10-04 left about 95 MiB free RAM with substantial compressor
and swap activity; final builds slowed to several minutes. Lower-priority
resource/cache/verdict attempts were deliberately interrupted and remain
unverified, with no correctness inference from cancellation. Keep lightweight
oracle/source preparation parallel, and let an existing third priority build
finish before admitting another. The lead coordinates build slots.

## Measured build work

One concurrent-load observation recorded in `evidence/build-timings.json`:
server C emission 9.740 s, native build 16.749 s, MCP native build 6.102 s.
These are individual observations, not isolated medians. Build reuse therefore
targets actual compilation work. It must fingerprint the complete loaded source
and native-effect graph, installed Base/runtime/compiler, flags and platform;
check cached executable bytes; and preserve every test/proof execution obligation.
It must decline reuse when dependencies are unresolved. No compiler/runtime
modification or unchecked game effect is introduced for caching.

Actual integration cache measurements are recorded separately. The first server
miss took 28.321 s including separate C emission and ordinary native compilation;
an uncontended verified reuse took 3.192 s with zero emission/native compilation.
These single measurements have different load conditions and are not medians or
game benchmarks. A 15.599 s concurrent reuse included waiting for the first
builder's lock and must not be presented as uncontended lookup cost.

The separate Window cache passed 31 checks and 26 hidden native executions,
including exact unchanged transform comparison and CPU-to-GPU mutation refusal.
Its tiny-fixture miss/hit/direct build observations are 9.249/6.768/0.613 s;
lookup probes dominate such a small fixture. Actual persistent-client cache
compilation and unchanged integration are queued after a resource-pressure
cancellation; no full-client cache speed claim is established.

## Evidence limits that affect scheduling

- The movement corpus includes 159 untouched `Entity.move` calls; world travel
  and Player aiStep add actual bounded observations. These admit neutral finite
  worlds and explicitly supplied context; full Player/LocalPlayer ticking,
  supporting-state integration and contextual hazards remain open.
- JSON's independent-kernel termination mismatch remains explicit. Ordinary
  typing or unrelated module laws do not repair it.
- The actor's stop message closes its state/timer. A parked accept operation is
  released by explicit native process exit in the current client instrument.
- The world lease and restart tests are available. They do not establish a
  journal/recovery protocol, hostile-writer exclusion, network-filesystem lock
  behavior or physical power-loss durability.
- CPU/Metal pixel equality on a small finite scene does not establish vanilla
  models, lighting, UI, gameplay, world generation, or game-scale performance.
