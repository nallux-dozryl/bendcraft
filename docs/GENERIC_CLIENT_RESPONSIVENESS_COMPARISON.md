# Matched native client drawing comparison

`tools/generic_client_responsiveness_comparison.py` prepares one paused, saved
104-section stone/dirt scene. Every arm restores identical bytes: seed 0,
body `(0.5,-60,0.5)`, pitch 15°, closed menu, complete 36-slot main inventory,
seven equipment slots and explicit creative status. It consumes retained
binaries and the existing actor, unchanged-byte relay, Cocoa observer and
process cleanup owners. It builds no compiler, actor, renderer or observer.

The first cohort is legacy 008 and Generic 010 against Actor 017. The cooking
client's initial cooking inspection is absent from 017. The runner also has
an unexecuted Actor022 cohort preparation path. The current fixed-quality
010/012 cohort exclusively uses the accepted Actor023 binary, SHA
`7fd7ee9269802a6e128716f53bf34030ec592728ef954f9b61bebecac36719d1`.
It persists one actual initialization before all arms; fresh entity factory
entropy must not vary between arms. Its source basis is frozen022 plus only
Backend's duplicate pulse lease-charge repair. The runner refuses mixed
cohorts. Cooking/public acceptance retains priority, and the public launcher
remains the delivery owner's separate acceptance target.

All native launches are hidden. The existing observer requires unchanged
frontmost PID, no client activation and no Spaces notification. The protected
historical Actor 012 PID 47566 remains running and is never registered with
cleanup. Broad 250ms process observations retain its CPU/RSS, all process
CPU/RSS and load averages; foreign compiler/native work refuses quiet
admission or invalidates the comparative claim if it starts during a trial.
Nothing signals or pauses another owner's process.

Each arm first returns two traced 1920×1080 images at 100% scene scale and
automatic 480×270 HUD scale, with two CPU workers and GPU disabled. All
2,073,600 RGB pixels must match literally within and between arms. Actual
sample/menu replies must match the independently authored fixture, including
epoch/sequence, every sample cell, full ItemKeys, equipment/status and carried
state. Full LocalPlayer inspection, paused clock and acknowledged saved owner
bytes must remain unchanged; saved bytes must also match between arms.

Only after those checks does the runner measure eight trace-off frames per
trial. Two-arm order is ABBA. Three-arm order is ABC/BCA/CAB, balancing every
position. The first **two** frames of every trial are predeclared warmup; all
eight values remain in the receipt. No timing is selected after observation.

`client.timing` measures drawing, composition and `Window.frame`. It starts
after sample/resource/menu preparation and excludes that work and trace I/O.
These observations are drawing envelopes for this limited scene; they do not
establish total input latency, FPS, whole-game performance, visible drawable
readback or physical OS-input acceptance. Earlier fresh010700/994ms and
quiet007131.5ms values used different workloads/load and support no speedup
claim.

Reproduction with the bundled Python runtime:

```sh
python3 -B tools/generic_client_responsiveness_comparison.py
python3 -B tools/generic_client_responsiveness_comparison.py --actor-generation 17 --native
python3 -B tools/generic_client_responsiveness_comparison.py --actor-generation 22 --clients 008,010,012
python3 -B tools/generic_client_responsiveness_comparison.py --actor-generation 23 --clients 010,012
```

Each invocation creates a new numbered directory under
`build/generic-client-responsiveness-comparison/`; it never overwrites a prior
attempt. Preparation starts no native process. Native receipts include actual
post-adapter argv, binary/helper/JAR/table pins, UTC order, full frame timings,
image/state checks, background loads and existing cleanup/focus observations.
Attempt006 completed both genuine Actor017 prechecks in the quiet interval.
Each arm retained identical complete 1,712,250-byte saved state, returned two
identical images within its own run, passed actual correlated sample/menu
checks, and changed neither focus nor Spaces. All owned groups were reaped;
the protected012 actor remained present in every load sample. There was no
foreign native/compiler workload during these prechecks.

Cross-arm image equality failed: **331,590 of 2,073,600 pixels (15.991%)**
differ, with inclusive bounds `(0,674)` through `(1919,1079)`. Every differing
pixel is grayscale in both images. The first difference is `(45,674)`, where
008 returns `(127,127,127)` and 010 returns `(143,143,143)`. The runner stopped
before every timed ABBA trial. The traced precheck timing values are retained
as raw observations and provide no admitted speedup or regression comparison.

The frozen callers establish a concrete world texture difference. 008's
`resource_frame.binding` bakes one unrotated `minecraft:block/stone` model.
010's `generic_resource_world_sample_frame.choice_ticket` selects each cell's
actual seed modulo the weighted variant total; `resource_block_catalog`
bakes that selected model and rotation. The pinned26.3 JAR supplies four
stone variants: plain, mirrored, plain Y=180°, and mirrored Y=180°. Its
mirrored cube uses reversed face UV `[16,0,0,16]`. In the actual010 reply,
the 128 stone cells distribute evenly across all four tickets. The origin,
camera words and appearances match; shared bake, mesh, rendering, HUD and
presentation source files are byte-identical. Confidence is high that the
observed texture orientation changes come from world model/UV selection;
there is no supported camera, HUD/status or shading explanation.

The [compact failure receipt](../evidence/generic-client-responsiveness-comparison-006.json)
pins the raw images, full native reports, source files and primary JAR members.
The output difference remains intact. No renderer change, quality masking or
native rerun was made to enable timing. No responsiveness conclusion exists.
Client011's bounded emission failed without a binary; the delivery owner's
substantively repaired client012 is the planned cooking arm. The runner
authenticates the chosen generation's actual completed build receipt and
binary rather than relabeling an earlier artifact.

The current023 preparation is attempt007: no native process was launched.
The [prepared receipt](../evidence/generic-client-responsiveness-comparison-prepared-023.json)
records the exact pins and launch condition separately from observed006.
Both010 and012 use retained `-O3` native builds. Client012 additionally uses
the accepted `-fno-stack-check` invocation; its exact binary SHA is
`3bd945855c7526f713ed1df03ab89e136429fbc36132f6152ef16fc7a491a232`.
Build receipts, native command lines, frozen source maps and manifests are
pinned explicitly. A future observation compares those deployed artifacts;
it does not isolate the cost of the Bend caller change from native build
differences. Every actual image and full-state check remains mandatory.

Only after the delivery owner's public groups reap and its foreground
approval window is pending may the coordinated quiet run add `--native` to
the023 command. The quiet process gate must still pass at launch and through
each arm, with protected012 retained. No new build or008 replay is needed.
This paused drawing comparison does not measure active server20TPS or remedy
the separately observed67-second two-recipe cooking sequence.
