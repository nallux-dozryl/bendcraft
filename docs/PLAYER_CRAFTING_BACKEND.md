# Crafting authority in the private Backend

`remote_resource_backend.State` owns the original saved Session and a seventh
`Maybe<player_crafting_session_adapter.Context>` field. The legacy factories use
`None`; `new_reserved_with_crafting` installs the service catalog, cached plan
and component mode supplied by startup. The Session shell and bundle ABI are
unchanged. All actor reconstruction paths retain this context, including public
dispatch, lease expiry, release, physical input, frame reads and refusals.

Authenticated menu open, close and click first validate the renderer epoch and
sequence, then require a nonzero Player capability. A contextual request goes
through the production Session adapter and its sole authoritative inventory
owner. Menu inspect refreshes the actual derived output. The `None` path retains
the existing inventory-menu behavior. The wire reply ABI stays unchanged.

A successful physical take remains accepted when the subsequent derived-cache
refresh fails. The committed inventory, returned context and error message are
published together. That situation is not an atomic refusal. The Transport
prospective-encoding boundary is maintained by the separate native-controls
lane; it is not a claim of these Backend laws.

## Proof scope

`player_crafting_backend_laws.bend` contains ten equations over the complete
production actor. Eight concern refusal before authoritative mutation, with
actual lease-admission premises for the public menu wrappers. Two concern
rejoining the complete Session/context after public dispatch and preserving an
accepted take after failed refresh. The proof bodies use the actual production
functions and complete affine owners; no axioms or unsafe proof bodies are used.

The original ordinary source checker accepted all ten laws and their proof
bodies with every imported declaration checked. Its retained export has no
excluded definitions. The full independent-kernel check fails specifically at
`json.encode_go` with `affine live code, calls that descend`; the ten-law group
is **not** independently certified.

The exact two composition roots were conservatively extracted from that same
export, preserving all retained declaration bytes and source order. Their
complete dependency closure passes the pinned independent kernel. These are
`public_dispatch_rejoins_complete_session_and_context` and
`committed_craft_with_failed_refresh_stays_accepted`. Opaque native type
declarations remain in the closure where referenced; this does not prove their
IO effects. The earlier failed extraction which omitted `opaque File` is retained
as a failed attempt. The production Backend/law/proof/adapter bytes match the
certified source generation. The later authority geometry-validation repair is
outside the two-root closure and is checked separately by the native fixture
generation.

## Focused native boundary

`tests/player_crafting_backend.bend` calls the production Backend with the real
Session inventory owner and a live File lease. Every emitted case checks the
complete raw Core owner and observes all 64 inventory backing cells, including
an otherwise unused final-cell marker. The fixture catalog exercises two actual
stick takes, stale-plan refusal, refreshed output authority, absent output,
epoch/sequence refusal, Observer and invalid Player refusal, legacy `None`
behavior, close reclamation and the accepted post-commit refresh failure.

The deliberately incomplete refresh-failure catalog is a fault fixture, not a
claim about the installed vanilla recipe catalog. No physics, durability/save,
full service-loader fidelity or network framing conclusion follows from these
cases.

The focused runner copies the actual imported Bend and C effect declarations
unchanged, then uses the existing guarded native-cache preparation helper. It
compiles that ordinary Bend C once with the original CLI's CPU flags and checks
the source/header/toolchain closure again afterward. This avoids the ordinary
builder's second C emission. The existing process receipt helper supervises
each stage.

All **15 native cases passed**, with complete raw Core preservation and all
64 inventory backing cells checked. Native execution took 1.604 seconds; direct
clang compilation took 23.194 seconds. The frozen C is 12,276,047 bytes with
SHA256 `d599986c4589997b0a81dd359e84722db11d22791cd6d575715fba5465d90521`.
The binary SHA256 is
`65e3548d9a915d5fb0bea5d1ba61765c675d7d7f0f75db9cc65af7dbb879e150`.
This is the retained Core/Runtime source generation in the fixture snapshot;
later runtime changes are outside this verdict. No target compiler or native
process remains.

The first ordinary build was not published because a new Wire dependency
changed during compilation. A missing C effect in the initial snapshot was a
quick preflight refusal. The corrected frozen ordinary builder reached its
600-second outer bound during its second compiler pass. Those failed attempts
remain recorded; the final passing route reused its already verified C output.
Current results and exact source/artifact pins are recorded in
`evidence/player-crafting-backend-001.json`. To reproduce from source, use
`python3 tools/test_player_crafting_backend.py --work <fresh-directory>`.
