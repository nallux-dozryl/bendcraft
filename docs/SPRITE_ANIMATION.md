# Pinned 26.3 sprite animation CPU contract

Confidence is high for the recorded official CPU observations. The Bend source
and harness pass ordinary checking. Both unchanged native runs pass all 494
prepared cases. The single full production verdict is **inconclusive**: it
reached the 60-second whole-process-group cap without output and was killed/reaped.
This module is a bounded prerequisite for animation integration; existing static
resource admission, sprites, atlas packing, UV mapping and renderers are unchanged.

`src/sprite_animation.bend` interprets animation metadata, admits an owned coherent
mip chain, advances the actual CPU timeline, and copies explicitly requested frame
rectangles. It does not implement an upload, shader interpolator or atlas animator.

## Actual receiver evidence

`tools/reference_sprite_animation_probe.py` executes the untouched installed Java
26.3 classes. `reference/sprite_animation.json` contains 349 metadata cases and
118 CPU image cases, including all 63 PNGs with animation metadata in the pinned
client. Of the CPU constructors, 116 succeed and two raw invalid-size cases fail.
There are 6,736 actual timeline observations and 2,252 actual `NativeImage.copyRect`
receiver calls. Thirty-five copy calls fail because their explicitly requested
frame mip dimensions reach zero; these remain diagnostic observations, not an
admitted atlas mip-level policy. Two fresh Java runs agree. Eight changes to
metadata, timeline, crop hashes, static sentinel, classes/resources/shaders are
rejected, including altered observations whose digest was recomputed.

Reference SHA256:
`b0a1368cf27bd99548f5a98203b195ba97b2d1488550e087e8ded458fec28294`.
Canonical observation SHA256:
`6d4961b02061f288b922f63f2402dc72129e7f5f26f6fa712b9de3508da85470`.
The reference also pins the client/library classpath, thirteen original class
byte arrays, inspected bytecode, the embedded Java receiver harness, each source
PNG/metadata resource, and the four animation shader resource byte arrays.
The shader bytes were inspected and hashed; the shaders were not executed.

The probe constructs normal `NativeImage` owners, decodes the actual animation
and texture CODECs, creates actual `SpriteContents`, invokes `increaseMipLevel`,
and reads its actual animation information. It reflectively invokes the untouched
private `AnimationState` constructor with its real outer contents, real animation
information, a real empty `Int2ObjectOpenHashMap`, and a zero-length real
`GpuBufferSlice[]`. These last two collections are explicit fixture inputs:
constructor, `tick`, and `needsToDraw` do not read GPU entries, as the original
bytecode establishes. Reflection reads fields and calls private frame-offset
methods; it never writes fields or allocates instances without constructors.
No mock GPU, client activation, window or renderer device is installed. Calling
this private CPU receiver path is distinct from successfully executing public
`createAnimationState`, `drawToAtlas`, or an upload; none of those is claimed.
Owners close through the actual Java `SpriteContents.close`/`NativeImage.close`.

## Metadata and frame grid

`Metadata` has optional `frames`, optional `width` and `height`, a default duration,
and an interpolation flag. A frame entry is a nonnegative numeric index or an
object with required nonnegative `index` and optional positive `time`. Width,
height and `frametime` are positive Java integer CODECs; default duration is one.
The interpolation flag defaults false. Unknown members are ignored. Null optional
members behave like missing members; `animation:null` at the document level is
an invalid section. Seventy-two failing direct CODEC cases expose a DataResult
partial-value flag; the source does not expose partial records or Java error text.
The actual resource consumer calls `DataResult.getOrThrow`, so those failures
remain rejected rather than becoming an admitted fallback metadata record.
ResourceJson preserves the observed first-root, BOM and last
duplicate-member behavior. The decoder reuses the existing exact
`TextureMetadata.boolean` contract for `interpolate`; it does not modify or add
fields to TextureMetadata's blur/clamp/strategy/bias record.

JsonOps/Gson integer conversion truncates decimal fractions and retains signed
32-bit results after decimal conversion; it is not a safe-integer schema. The
source reproduces the measured truncate/mod32 behavior, including numeric values
such as `4294967297` becoming one and `-2147483649` becoming 2147483647. Strict
number-token validation precedes conversion, including for a directly forged
`JNumber` token. Decoder work is bounded by the existing JSON input limit,
65,536 frame entries and an explicit decimal-exponent magnitude budget of
100,000. Inputs beyond those engineering limits are excluded from parity claims.
A numeric result must satisfy the requested positive/nonnegative signed domain.

The actual `calculateFrameSize` rules are:

| Metadata | Frame size |
| --- | --- |
| Absent animation section | Whole image width and height |
| Width and height both absent | Square of the smaller image dimension |
| Width only | Explicit width, whole image height |
| Height only | Whole image width, explicit height |
| Both supplied | Both explicit values |

Absent frames enumerate the integer grid in index order. Explicit entries retain
order and duplicates, resolve an absent entry duration to the default, then filter
nonpositive durations and negative/out-of-grid indices. A raw directly constructed
metadata record can therefore have filtered invalid entries even though its
CODEC would reject those entries. An absent frame list with a raw invalid default
duration follows a different Java constructor path; the source admits only a
positive signed default duration. The raw zero/negative-default observations
remain in the reference and test rejection domain.

Zero or one surviving entry disables animation. In that case the actual
`SpriteContents.getUniqueFrames()` returns **`[1]`**, including a sole explicit
index two. This is preserved as an observation. It is not interpreted as frame
one, frame zero, a crop, or a texture upload. For animation, unique indices retain
first occurrence order. `Plan.frames` exposes the active ordered entries when
animation exists; static plans expose an empty active list and the raw sentinel.

The resource loader checks divisibility and closes/rejects nonmultiples. Direct
`SpriteContents` construction can truncate a nondivisible grid, divide by zero,
or fail on negative derived list capacity. These direct constructor observations
are explicitly distinct from the source's loader-style admission.

## Affine API and admission

The public API is:

```text
parse_document(text) / parse_document_with(text,json_limits)
  -> Result<Error,Maybe<Metadata>>
decode_section(value) -> Result<Error,Metadata>
decode_document(value) -> Result<Error,Maybe<Metadata>>
admit(chain:M.Chain,metadata:Maybe<Metadata>,limits:Limits)
  -> Result<&1,&1,Rejected,Contents>
inspect(contents) -> Contents & Result<Error,Observation{plan,selection}>
tick(contents) -> Contents & Result<Error,Selection>
read_frame(contents,explicit_index,mip)
  -> Contents & Result<&2,&1,Error,M.Level>
close_contents(contents) -> Unit
close_rejected(rejected) -> Unit
```

`Rejected` owns the original chain plus a Data error. `Contents` owns the chain,
metadata, admission limits, its timeline, and a recursive optional owned tail.
Admission creates a canonical empty tail. Operations reject a nested tail with
`NestedOwner` and return the entire nested owner; recursive close consumes every
chain. `Plan`, rectangles and `Selection` are immutable observations, not a
separate authoritative timeline. Forged entry, subframe or timeline kind is
revalidated and rejected while retaining the owner.

Default limits are dimension 8192, 16 levels, 4096 grid frames, 65,536 explicit
entries, 4,194,304 allocated cells, and 1,048,576 logical work pixels. Limits
admit dimensions up to 16,384, up to 16 levels, up to 65,536 grid frames/entries,
and capacity/work budgets up to 16,777,216. All supplied levels must have positive
bounded dimensions and complete balanced storage covering the logical rectangle.
Each mip is exactly the original sheet width/height shifted by its level. All
provided extra levels are retained and checked. Every admitted frame dimension
at every supplied mip must remain positive. Frame dimensions must fit the image
and divide it exactly. Capacity counts full power-of-two allocation, including
unused cells; work counts the full logical sheet at every level.

Before copying, `read_frame` requires animation, an explicitly referenced unique
index, an admitted supplied mip, a fitting rectangle, and enough remaining
capacity/work budget for the new output. Static reads return `StaticSelection`.
Unreferenced frame indices and unavailable mips are explicit errors. The source
retains every original padding cell. A cropped output uses minimal power-of-two
capacity, row-major straight ARGB words, and zero padding. Rectangles are:

```text
x = ((index % row_size) * frame_width) >> mip
y = ((index / row_size) * frame_height) >> mip
width  = frame_width >> mip
height = frame_height >> mip
```

A read produces a new owned level; the caller must consume it before allocating
another if it wants the per-read budget to bound simultaneous outputs. The test
harness closes each crop before issuing the next request. The admission/operation
errors retain structural ownership and original cells; no physical address
identity is asserted. `BufferShape` inspection remains in source, but unequal
Array tree native coverage is absent: installed Base's native `ANode` constructor
rejects unequal child classes before the value can reach the API.

The caller owns texture settings and mip generation. The harness decodes the
existing four-field TextureMetadata and uses the already verified Bend mipmap
generator on original base pixels, including its measured strategy resolution
and base preconditioning. Animation neither changes that metadata nor silently
regenerates mips. A later atlas consumer must separately choose a coherent admitted
mip level and handle texture policy.

## Timeline and open GPU boundary

The actual initial animation state is entry zero, subframe zero, dirty true.
A tick increments subframe and clears dirty. At the current duration, it advances
to the next ordered entry modulo the list size, resets subframe to zero, and sets
dirty exactly when the image index changes. Duplicate indices can change entry
and duration while remaining clean. `needsToDraw` is interpolation OR dirty.
Selections expose actual current/next image indices, entry, subframe, duration,
dirty/draw flags, and the rectangles of both indices at every supplied mip.
Static selection exposes frame width/height only.

In 26.3, the public animation path allocates GPU textures/views and mip uniform
buffers. Its draw path quantizes a float progress value and passes it through
vertex indices; the fragment shader mixes current and next sampled sprites.
There is no old CPU interpolation receiver to reproduce here. This module does
not invent a CPU blend, shader progress result, upload, sampler behavior, atlas
copy, mip uniform packet, final frame or GPU/sRGB equivalence. Those consumers
remain separate integration work.

## Reproduction and preparation

```sh
python3 tools/reference_sprite_animation_probe.py extract
python3 tools/reference_sprite_animation_probe.py validate
python3 tools/reference_sprite_animation_probe.py selftest
python3 tools/test_sprite_animation.py --prepare-only
```

The prepared suite has 494 cases: 349 actual CODEC/document cases and 145 CPU or
explicit engineering-policy cases. CPU inputs contain original base ARGB pixels,
metadata, supplied extra levels/padding and explicit queries only. Expected mip
and cropped pixels remain comparison-only actual Java hashes. The reference
uses normal Java image/mipmap/copy receivers; Python never decodes or implements
runtime animation pixels. The prepared manifest seals every transitive Bend file,
installed Base/compiler, runner/probe/reference and semantic/byte input generation.
Missing or stale preparation requires explicit preparation; later phases never
silently regenerate archives or executable inputs.

Heavy phases require the lead's explicit resource slot. Once granted, exact
commands are:

```sh
python3 tools/test_sprite_animation.py --skip-kernel --build-only
python3 tools/test_sprite_animation.py --skip-kernel --reuse-build
python3 tools/test_sprite_animation.py --kernel-only
```

The runner uses a new process group with a 600-second whole-group emission cap,
120-second cap for each of two native comparisons, and a separate 60-second full
production verdict cap. It preserves stdout/stderr and the first failed execution
or comparison, stops before the next run/verdict, and performs no automatic
source/oracle/compiler repair. Original emitted C and actual clang command are
captured read-only when observable; full native header/library closure remains
explicitly uncaptured. Native output is compared before starting the second run.
Current source laws state only a default grid-size and static timeline-kind fact;
ordinary checking does not certify their mathematical validity or full behavior.

## Frozen native handoff

The lead's pregrant audit accepted the exact source, harness, probe, runner,
reference and 494 executable inputs. The single installed build succeeded in
261.115 seconds. Its binary has 3,102,776 bytes, SHA256
`742ff21e7e3be631cb47ffb4729c87a1245dfcb159fedd591ea65eb1d6b54bb2`. Original emitted C is
7,792,750 bytes, SHA256
`5a88afd1decfcf5555f9f8d5e0e436890254bb105e1e8db11e3c7c375b9cf88f`.
The actual clang driver and cc1 invocations are recorded. The driver uses
`-std=c11 -O3`, links `-lpthread -lm`, and was first observed at 239.450 seconds;
that observation is not an exact internal emission/compilation timing boundary.
Full native header/library closure remains uncaptured.

The read-only macOS process sample at approximately 122 seconds reports physical
footprint `10.3G` and peak `10.3G` in its original units, whereas the nearby
`ps` resident-memory observation is about 2.1 GiB. These are different measures;
the smaller resident figure must not be substituted for total footprint. The
original sample and its hash are preserved in the build profile.

The two retained-binary runs completed in 9.823 and
8.969 seconds, and their full outputs agree. There are
349 metadata comparisons, 113 ordinary admitted image cases, 772,106 Java-hash
pixel comparisons including repeated policy fixtures, 6,551 actual-receiver
timeline comparisons, 2,276 successful frame reads, 229 rejected reads,
28 admission/metadata rejections, 21 successful same-owner re-admissions, and
four forged nested-owner/timeline cases. Expected outputs stayed outside native
inputs. Canonical native output SHA256 is
`0c76f01dc9cb89e3df52c2d725cd163eeb412f909cc14cfa45185f6f5f5d8e28`.

`evidence/sprite-animation-native.json` preserves native verification separately
from `evidence/sprite-animation-kernel-failure.json`. The single full source
`--verdict` reached its cap at 60.130 seconds with no stdout/stderr, then
its complete process group was killed and reaped. This is an inconclusive
mathematical verdict, not a failed native comparison or a proof success. No
projection, compiler experiment, source/reference/expectation change or retry
followed. All frozen source, transitive Base/compiler, runner/probe/reference,
prepared inputs and compiled artifact pins were rechecked unchanged. The slot
was explicitly released after all groups had no remaining members.

The original preparation-stage documentation is retained at
`build/sprite-animation/preflight-SPRITE_ANIMATION.md`; this final documentation
change is reporting-only. Initial ready/pregrant manifests remain as original
receipts. Confidence is high within the tested CPU domain. Public GPU animation
construction, sampler/shader/upload execution and presented animation remain open.
