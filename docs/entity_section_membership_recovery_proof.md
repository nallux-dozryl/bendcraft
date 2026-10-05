# Entity section membership recovery production proofs

Fifteen laws over the actual recovery API, complete `T.State` scene owner and
complete `M.State` membership manager pass the original ordinary API checker
and the pinned independent kernel with zero exclusions. The authoritative
generation-8 receipt is `evidence/entity-section-membership-recovery-proof.json`.
Confidence is high for these stated contracts; numerical constructor-capacity
and cursor-wrapper obligations remain unproved.

The ordinary API check took `0.549295083` seconds. Source checking and export
together took `2.509485` seconds; the independent kernel took `0.291783` seconds.
The unchanged 1,232,916-byte artifact is
`build/entity-section-membership-recovery-proof/1791172548764743000/selected.bendtt`
(SHA-256 `6dc2322c97a9661771377b95e953030a45f60937b8187967d464993b495fe702`).

| Actual contract | Current laws | Scope |
| --- | ---: | --- |
| Recovery inputs and reconciliation | 7 | Missing saved membership or current loader observations refuses. After actual codec validation admits the image, invalid saved insertion chronology refuses through `prepare`/`commit` with both complete owners retained. Empty reconciliation preserves every plan field. Observing an arbitrary complete plan before and after actual reconciliation establishes retention of level RNG, UUID seed, entity-ID and insertion cursors and every runtime field. Actual chunk reconciliation preserves the complete registered-member list, including keys, boxes and orders. |
| Recovery activation | 4 | Failed preparation or refused acceptance retains both complete affine owners and the exact error. Acceptance installs the entire supplied plan and retains sound RNG. Induction over arbitrary records establishes lossless inspection of the installed actual entity owner. |
| Fresh publication | 3 | Failed preparation or refused publication retains both complete owners. Acceptance installs the supplied scene/manager plan and returns the complete callback journal and remaining constructor-time words. |
| Proposed registration order | 1 | The observed order of actual `fresh_added` equals the constructor order when the actual manager proposal order agrees with it. This consequence retains the proposal's cursor rather than advancing it again. |

The exact statements are in `src/entity_section_membership_recovery_laws.bend`;
their proofs are in `src/entity_section_membership_recovery_proof.bend`.

`Recovery.prepare` receives a saved `M.View`, the retained entity view/runtimes
and current `M.Chunk` facts supplied by the actual loader authority. The API
validates membership structure, record/runtime identity, registration order,
cached accessibility, actual finite boxes and loader observations before
reconciliation. The stated laws do not establish universal validator
completeness, loader authenticity or successful recovery of every valid image.
Missing evidence remains a refusal; decoded entity records alone cannot create
recovered registration.

Activation laws certify the actual acceptance/refusal branches over supplied
plans and acceptance results. Installation preserves the supplied record contents;
this target does not establish that every reconciled record differs from its
original only in Common accessibility fields. They do not prove that external acceptance means
a durable write. The fresh-order consequence assumes that the actual manager
proposal order equals the constructor order; it does not assert an
unconditional success theorem for arbitrary `fresh_prepare` inputs. Native
Java parity, complete scene adoption, IEEE geometry, save IO and rendering
require separate evidence. The 58-case native run against frozen production
`e48cd4c` is separate from this kernel verdict.

Six unsupported numerical cursor/capacity/preflight statements were removed
entirely from the active laws and proofs. Their obligations remain open:
the numerical capacity bound and maximum-boundary behavior of
`Recovery.constructor_capacity`, exact admission/refusal of
`Recovery.constructor_cursor`, the exhaustion preflight in
`Recovery.constructor_ready`, and numerical cursor refusal propagated through
the actual `Recovery.fresh_prepare` wrapper. The active proposed-order
consequence assumes cursor agreement; it does not prove any of those bounds.
The receipt explicitly retains the six removed goals as `unproved_obligations`:

- `constructor_cursor_accepts_exactly_one_advance`
- `constructor_cursor_refuses_any_disagreeing_advance`
- `invalid_constructor_cursor_preserves_both_complete_owners`
- `constructor_cursor_exhaustion_refuses_before_addition`
- `exhausted_constructor_cursor_preserves_both_complete_owners`
- `constructor_preflight_refuses_exhausted_retained_cursor`

Generation 2 accepted seventeen earlier pre-exhaustion-guard laws. Its original
4 MiB Node stack hit `RangeError` in `Safe.safe_emit`; 6 MiB completed that
export without compiler or proof-source edits for the stack workaround.
Later numerical obligations failed in ordinary checking with `RangeError` in
`term_higher`/`compare_go`, despite 6 MiB and an isolated 32 MiB Node stack.
These failures are retained under `build/entity-section-membership-recovery-proof/`:
generation 3 in `1791171807390907000`, generation 4 in `1791172050313479000`,
and generation 5 in `1791172144728096000`. The exact generation-5 failed source
snapshot manifest is
`build/entity-section-membership-recovery-proof/1791172144728096000/failed-source-snapshot.json`.
No failed attempt is counted as acceptance. Generation 8 certifies only the
remaining fifteen laws; no axioms or export exclusions manufacture that pass.

Reproduce the accepted target:

```sh
python3 tools/test_entity_section_membership_recovery_proof.py --generation 8
```

The harness checks the original production book once, dynamically selects only
declared checked pure law roots by changing `book.order`, and retains the
original declaration maps, types, source bodies and checked proof bodies.
The complete referenced closure must export with zero exclusions and receive
the pinned kernel's exact `ALL PROOFS CHECK` verdict. This certifies that
theorem closure, not a full-book verdict.

Each run retains source/toolchain pins, theorem-term pins, process receipts and
the emitted artifact in a fresh time-stamped build directory. Both success and
failure update `evidence/entity-section-membership-recovery-proof.json`; failed,
timed-out and interrupted attempts remain retained and clean up their process
groups. The successful generation-8 result supersedes the earlier summary
without deleting the historical successful and failed artifacts.
