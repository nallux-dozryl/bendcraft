The demand planner is a pure client API over the real loaded Registry owner, the
committed family-request inventory, a catalog, and an observed `GS.Sample`.
Its source and 16 proposed laws are prepared; source, independent-kernel, and
native checks have not been run for this new API.
The proposed laws cover named admission/refusal and already-seen branches, the
actual startup decode call, and the complete plan prefix/materials; they do not
yet prove the traversal's seen-map invariant or an arbitrary end-to-end success
theorem.

`collect(owner, sample, catalog, admission, limits)` returns the complete affine
`Owner` and `Result<C.Error,Plan>` on every outcome. It keeps `Owner.committed`
unchanged, including on success. A successful plan contains the original
committed requests followed by new families in first-observed cell order;
`additions` identifies that suffix. Each family's complete state set is loaded
by the existing catalog loader. The planner neither alters the sample's cells,
seeds, appearances, origin, camera, or clock fields nor performs model selection.

At startup, `initial(owner, sample, admission, limits)` requires an empty
committed inventory and obtains initial family requests from the first observed
sample. Its context contains `None` instead of a catalog; it uses actual registry
decoding directly after identity, sample and budget admission. It neither
constructs a fake empty resource catalog nor injects a synthetic miss error.
`collect` subsequently wraps the actual admitted catalog in `Some`.

The caller constructs `Admission{default_mode,modes,materials}`. With
`default_mode=None`, an unlisted family produces `ModeNotAdmitted`. An explicit
`Some{mode}` is the caller's blanket renderer admission, overridden by named
`modes`; this module supplies no default renderer and no vanilla or sprite-layer
classifier. Every newly demanded mode passes the production `C.mode_guard`, so
an explicit special renderer yields `UnsupportedRenderer` before resource IO.
The complete `BR.Policy` material declaration is returned unchanged.

The planner first compares the sample and catalog identities with the admitted
owner identity. It then threads the actual owner through `Registry.identity`
and compares its computed identity before catalog lookup or state decode. It
admits sample structure and both demand and catalog request budgets. For each
distinct raw state with an installed catalog, it calls production `C.lookup`; only an exact
`StateNotLoaded` code reaches `Registry.decode`. Separate sets coalesce repeated
raw IDs and different missing IDs that decode to the same family. Other lookup
errors retain their original code, resource, and detail. Registry decode failures
retain the returned owner and use the existing `Registry` error convention.

An observed loaded family absent from the committed inventory produces
`CatalogLedgerMismatch`. A missing state belonging to an already committed
family produces `CommittedFamilyMissing`; the caller must resolve that catalog
invariant rather than retry the same family indefinitely. The owner Registry
must come from validated registry loading. Successful catalog entries are
trusted under the existing loaded-catalog contract: lookup checks their raw ID,
and this planner does not independently revalidate their name/property metadata.

`Limits{max_cells,max_families,catalog}` bounds observed cells, total committed
plus proposed families, and the production `C.request_guard`. Family expansion
state counts and model/texture/resource budgets remain the existing loader's
responsibility. A small observed sample can demand a family with many states.

The integration worker must pass **all** `Plan.requests` and `Plan.materials` to
a fresh coherent catalog load. `CLoad.load` replaces a complete material context;
loading only `additions` and replacing assets would discard prior families, and
catalog maps cannot be merged independently of their texture slots. Keep the
old assets/catalog and committed inventory until the candidate load and actual
sample/frame admission succeed, then publish the coherent replacement and its
full request inventory. No commit or installation helper is included here,
because a host-declared successful plan is insufficient to establish that
candidate admission. Entry/client integration is a separate coordinated change.
