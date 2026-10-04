# Remote LocalPlayer resource client

The 2026-10-04 generation adds a saved nine-slot hotbar, stack counts,
crosshair, correlated inventory queries and reserved-player break/place actions.
Its sealed human path uses a 320×180 logical image projected in Bend to the
960×540 native drawable; hidden verification retains 128×128. These are
prototype dimensions, not a measured hardware ceiling. The user has requested
configurable high-resolution output, internal render scale and HUD sizing for
the next revision. Enlarging the current image does not add rendered detail.
The pure HUD and its focused source harness check successfully; the presenter
and client entry report only their 55 and 65 declared native-dependent
definitions. New native pixel and visible-input acceptance remain pending.
The results below describe the separately retained earlier generation.

The production backend now accepts the explicit bounded
`bendex:stone-dirt-superflat` profile without the verification flag. Fresh
creative or survival inventory and terrain are initialized through the saved
session; loaded records retain their saved abilities and inventory. The
production default runs the actual actor timer. `--paused` supports bounded
inspection, while `--verification-fixture` preserves the earlier paused
fixture/catalog/save contract. This custom terrain and three-item inventory
do not establish general Minecraft world or item support.

This is a changed integration consumer, prepared after three monolithic resource-client emissions failed to produce a native artifact within their bounds. The compiler bottleneck remains unknown. Separating the saved actor from the renderer removes their concrete owner/callback join; native compilation and runtime benefit are not yet measured.

`remote_resource_client.bend` connects to the private loopback endpoint of the actual saved LocalPlayer backend. The backend owns the only world, complete supported LocalPlayer record, persistence lease, public 18-operation TCP/MCP catalog and 50 ms timer. It returns one immutable `WorldVisibility.Sample` from one actor operation. The renderer owns one socket, actual `ResourceFrame.Assets` and a native Window. It does not step physics, load/save a world, or hold an actor handle.

The client loads the pinned JAR through unchanged `ResourceFrame.load`, using the first atomic sample's actual dynamic palette. This closes the archive after resolving actual model parents, decoding original PNGs and baking explicit zero-transform stone/dirt/oak-planks. Each frame uses unchanged `WorldResourceFrame.draw` → visibility/mesh production → BVH CPU rendering. Missing/unsupported resources, mismatched palettes and invalid samples remain errors; no substitute pixels or general blockstate selection are supplied.

Private protocol requests are `Hello(capability)` and `Call(epoch,sequence,Frame(width,height)|Input(packet)|Release)`. The actor controls one renderer lease and strict nonwrapping sequence; queries never define time. The client requires exact reply kind, epoch and sequence, and rejects extra completed or partial records. A single five-second read/response deadline survives partial chunks, with checks immediately after `TCP.poll` and after reply decoding. `TCP.connect` and `TCP.send` remain unbounded Base effects; this deadline does not bound a complete exchange, terminal Release or process exit. Normal teardown closes the Window and image owners before best-effort network release. Backend epoch-qualified EOF/expiry cleanup is the final controls-release authority. The host supervisor separately caps and cleans up whole process groups.

Admitted backend calls renew a lease of 100 actual 50 ms actor pulses, including paused pulses. Initial resource loading or a slow draw may exhaust that lease before the next call, which then fails closed; startup renewal is not implemented. An immediate new Hello can observe `RendererLeaseBusy` while the previous socket's actor cleanup is pending. The verifier records every such expected observation under one fixed acquisition deadline; other faults stop the run.

The wire is canonical ASCII JSON, with Unicode string data escaped by the shared codec. The timed Base `TCP.poll` decodes a chunk to String. Its pinned native UTF-8 decoder substitutes U+FFFD for malformed/overlong sequences and produces non-ASCII scalars for every admitted multi-byte sequence; the presenter rejects all raw non-ASCII decoded scalars before passing ASCII bytes to the existing strict Framing parser. This is an explicit ASCII transport admission, not arbitrary raw UTF-8 support. Input values retain raw F32 words and actual event/action order.

The consumer reuses `ClientPresenter.events`, `window_policy` and `lost_actions`, and observes native focus/capture before and after every OS packet. It reverses the same backwards accumulator once, then sends the entire physical batch as one acknowledged actor operation. Escape, close, focus/capture loss and policy refusal carry releases. Automated launch must use the guarded native platform build and `BEND_MINECRAFT_LAUNCH_MODE=hidden`; no focused input or foreground launch is authorized by the preparation.

Set `MC_RENDER_PORT` and `MC_RENDER_TOKEN` from the separately started backend. Client options are `--frames <U32>` and `--jar <path>`; the renderer has no world fixture or save option. Human launch follows normal capture policy; automated checks use hidden mode. Optional `BEND_MINECRAFT_FRAME_DIR` must name an existing directory. It emits raw sample observations and writes PPM/CRC observations from the **Image returned by `Window.frame`**. Expected Java quads, reference state-pair visibility and Pillow pixels remain outside executable inputs. Returned CPU images do not establish drawable or vanilla final-frame equivalence.

Scope remains the measured air/full-cube visibility domain, explicit three model choices, normalized static sprites, solid layers, white tint/light and existing integer directional shading. Atlas stitching, animation, mipmaps, biome tint, AO, world lighting, GPU blending/sRGB, UI/inventory, full gameplay and visible OS acceptance are not established here. The LocalPlayer camera originates from the exact cached Pose eye in the atomic backend query; no standing-eye constant is inferred by the renderer.

Ordinary source checks admit the declared IO and lifetime boundaries. Final paired preparation includes six separately prepared paused LocalPlayer records. Their original all-sky scene candidate is archived; an explicit three-block relocation places actual dirt/planks in those records' views without altering the retained Java records, geometry or PNG observations. The tests compare exact atomic samples and pixels, public live edits, complete LocalPlayer/Core save/reload bytes, eight actual Java phases, timer cadence and necessary protocol failures. Malformed socket peers supply handshake bytes only, never a world Sample, texture, mesh or image. The exact late-poll race and stale-disconnect branch remain source reviewed unless separately observed; hidden pixels do not establish physical input or drawable equivalence.

Prepare and audit with the bundled Python interpreter and `tools/test_remote_resource_client.py --prepare` / `--audit`. A grant permits exactly one `--backend-build-only --lead-slot-granted` and one separately granted `--build-only --lead-slot-granted`, each with a 600-second whole-group cap, preopened streams, immutable attempt receipts and no source-drift retry. Backend compilation uses the standard native route; rendering uses the guarded hidden Window route. `--native --lead-slot-granted --backend-build-report <report>` reuses the exact artifacts under a 120-second outer cap and records all owned groups. An external unchanged backend artifact may also be supplied. No native artifact, paired run, native pixel result or proof result exists for this entry yet. Earlier source, failed generations and six plain-Player reference views remain frozen.
