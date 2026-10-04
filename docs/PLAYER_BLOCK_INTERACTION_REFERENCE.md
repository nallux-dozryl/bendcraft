# Pinned ray geometry and block reach reference

Confidence: **high for the recorded direct production method calls**. These
observations do not establish complete player picking, block interaction,
placement, digging, permissions, packets, or contextual shape parity.

The extractor is tools/reference_player_block_interaction_probe.py; its durable
fixture is reference/player_block_interaction.json, with summary evidence in
evidence/player-block-interaction-reference.json. It uses the official pinned
26.3 server classpath after checksum verification. Every observed owner
(Direction, AABB, VoxelShape, Entity, Player, ServerPlayer, Attributes) was also
checked byte-for-byte against the installed 26.3 client. All seven complete
production classes are identical.

## Observed production behavior

- VoxelShape.clip first rejects an empty shape, then rejects a ray whose
  delta.lengthSqr() is **strictly less than 1e-7**. This is a squared-length gate,
  separate from the AABB component-delta gates.
- Its inside test samples **start + delta * 0.001**, checks the discrete shape
  cell containing that sample relative to the supplied block position, and
  returns that sample as the hit location. The inside face is the opposite of
  Direction.getApproximateNearest(delta); inside is true. Unit-shape sample
  membership includes the minimum bound and excludes the maximum bound.
- When that sample is outside, VoxelShape.clip delegates to AABB.clip over its
  realized boxes. The extractor records those boxes rather than assuming shape
  construction preserves every source bound or box ordering.
- AABB planes are visited X, then Y, then Z. A component contributes a candidate
  only when it is greater than 1e-7 or less than -1e-7. Candidate parameter
  acceptance is **0 < t < currentBest**, with initial best 1. Exact face ties
  preserve the earlier axis. Exact hits only at the segment endpoint are
  rejected. Each transverse coordinate must lie strictly within
  (minimum - 1e-7, maximum + 1e-7).
- Across an AABB iterable, equal-distance candidates preserve the first box's
  accepted face. Reversing two tied boxes in the recorded fixture changes the
  selected face from WEST to DOWN.
- Direction.getApproximateNearest(double,double,double) narrows each component
  to float and calls the float overload. That overload starts with NORTH and a
  score of Float.MIN_VALUE, computes float dot products, and updates only on a
  strictly greater score while iterating DOWN, UP, NORTH, SOUTH, WEST, EAST.
  There is no normalization. Ordinary largest-magnitude ties therefore favor
  Y, then Z, then X. Zero vectors and positive single-axis magnitude exactly
  Float.MIN_VALUE return NORTH.
- Entity.calculateViewVector(pitch,yaw) computes float
  pitchRad = pitch * 0.017453292f and yawRad = (-yaw) * 0.017453292f, then calls
  the production table-based Mth.sin/Mth.cos using the widened float radians.
  Its returned vector is
  (double(float(yawSin*pitchCos)), double(-pitchSin),
  double(float(yawCos*pitchCos))).
- The production player block-interaction attribute defaults to **4.5**.
  Applying the reflected private ServerPlayer modifier
  minecraft:creative_mode_block_range with amount **0.5** and operation
  ADD_VALUE through the actual AttributeInstance yields **5.0**. Removing that
  modifier restores 4.5. This observes the attribute calculation and production
  modifier; it does not execute a complete ServerPlayer game-mode transition
  or player picking.

## Extraction and verification

The retained extraction contains **634 cases**:

| Actual operation | Cases |
| --- | ---: |
| VoxelShape.clip | 215 |
| AABB.clip | 215 |
| Direction.getApproximateNearest | 133 |
| Entity.calculateViewVector | 70 |
| Actual block-reach attribute/modifier calls | 1 |

Inputs include squared-length and component-delta boundary neighbors, signed
zeros, float narrowing ties, inside sampling boundaries, exact edge/corner
ties, transverse epsilon boundaries, translated block positions, empty shapes,
a slab shape, multiple boxes in reversed orders, and seeded random rays and
nearest-direction vectors. Every expected result comes from an actual
production Java call; Python generates inputs and records/verifies observations.

The authorized extraction chain compiled one Java source, ran it twice, and
retained seven bytecode inventories. Both observation files are byte-identical
(SHA-256 81017fd705d1478e460ab70df3ddf881d17edd0846dedfd3e6c1d8188a17e219).
The outer chain exited 0 in **7.619904 seconds**, with no timeout or failure.
The cleanup receipt records PGID **32263** absent before and after cleanup.
No client, window, server, or world was launched.

Raw source, inputs, outputs, logs, and bytecode inventories are retained in
build/player-block-interaction-reference/. The extraction-chain subdirectory
contains the preopened stdout/stderr captures and request, start, execution, and
cleanup receipts.

Reproduce extraction from the project directory:

    python3 tools/reference_player_block_interaction_probe.py

Verify retained observations without launching Java or a compiler:

    python3 tools/reference_player_block_interaction_probe.py --verify-existing

Prepare source and inputs without launching Java or a compiler:

    python3 tools/reference_player_block_interaction_probe.py --prepare

The verifier regenerates all inputs, checks source/tool/runtime/classpath
identities, verifies all recorded owner class hashes against both pinned jars,
requires exactly two byte-identical raw observation files, compares the durable
fixture exactly to those observations, checks retained source/log/bytecode
inventories and the evidence fingerprint, and reruns directed semantic
assertions.
