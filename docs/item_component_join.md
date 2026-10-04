# Typed suspicious-stew component integration seam

The typed adapter, actual catalog admission, and actual version-3 saved writer/reader
are implemented. The current narrow native replay passes 115 cases, including all
seventeen modified recipe outputs in main/equipment slots and seventeen cold
codec reloads in separate processes. The full runtime/transport integration and
world publication remain root-owned. Enable `TypedStew` there after those joins pass.

## Catalog admission

Keep the `D.metadata` empty-component branch and its bytes/limits unchanged.
The actual `D.metadata` nonempty branch resolves its exact definition through
`D.component_defaults(catalog,id)`. A missing definition refuses. Its helper uses:

```bend
C.metadata(C.default_from_identity(id,enabled && U32.is_eq(limit,1),components_sha256),key)
```

`C.default_from_identity` admits only the enabled suspicious-stew definition
whose verified initialized-default digest is
`7f324fff5c212f399a85e4e3962f34f634fdedeeddff5f6bb3e39dbf229b5c25`.
It never derives admission from an envelope prefix. The adapter imports the
foundation `Inv`, JSON/NBT codecs, and recipe components; it does not import `D`
or `I`, so a `D -> C` join introduces no inventory/catalog cycle.

If an actual initialized default JSON map is available, use `C.initialize` and
retain its successful `C.Defaults` token. This validates the entire pinned
seventeen-component map, including numeric AST lexemes before serialization.
The optional `R.Catalog` default-map initializer remains recipe-owned; absence
must refuse its output decoder. `R.output_metadata` is a decoder-produced helper
and must not replace `C.metadata` for arbitrary submitted keys.

## Full inventory admission and authority

`I.slot_valid_with`, `I.persisted_valid_with`, and `I.acquire_existing` already
consume `D.metadata`. Join there instead of installing unchecked foundation
metadata. Keep the complete `I.State` failure branches, ability/status words,
menu authority, selected index, and world/session owners untouched.

The former inline blanket refusal law was replaced by an actual missing-default
refusal law. New laws cover disabled defaults, unchanged plain metadata, fallible
slot encoding, and complete `Saved` owner/payload retention.

`C.load` is a separately tested foundation `Inv.Inventory` adapter. It consumes
the actual affine backing array and returns it untouched on component, count,
or bounds refusal. It is not a replacement for the full `I.State` consumer.

The crafting outerauthority calls `C.metadata` for exact nonempty grid/output/
inventory keys, then supplies only those successful complete-key metadata values
to `R.find_with_metadata`. Plain input ingredients remain ID-matched as observed
in Java. The outerauthority's default `DefaultOnly` mode continues refusing all
component-bearing input/output until this seam is enabled.

## Saved writer and reader

The implemented full version-3 path uses the new fallible
`item_component_inventory_codec.slot_tag` with these branches:

1. Empty slot: existing empty `Compound` unchanged.
2. Plain/default key: existing `id:String,count:Int` tags unchanged.
3. Nonempty key: resolve the trusted catalog definition as above, then call
   `C.encode_modified_slot(defaults,key,count)` and propagate failure before
   publishing a complete root or saving bytes.

Both main/equipment tag lists are collected through `Result` before constructing
the complete version-3 root. Legacy/version-2 helpers are unchanged. Their exact
bytes and plain version-3 bytes pass independent fixture comparisons.
`I.snapshot_valid` prevents modified slots from selecting legacy/version-2.

The implemented version-3 reader keeps empty/plain tags and delegates exactly the
three-field modified slot schema (`id`, `count`, `components`) to
`C.decode_modified_slot(defaults,value)`. Determine defaults from the catalog's
definition of the decoded item ID; a fixed `None` capability must refuse.
The catalog is threaded through full `sized_slots`/`full_projection`, retaining
the existing `I.restore_persisted` admission. Unknown/duplicate fields, component
removal, unknown effects, and malformed duration tags must refuse the whole save
load; no partial slot installation is authorized.

The full-root NBT depth limit is now 8; the existing 65,536-byte and 16,384-node
limits are preserved.
The physical patch is the Java `components:Compound` patch, containing
`minecraft:suspicious_stew_effects:List<Compound>` with `id:String` and optional
`duration:Int`. It is not a stored effective-map JSON string. Canonical identities
are rebuilt through the shared recipe resolver after typed NBT decoding.

## Wire structural and authority checks

`I.structural_slot`, `I.menu_snapshot_valid`, `Wire.acquire_valid`, and
`Wire.main_snapshot_valid` currently refuse any nonempty component string.
Permit only the same full validated typed profile at these gates. For a
catalog-free structural observation, `Some{C.InitializedSuspiciousStew{}}` can be
an explicit pinned structural capability; the backend/authority must still
resolve and validate the actual enabled catalog definition before mutation.
Do not accept an arbitrary bounded string or trust `BendCraftComponents1`.

Preserve the existing item-key array encoding and transport size limits. The
canonical identity remains exactly
`BendCraftComponents1<TAB>1<TAB>canonical_effective_map_JSON`; a patch equal to
the complete defaults remains the empty marker. The new key factory also
refuses identities whose effective JSON exceeds the shared 65,536-character
parser budget, including a small physical NBT list that would expand beyond it.

## Remaining root-owned integration evidence

Before enabling `TypedStew`, test each of the seventeen outputs through actual
craft/take, inventory observation, version-3 physical save, cold reload, and the
actual transport. Check refusal retains the complete player/session/world owners
and every raw ability/status word. Keep plain/default and legacy/version-2 save
bytes identical. The adapter's foundation-owner laws and native fixtures do not
establish those full-consumer properties.

## Evidence and proof limits

`evidence/item_component_inventory.json` records the actual D/IC 115-case replay.
Every encode returns the complete owner, compared across all 64 backing cells,
including sixteen hidden inadmissible cells, logical length, selected index,
abilities, all raw status words, menu opened/revision, catalog count, complete
record bytes, and fresh flag. Temporary crafting/carried stacks refuse saving.
Reload deliberately restores durable main/equipment and resets temporary/menu
fields; hidden cells are outside the durable projection. Physical modified tags
compare against primary Java typed values, with Compound key ordering treated
as unordered. Product deterministic full-root bytes are also independently
assembled and compared. Cold codec reload is not filesystem atomic publication.

All thirteen component laws pass the ordinary source checker. The historical
eight-root pure subset passed the independent kernel. The current full thirteen
export has no exclusions after the shared decimal/diagnostic repair, but the
independent kernel rejects `json.encode_go` with `affine live code, calls that
descend`. That attempt is retained; eight roots must not be reported as thirteen.
The physical-byte decoder theorem also remains unsupported after a checker
stack overflow. Native byte fixtures do not establish that theorem.

The actual IC import graph has forty-three existing declared storage foreign/
unsafe dependencies; its whole-import CLI verdict reports those boundaries.
The new catalog/Saved owner laws are selected from the unchanged checked terms
and exported separately for independent kernel checking. Three actual laws pass:
missing/disabled initialized defaults and unconditional complete `Saved` owner/
payload retention. The full six-law export and a five-law diagnostic subset
are both rejected at the same shared JSON encoder; the metadata, slot encoder,
and conditional menu encoder laws are not independently certified. No foreign storage operation
is included in the proof claim. The full player/session/world owner and gameplay
effect-consumption contracts remain outside this adapter's evidence.
