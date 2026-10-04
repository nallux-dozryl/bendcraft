# Checked fall-reset supplier: R2 native results

The repaired host runner passes independent host, artifact and native-output
review. The frozen supplier and Java oracle are unchanged. One fresh native
build took 27.003444 seconds, with zero retries. Its executable SHA-256 is
`6311ff2c0623f1d5f95d560c4ef19243fadcc65afcf4bc56f768a533568a812c`.

Two complete runs each passed 107 admitted actual Java comparisons, 29 policy
and recovery cases, and 14 registry remaps. All 300 native processes passed;
complete comparison results were identical. Independent review replayed the
retained outputs through the unchanged comparator and checked commands, input
digests, captures, process statuses and cleanup. All 300 observed process
groups are absent, with no cleanup errors or unknown groups.

Receipts: `evidence/fall-reset-world-continuation-r2-build.json`,
`evidence/fall-reset-world-r2-artifact-review.json`,
`evidence/fall-reset-world-continuation-r2-native.json`, and
`evidence/fall-reset-world-r2-native-review.json`. Raw generations remain in
`build/fall-reset-world-continuation-r2/`. Original host failures, R1 and its
sealed preparation are retained.

This result establishes the explicit four-state, read-only, bounded supplier
contract. Unsupported states, missing sections, unresolved tags, outside cells
and exhausted work still refuse the query. The caller obtains an actual query
observation; it does not substitute a guessed MISS. The supplier's full-harness
kernel verdict has not been attempted in R2. The saved-player facade has now
enabled its exact additive reset call, but the changed saved consumer's native
and recovery acceptance remains pending.
