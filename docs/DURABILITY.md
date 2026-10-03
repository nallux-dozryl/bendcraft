# File publication substrate

`src/atomic_file.bend` implements checked sequencing for publication of complete byte payloads. `src/durability.bend` supplies five narrow POSIX effects missing from the pinned Base File interface: exclusive creation, file synchronization, atomic rename, parent-directory synchronization and unlink. The native adapter interprets no Minecraft state or file format.

The capability gap is visible in `../bend/bend2/base.bend`: `File.open/read/read_bytes/read_at/size/write/write_bytes/close` expose neither exclusive creation nor a synchronization/rename operation. Base's `File.open("w")` uses `O_TRUNC`; using that to replace an existing save would expose partial writes. The added source leaves Bend and its runtime unchanged.

```text
Atomic.publish(path, suffix, bytes) -> IO(Outcome)
Outcome = Durable{}
        | NotPublished{code: U32, message: String}
        | PublishedUnsynced{code: U32, message: String}
```

The temporary name is `path + ".pending-" + suffix`, adjacent to the destination. A suffix contains 1–64 lowercase letters, digits or hyphens. Callers choose a fresh suffix; an existing temporary file or symlink fails exclusive creation without altering it. The temporary mode is 0600. Native `O_EXCL|O_NOFOLLOW` protects that final temporary component. There is no implicit directory creation or automatic deletion of another caller's pending file.

The sequence is:

1. Create the adjacent temporary exclusively.
2. Write the complete byte list using Base `File.write_bytes`.
3. Synchronize the file with `fsync`; on macOS also require successful `F_FULLFSYNC`.
4. Close the file and replace the destination through POSIX `rename`.
5. Synchronize the destination's parent directory with `fsync`.

`NotPublished` means this operation did not rename its temporary into the destination. After successful creation, errors attempt cleanup of that owned temporary. A cleanup failure is reported in the message. `PublishedUnsynced` means rename succeeded but directory sync failed: the new complete bytes are visible, and the caller must not interpret this as an unchanged destination. `Durable` means both native file and parent-directory sync calls reported success. The filesystem/device's guarantees are those of those OS operations; no Bend theorem establishes physical storage behavior.

The destination parent must remain stable during publication. This first path-based substrate does not provide a retained directory handle, world lock, concurrent writer arbitration, automatic orphan recovery, a journal, checksums or a world-save schema. Raw effects are module-visible and callers can bypass sequencing; normal callers use `Atomic.publish`. JavaScript effects explicitly return unavailable rather than pretending to implement macOS full sync. POSIX native macOS is the tested target.

`publish_with` accepts a compile-time stage hook, used by the test executable to pause after creation, writing, file sync, rename or directory sync. Normal `publish` uses a quiet hook. Hooks observe progress; they are not serialized save data.

## Evidence

`python3 tools/test_atomic_file.py` builds and executes the actual native effect boundary. Twenty cases use `SIGKILL` at the five publication stages, with and without an existing destination and with empty and nonempty new bytes. Before rename, the existing destination stays byte-identical or remains absent. After rename, the destination contains the exact complete new payload and no pending file. Additional checks cover stale/symlink temporary collisions, invalid bytes, suffix validation, failed opening/renaming and cleanup ownership.

The tests exercise process crashes on this filesystem. They do not simulate power failure or inject a parent-directory sync failure. The `PublishedUnsynced` branch is explicit but has no fault-injection evidence yet. Source/binary hashes, stage outcomes and compiler diagnostics are in [atomic-file.json](../evidence/atomic-file.json).

These five definitions are foreign OS effects. The test's `--check-only` correctly reports their dependent definitions as `SOME PROOFS FAIL`; native success does not turn them into proved effects. Pure helpers and sequencing introduce no axioms or unsafe recursion. This component supplies file publication only, not established Minecraft persistence/recovery parity.
