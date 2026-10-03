# Pure typed block-model data and resolution

`src/block_model.bend` interprets model JSON values and resolves an explicitly
supplied model library. It contains no file reads, host calls, unsafe definitions,
texture loading, rotation matrix construction, or geometry baking. The module is
a data prerequisite for baking; it does not generate render quads.

The behavioral authority is the installed, hash-pinned Java 26.3 client. The
existing `reference/model_semantics.json` records executed production model
deserializers and parent/texture resolution. `tools/test_block_model.py` also
executes the same pinned Java harness against a small set of field and graph
boundaries in its own ignored `build/block-model-edges` directory. Python drives
those tests and projects their observations; the runtime interpretation and
resolution are Bend code.

## Public entry points

```bend
import ./block_model.bend as M

M.decode(value: J.Value) -> Result<&2, &2, M.Error, M.Model>
M.decode_library(value: J.Value, missing: M.Model)
  -> Result<&2, &2, M.Error, M.Library>
M.empty_model() -> M.Model
M.resolve(library: M.Library, id: String)
  -> Result<&2, &2, M.Error, M.Resolved>
M.resolve_graph(library: M.Library, roots: List<&2, String>)
  -> Result<&2, &2, M.Error, M.Graph>
M.material(value: M.Resolved, slot: String) -> Maybe<&2, M.Material>
M.material_status(value: M.Resolved, slot: String) -> M.MaterialStatus
```

`Error{code, path}` identifies the rejected field or model. Codes and paths are
this implementation's diagnostics; the tests compare Java acceptance/rejection,
not Java exception message spelling. A library is a map of decoded models plus a
caller-supplied missing-model value. The fallback must have no parent. The test
fallback is an empty model, matching the controlled Java fixture context; a
caller can supply its actual missing-model geometry and textures instead.

`decode_library` accepts an object from model identifiers to model JSON objects.
It normalizes identifiers and rejects collisions after normalization. An
already typed `Library{models, missing}` can be supplied directly.

## Geometry and material representation

| Type | Fields and interpretation |
| --- | --- |
| `Vec3` | `x,y,z:F32`, preserving the resulting binary32 bits |
| `UV` | `u0,v0,u1,v1:F32`, source UV rectangle; reversed bounds are preserved |
| `Face` | direction; optional cull direction and UV rectangle; quarter rotation in degrees; texture string; signed tint index as its two's-complement `U32` bits |
| `Element` | model-unit `from` and `to`; optional rotation; face list; emission; optional shade direction override |
| `Rotation` | origin divided by 16; `SingleAxis{axis,angle}` or `Euler{angles}`; rescale boolean |
| `Transform` | rotation in degrees; translation divided by 16 and clamped to `[-5,5]`; scale clamped to `[-4,4]` |
| `Material` | normalized sprite identifier and `force_translucent:Bool` |
| `Texture` | `Sprite{material}` or `Alias{slot}` |

Element endpoints are checked after float conversion against `[-16,32]`.
Each element has one to six faces, identified by exact lowercase direction
names. UV arrays contain exactly four values; vectors contain exactly three.
Face rotation is converted through the signed integer semantics and normalized
modulo 360, then must be a multiple of 90. Tint defaults to `0xffffffff` (-1),
emission to zero, and emission is checked in `[0,15]` after conversion. Unknown
`cullface` strings yield no culling; uppercase cull names also yield no culling.
An unknown face name or shade direction rejects the model. The old `shade`
member is ignored by the observed current deserializer; it is not a face-shading
factor in this data representation.

Rotation origin is required. Presence of either `axis` or `angle` selects the
single-axis branch, which requires both fields, even if Euler fields are also
present. Axis names are lowercased before validation. Otherwise any of `x,y,z`
selects Euler data and omitted components default to zero. Arbitrary numeric
angles and rescale flags are preserved. This module neither approximates such
rotations nor applies trigonometric transforms.

## Defaults, coercions, and text boundary

Absent `elements` is `None`; explicit `elements:[]` is `Some{Nil{}}`. This
distinction survives resolution as `geometry_present` and determines whether
parent geometry is inherited. Absent ambient occlusion and GUI light remain
optional in `Model`; final defaults are true and side respectively. Explicit
null does not act as absence for these decoded fields.

Ordinary model string fields use the observed primitive conversion: strings
are retained, numeric lexemes become strings, and booleans become `true` or
`false`; null and compound values reject. Ambient occlusion and rescale accept
primitive booleans, strings compared case-insensitively with `true`, and numbers
which convert to false. These permissive conversions do not apply to the typed
texture-object codec: its sprite is a JSON string and its optional
`force_translucent` is a JSON boolean. A plain texture string beginning with `#`
is an alias; other strings are sprite identifiers. Unknown object members are
ignored where the executed production fixtures observe that behavior.

Float and integer fields require JSON numeric primitives. Numeric strings,
including `"0.1"`, `"+1"`, Java hex float forms, `"NaN"`, and `"Infinity"`, are
rejected by the production model helper. Although `FloatParse.parse_java_f32`
can interpret those Java text forms, the model deserializer does not admit them
at this boundary. Numeric floats use exact `FloatParse.parse_f32`; tests compare
raw hexadecimal binary32 bits, including negative zero and rounded decimals.
Decimal overflow can produce infinity where the subsequent field validation
allows it; an infinite endpoint fails the endpoint range check.

Numeric integer conversion truncates the exact decimal toward zero and retains
the low 32 bits, matching the measured Gson `getAsInt` behavior. It does not
round through a float. For example, `4294967311` becomes 15,
`9007199254740993` becomes 1, and `-0.9` becomes 0. The resulting signed bits are
then interpreted by the relevant face rotation, tint, or emission rule.

Identifiers default an absent/empty namespace to `minecraft` and validate the
observed namespace/path character sets. This is identifier interpretation;
it does not normalize or extract filesystem paths. A parent empty string means
no parent. Faces retain their source list order; object/map projections in the
test harness compare names and values independently of that order. This is a
representation difference: the Java model stores faces in a `Direction`
`EnumMap`. A future baker must visit down, up, north, south, west, east within
each element to reproduce Java face/quad iteration. This module does not claim
baked ordering from its face-list order.

The decoder accepts `J.Value`, not text. The native test harness uses
`J.parse_with(text, J.Limits{4194304n,512})` for ordinary unique-member legal
JSON. Two existing reference cases involving duplicate or malformed textual
JSON are excluded from this AST-boundary comparison. Production resource-reader
strictness, first-value completion, duplicate replacement, and lone UTF16 unit
handling belong to the separate resource text parser. This module does not
claim that strict live `J.parse` has the production resource reader's syntax
profile. A resource parser's resulting values can be supplied to `decode`.

## Parent and texture resolution

`resolve` follows the supplied library, checks parent cycles, and finds the
nearest present geometry, ambient-occlusion, and GUI-light value. Child texture
definitions override parent slots before aliases are resolved, so a parent's
alias observes a child's replacement of its target. Alias cycles and missing
slots yield `None` from `material`; `material_status` distinguishes
`TextureCycle` from `MissingTexture`. A single optional leading `#` is removed
from a requested slot name. No sprite loading is performed.

Display inheritance is per context, with nine keys:
`thirdperson_righthand`, `thirdperson_lefthand`, `firstperson_righthand`,
`firstperson_lefthand`, `head`, `gui`, `ground`, `fixed`, and `on_shelf`.
`Display.transforms` contains only actual transforms. A missing context is the
Java `NO_TRANSFORM` sentinel; an explicitly parsed `{}` is an identity transform
which stops inheritance for that context. Missing left-hand transforms use an
existing right-hand transform from the same model. If both are absent they stay
absent and can inherit. Thus `display:{}` inherits parent contexts, while
`display:{"gui":{}}` overrides only GUI with identity.

Missing parents are replaced by the supplied fallback and reported with
`MissingParent`; missing roots report `MissingModel`. A missing root has debug
identity `minecraft:builtin/missing`, while a graph keeps its requested map key,
matching the observed Java result. `resolve_graph` starts with the canonical
missing entry and the requested roots, follows their parent closure, and returns
successfully resolved models plus rejected cycle/dependent errors. It does not
insert failed cycle members or their dependents into the resolved map.

## Bounds and verification

Float tokens inherit the exact parser's limits: 4096 codepoints and 1024 mantissa
digits. Integer tokens use the same validated JSON-number grammar and budgets;
their exponent magnitude additionally has an explicit maximum of 100000 and
reports `UnsupportedIntegerExponent` above it. This is a supported-input bound,
not a claim of unbounded Gson numeric conversion parity. Library resolution
supports at most 65535 model entries and 65535 roots. Parent, graph, and texture
walks have explicit fuel derived from finite input sizes and seen maps, so cycles
terminate with diagnostics. The decoder's input-text limit is controlled by its
caller; it does not introduce a second global text parser or limit.

Run:

```sh
python3 tools/test_block_model.py
```

The runner records source/transitive/binary/reference hashes and compares:

- 105 of the 107 original parse cases at the `J.Value` boundary;
- all 27 parsed installed models;
- all seven original parent/texture graphs;
- all 27 resolved installed models, plus the controlled missing-model entry;
- 52 newly executed Java field-boundary cases and two additional graphs.

The recorded final comparison used `--skip-build` with the executable freshly
built by the preceding default invocation. That invocation completed its native
build and all comparisons, then exceeded the source verdict's 60-second budget
before report writing. The runner now records such timeouts and finishes its
report; a fresh default invocation performs the native build again. Build time
from the interrupted report is not reconstructed or presented as a measurement.

All compared model vectors, UVs, display components, and rotation inputs use raw
F32 bit strings. Derived rotation matrices and baked vertices are deliberately
excluded because this module does not implement them. The separate mesh renderer
currently receives geometry baked by the Java reference; it does not yet bake
this model representation.

Ordinary Bend source and test checking includes three finite data examples.
Independent-kernel status is recorded separately in
`evidence/block-model-native.json`. Full source/test verdict commands have a
60-second budget and a timeout is recorded as a timeout, without attributing its
cause to a particular definition. The transitive JSON serializer also has an
existing independent-kernel `encode_go` mismatch. Neither a timed-out command
nor the known dependency permits an independent-kernel success claim for this
module. There is no universal model decoder/resolver correctness theorem and no
bake theorem. Native observations and ordinary checking remain distinct from
independent mathematical validation.
