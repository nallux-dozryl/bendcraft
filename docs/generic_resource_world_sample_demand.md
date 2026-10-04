The demand planner is a pure client API over the real loaded Registry owner, the
committed family-request inventory, a catalog, and an observed `GS.Sample`.
Its production API now passes the complete runnable generic-client source check
in 14.740 seconds. The 16 proposed planner laws remain separately unverified;
this source result is not an independent-kernel result. Earlier parameter-match,
annotation and caller ownership failures are retained in their own receipts.
The proposed laws cover named admission/refusal and already-seen branches, the
actual startup decode call, and finalizer preservation of the supplied request
prefix and materials under the catalog request-budget premise; they do not
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
`default_mode=None`, an unlisted newly demanded family produces `ModeNotAdmitted`.
Already loaded committed families retain their admitted catalog modes. An explicit
`Some{mode}` is the caller's blanket renderer admission, overridden by named
`modes`; this module supplies no default renderer and no vanilla or sprite-layer
classifier. Every newly demanded mode passes the production `C.mode_guard`, so
an explicit special renderer yields `UnsupportedRenderer` before resource IO.
The complete `BR.Policy` material declaration is returned unchanged.
The planner does not validate its layer keys or per-sprite assignments. The
resource loader remains responsible for those material checks before candidate
installation.

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
Ledger checks compare family-name membership; they do not independently check
committed-mode equality with an installed entry or completeness of unobserved
family states. Those obligations belong to the coherent loaded-catalog contract.

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
full request inventory. The planner itself performs no installation effects.
The actual runnable client now uses the
[resource session worker](generic_resource_world_sample_resources.md), retaining
the Registry, complete request ledger and assets. It loads a replacement only
after a genuine missing-state observation, and admits the candidate through the
actual frame and scene APIs before publication. Refusal retains the prior
assets/ledger and the returned Registry owner. Changed native acceptance is
tracked separately from source checking.
