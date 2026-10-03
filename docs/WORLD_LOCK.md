# Exclusive world lease

`world_lock.acquire(path)` returns an affine `Lease` or the OS error. The
persistence caller supplies the adjacent `save_path + ".lock"`, acquires it
before loading the save, and retains the lease throughout the simulation.
`release(lease)` consumes that owner and reports the close result.

The native boundary opens a regular file with `O_NOFOLLOW`, `O_CLOEXEC`,
`O_NONBLOCK`, and creation mode 0600, then requests `flock(LOCK_EX | LOCK_NB)`.
It preserves existing lock-file bytes. It never removes the lock file: retaining
the inode lets subsequent cooperating processes contend for the same lock.
Symlinks and nonregular objects fail. File checks, acquisition and release run
in the existing IO worker mechanism; formats and world decisions remain Bend.

These are BSD advisory semantics. The relevant contracts are Apple's
[flock manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html)
and [close manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/close.2.html).
They apply to cooperating processes. A stable parent and lock inode are required;
an external process replacing the lock inode is outside this contract. Network
filesystem behavior and hostile parent replacement have not been tested.

The pinned Bend compiler supports Base's opaque handle laws and explicitly
excludes user handle laws. `Lease` therefore wraps one affine `Base.File`; the
two raw effects use that supported descriptor representation. There is no new
axiom or unchecked handle law. The wrapper constructor is public to compiled
Bend code, so its type asserts ownership, not unforgeable acquisition provenance.
The persistence entry creates its lease only through `acquire`. JS reports an
unavailable effect rather than opening an unlocked world.

## Verification

Run `python3 tools/test_world_lock.py`. Native experiments pass:

- Eight simultaneous processes produce exactly one successful lease and seven
  immediate `EWOULDBLOCK` failures.
- An independent Python `flock` observer confirms exclusive acquisition.
- `SIGKILL` releases the kernel lease; five immediate reacquisitions preserve
  the original file inode and bytes.
- Different world paths remain independently available; explicit release
  permits subsequent acquisition.
- Symlink, directory, FIFO, missing/unwritable parent, and embedded-NUL inputs
  fail without modifying the target or waiting for FIFO IO.

Source and executable hashes are recorded in `evidence/world-lock.json`.
Confidence is high for these local macOS experiments. The lease does not prove
save-content durability, power-loss recovery, journal correctness, or the full
persistence objective. The two OS effects are foreign code and are excluded
from mathematical proof claims.
