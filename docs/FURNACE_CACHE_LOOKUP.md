# Cached furnace lookup: retained diagnosis and narrow repair

The actual Actor023/Client012 ambient cooking consumer completed both 200-tick
recipes in an observed 67.00910229235888 seconds. That interval includes the
unpause RPC, repeated CookingInspect requests, and waiting for a completed
rendered image. It is not an isolated measurement of 400 actor ticks.

The retained Client012 timer begins after FrameCatalog, resource preparation,
and CookingInspect, and ends immediately after Window.frame. PPM extraction and
write, RGBA extraction and CRC, later inputs, and the next serial request loop
are outside it. The partial frame 10 to completed frame 28 span is 63.963584
seconds; the intervening frame 11–28 timer values total 6.141 seconds. The
remaining 57.822584 seconds cannot be assigned to an individual phase: the relay
has no per-request timestamps, and that consumer retained no CPU profile.
There was one catalog demand before frame 0 and no subsequent successful reload.

The emitted Actor023 C establishes a concrete defect independently of timing.
In `build/compiler-producer-diagnostic-023/diagnostic.c`, the cached lookup calls
K.plan at line 586421, then K.matches at 586585, then recursively evaluates the
whole remaining recipe list at 586712. Only afterward does it compare the cached
ID at 586839. For Cooking rows, K.plan validates the output through
R.create_output. R.item_definition likewise traverses its whole tail at 1432124
before its ID comparison at 1432193. These discarded alternative computations
are actual generated execution, not a guess about source-level laziness.

The pinned metadata supplies 2,042 ordered recipe IDs and 1,658 item-definition
rows. The same installed 26.3 JAR has 73 smelting, 25 blasting, 9 smoking and 9
campfire recipe templates. These counts describe the source data, not a timing
estimate. The empty-input tick branch skips cached selection; the retained
post-completion tick jumps are consistent with this expensive active-input
path disappearing. Their image timestamps and sampled Core ticks are different
boundaries, so they do not establish instantaneous TPS or its causal fraction.

The narrow production change branches on cached-ID equality before evaluating
either destination. An ID miss alone recurses. The first ID hit checks K.matches
before calling K.plan. It retains the first duplicate ID's result, even when an
Unsupported row, wrong kind or wrong input yields None. The existing ordinary
fallback still runs after that None. Invalid output still produces the original
Some Plan with an empty output; it does not become a cache miss.

Five new laws cover universal equality to the retained prior lookup and the
first-ID refusal/full-plan contracts. The focused native fixture has 18 complete
cached-plan goldens and 6 selection/cache/count/fallback cases, including exact
component identity and invalid output admission. The runner uses the frozen Actor023
pure imports plus the changed furnace source. All five laws passed the independent
kernel with no holes or export exclusions, and all 24 native cases passed with
one and four threads. See `evidence/furnace-authority-cache-001.json`. The complete
Actor024 Entry passed the original checker in 14.4763 seconds, with 9,588 order
events, 203 loaded files and unchanged source pins. Its 208 frozen source paths
match Actor023; only `src/furnace_authority.bend` differs. Actor024 emitted complete
C in 323.4662 seconds and compiled natively in 198.3368 seconds, with empty clang
stderr and all owned groups reaped. Its binary SHA is
`c8dd57c0f5cd6d3607bc932bf6bb74ce27009f8b90efa7db4309beea5d1e2cc4`.
No item lookup, metadata validator, simulation tick, timer, transport, renderer
or future subsystem is changed.

The separate original Actor023 actor-only diagnostic measured 400 actual cooking
ticks in 53.608212626 seconds, followed by 100 empty-input ticks in 1.455222291
seconds. Its ten paused clock/full-inventory/furnace observations passed. The
later host Close assertion was wrong about an empty return's revision; the
accepted actual Close retained revision 4, so the wrapper recorded failure and
its subsequent durable-save stage was unexecuted. The timings remain retained
observations, not a passed save consumer. See
`evidence/cooking-tick-throughput-023.json`.

The matched Actor024 run copied the same initialized, paused tick-213 save and
used the same actual production simulation.step batches. Its 400 cooking ticks
took 7.159371374 seconds, an observed 7.487837943-fold throughput improvement
over Actor023. Its subsequent 100 empty-input ticks took 1.391990042 seconds.
All ten complete clock, inventory, furnace-slot and timer observations passed.
This comparison removes renderer and PPM work and changes only the cached
lookup source, so confidence is high that the repair removes the dominant
avoidable cost in this synchronous cooking fixture. It does not establish
ambient cadence or explain every second of the earlier 67-second client run.

Actor024's authenticated Close retained revision 4, and its actual player.inspect
and typed atomic durable save completed. The 1,713,688-byte save has SHA
`01c716bb83a6b45e9f0200b511a431c4c51ec86d0d12da0503353daaecccb9ee`,
peer highwater 46 and journal sequence 6. All ten saved-owner checks passed,
including the complete 104-section Core, 43 inventory slots, physical furnace,
entity/RNG authority, incarnation map, empty effects and complete clean journal.
The retained original wrapper reported a host expectation failure: it expected
decoded max_peer None, but the actual ignition event's peer-0 stamp correctly
produced max_peer 0. Finalization checked the unchanged save against that source
contract without a native replay. See `evidence/cooking-tick-throughput-024.json`.
Actor023's later save stage was unexecuted, so there is no whole saved-byte A/B
equality claim.

Actor024's actual emitted C confirms the intended execution gates. Cached-ID
equality is evaluated at line 586400. The result branch at 586445 calls the
deferred tail only on a miss; a hit calls K.matches at 586563. Its false result
returns None, while its true result alone calls K.plan at 586813. The compiler
therefore retained the source correction in the full production artifact.

The actor timer advances each deadline by 50 ms from the previous deadline. Its
bounded mailbox preserves delayed pulses. Replacing that deadline with fresh
time could erase owed simulation ticks; this repair instead removes proven
discarded computation. The matched paused batches establish the scoped
throughput gain. Actual ambient delivery remains a separate acceptance boundary.

Reproduction after the coordinated timing window is released:

```sh
PY=/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3
"$PY" -B tools/test_furnace_authority_cache.py --native
"$PY" -B tools/test_playable_client_actor004.py --actor-generation 24 \
  --baseline-generation 23 --furnace-overlay src/furnace_authority.bend \
  --snapshot-only --native-seconds 600
```

The snapshot command does not compile or execute the actor. A whole original
Entry source verdict and one substantive024 producer/native attempt are separate
steps; runnable023 and012 remain available throughout.
