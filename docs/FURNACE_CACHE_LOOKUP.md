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
match Actor023; only `src/furnace_authority.bend` differs. The actor native build and
candidate performance measurement remain pending. No item lookup, metadata
validator, simulation tick, timer,
transport, renderer or future subsystem is changed.

The separate original Actor023 actor-only diagnostic measured 400 actual cooking
ticks in 53.608212626 seconds, followed by 100 empty-input ticks in 1.455222291
seconds. Its ten paused clock/full-inventory/furnace observations passed. The
later host Close assertion was wrong about an empty return's revision; the
accepted actual Close retained revision 4, so the wrapper recorded failure and
its subsequent durable-save stage was unexecuted. The timings remain retained
observations, not a passed save consumer. See
`evidence/cooking-tick-throughput-023.json`. This eliminates renderer and PPM
work from that measured cooking cost; only the matched candidate comparison can
attribute an improvement to this sole source change.

The actor timer advances each deadline by 50 ms from the previous deadline. Its
bounded mailbox preserves delayed pulses. Replacing that deadline with fresh
time could erase owed simulation ticks; this repair instead removes proven
discarded computation. Root's separate original023/candidate actor-only batch
measurement must isolate throughput before any speedup claim. Actual ambient
delivery remains a separate acceptance boundary.

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
