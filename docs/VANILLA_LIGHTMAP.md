# Pinned 26.3 evaluated lightmap

Production is in `src/vanilla_lightmap{,_model,_eval,_sample,_scene}.bend`.
The pinned classes are **LightmapRenderStateExtractor**, **Lightmap** and
**LightmapRenderState**, rather than the earlier-version LightTexture class.
The installed `assets/minecraft/shaders/core/lightmap.fsh` supplies the RGB
calculation. No installed assets, JARs or binaries are committed.

## Integration contract

Import `vanilla_lightmap_model.bend` as M, `vanilla_lightmap.bend` as V,
`vanilla_lightmap_eval.bend` as E and `vanilla_lightmap_sample.bend` as S.

```
V.State{random:R.Source, flicker:F32, dirty:Bool,
        uniforms:M.Uniforms, texture:M.Texture}
V.fresh(actual_renderer_random_source) -> V.State
V.tick(V.State) -> V.State
V.extract(M.Presence, V.State, L.Tables)
    -> V.State & (L.Tables & Result<M.Error,M.Publication>)

M.Publication{needs_update:Bool, texture:M.Texture}
M.Texture = InitialWhite{} | Evaluated{uniforms:M.Uniforms}
E.pixel(M.Uniforms, block:U32, sky:U32) -> Result<M.Error,M.Color>
E.texture_pixel(M.Texture, block:U32, sky:U32) -> Result<M.Error,U32>
S.sample(M.Texture, block_coordinate:U32, sky_coordinate:U32)
    -> Result<M.Error,M.Color>
S.sample_packed(M.Texture, packed:U32) -> Result<M.Error,M.Color>
S.sample_argb(M.Texture, packed:U32) -> Result<M.Error,U32>
```

The extractor owns a **separate client renderer RNG**. Java RandomSource.create
uses a unique host seed and creates LegacyRandomSource. The live constructor
must supply that independently initialized Legacy source; this module does not
invent a seed or borrow a world, entity, sound or gameplay random source. Existing
`R.seeded_legacy(actual_seed)` matches the seeded Java factory. Persist/restore
all five State fields together. A restored extractor must not be replaced by
`fresh`: that would reset its RNG, flicker, dirty flag, previous uniforms and
texture. The State constructor is the explicit typed restoration seam; durable
serialization and live renderer ownership belong to the client owner.

Tick V.tick at the actual client tick cadence. It consumes exactly four float
draws, performs `(flicker + (((a-b)*c)*d)*0.1)*0.9` in F32 order, and marks the
extractor dirty. Render queries never tick or draw random numbers. Clean
extraction ignores the supplied presence/context and retains every owner.
Successful dirty extraction publishes evaluated uniforms and clears dirty.
Absent level **or** player retains prior uniforms and dirty, as Java does;
Lightmap.render still receives needsUpdate=true and re-renders those prior
uniforms. Fresh construction has dirty=false and the actual initial cleared
white 16×16 texture, separately from the default render-state uniforms.
Refused context/evaluation retains the complete original extractor and sine
table owners. The sine table remains the existing hash-verified Mth table.

`M.Presence` is Absent{} or Ready{Inputs}. Required Ready inputs are:

```
M.Inputs{
  environment:M.Environment{
    block_tint:Color, sky_factor:F32, sky_color:Color,
    ambient:Color, night_color:Color},
  player:M.Player{
    tick_count:U32, darkness_blend:F32,
    night_duration:Maybe<U32>, water_vision:F32, conduit:Bool},
  options:M.Options{gamma:F64, darkness_scale:F64, hide_flash:Bool},
  transitions:M.Transitions{
    end_flash:Maybe<Interpolation{previous:F32,current:F32}>,
    boss_fog:Bool, boss:Interpolation},
  partial:F32}
```

The five environment values are mandatory, **actual camera
EnvironmentAttributeProbe values at that same partial tick**: BLOCK_LIGHT_TINT,
SKY_LIGHT_FACTOR, SKY_LIGHT_COLOR, AMBIENT_LIGHT_COLOR and NIGHT_VISION_COLOR.
They encode the current dimension, position, timeline/day, weather and resource
attributes. An old DimensionType.ambientLight scalar is not the 26.3 shader's
ambient RGB. No hardcoded Overworld/Nether/End table, guessed weather blend,
zero flicker, white light or synthetic fixture RGB supplies live authority.
This implementation accepts arbitrary finite attribute colors/factors, rather
than defining a limited list of product dimensions or situations.

Player tick count and night duration retain Java signed int bits. None means no
night-vision effect; -1 is infinite. Duration <=200 uses the actual Mth sine
pulse; longer/infinite duration produces one. Night vision overrides conduit;
otherwise positive water vision with conduit supplies intensity. Darkness uses
the actual Mth cosine and the option scale twice: the player blend is first
scaled, then the computed darkness amplitude is scaled again. Options remain
F64 until Java's narrowing to F32. Hidden flash contributes nothing; End flash
interpolation is divided by three under boss fog. Boss darkening uses Java
interpolation order. These facts must come from their gameplay/client owners.

Uniform ordering mirrors Lightmap's Std140Builder writes: six floats
skyFactor, blockFactor, nightVision, darkness, boss, brightness at byte offsets
0,4,8,12,16,20; vec3 blockTint, skyColor, ambient, nightColor at 32,48,64,80.
The actual Java size calculator returns **92 bytes**; GL's reflected block size
rounds to 96. The final four padding bytes carry no semantic field.

## Scene and vertex consumer

`vanilla_lightmap_scene.bend` exposes:

```
entity(texture,id,block,sky) -> Result<Error,ItemRender.Light>
world(texture,block_state,block,sky) -> Result<Error,Scene.WorldLight>
vertex(texture,packed_coordinates) -> Result<Error,M.Color>
```

Entity rows compute the item color at its actual light probe and the orb color
at min(block+7,15), retaining original levels and ID. World is compatibility
with the existing single-color material path; use an actual face light probe,
not the solid block's own dark center. The module does not certify a caller's
Core stamp, create block/sky samples, mutate authoritative entities, or alter
the shared scene API.

The live owner must join **settled block and sky samples with the same Core
clock/revision/dimension and renderer/environment partial/camera**. Unknown,
unloaded, stale or unfinished authority cannot be substituted by white/15.
Sky's batch sampler can accept every required face/vertex/entity position.
Vanilla model lighting defines the stencil: opaque terrain's own sky level is
normally zero, while an exposed face can sample adjacent air at level15.
Smooth lighting requires the actual model lighter's neighboring vertex stencil,
model emission and AO policy, not six guessed center colors.

Packed sampling preserves all sixteen bits of each coordinate and clamps to
the 0..240 texel-center range, matching sample_lightmap.glsl and RenderSetup's
**LINEAR clamp-to-edge** sampler. It evaluates/quantizes neighboring integer
texels before interpolation. Low four bits from smooth AO coordinates are never
floored away. `vertex` returns normalized RGB F32; retain it and the actual
per-vertex AO/side-shade until renderer interpolation. The current shared
WM.Appearance has one material light color. Installing the actual four vertex
light values is the existing renderer owner's consumer change; it is not
claimed installed here. The 022/cooking011 client delivery does not depend on
this checkpoint.

## Numerical boundary and evidence

The shader computes curved brightness, ambient/night-color component max,
sky contribution, level-dependent warm block tint, boss tint, darkness subtraction,
clamp and its fourth-power gamma function. E.pixel exposes raw F32 and refuses
fully black because the installed shader divides 0/0 there. Actual offscreen
CGL on Apple M3 Pro, OpenGL4.1 Metal90.5, produced NaN float components but
stored opaque black in RGBA8_UNORM. The stored-pixel API explicitly implements
that observed black conversion; nonfinite other shader output is refused before
integer conversion. For finite values it uses CPU nearest RGBA8 quantization.
This is a recorded storage/numerical boundary, not a universal GPU parity claim.

`python3 tools/reference_vanilla_lightmap.py` independently observes real pinned
extractor ticks, private darkness helper, GameRenderer night-vision and boss
helpers, EndFlashState intensity interpolation, actual attribute defaults and
actual UBO size. Remaining uniform assembly arithmetic is an independent
bytecode-derived Java specification, **not** a full initialized client extractor
receiver. It executes the unmodified installed lightmap and sampling shaders
in offscreen RGBA32F/RGBA8 FBOs. No client/window/focus changes or OS presentation
are involved. Reference fixtures establish numerical behavior, not live
environment, dimension, sky or block authority.

`python3 tools/test_vanilla_lightmap.py` checks original source, exports the actual
checked proof roots without rewriting bodies/maps, invokes the independent
kernel, emits original-source C, and compares native results at one and four
threads. Final recorded results:

- 96 actual Java ticks match raw flicker and complete Legacy RNG seed exactly.
- 28 helper preparations match all 18 uniform components bit for bit, including
  duration199/200/201/infinite, signed ticks, option scaling and flash/fog modes.
- 2,048 actual installed shader pixels: all 6,144 stored RGB bytes match exactly
  in these cases; largest raw finite difference is 4.76837158203125e-7.
- 586 black pixels expose the actual float undefined case and stored zero.
- 88 actual installed LINEAR sampler probes retain fractional packed coordinates;
  largest observed CPU/GPU normalized difference is 3.0666589736938477e-5.
  GPU filter precision and possible fused arithmetic remain numerical boundaries.
- Thirteen implementation-connected ownership/dirty/publication/refusal laws
  pass ordinary checking and the independent kernel. The laws do not prove
  floating arithmetic, RNG equivalence, GPU behavior or live publication.
- Native output is identical at one and four threads.

Receipts: `reference/vanilla_lightmap.json`,
`evidence/vanilla-lightmap-{native,proof}.json`. Build caches are ignored.
The scoped implementation is ready for the live client owner to consume;
environment/effect extraction, durable client framing, stamped settled light
publication, per-vertex renderer integration and visible full-client acceptance
retain their stated owners and are not silently claimed complete.
