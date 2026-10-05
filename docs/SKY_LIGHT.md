# Sky-light authority and Core publication

`src/sky_light.bend` supplies a sky field over the actual production
`block_light.bend` propagation engine. `src/sky_light_world.bend` supplies the
source-column, chunk enablement, bootstrap, accepted-edit, and settled-frame
boundary over the actual `Core.World`. Python extracts the pinned Java reference
and orchestrates checks; propagation and source-height scanning run in Bend.

The sidecar owns **sky facts and work only**. It never owns a second Core world,
section map, or section array. Every Core operation transfers the caller's real
affine owner in and returns it. `BW.section_keys` and `BW.snapshot` preserve its
exact trie/bucket order and original arrays. Snapshot lists are scalar loading
work and are consumed during bootstrap. The block-light owner and this sky owner
can therefore share the sole Session/Core lifecycle without cloning the world.

## Provider contract

The supplied callbacks are closed Bend definitions over immutable `Context`:

```text
properties: Context -> U32 -> Maybe<BL.Descriptor>
occludes: Context -> BL.Descriptor -> BL.Descriptor -> BL.Direction -> Bool
bounds: Context -> String -> Maybe<SW.Bounds>
section_policy: Context -> Core.Position -> SW.SectionPolicy
enabled: Context -> Core.Position -> Bool
```

Use the actual authenticated `BR.Catalog`, `BR.properties`, and `BR.occludes`
providers described in `docs/BLOCK_LIGHT.md`, directly or through an immutable
consumer context. Sky preserves the raw state ID and cached light dampening;
ordinary block emission is discarded. The occlusion callback is the exact
source face / target opposite face union from the authoritative registry.

`Bounds{min_y,height,air,has_sky}` is actual dimension/chunk authority, not a
rendering crop. `min_y` and `height` must align to sections; positive height and
signed coordinate range are checked. `air` names the registry's actual empty
state, whose descriptor and faces must be supplied. `has_sky` is the dimension's
sky-light policy. The enablement callback receives a normalized chunk origin
(X/Z at multiples of 16, Y=0), and controls initial source admission.

Every chunk represented by a resident Core section is completed across these
bounds for lighting. Existing sections, including Core air halos outside build
height, are acquired from real Core arrays. Source membership extends through
the official one-section storage halo; the height scan stays within build bounds.
A missing Core section is accepted only when `section_policy` explicitly returns
`KnownEmpty{}` from real chunk/generator authority; its sky geometry uses the
bound empty state. `Unknown{}` returns `UnknownSection` and preserves the entire
Core owner and resumable cursor. Neither a missing chunk nor an unlisted section
is implicitly known air. No neighboring absent chunk is manufactured.

The dense sky field includes declared known-empty internal geometry so light can
cross a gap beneath a roof. Frame observations still report `None/None` for
positions lacking an actual Core section. This interface deliberately binds
physical Core residency, rather than using Java's allocated light halos or
above-top level-15 lookup as evidence that a block exists. Raw Java sparse-layer
and halo observations are documented separately in `SKY_LIGHT_REFERENCE.md`.

## Flat-world authority adapter

`src/sky_light_flat_authority.bend` provides closed callbacks for the existing
saved flat-world consumer, using the **actual** `WG.Settings` and authenticated
`BR.Catalog`. Its immutable `Context{catalog,generation,air,has_sky,enabled}` can
be passed directly to `SW.load_resume` with `F.properties`, `F.bounds`, `F.policy`,
`F.enabled`, and `F.occludes`. Dimension sky policy, registry-resolved empty state,
and initial chunk enablement remain explicit actor authority.

The bounds callback validates actual generation settings, dimension identity,
and the sky provider's signed-coordinate bounds; an exclusive upper endpoint
that wraps through signed minimum is refused.
The missing-section policy requires the existing `WG.base_only` predicate:
features and lakes are off and structures are explicitly empty. It admits an
aligned section only when its origin is at or above `min_y + WG.layer_height`
and below build maximum. A missing section containing any base layer remains
unknown. Unspecified generation, noise, another dimension, invalid settings,
or outstanding feature/structure authority cannot manufacture empty geometry.
This derives the current flat consumer's empty upper sections from its real
existing generator contract; it does not duplicate the generator or assert that
missing sections in arbitrary worlds are air.

## Source law

A top-to-bottom scan begins above the actual build height using the bound empty
state. The first edge blocked by nonzero **target** dampening or the upper DOWN /
lower UP effective face union determines the lowest direct sky source. Its Y is
the upper cell's Y. A completely unobstructed column uses `Everywhere{}`, matching
Java's externally exposed `Integer.MIN_VALUE` threshold without sentinel
arithmetic inside source membership.

All enabled physical cells at or above their column threshold receive direct
15. Other cells start at zero. Ordinary propagation uses the existing block-light
edge law: face occlusion or saturation prevents transfer; every open edge loses
`max(1,target_dampening)`, including DOWN. There is no special zero-cost downward
edge. Actual pinned water dampening is 1. Initial sources are established together;
only dark cells adjacent to direct sources enter the FIFO, and later level
changes notify their consumers. Rejected descriptors cannot change the field.

## Lifecycle API

```text
SW.begin(world) -> world & sky
SW.load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,
               context,budget,world,sky)
  -> world & (sky & Result<SW.Error,Unit>)
SW.progress(sky) -> sky & SW.Progress
SW.advance(~Context,~occludes,context,budget,sky) -> sky & SW.Progress
SW.sample_batch(positions,world,sky)
  -> world & (sky & Result<SW.Error,SW.FrameSamples>)
```

`Progress` is `Bootstrap`, `Propagating{pending}`, or `Settled`. Work is resumed
in bounded units: key enumeration, one section acquisition, one scalar
publication, one source-edge scan, one seeded cell, or one repaired cell.
Section acquisition snapshots 4096 scalars in one unit, so this budget is not a
microsecond bound. Source scans stop after the highest obstruction. The field
has no fixed chunk count, block catalog, dimension height, or fixture domain.
There is currently no compact Java nibble/sparse storage representation; native
memory and latency for large worlds require measurement alongside integration.

`FrameSamples{clock,cells}` binds the real current `Core.Clock` to observations
`Observation{position,block:Maybe<U32>,level:Maybe<U32>}`. Sampling refuses
bootstrap, pending propagation, and a revision mismatch. A missing actual block
section yields `None/None`; a present block without sky facts yields a residency
error. No light values are exposed as settled until all source and propagation
work ends. Tick/time changes without spatial revision changes do not force a
sky rebuild; the frame receives the actual current clock.

The accepted mutation hooks are:

```text
SW.preflight(~Context,~properties,context,mutation) -> Result<Error,Unit>
SW.accept_result(~Context,~properties,context,mutation,sky,
                 actualCoreApplyResult)
  -> world & (sky & Result<Error,Unit>)
SW.refresh_block(~Context,~properties,context,position,world,sky)
  -> world & (sky & Result<Error,Unit>)
SW.rebuild(world,sky) -> world & sky
SW.accept_plain(world,sky) -> world & sky
```

Preflight can run before Core acceptance; it cannot grant permission or alter
Core. `accept_result` retains both owners after an actual Core refusal. A
successful block mutation reads the accepted state ID from the actual world,
updates its descriptor, rescans its complete source column, republishes affected
source baselines, and then propagates additions/removals. Descriptor and read
failure preserve both owners for retry. Sampling during column repair refuses.
Section creation/replacement, a further spatial edit during bootstrap/column
repair, and explicit rebuild restart loading from the current sole Core owner.
For a batch of accepted spatial edits, one rebuild also supplies a coherent
fallback without losing mutations. Nonspatial accepted operations update the
revision binding. The hooks do not apply permissions, finish actions, increment
revision, or drive simulation ticks; those remain the Core/Session owner's work.
Direct Core mutation/replacement must pass through a hook before sampling.

`set_enabled(position,enabled,sky)` changes actual chunk enablement. Disabling
retains the stored field. Enabling alone retains values except Java's specific
fill of wholly zero-valued upper sections above the highest source obstruction.
For all-air columns, Java's `MIN_VALUE-1` wraps to MAX_VALUE and no such section
is filled; this branch is represented explicitly. The upper-section emptiness
check and fill are synchronous work in this API, with no fixed section count.

`propagate_sources(position,sky)` explicitly enables the chunk and starts
resumable direct-source injection. It does not clear existing stored values
below the new threshold. While disabled, a block edit repairs its own descriptor
and source-height metadata, and retains other cached source values. This matches
the actual retained-layer roof history recorded by Java: disable, add roof,
reenable, and propagate can retain stale level 15 below that roof. Fresh rebuild
is a different lifecycle and is not substituted for these operations.

## Verification boundary

`src/sky_light_laws.bend` / `src/sky_light_proof.bend` contain 25 contracts
against the actual sky implementation and production registry interfaces. Run
`python3 tools/sky_light_proof.py` for the ordinary check and independent pinned
BendTT kernel. The laws cover source admission/refusal, emission isolation,
unknown values, exact opposing-face composition, attenuation in all directions,
and complete-owner preservation at rejected/zero-work boundaries. They do not
prove universal propagation convergence or authenticate Java table contents.

`tools/reference_sky_light.py` separately executes actual installed Java 26.3
classes and palettes. The retained fixtures establish the specification across
roof edits, attenuating blocks, partial shapes, signed chunk boundaries,
enablement, sparse storage, absent chunks, and direct versus ordinary DOWN
transfer. `docs/SKY_LIGHT_REFERENCE.md` states that receiver's precise boundary.

`python3 tools/sky_light_world_proof.py` checks 26 additional world-boundary
contracts with the independent kernel, including exact arbitrary affine section
enumeration / original Core retention, bootstrap and stale/pending refusals,
actual Core-result failure, deferred repair, and disabling-only stored-field
retention. Together the two targets contain 51 checked contracts, with no
excluded declarations. Receipts are `evidence/sky-light-proof.json` and
`evidence/sky-light-world-proof.json`; their explicit proof scopes remain binding.

`python3 tools/sky_light_flat_authority_proof.py` checks 12 supplemental adapter
contracts with the same independent kernel, covering exact supplied registry
delegation and generation, dimension, source-field-bounds, base-only policy,
signed layer-ceiling and disabled-authority refusals. Its receipt is
`evidence/sky-light-flat-authority-proof.json`. These contracts do not establish
catalog authentication, caller air/sky bindings, or universal generation geometry.

`python3 tools/test_sky_light.py` builds and runs the actual native Bend receiver.
It compares all 8 retained Java scenarios / 36 phases, plus propagation-budget
variants: 47 phase comparisons and 509 resident block/light pairs. The expected
Java levels and source heights never enter Bend. It also compares 409,600 actual
Core array cells, all six clock fields, missing physical samples, future pending
mutations, invalid-bounds / unknown-section / missing-descriptor refusal and
retry, and an existing below-build-height Core air halo. Receipt:
`evidence/sky-light-native.json`. This is a focused CPU native byte/ownership and
behavior boundary, not an independent proof, large-world benchmark, persistent
storage claim, sparse Java-layer implementation, or rendered client acceptance.

Frame adoption and evaluated lightmap RGB remain the lead-owned consumer work;
this provider supplies actual block-state-bound sky levels, not fabricated RGB.
