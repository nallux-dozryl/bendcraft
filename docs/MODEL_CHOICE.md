# Model choice and RNG consumption, pinned Java 26.3

`src/model_choice.bend` implements the production block-model selection boundary
given an already instantiated `BlockstateModel.Root` and an explicit
`Random.Source`. It returns selected model IDs/transforms/source-part indices and
the final raw RNG state. It performs no geometry baking or rasterization.

Implementation, ordinary module/driver checks and native comparison pass: 516
cases / 1,484 selection observations, including all 484 actual Java-reference
cases and 32 defensive cases, plus 69 exact default-position seeds. Native runs
reproduce twice. Seven malformed provenance/reference and four altered-output
cases are rejected. See `evidence/model-choice-tests.json` for build receipts,
source/compiler hashes and separately scoped kernel results. Confidence in this
measured selection boundary is high. No full-client or gameplay parity follows
from this module.

## Production authority

`tools/reference_model_choice_probe.py` verifies the installed 26.3 client jar,
version JSON, Java executable and 80 available official libraries using the
existing read-only pinned client verifier. It runs untouched production
`SingleVariant`, `WeightedVariants` and `MultiPartModel.collectParts` methods.
Marker implementations of `BlockStateModelPart` carry only model/transform
identity. Their geometry method throws; the probe cannot accidentally use a
marker as a geometry oracle. Multipart's private production receiver and shared
state are constructed reflectively. Its production `selectModels` and
`collectParts` still execute; an empty active subset retains one false selector
to meet the production shared-state constructor's nonempty-selector contract.

The 124 official roots come from actual
`BlockStateModelDispatcher.CODEC.parse(...).instantiate(...)` across stone,
dirt, oak planks, grass block, glass, oak stairs, oak slab and oak fence. Their
already bound active choices and original source indices are projected into
marker receivers. Thus this corpus verifies selection given those instantiated
roots; it does not independently re-run model baking, sprite resolution or
every arbitrary blockstate condition through the new module.

The reference contains 484 cases / 1,452 consecutive selection observations,
including deterministic independent inputs, all 124 selected official states,
singletons, totals 63/64 (the actual flat/compact selector threshold), maximum
signed-positive totals, zero active multipart subsets and mixed part ordering.
Every method records its receiver RNG state before/after, argument and result.
Bounded draws additionally record primitive advancement counted by an independent
clone of the actual Java source. The corpus observed up to four primitive draws
for one bounded call. Two fresh Java runs reproduce exactly. Raw transcripts,
Java source and disassembly remain ignored under `build/model-choice`; the
compact, approximately 1.45 MB `reference/model_choice.json` preserves the
necessary identity and raw-state fixtures without asset bytes.

The authority inventory records SHA256 for 26 named class files and their
`javap -c -p` output, the harness source, every used blockstate resource, client,
metadata, runtime and libraries. Runtime is the installed Microsoft OpenJDK
25.0.1+8-LTS. `evidence/model-choice-reference.json` summarizes provenance/counts;
the reference contains the exact values, not estimates.

## Observed selection contract

| Receiver | Production RNG calls | Result |
| --- | --- | --- |
| `SingleVariant` | none | Append its one model part. |
| `WeightedVariants` | `nextInt(totalWeight)` | Select by original ordered cumulative weights, then collect the chosen child. Even an array containing one positive-weight entry consumes this draw. |
| `MultiPartModel` with no active parts | `nextLong()` | Append no parts; retain the state after that long. |
| `MultiPartModel` with active parts | One `nextLong()`, then `setSeed(theSameLong)` before each active child in source order | Every part starts from the same reseeded source; the final source is the state left by the final active choice. Single children still receive the preceding reseed. |

Weighted selection calls `WeightedList.getRandomOrThrow`; the pinned
`WeightedVariants.Unbaked.bake` always constructs a `WeightedVariants` receiver.
There is no singleton-array optimization in this measured path. A bare object
is a `Single` and does not consume randomness. The existing decoder owns
resource-codec weight validation; the adapter revalidates typed weights/totals
before consuming any RNG.

Seven additional actual raw receiver cases preserve failure phase/class/message
and unchanged RNG state. Empty entries fail during `WeightedVariants`
construction with `NoSuchElementException`; all-zero weights construct but
`collectParts` throws `IllegalStateException`; negative weights and overflowing
totals fail construction with `IllegalArgumentException`. Raw Java `Weighted`
allows zero weights, while the frozen blockstate resource codec requires
positive entries. These receiver-construction observations are a separate
layer; the adapter's typed `Choice` validation errors do not claim identical
Java exception classes or phases.

The renderer's `ModelBlockRenderer` creates
`RandomSource.createThreadLocalInstance(42L)`, which returns
`SingleThreadedRandomSource`. Its `tesselateBlock` first calls `setSeed` with an
explicit caller-supplied long, then `collectParts` once. The fixture corpus
executes that actual single-threaded receiver and the official
`LegacyRandomSource`, seeded Xoroshiro and explicit-state Xoroshiro receivers.
`Random.Source.Legacy` represents the observed single-threaded/legacy bit
algorithm. It does not implement either receiver's Java threading detector or
concurrent mutation semantics. Xoroshiro remains an explicit caller option; it
is not claimed to be this renderer's default source.

Raw `Random.Source` represents only the supported bit-generator state. Gaussian
cache state, nondeterministic factory seeds and concurrent mutation are outside
this adapter's input/output contract and the existing RNG module's domain.

The pinned `SectionCompiler.compile` bytecode supplies
`blockState.getSeed(theWorldBlockPos)` to that renderer. The moving-block feature
instead uses `blockState.getSeed(MovingBlockRenderState.randomSeedPos)`; its
render position is a distinct field. These call sites are pinned in the class
inventory and inspected as bytecode, not executed as world-rendering fixtures.

## Public adapter

```text
Selected { part_index: Maybe<U32>, variant: BlockstateModel.Variant }
Selection { parts: List<Selected>, multipart_seed: Maybe<Random.Bits64> }

select(root, source, fuel)
  -> source & Result<Error, Selection>
select_seeded(root, source, seed, fuel)
  -> source & Result<Error, Selection>
default_position_seed(x, y, z) -> Random.Bits64
```

`part_index=None` identifies a variant root. Multipart outputs preserve original
source indices from `Root.parts`; filtered-out parts do not appear. The output
list preserves source order and each selected `Variant` retains model, x/y/z
quarter turns and UV lock unchanged for `BlockBake.State`. `multipart_seed` is
the actual long drawn at the multipart boundary, including an empty subset.
Dependencies remain owned by the blockstate root and are not a selection list.

The caller may parse/instantiate with `BlockstateModel`, look up the actual state
root, then pass it to this adapter. Missing roots, property/schema errors,
exceptional block behavior and root preparation remain explicit caller errors;
this module never substitutes a missing model root.

`select_seeded` resets the same source kind from the supplied long before
selection. A per-choice `Nat` fuel limits the existing RNG rejection loop.
Successful operations consume exactly the measured Java draws. Any malformed
typed choice or rejection exhaustion returns the entire pre-call source and no
partial selection. That whole-call rollback includes a preceding explicit
reseed and already processed multipart parts. Finite fuel and atomic rollback
are explicit Bend extensions; Java's production receiver has neither policy.
The structural law proves `commit(Fail)` preserves its supplied original source.
It is not an RNG/model equivalence theorem. Full imported kernel status is
reported separately from ordinary checks/native observations.

## Position seed boundary

`default_position_seed` is only the actual `Mth.getSeed(int,int,int)` method:

```text
l = (long)(x * 3129871) XOR ((long)z * 116129781L) XOR (long)y
l = l * l * 42317861L + l * 11L
return l >> 16
```

The x multiplication wraps as Java signed int before sign extension. Later
arithmetic wraps as signed-long bit patterns; the final shift is arithmetic.
Coordinates are Java int bit patterns, high/low long words are unsigned U32
words. Sixty-nine actual Java coordinate cases include signed extremes and
independent random triples. No Python arithmetic supplies their expected seeds.

`BlockState.getSeed(pos)` delegates to its actual block. Bytecode and executed
stone/door/sunflower/bed state fixtures show why callers must not substitute the
default unconditionally:

- `DoorBlock` and `DoublePlantBlock` use the lower half's y coordinate; upper
  halves subtract one using `BlockPos.below(1)`.
- `AbstractBedBlock` uses the head location's x/z: head keeps its coordinate,
  foot moves one block along its state facing. Y comes from the original pos.

These exceptional block policies are documented observations and are not
implemented as automatic dispatch in `ModelChoice`. Caller seed/context must
be explicit. The seed tests compare the default helper; exceptional seeds are
preserved as separate Java observations and never relabeled default parity.

## Reproduction

```sh
python3 tools/reference_model_choice_probe.py --random 100
python3 tools/test_model_choice.py --prepare-only --selftest
# Run only after the lead admits one heavy compiler job:
python3 tools/test_model_choice.py --selftest
```

`--prepare-only` verifies pinned provenance, deterministic inputs, raw-state
chaining/call ordering, two independent fresh Java executions and ordinary Bend
checks without starting a native build. The full command builds the actual
driver with a 600-second bound, compares native selections/final raw states
twice, checks default seeds, fuel exhaustion/whole-source rollback and malformed
choices, then rejects altered provenance and observation tables.
`--no-build` requires a successful receipt matching the binary, compiler and
current source. Build receipts retain binary and all seven transitive Bend
source hashes. No second parallel native emission or
unbounded imported kernel work is part of this command.

The final admitted build completed in 77.75 seconds and produced binary SHA256
`feac8367655ffb4a3da37ab2f772a037af41f16b0e8aa9590bbcc3ac9c681927`.
Production source SHA256 is
`d95595cf878faa8598d96bd19200e79fff142feab1b35111348951be4a71b240`;
driver SHA256 is
`3e5d6f0e0848648d314d52f32a26d1b511f06a2505d218ee656d7173c69332e9`.
All frozen source/compiler receipt inputs remained identical after native runs.

## Independent kernel scope and reproduction

The direct full-import `src/model_choice.bend --verdict` ended in 22.86 seconds
with Bend's generic TypeScript/BendTT mismatch. It is recorded separately in
`evidence/model-choice-kernel.json`; no full-import proof success is claimed.

An exact source projection passed the independent kernel in 25.17 seconds.
It retains the complete production F64, ResourceJson, BlockstateModel, Random
and ModelChoice definitions and their laws, with import deletion and lexical
namespace renaming only. JSON contributes its exact `Value`, `Member` and
`Limits` declarations. Its generic parser/serializer are unreachable from the
retained production definitions and are omitted. There are no test-module
imports, substituted implementations, axioms or unsafe definitions. This
establishes typing/termination and the retained stated laws, including
whole-source preservation by `commit(Fail)`. Java behavioral equality remains
independent measured evidence, not a consequence of those laws.

`evidence/model-choice-kernel-projection.json` records every source hash,
projection hash, namespace map, command and output. The projection can be
regenerated from the committed production sources without its ignored cache:

```sh
python3 - <<'PY'
import pathlib,re
root=pathlib.Path.cwd()
files={'J':'json','F':'f64','RJ':'resource_json','B':'blockstate_model',
       'R':'random','C':'model_choice'}
sources={k:(root/'src'/f'{v}.bend').read_text() for k,v in files.items()}
s=sources['J']
sources['J']=s[s.index('type Value is Data:'):s.index('def default_limits()')]
def symbols(s):
    names=set(re.findall(r'^(?:type|def|law) (\w+)\b',s,re.M))
    for block in re.findall(r'^type \w+ is Data:\n((?:  [^\n]*\n)+)',s,re.M):
        names.update(re.findall(r'^  (\w+)\{',block,re.M))
    return names
maps={k:{n:'MC_'+k+'_'+n for n in symbols(s)} for k,s in sources.items()}
aliases={'J':{},'F':{},'RJ':{'J':'J'},'B':{'J':'J','R':'RJ'},
         'R':{'F':'F'},'C':{'B':'B','R':'R'}}
token=re.compile(r'"(?:\\.|[^"\\])*"|#[^\n]*|\b\w+\.\w+|\b\w+\b')
def rewrite(k,s):
    s='\n'.join(line for line in s.splitlines() if not line.startswith('import '))
    def convert(m):
        t=m.group()
        if t.startswith(('"','#')): return t
        if '.' in t:
            alias,name=t.split('.')
            return maps[aliases[k][alias]][name] if alias in aliases[k] else t
        return maps[k].get(t,t)
    return token.sub(convert,s)
text='import Base\n\n'+'\n\n'.join(rewrite(k,sources[k])
    for k in ['J','F','RJ','B','R','C'])+'\n'
p=root/'build/model-choice/kernel-projection.bend'
p.parent.mkdir(parents=True,exist_ok=True)
p.write_text(text)
PY
# Admit this bounded kernel job through the same build queue:
/Users/chuah/.bend/bin/bend build/model-choice/kernel-projection.bend --verdict
```
