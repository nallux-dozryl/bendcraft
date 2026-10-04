# Passive observation of the concrete resource presenter build

Confidence is high in the distinction this observation can measure: publication of checked native C versus compilation of that C. Attribution within installed Bend remains unknown. The two sealed resource entries each reached their 600-second cap without C. The Node graph control failed during loading, and the Bun control returned empty streams without a phase record. Those diagnostic routes supplied no usable graph comparison.

The next consumer is `resource_player_presented_client.bend`, with the new monomorphic presenter owned by `client_render`. Its named continuations call the frozen scene snapshot/draw methods directly and retain the same Session actor and input handling. This is a source experiment with an unmeasured compiler benefit. The existing sealed original/boxed sources, references, helpers and failure receipts remain unchanged.

The observer is the ignored host tool `build/resource-player-presenter-build-observer/observe.py`. Default invocation prints its plan and hashes; `--selftest` performs eight Python-only assertions. Neither route starts a compiler, sample, native client, kernel, UI operation or input operation. Preparation also read the current Python process path without launching another runtime. Homebrew's Python launcher and the live `Python.app` executable are different files; attachment checks the requested launcher and the actual executable of this same interpreter, rather than treating the launcher path as the live process path.

## Hypotheses and resulting decisions

| Hypothesis | Falsifiable observation | Next decision |
|---|---|---|
| The concrete presenter bounds the resource callback specialization admitted by the generic presenter. | The normal installed build emits C within its unchanged budget, with retained C size/function metrics and the same intended resource consumer. | Finish the actual hidden TCP/edit/save/reload/pixel suite. Compare resulting behavior, without claiming an isolated compiler cause or game speedup. |
| Resource visibility/draw/parsing still produces expensive installed lowering or emission after removing that generic callback. | Installed Bend remains active without C; the single authorized stack sample may show source symbols, and RSS records describe allocation pressure. | If the sample supplies usable attribution, propose one narrow source change to that consumer. If it is unsymbolized, keep attribution unknown and preserve the failure; no identical retry. |
| C completes, while native Clang dominates the remaining build. | The cache receipt separates its C CLI duration from native compilation; the observer sees the actual generated-C command rather than SDK dependency probes. | Evaluate the retained C and native compiler phase. Do not change or bypass checking based on RSS or nominal wall time. |

The checked C CLI combines loading, type/ownership checking, native lowering and C writing. No instrumentation has been added to separate those internal phases. A `/usr/bin/sample` stack whose addresses cannot be mapped to those bodies cannot resolve them.

## Attachment contract

The consumer runner owns the one normal guarded build and its 600-second process-group deadline. After root grants that sealed build, its immediately printed lifecycle supplies a request with exactly these fields:

```json
{
  "process_group": "actual integer PID/PGID from the build lifecycle",
  "started_monotonic": "actual numeric lifecycle timestamp",
  "deadline_monotonic": "actual numeric lifecycle timestamp + 600",
  "build_argv": "actual eight-element platform_cache.py build argv",
  "entry_sha256": "final sealed consumer entry hash",
  "bend_sha256": "99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e"
}
```

The quoted descriptions are placeholders, not an executable request. The observer validates the entry/compiler hashes, the exact guarded build route/output directory, its same Python launcher, the live controller executable and CLI tail, and the owned process group. It queries process names/RSS/elapsed time every five seconds, retaining only owned rows. It never requests process environments or unrelated command lines. For installed Bend and owned Clang only, it reads the actual argv and records commands recognized as `.source-*/original.c` emission or `.native-*/generated.c` native compilation. Dependency scans, `-###` probes, framework link probes and ordinary `--check-only` calls are not relabeled as these phases.

The exact attachment command is:

```text
PYTHONDONTWRITEBYTECODE=1 python3 build/resource-player-presenter-build-observer/observe.py --observe --root-observer-granted --request build/resource-player-presenter-build-observer/request.full.json --report build/resource-player-presenter-build-observer/attempt-1/result.full.json
```

The attempt directory must be new and exclusive. The request is derived from the live printed build record; no attachment or native build has run during preparation. Root has approved the passive observation and one sample, while the sealed consumer's actual build remains pending its explicit grant.

## Bounded sample and retained evidence

When a verified installed emitter reaches approximately 60 seconds, the observer may take one sample:

```text
/usr/bin/sample ACTUAL_VERIFIED_EMITTER_PID 1 -file build/resource-player-presenter-build-observer/attempt-1/emitter-PID.full.txt
```

It rechecks process path, entry/output argv and membership immediately before sampling, then rechecks the remaining build budget. It skips the sample if fewer than 20 seconds remain or the emitter no longer matches. A requested one-second sample can have more host overhead. The exact frozen host watchdog (`run_graph_probe.py`, SHA256 `7e0ac980d50ac94a488f3e2db042342604f6580251b2acc85771b760b9c615b0`) supervises only the new sampler process group: nine seconds plus two seconds TERM grace, half a second pipe drain and half a second final cleanup, at most 12 seconds for pipes/wait. Its legacy receipt filenames contain `graph`; this invocation starts `/usr/bin/sample`, with no TypeScript/source loading. It cannot signal the build group. The observer never extends the build deadline or owns build termination.

The ignored receipt stores observation timestamps, owned process rows, actual recognized commands, first observed C-file existence, sampled stack hash/size, sampler lifecycle/cleanup and any observation errors. First-seen timestamps have a polling delay; macOS `ps` elapsed values have one-second resolution. The normal platform-cache receipt remains authoritative for C/native durations, source/transformed-C hashes, exact SDK/effect/compiler closure and immutable executable hash. Subsequent compact diagnosis should reference those receipts and analyze the retained C only after the build, then report the actual product integration result. Stack samples, frame logs and CPU image readback cannot establish visible presentation or held OS-input acceptance.

Preparation's Python-only checks passed eight assertions covering elapsed parsing, owned-group filtering, recognized entry/output routes, rejection of the boxed entry and Clang probes, and the fixed installed compiler/supervisor hashes. The earlier Python launcher/live-path mismatch was corrected before attachment and retained as a read-only preparation observation. No installed compiler, Clang, kernel, native client or sampler was executed by this preparation.
