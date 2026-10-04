# NormalNoise density sampling

`src/worldgen_density_noise.bend` implements the pinned Java 26.3
`NormalNoise.Parameters` constructor and scalar `NoiseStack.Perlin.get` route.
It retains the registry identity, complete typed parameters and immutable seed
root with every actual owned Perlin permutation. This supplies a density graph
dependency; complete normal chunk population remains refused while the final
density, biome, aquifer, material and structure phases are absent.

The public interface is:

```text
Config{identity:String, base_amplitude:F64, base_octave:U32,
       octave_count:U32, normalize:Disabled|Enabled|Legacy,
       amplitude_modifiers:List<&2,F64>}
create(root:WS.Root, name:String, fuel:Nat, config:Config)
  -> Result<&2,&1,String,Noise>
get(noise:Noise, x:F64, y:F64, z:F64) -> Noise & F32
initialize(fuel:Nat, source:R.Source, config:Config)
  -> R.Source & Result<&2,&1,String,Built>
```

The base octave is a signed Java int encoded in a U32 word. Actual codec bounds
are `[-32,32]`, octave count `[1,32]`, base amplitude
`[9.999999747378752E-6,1000000]`, and modifiers `[0,1000000]`. The modifier list
is empty for the default all-ones sequence, or has exactly `octave_count`
entries. Config admission refuses nonfinite numbers and runs before any draw. The
actual boxed-Double modifier codec rejects `-0.0` below its `+0.0` lower bound;
Bend applies that same signed-zero admission rule.
The supplied name must match the Config registry identity.

Normalization accepts the actual codec forms: omitted or JSON `true` means
Enabled, `false` means Disabled, and the string `"legacy"` means Legacy. Legacy
normalization is distinct from the separate legacy biome initializer. Both
ordinary LegacyRandom and Xoroshiro named sources are supported.
`minecraft:nether/temperature` and `minecraft:nether/vegetation` are explicitly
refused because RandomState always dispatches those keys to
`createForLegacyNetherBiome`, whose constructor is not implemented here.

The constructor uses exact binary64 powers of two within the admitted exponent
range. Absolute octave amplitudes use Java's sequential compensated
`DoubleStream.sum`; deviation squares use the different, ordinary ordered
double sum followed by sqrt. Legacy normalization and the float range boundary
follow their actual bytecode operation order. Current `F.sqrt` is reused.

Initialization forks the named source positionally twice before building any
layer. Every nonzero modifier constructs first and second Perlin noises from
`octave_<signed index>` in the two factories. Their layers are interleaved, with
the second frequency multiplied by binary64 `1.0181268882175227`. Amplitude is
the rounded double normalization-times-octave product narrowed once to float.
Positive zero modifiers are skipped; a nonzero modifier whose amplitude underflows is
still constructed. An entirely zero modifier list constructs no Perlin layers
but still advances the two initial forks. Any failure restores the exact
original constructor source, including earlier initialization progress.

The getter reuses the actual affine NoiseStack/Perlin producer: each coordinate
is multiplied by that layer's double frequency, then the float noise sample is
multiplied by its float amplitude and added to the float accumulator in layer
order. It returns the complete Noise owner.

Six laws in `src/worldgen_density_noise_laws.bend` are independently kernel
admitted through `src/worldgen_density_noise_proof.bend`: whole getter retention,
invalid-config source retention, every failed constructor's source rollback,
unsupported legacy-biome refusal, invalid named-parameter refusal and the
negative-zero modifier boundary.
`evidence/worldgen-density-noise-owner-proof.json` records exact source snapshots,
unchanged checked terms/maps, zero exclusions and reproducible command receipts.
These contracts do not establish numerical parity. Separate coordinated
pinned-Java/native observations passed 68 constructors, all 180,224 permutation
words, 544 getter words and another 544 public-constructor getter words, plus 20
codec, fuel and unsupported-initializer boundaries. The refreshed NormalNoise
native artifact's source pins are all current; its exact identity is recorded
in `evidence/worldgen-density-native.json`.

`tests/worldgen_density_noise.bend` exposes actual constructor parameters,
normalization/range words, all layer frequencies/amplitudes/offsets and complete
256-byte permutations, post-constructor Source words and raw scalar float bits.
The fixture passes ordinary source checking and the substantive signed-zero
native rebuild. The pinned-Java raw-word comparison passed the stated cases.
The fixture interface accepts one pipe-delimited argument. `normal` fields are
seed hi, seed lo, legacy flag, identity, random fuel, amplitude hi/lo, signed
octave word, octave count, normalization name, modifier words and coordinates.
Modifiers are semicolon-separated `hi,lo` pairs; empty means defaults.
Coordinates are semicolon-separated `xhi,xlo,yhi,ylo,zhi,zlo` words.
`api` uses the same fields and exercises public admission; `parameters` takes
amplitude hi/lo, octave word, count, mode and modifiers; `octave` takes one word.
The fixture parser is for controlled reference inputs, not the product resource
decoder. Independent expected values remain owned by the pinned Java producer.

`tools/reference_worldgen_density_noise.py` supplies the NormalNoise participant
for the coordinated single-JVM density batch. Its 88 cases include the six
shipped climate configurations in both random algorithms and four seeds, all
normalization forms, signed octave/count boundaries, compensated sums, zero and
underflow modifiers, actual codec refusals, fuel rollback and the two real
legacy Nether initializer routes that Bend refuses. It emits actual loaded
Minecraft class pins plus the shipped JVM DoublePipeline/Collectors class pins.
The strict native parser compares full observed constructor/state/permutation
words and getter bits; an additional `api` route checks the public constructor.
Python syntax and wire-format controls passed. The parent's actual Java batch and four-case supplement have completed.
Comparison against the refreshed signed-zero native artifact passed. These
finite observations cover the listed constructors and coordinates; they do not
establish every noise input or complete normal-world generation.
