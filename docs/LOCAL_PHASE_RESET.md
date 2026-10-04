# Additive checked local-phase fall-reset policy

`X.resume_apply_with_reset_checked(stage,status,policy:TH.ResetPolicy)` returns
the sole `X.State` and `Result<X.Error,X.Observation>`. Preparation and provider
resolution use the existing `prepare_*`, `stage_intent` and `stage_query` APIs.
The original 81,112-byte X source is an exact prefix: its types, definitions,
laws, diagnostics and CheckedNotRequired entry points remain unchanged.

The new dispatcher repeats the existing shape, pending structure, immutable
authority, remembered provider error and ordered sprint/facts gates. It calls
`LI.prepare_checked` once, including input decay, cleanup and jump, then invokes
`TH.travel_with_reset_checked`. Successful travel uses the unchanged player
finish, rotation normalization, actual late pose queries, resize and cached eye
calculation. No extra Core/common tick or input sample is introduced.

`TH.ResetTravelError` preserves `X.TravelError`. `TH.ResetHistoryError` preserves
the existing `TravelError(MovementError(HistoryError))` diagnostic route. Only
`TH.ResetSupplierError` maps to `X.ViewError`, with the explicit string prefix
`local-phase-reset:reset-supplier:` followed by the supplier diagnostic.

Every admitted failure restores the entire direct-entry or post-common
`PreFrame` Body/view/cache, support, minor state, fall history, LI, player
metadata, sprint flag, pose, controller and ECT metadata with the returned Core
and Tables owner. Malformed owner/pending/authority refusals retain the incoming
owner before a provider/reducer runs. This remains the declared project
transaction policy. It is not Java exception atomicity.

LM has already formed its immutable movement candidate when the real required
ray is queried. The supplier derives endpoints from original feet and resolved
motion, capped at length eight; it runs before history completion/commit. This
ordering equivalence is admitted only under fixed neutral read-only services
without observable callbacks. No fabricated MISS or independent Body/endpoints
are accepted. Nonrequired rays do not call the supplier. Required supplier
failure rolls back all local state, including jump and history preparation.

The proposed closed consumer policy uses the same declared `[-64,64]^3`
whole-cell interior as the existing facade's movement service, 128 read-work
units, `FR.DefaultClientOverworldFourState`, and an empty policy tail. Its bound
is an admission budget, not a termination theorem: pathological negative
subnormal rays must return checked work/interior failures. The policy never
expands around a Body or treats missing sections as air. Other tags, data packs,
dimensions, fluids and reset hits remain outside the profile.

The facade contains `reset_policy()` with those exact bounds/profile. After the
frozen fall-reset supplier's independently admitted native prerequisite passed,
root granted the exact activation: `apply_resolved` now calls
`resume_apply_with_reset_checked(stage,status,reset_policy())`. Its other archived
bytes remain unchanged outside the permitted import/policy additions. The saved
Session consumer still requires its shared-artifact native verification.

`tests/local_phase_reset.bend` exports `arguments([exe,table])` for the next
shared LocalPlayer executable's `phase-reset-cases` branch. It exercises two
required-ray successes, seven refusals with exact-owner direct recovery, two
pre-provider malformed-stage refusals, and two existing actual jump steps.
The producer checks `TH.air_miss` Body/support/minor/history raw words and full
unchanged `scheduled_jump` phase observations. Holding zero keys omits the
travel fixture's observed shift-only above-ground probe; there is no whole-X
airborne-control or full required-ray tick Java oracle. Whole phase metadata is
checked through exact rollback/recovery and the separate actual jump cases.

`tools/test_local_phase_reset.py` provides read-only `contract()` and
`compare_output(stdout)` for the integration runner. It verifies the original
14-file archive, frozen inputs, exact old X prefix, complete current source
closure and immediate before/after comparison pins. `facade_generation()`
admits only the exact new FR import, bounded policy and eventual single resume
call substitution; the rest of the archived facade must remain byte-identical.
It records whether the route is staged or active instead of requiring the old
facade SHA after the reviewed activation. It cannot emit, launch, extract Java
or calculate gameplay expectations. The consumer runner must seal the complete
producer, binary and receipts and compare two fresh focused runs immediately.
Existing standalone seals intentionally refuse the additive source.

Authorized ordinary commands, each with 55 seconds plus five seconds of owned
group cleanup, are:

```text
/Users/chuah/.bend/bin/bend src/local_phase_runtime.bend --check-only
/Users/chuah/.bend/bin/bend tests/local_phase_reset.bend --check-only
```

The retained source001 and harness004 ordinary checks pass. The saved consumer
is enabled in source; its native parity remains pending. The unchanged focused harness does not
need another ordinary run; its next comparison uses the single changed shared
consumer artifact. No new Java extraction, independent native artifact, kernel
run or UI execution belongs to this lane.

The shared entry imports `./local_phase_reset.bend as PhaseReset` and calls
`PhaseReset.arguments([exe,table])` for `phase-reset-cases`. The travel handler
imports `./local_travel_reset.bend as TravelReset` and calls
`TravelReset.arguments(table <> commands)` for `travel-reset-cases`. Both join
the new `tests/playable_client_session.bend`; the old Session harness and its
existing comparison helpers remain intact.
