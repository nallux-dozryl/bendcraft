# Generic003 public launcher adoption proposal

Generic003 is an actual runnable catalog client for Actor017. Its native socket,
Window-loop, pixel and durable reload checks passed. A public launcher can select
that binary without changing the actor protocol or the close/save helper. An
unconditional replacement of Renderer008 is not yet justified: Generic003 still
loads a fixed resource profile and exits when an unadmitted state enters its
sample. This is a file-only proposal; the public launcher remains Actor017 with
Renderer008. Confidence is high for the recorded native observations and the
source-derived integration below, and unknown for unexecuted public-shell or
visible-input scenarios.

## Exact candidate and observed behavior

| Component | Existing public route | Catalog candidate |
| --- | --- | --- |
| Actor | `build/compiler-producer-diagnostic-017/actor` | Same actual Actor017 |
| Renderer | `build/playable-renderer-current/008/renderer` | `build/generic-resource-world-sample-client-native/003/renderer` |
| Bend entry | `remote_resource_client.bend` | `remote_resource_catalog_client.bend` |
| Scene command/reply | Frame0 / FrameReply1 | FrameCatalog13 / CatalogFrameReply7 |
| Protocol version | 1 | 1 |
| Resource owner | Legacy `RF.Assets` | Retained `CW.Assets` through the real Window loop |
| Scene draw | Legacy frame/palette path | GS.Sample → Frame.draw_frame → WRF.draw_catalog |
| Shutdown | Presenter.release_close, then launcher MenuClose/world.save | Same shared Presenter and existing launcher transaction |

Actor017 SHA256 is
`66bbe97279f8ee268d891ad762d5da40337e1c318d09160e415823e25d4d8bd5`.
Generic003 SHA256 is
`3346be8b07699db488591935b8e9e502c10a8f1aa437c99543dcb97d4f21ce6a`.
Renderer008 remains pinned to
`3134689e2905e3b3a3ca3790f854996f9da49d8ca33b19677890cc4b10c91d04`.
The catalog source map is the immutable
`003/private/source-map.json`, SHA256
`b3f2c4c83ae26860285fe40885bc1771eb85a89ec5f20687e5c21d655d47d63d`.

Commit `318e71a` records two actual hidden 128×128 catalog frames with all 512
raw cells per sample. The current CPU oracle using original Java baked geometry
compared 32,768 pixels with zero differences, including slab and stairs pixels
outside the HUD. A complete 104-section world, 36 main slots, seven equipment
slots, status, generation metadata and clocks survived acknowledged durable save,
cold reload and resave. The actual glass661 scenario returned
`render: StateNotLoaded:catalog:661`. All five owned runtime groups were reaped;
there were zero observed focus or Spaces changes. This establishes neither an
AppKit drawable readback nor visible keyboard/mouse acceptance.

## Settings, controls and menu join

The shell can retain `--gpu off --threads 2`, the pinned 26.3 JAR, generated item
table and forwarded client arguments. Both entries use `player_client_options`
and `player_presentation`: width/height 4..4096, render scale 25..100%, HUD scale 0
(auto)..4, `--frames`, `--display-native`, fullscreen and windowed options.
Human resolved defaults are 1920×1080, 100% scene scale, automatic HUD scale,
windowed, with native-display selection disabled. Actual drawable geometry drives
the human output plan; a requested size is not proof of that drawable size.
The initial logical human window is 960×540. Hidden defaults are 128×128; the
128×128 hidden case initially opens a 512×512 logical window before native
configuration. Generic003 initially requests a 128×128 sample and subsequently
requests the current scene dimensions.

GenericClient has its own real asset-owning loop and uses the shared Presenter's
input command, menu-intent, correlation, trace, close and item-table APIs. It joins
the same physical-key profile, native inventory-key configuration, captured
pointer/status, native events, HUD composition and menu drawing modules as 008.
It sends MenuInspect after each correlated sample before drawing that menu. This
is a source-level controls/menu join; the generic128 test did not execute human
hardware input or all menu actions. Existing HUD item-icon selection still
recognizes only stone, dirt and oak_planks, despite the larger texture owner.

The frozen008 manifest contains77 project and32 external files (109 total);
generic003 contains81 project and33 external files (114 total). There are76
common project paths:72 have identical bytes and four differ. Five project paths
are generic-only and one is legacy-only. All19 explicitly inspected shared
settings, control, menu, presentation and renderer component pins match. The four
changed common paths are the two measured numeric scanners, the GS client-only
graph extraction/local map accessors, and a framing comment. The extra external
file is the source-API `bend.ts`, not an original compiler mutation. The companion
comparison records the exact per-path differences; these inventory counts are
not a runtime or proof verdict.

Actor017's normal CLI profile is `bendex:stone-dirt-superflat`, creative and
running unless explicitly paused. Its pristine generator uses stone/dirt/stone
layers, all present in the static catalog. Loaded worlds and later edits remain
authoritative, so those defaults do not establish that every future sampled
state will be admitted.

## Concrete shell delta for root selection

For a deliberate catalog selection using the **current017 actor**, the minimal
change to `tools/play_minecraft.sh` is:

```diff
-renderer="$root/build/playable-renderer-current/008/renderer"
+renderer="$root/build/generic-resource-world-sample-client-native/003/renderer"
-  echo "Current actor017, renderer008 and bundled Python are required." >&2; exit 1
+  echo "Current actor017, catalog renderer003 and bundled Python are required." >&2; exit 1
-for path,expected in zip(sys.argv[1:],['66bbe97279f8ee268d891ad762d5da40337e1c318d09160e415823e25d4d8bd5','3134689e2905e3b3a3ca3790f854996f9da49d8ca33b19677890cc4b10c91d04']):
+for path,expected in zip(sys.argv[1:],['66bbe97279f8ee268d891ad762d5da40337e1c318d09160e415823e25d4d8bd5','3346be8b07699db488591935b8e9e502c10a8f1aa437c99543dcb97d4f21ce6a']):
 export MC_BLOCK_REGISTRY="$root/generated/reference_blocks.tsv"
+export BEND_MINECRAFT_REGISTRY="$MC_BLOCK_REGISTRY"
-logs=$(/usr/bin/mktemp -d "$root/build/playable-renderer-current/008/current-launch.XXXXXX")
+logs=$(/usr/bin/mktemp -d "$root/build/generic-resource-world-sample-client-native/003/current-launch.XXXXXX")
```

This proposed delta has not been applied. The registry export matters because
the actor reads MC_BLOCK_REGISTRY while the generic entry reads
BEND_MINECRAFT_REGISTRY. The current launcher force-sets the former to the
generated registry; explicit alignment prevents an inherited second path from
giving the client a different registry owner. No new client CLI flag, protocol
version, save codec or arbitrary executable-path selector is needed.

The shell's existing traps, readiness bound and renderer status handling can
remain. On a renderer error it still attempts MenuClose and durable world.save;
on close/save refusal it retains the actor, writes a 0600 reconnect file and exits 2
without claiming a saved result. Reconnect verifies the actor PID belongs to the
exact actor binary. `play_minecraft_close.py` uses Hello, MenuClose10/Reply6 and
the public save operation, without requesting either scene format. Source
compatibility is high-confidence; that exact shell transaction, refusal and
reconnect route has **not** yet been executed with Generic003. A future018 actor
needs its own completed artifact identity and coherent acceptance; the current
017 observations do not certify 018.

## Product boundary and useful next selection

The normal catalog entry loads air plus 129 states from eleven families, 33
models and 12 sprites. It discards the returned Registry owner after
loading CW.Assets, so the real loop cannot yet use the new Demand APIs. The
profile includes unsnowed grass, but Actor017's default policy supplies empty
tints and white light: the actual WorldMesh code predicts MissingTint for a
sampled grass quad with tint index 0. That grass outcome is a source inference,
not a newly executed native refusal. State identity is arbitrary in the wire;
admission and rendering remain bounded by the loaded catalog.

The generic producer emits complete model quads for every admitted non-invisible
sample cell rather than using the legacy neighbor visibility mask. Existing
WorldMesh bounds include 4096 source quads and 64 translucent quads. It uses the
explicit deterministic seed mixer rather than Java position Random, and has no
full biome-tint, lighting, AO/lightmap/atlas or special-renderer parity. These are
material adoption limits, not problems solved by changing the shell binary path.

Root can choose a bounded public catalog route now, clearly presenting its
admission failures, while keeping 008 as the existing default. A general default
should retain the Registry with CW.Assets and integrate functional demand or
complete resource loading, plus the actual tint/material requirements. This
requires a changed consumer generation; retrying unchanged 003 cannot extend it.

The next public-shell acceptance should reuse the existing launcher, close/save
helper and process observer: a hidden bounded normal-profile run at the intended
output dimensions; close/save after a catalog refusal; and a temporary-menu
close refusal followed by reconnect to the retained actor. These are concrete
unexecuted scenarios, not a requirement to repeat completed proofs or rebuild
unchanged artifacts. Visible hardware input remains a separate coordinated or
isolated desktop acceptance. This proposal starts none of those processes and
does not change the current launcher or saved world.

Related compact records: `generic_resource_world_sample_launcher_comparison.md`,
`generic_resource_world_sample_client_native_003.json`,
`generic_resource_world_sample_client_runtime_001.json` and
`generic_resource_world_sample_launcher_adoption.json`.
