# Actor020 unfinished atomic publication consumer

`tools/test_playable_client_cooking_atomic_crash.py --actor-generation 20` is a
separate consumer for the already verified immutable Actor020 binary. Current
status is **prepared file-only; crash-window execution is pending**. It does not
build, change source, install stage hooks or repeat the earlier five-save entity
consumer. That consumer's actual final format3 snapshot supplies the complete
player/inventory/equipment/status/generation and two Item/one Orb owner.

The new fixture retains those exact owners and the legacy generation bytes,
expanding the resident Core to 104 sections with 425,984 cells. Existing section 0
and its y7 floor remain exact; added sections contain authenticated air. The
independent old/new images are 1,714,636 and 1,714,835 bytes in preparation.
Actual runtime peer and admission sequence values are observed through TCP.

Preparation:

```sh
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -B tools/test_playable_client_cooking_atomic_crash.py --actor-generation 20 --expectations
```

The eventual separately coordinated run substitutes `--native`. It reuses the
existing 600-second bounded process owner, actual actor/TCP journals and cleanup.
It does not signal the user's unrelated 012 actor. The prepared receipt is
`evidence/playable-client-cooking-atomic-crash-prepared-003.json`.

The frozen writer protocol is concrete:

1. Extended persistence calls `Atomic.publish` with suffix
   `save-<peer>-<incremented session sequence>`.
2. The native durability adapter exclusively creates
   `<destination>.pending-save-<peer>-<sequence>` with no symlink following.
3. `File.write_bytes` first converts the complete byte list to an owned native
   buffer, then invokes a POSIX `write` loop. A short write causes another write;
   a negative result returns failure.
4. Successful byte transfer is followed by file `fsync` and macOS `F_FULLFSYNC`,
   close, rename to the destination, and parent-directory `fsync`.

Production uses the quiet stage callback. The frozen generated C contains the
actual transfer loop at line 1631795 and buffer conversion at line 1631827; the
prepared receipt pins its exact 63,107,010-byte image. An empty temp can precede
the first OS write, while a full temp can await sync or rename. Neither alone
qualifies as this consumer's unfinished payload witness.

The planned actual sequence acknowledges and byte-compares a full large format3
baseline. It then admits a stone block replacement at the next Core tick and a
distinct day-time change at the following tick, leaving both actions pending in
the independently expected new image. Saving starts through the real quiet
`world.save` TCP operation. A host monitor observes only the actual temporary
file belonging to that request.

SIGKILL is sent only after a regular-file observation satisfies
`0 < size < expected new-image size`, with a nonempty actual prefix matching the
independent image. The runner records inode/device, measured size, prefix hash,
observation and signal times, and the actual raw request. It retains the same
open inode and all available bytes after process exit. The signal is sent to the
registered owned actor group, then the existing teardown verifies reaping and
listener disappearance.

The observation-to-signal interval permits the writer to finish and rename.
Consequently the canonical destination must be **exact old or exact complete
new bytes** after reaping. The runner records which image won and whether the
same-inode retained payload is still incomplete. It never infers a syscall or
stage from elapsed time. A partial payload also cannot distinguish a running
transfer from failure cleanup without syscall tracing; the exact active effect
remains UNOBSERVED.

Cold startup must decode the chosen complete Core and all player/entity fields
under the same lock inode. Two actual Core/player ticks then apply the selected
pending action set exactly once: zero restored actions for old, two for new.
The final full atomic save compares the independent Core/event queue plus the
complete unchanged entity View, factory, RNG, IDs, empty effects and clock inputs.
This checks complete-image recovery and action replay continuity without a
shadow world or a host-side game implementation.

If only empty/full temporary states or a completed save are observed, the result
is **UNOBSERVED** and the runner sends no witness-driven SIGKILL. It retains the
size transitions, actual reply or transport fault and destination identity. No
crash-during-write success is manufactured from a missed window.

The first file-only preparation exposed the old small consumer's outer NBT
reader element bound at the new large ByteArray. The new runner uses an explicit
33,624,064-byte/element outer reader; the verified entity consumer is unchanged.
The failure is retained in
`evidence/playable-client-cooking-atomic-crash-prepared-failure-001.json`.
Preparation 003 passed complete old/new framing checks. Confidence is high in the
inspected protocol and retained source identities; actual crash-window behavior
is unknown until this separate native attempt. Physical power loss and precise
inside-syscall interruption remain outside its scope.
