# Resource-client Bun control result

The single granted watchdog invocation failed its plain-control protocol check. The child exited zero, but stdout and stderr were both empty. No `load.start` or other compiler phase record appeared. Boxed was not started; no retry, source patch, C emission, Clang, kernel or client run followed.

Exact command:

```text
PYTHONDONTWRITEBYTECODE=1 python3 build/resource-player-client-diagnosis-bun-watchdog/run_graph_probe.py --root-bun-watchdog-graph-slot-granted
```

The child PID/process group was 54823. The recorded host-supervision interval was 0.010486667 seconds, including receipt/process/cleanup overhead; this is not a compiler phase timing. Validation failed with `phase missing/duplicated: load.start`. The final group SIGKILL observation was `already-gone`, the leader was reaped, and a separate post-run check confirmed the group absent. Heavy Slot A was explicitly released and root acknowledged release.

Both zero-byte streams have SHA256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`. The full attempt receipt remains in `build/resource-player-client-diagnosis-bun-watchdog/plain-graph-result.full.json`, SHA256 `3dd0f76c43d6997c55ecf99c68da74c0dfb5178e866c8f3d0ba5416c676e7d91`. The post-attempt audit retained the original Node, Bun, watchdog and lineage pins and both 85/99-file live source/native/Base manifests unchanged. Historical preflight documents and receipts were not edited.

This result does not establish that the TypeScript probe started or that source modules loaded. It measures no source loading, checking, native graph traversal, templates or layouts. The reason for the empty runtime route remains unknown; version-only Bun discovery did not establish source-route compatibility. The two installed native timeouts remain unexplained. Confidence is high in the recorded refusal/cleanup/preservation and unknown in compiler attribution.

No compiler workaround follows from this invalid control. The next product experiment is the separately approved monomorphic resource presenter, with named concrete continuations and the same Scene/RF/WRF/actor/input/save paths. Its benefit remains unmeasured. It preserves the failed original and boxed entries and is a new integrated source generation, rather than another identical 600-second attempt.

The next granted build will use the actual installed Bend native emitter and guarded platform-cache route. Read-only process/RSS observations, narrowly bounded samples and actual C/artifact/cache phase receipts can assess that candidate. Samples whose JIT frames are unsymbolized cannot isolate checker versus backend work. Actual hidden TCP/edit/save/reload and CPU-frame readback remain the consumer acceptance target; a smaller harness or profile alone is insufficient.

The compact [result receipt](../evidence/resource-player-client-diagnosis-bun-watchdog-result.json) pins this failure. The [sealed preparation](resource-player-client-diagnosis-bun-watchdog.md) remains historical and unchanged.
