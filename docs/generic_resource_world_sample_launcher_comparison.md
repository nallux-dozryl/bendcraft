Generic003 can use the existing public launcher's connection, settings, input,
menu, close/save and reconnect contracts. It is not currently selected by that
launcher. Selecting it would replace the legacy three-model scene with an
actual registry/state/model scene, while retaining a fixed 130-state content
boundary. That is useful native coverage; it is not the functional demand-loader
transition. Confidence is high for the source comparisons and the recorded
native observations below. Visible generic OS-input acceptance remains unknown.

The public [launcher](/Users/chuah/Documents/ChatGPT/bendex/minecraft/tools/play_minecraft.sh:4)
selects actor017 `66bbe97279f8ee268d891ad762d5da40337e1c318d09160e415823e25d4d8bd5`
and renderer008 `3134689e2905e3b3a3ca3790f854996f9da49d8ca33b19677890cc4b10c91d04`.
The built candidate is
[generic003](/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/generic-resource-world-sample-client-native/003/renderer),
SHA-256 `3346be8b07699db488591935b8e9e502c10a8f1aa437c99543dcb97d4f21ce6a`.
These three binary hashes were read and compared with their recorded identities
during this file-only comparison. The launcher's current renderer path and hash
both need an explicit change to select the candidate. Substituting its bytes at
the old renderer path fails the present hash check.

The immutable generic003 build receipt retains its build-time
`native_built_consumer_run_pending` status. Later
[runtime evidence](/Users/chuah/Documents/ChatGPT/bendex/minecraft/evidence/generic_resource_world_sample_client_runtime_001.json)
records actual execution with actor017: two 128 by 128 returned Window CPU images,
32,768 compared pixels and zero differences; all 512 cells per sample including
air; actual slab/stair pixels; 104 typed saved sections, 36 main inventory and
seven equipment slots; durable exact typed save and cold reload; and the named
glass-state-661 refusal. All five owned process groups were absent after cleanup.
The observation recorded zero activation and Spaces notifications. Its image
oracle uses Java baked observations with the explicit current CPU sampling and
seed policy. It does not establish a vanilla frame, AppKit drawable readback,
visible generic controls, or generic full-1080 performance.

The actual built generic sources are under
`build/generic-resource-world-sample-client-native/003/private/source`, and the
legacy sources are under `build/playable-renderer-current/008/source`.
Nineteen inspected common files are byte-identical: `client_presenter`,
`client_controls`, `window_input`, `player_menu_input`, `player_hud`,
`player_inventory_screen`, `inventory_key_consumer`, `player_item_catalog`,
`player_item_definitions`, `player_client_options`, `player_presentation`,
`player_presentation_native`, native `player_presentation.c`,
`remote_resource_presenter`, `resource_client_wire`, `world_resource_frame`,
`world_mesh`, `mesh_render`, and `client_render`. Frozen and working bytes of the
four generic sample/client/frame/presenter modules also match at this comparison.
This is source/API parity, not a fresh native control test.

The actual source maps record 77 legacy project files plus 32 external pins
(109 total), versus 81 generic project files plus 33 external pins (114 total).
There are 76 common project paths, five generic-only paths and one legacy-only
path. The generic-only paths are the catalog entry, generic client, client frame
selection module, generic presenter and static catalog profile; the legacy-only
path is `remote_resource_client.bend`. Of the 76 common paths, 72 map to identical
hashes. Four differ: the two model scanners use explicit bounded exponent
continuations, `generic_resource_world_sample` removes client-only selection into
the new frame module and replaces imported map destructors with local helpers,
and `resource_client_framing` changes a comment from replies to requests and
replies. The extra external pin is the source API's `bend.ts`, not an additional
game effect. These counts describe the source-map inventories, not an executed
function-coverage count. The evidence file lists every differing path and pin.

| Contract | Legacy008 | Generic003 and adoption consequence |
|---|---|---|
| Options and settings | Shared `O.parse`, `Presentation.valid_requested` and `resolve`. Options are `--frames`, `--jar`, `--item-table`, `--width`, `--height`, `--render-scale`, `--hud-scale`, `--display-native`, `--fullscreen` and `--windowed`. Human defaults resolve to 1920 by 1080, 100% rendering, automatic HUD scale, windowed; hidden defaults resolve to 128 by 128 with HUD scale 1. Dimensions are 4..4096, rendering 25..100%, HUD scale 0..4. | The entry uses the same modules and guards. The generic loop measures geometry, replans after resize, uses the same point/backing/HUD coordinate conversion, and refuses inadmissible drawable dimensions. No settings option is removed. Only 128 by 128 at 100% is observed by the new generic runtime receipt. |
| Controls | Shared ordered `Controls.Packet`, focus/capture release handling, `Wire.Input`, `HUD.packet_commands` and game commands. | Generic client uses the same functions. It intercepts inventory keys before game events and preserves physical-key handling. The default AppKit hotbar codes are 18,19,20,21,23,22,26,28,25; offhand 3, inventory 14 and close 53. `open_item_table_bindings` still accepts a caller profile, while the entry uses defaults. Positive visible OS delivery/capture is not established by the generic hidden run. |
| Menu and HUD | Authoritative `MenuInspect`, shared `MenuInput.packet_keys`, `P.send_menu_intents`, menu reply admission and drawing. A refused opened menu keeps its authoritative snapshot and displays `Rejected`. | Generic client reuses these exact APIs and modules. It returns its complete `CW.Assets` owner through HUD/menu preparation before rendering. Shared HUD icons still recognize only stone, dirt and oak planks; loading eleven scene families does not supply general item icons. |
| Renderer close | Close Window, consume `RF.Assets`, `P.release_close`, then exit. | Equivalent operations with `CW.Assets`. `release_close` sends `Wire.Release` and closes the socket; it does not inspect the returned status for an acknowledgement. Neither renderer's close function itself performs `MenuClose` or durable world save. |
| Save after exit | Launcher runs `play_minecraft_close.py` after normal exit, error, startup timeout or handled INT/TERM. | The same wrapper can surround generic003. The helper retries a busy renderer lease within its bounded window, requires a correlated accepted `MenuClose` and empty temporary menu, then uses developer `session.open` and `world.save`, requiring `status=durable`, `published=true`, `durable=true`. Generic runtime001 separately executes exact typed saves via its actor test helper; it does not newly execute the public close helper around a promoted generic launcher. |
| Close/save refusal | The wrapper removes its termination traps, writes an owned permissions-0600 `connection.env`, retains a live actor and exits 2. It explicitly claims no saved result. | Preserve this existing wrapper behavior. A resource/render failure must not bypass close/save or kill an actor whose temporary items could not be returned. Generic glass refusal currently closes its own client resources; a public generic wrapper around that refusal has not been executed. |
| Reconnect | `--reconnect` checks regular file, owner and mode 0600, sources the saved capability/port/world environment, validates the retained actor PID's executable path and reuses that actor. | It can restart generic003 against the retained actor with a fresh Presenter connection and the same lease protocol. The standalone generic entry provides no reconnect orchestration. A promoted generic refusal/reconnect/second-close sequence remains unexecuted. |
| Scene protocol | Version 1, `Frame` command tag 0, `FrameReply` reply tag 1. Carries legacy palette/raw rows/visibility masks. | Version 1, `FrameCatalog` command tag 13, `CatalogFrameReply` reply tag 7. Carries registry identity, tick/revision, eye origin, relative camera and all per-cell raw state/seed/appearance decisions. Hello, epoch/sequence correlation, input/menu/release tags stay unchanged. |

The concrete API join is visible in the
[generic entry](/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/generic-resource-world-sample-client-native/003/private/source/remote_resource_catalog_client.bend:99):
`Presenter.connect(port, token)` returns the real `Presenter.Link`; after
`HelloAck`, the entry requests `FrameCatalog{128,128}`. The actor017
[transport](/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/compiler-producer-diagnostic-017/source/src/remote_resource_transport.bend:74)
already dispatches this to `GenericBackend.frame(..., GS.defaults())` under the
existing lease and sequence admission. Actor017, legacy008 and generic003 have
identical `resource_client_wire.bend` bytes. A catalog request is
`[1,1,epoch,sequence,[13,width,height]]`; its reply is
`[1,7,epoch,sequence,sample]`. This is a new command within the existing protocol,
not a new handshake version.

After the first sample, generic003 loads `Registry.Registry.load(path)` and
`RF.catalog_load(jar, registry, Profile.static_requests(),
Profile.static_policy(), Catalog.defaults())`, then opens
`GenericClient.open_item_table(assets, link, sample, human, frames, settings,
item_table)`. Subsequent frames pass through
`Frame.draw_frame(sample, CW.info(assets))` and `WRF.draw_catalog`. The candidate
checks registry identity, looks up actual state roots, chooses variants/multipart
tickets per cell, and binds the actual loaded model/texture context. The legacy
entry instead calls `RF.load(jar, WRF.resource_palette(palette))` for three fixed
models with zero transform.

The launcher currently force-sets `MC_BLOCK_REGISTRY` to
`generated/reference_blocks.tsv`; it does not preserve a custom existing value.
The generic entry reads `BEND_MINECRAFT_REGISTRY`, falling back to that same
relative file. The exact alignment change for a later adoption is
`export BEND_MINECRAFT_REGISTRY="$MC_BLOCK_REGISTRY"` after the actor registry
assignment. This also prevents an inherited renderer-only registry variable from
selecting a different identity. No environment or launcher change was made here.

The static profile is air plus stone, dirt, oak planks, cobblestone, sand, bricks,
grass block, oak log, oak slab, oak stairs and oak fence: twelve requests,
130 retained states, 33 model-closure resources and twelve sprites. Waterlogged
states describe only their static block component; they do not render the fluid.
Glass, water/lava, chest/block-entity rendering, other families and animations are
not supplied by this entry. Profile loading does not make all states drawable.
The actual glass refusal is `render: StateNotLoaded:catalog:661`; the client closes
and exits 1. Unknown states are not dynamically loaded or ignored.

Default actor sampling is seed 0, no tint overrides and opaque white light
`0xffffffff`, with clamp addressing, back-face culling and cutout threshold 128.
Position tickets use the explicit `GS.mixed` U32 mixer, then modulo the actual
weighted totals; multipart parts use mixed per-part tickets. This is not Java's
position-seeded Random sequence. Legacy rendering also uses default white
appearance, but its three untinted fixed models avoid the tint issue.
Unsnowed grass state 9 selects a model with five tint-index-0 faces, while the
default tint list is empty. `WM.baked_error` therefore predicts a named
`WorldMesh:MissingTint` refusal for that state. **That prediction is source-derived
and unexecuted here.** Snowy grass state 8's selected model has no tint indices.
Supplying arbitrary white tint could admit geometry, but it would not establish
actual biome tint or block/sky lighting. Those decisions need the actual scene
provider; this comparison adds none.

Generic samples retain air on the wire and omit only explicit `Catalog.Invisible`
cells when producing instances. They do not carry the legacy neighbor visibility
masks: each retained cell binds its complete chosen model into one shared
accumulator. Global quad/layer budgets and per-cell binding budgets can still
refuse a scene. Default limits are 4096 blocks, 1024 binding operations, 4096
quads, 64 translucent quads and 256 tints. Shared transport still bounds ASCII
text at 65,536 bytes and the JSON value tree at 16,384 nodes. A structurally valid
4096-cell sample need not fit that wire envelope; the sampler native corpus
already records distinct value/transport refusals. This change is not an
unbounded view, general atlas, AO/lightmap or GPU renderer.

The immediate launcher delta is concrete: select the candidate renderer path and
its exact hash, retain the present jar/item-table/CLI forwarding and all existing
close/save/refusal/reconnect code, align the renderer registry environment, and
use the actual accepted actor018 path/hash when root completes that actor work.
This comparison supplies no actor018 identity or execution claim. Actor017 is
the observed generic pair. Exercising the resulting wrapper's catalog frame,
normal close, refusal retention and reconnect against that accepted actor is the
remaining public-wiring behavior, rather than a requirement to rebuild unchanged
common modules. Hidden returned-image/save evidence and visible desktop/input
acceptance must remain separate claims.

The requested product content transition additionally needs a real client
session retaining the returned Registry owner and the committed family requests.
Generic003 currently discards that owner in `catalog_loaded` and loads the fixed
profile once. Integrating the prepared demand API requires initial requests from
the first sample, `StateNotLoaded`-only family coalescing thereafter, explicit
caller renderer/material admission, and a coherent replacement load of **all**
planned requests. Publish assets/catalog and committed inventory only after the
candidate passes actual sample/frame admission, retaining the previous owner on
refusal. The prepared demand source is explicitly unverified at this checkpoint;
its integration and appearance provider are separate source work. Merely changing
the public binary selector cannot accomplish them.

Only this comparison and its evidence receipt are produced here. No sources,
scripts, frozen artifacts, compiler files or launcher selection were changed;
no compiler/check/export/kernel/native/JVM jobs or desktop interaction ran.
