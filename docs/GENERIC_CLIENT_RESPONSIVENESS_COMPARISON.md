# Matched native client drawing comparison

`tools/generic_client_responsiveness_comparison.py` prepares one paused, saved
104-section stone/dirt scene. Every arm restores identical bytes: seed 0,
body `(0.5,-60,0.5)`, pitch 15°, closed menu, complete 36-slot main inventory,
seven equipment slots and explicit creative status. It consumes retained
binaries and the existing actor, unchanged-byte relay, Cocoa observer and
process cleanup owners. It builds no compiler, actor, renderer or observer.

The first cohort is legacy 008 and Generic 010 against Actor 017. Generic 011
requires genuine Actor022 because its initial cooking inspection is absent
from 017. A subsequent 008/010/011 cohort therefore uses 022 for **every** arm.
It first saves one real 022 initialization, then restores those exact owner
bytes throughout; fresh entity factory entropy must not vary between arms.
The public launcher remains the delivery owner's separate acceptance target.

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
python3 -B tools/generic_client_responsiveness_comparison.py --actor-generation 22 --clients 008,010,011 --native
```

Each invocation creates a new numbered directory under
`build/generic-client-responsiveness-comparison/`; it never overwrites a prior
attempt. Preparation starts no native process. Native receipts include actual
post-adapter argv, binary/helper/JAR/table pins, UTC order, full frame timings,
image/state checks, background loads and existing cleanup/focus observations.
Native comparison is pending a quiet window after cooking-client delivery
builds and consumers finish. No measured comparative conclusion exists yet.
