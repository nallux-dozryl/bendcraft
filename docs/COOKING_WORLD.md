# Cooking owners joined to the actual world

`cooking_world.State` contains the sole `block_light_world.State` and a general
affine keyed store of actual `furnace_authority.State` / `campfire_authority.State`.
Keys are the complete actual Core dimension and signed-coordinate word values.
There is no second Core world or copied inventory array.

The actor hook is `cooking_world_actor.realtime_tick(~Light, ~properties,
~enabled, lightContext, cookingContext, owner)`. Replace the existing Core/BW
simulation-tick call with this call; do not advance either world separately.
Call at the existing vanilla cadence, consume returned effects exactly once,
and retain the returned owner on errors. Pending cooking retries its original
clock tick; rendering, polling, and a second start cannot advance that tick.
Paused idle worlds do not advance. The explicit `start_tick` seam permits the
existing developer single-step behavior even while paused.

`Context{bindings,campfire,fuel,max_provider_depth}` uses the actual loaded
cooking catalog, initialized item defaults, feature admission, and fuel
providers. `cooking_world_items` reconstructs patches with the physical codec's
checked `CC.patch`, then invokes actual `CI.admit` / `FD.admit`; an envelope,
marker, caller metadata, or item ID alone never grants patched fuel authority.
The contexts must come from the same initialized registry/recipe reload.

Load the authenticated `reference/cooking_world_bindings.tsv` with
`cooking_world_bindings_loader.parse(actualRegistryIdentity, actualStateCount,
callerByteBudget, bytes)`. Its complete pinned classification covers all
35,723 states, with 88 cooking bindings. All in-range omitted states are known
ordinary blocks; outside the registry is unknown. Java's actual block subclass
and `state.setValue(LIT)` receivers establish the bindings. Every non-LIT
property is preserved, including campfire facing and waterlogged state.
The loader verifies the manifest and actual canonical registry identity.

For a loaded world, call `begin(existingBWOwner)` and `load_next(context,owner)`
until `loading` is empty. Each call snapshots one actual Core section and
creates every cooking owner in that section; unknown properties retain the
complete current cursor and owners. This works for the existing saved-section
map and does not impose a section or entity count limit. Run BW bootstrap to
completion before simulation or slot edits. Unloaded sections are refused;
they never become air, dummy cookers, or transient second worlds. The initial
bodies are empty: attach decoded persisted records before starting simulation.

Developer scheduling is `CW.admit`, which calls actual `BW.admit` and retains
Core capability, future-tick, queue and state admission. At `start_tick`, the
whole descriptor/store batch is preflighted, then actual `C.apply/C.finish`
executes due mutations in Core order. Successful edits create, retain or remove
the exact block-entity owner; rejected edits do none of those. Same block
identity retains furnace slots/timers; campfire state changes replace its
ephemeral recipe cache. Replacement emits ordered drop/XP intents from the
current owner, including empty RNG-consuming drop calls. Remove/recreate/remove
in one due batch cannot emit the old items a second time.

`CWEdit.player_edit` calls actual Player CoreEdit for the server-issued
capability, observed `maybuild`, current revision and sequence. Refusal retains
Core, lighting, the complete array owners and entry order. Accepted edits join
lighting and cooking lifecycle and return teardown effects. It creates no
developer capability and bypasses no scheduled-edit contract.

`CWSlots.dispatch` joins actual Core read/residency/state with furnace set/take
and campfire one-item placement. `FurnaceSet{index, CI.Input}` returns the previous
slot and any unplaced input, preserving complete keys/patches; output placement
is refused. `FurnaceTake` returns the actual previous stack. Campfire placement
returns the held input remainder and exact accepted slot. Server capability and
`may_interact` are required; the existing actor/menu owner must validate current
menu, distance, hopper face and the inventory/cursor transaction. These methods
do not secretly claim ownership of the player's separate inventory array.

`finish_tick` checks all actual `FA.tick` / `CA.proposed` transitions, component
authority, world residency and LIT descriptors before committing any cooker.
LIT changes call actual Core application/acceptance and update the same light
owner. Internal stamps use current tick, server peer zero and the next actual
revision. Such writes are simulation-internal, never a user edit endpoint.
The commit invariant is that validated in-range partners remain in the same
loaded section without an interleaved owner; an unexpected Core commit failure
is explicitly reported as an invariant defect. The combined actor hook is a
recoverable two-phase tick, not a claim that an already-applied scheduled batch
can be rolled back by copying affine arrays.

Physical NBT is owned by `cooking_block_entity_codec`: furnace records are
`FA.Persisted`, campfire records are `CA.Record`. Actual `Store.inspect` returns
owned arrays plus immutable full-body views; `FA.persisted(snapshot)` and
`CA.Record{cells}` provide those direct record types. Kind/LIT come from the
actual world binding; caches are ephemeral. Unknown/base-field extras belong
to the physical codec/actor save owner. Durable save adoption and actor menu,
item/XP entity spawning, fragmentation/positions/velocity/RNG, neighbor/block
notifications and recipe award delivery remain named consumer boundaries.
Campfire never awards cooking XP. No existing actor/Core/menu/frame files are
edited by this lane.

`cooking_world_persistence.load(context, owner, position, limits, bytes,
Developer{})` attaches a physical cooking body after section discovery and BW
bootstrap. It reads the actual Core block and requires the registered entry's
exact current state. It calls the committed physical codec's existing-owner
loader, preserving furnace kind, campfire kind/LIT and backing array ownership;
malformed bytes, unsupported components, a missing/unloaded entry, pending tick
or non-developer capability retain the returned whole owner. Success returns
`CB.Details`, including canonical input patches and explicit root/base extras;
the actor must retain that sidecar for its world save framing.
`save(context, owner, position, limits, Developer{})` returns the known physical
cooking body bytes while preserving the same owner. It does not write files or
silently interpret/reinsert base extras. Restoring the world section and body
is a trusted loading operation, not a player slot endpoint.

Verification: `python3 tools/reference_cooking_world.py` observed every installed
26.3 registry state and both LIT partner receivers once. The unchanged cooking
and propagation reference corpora were reused. `python3 tools/test_cooking_world.py`
checks this actual production graph, exports its six checked laws without
changing bodies or types, and checks them with the independent kernel. All six
passed with zero exclusions. They prove failed whole-owner cooking plans,
furnace array retention across property transitions, campfire cache replacement
while retaining items, and exact registered LIT partners. Generic whole-state
permission/cadence equations do not normalize in the current compiler matcher;
these are covered by named native guards, not presented as universal proofs.

The real-Core native receiver passed 17 guards: physical body roundtrip and
malformed-load recovery for each of the five families; player body-import
refusal; pending tick refusal and unsupported-provider retry; two actual
campfire outputs; completed-tick non-replay; observer/output-slot/unloaded
refusals; retained Java furnace ignition fields; and remove/recreate/remove
ownership. The teardown retained exactly three original items and twenty
empty-inclusive drop calls. Final native execution took 11.07 seconds with
83.6 MB maximum RSS; C emission took 12.41 seconds and 2.993 GB sampled peak RSS,
and clang `-O1` took 14.73 seconds and 1.785 GB sampled peak RSS. This is a narrow
boundary receiver, not a gameplay performance benchmark. An initial `-O3`
compile exceeded the chosen 1 GiB test bound; measured `-O1` completed. Two
incorrect fixture expectations were corrected, with the failed observations
retained in `evidence/cooking-world-native-attempt.json`: undefined providers
use the verified vanilla fallback, and unlit campfires produce no cooked drops.
The final fixture-only retry reused the same emitted C and native binary.
