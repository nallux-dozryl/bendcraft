# Owned support sampling and updates

`src/support_world.bend` connects the frozen support operations to the sole world held by `client_world.State`. It reads actual checked Core sections and dynamically resolved `air`, `stone`, `dirt`, and `oak_planks` states. It advances no simulation clock, applies no world edit, and constructs no terrain. Its scope is the finite, local-authoritative neutral movement instrument; a complete entity, player, server, or client tick is not implemented here.

The checked interfaces are:

```bend
sample_checked(W.State, S.State)
  -> W.State & Result<&2, &2, Error, Sample>
update_checked(W.State, S.State, M.Transition)
  -> W.State & Result<&2, &2, Error, S.State>
update_retained_checked(W.State, S.State, M.Transition)
  -> W.State & S.State & Result<&2, &2, Error, Unit>
update_with_movement_checked(W.State, S.State, Maybe<&2, M.Vec3>)
  -> W.State & Result<&2, &2, Error, S.State>
```

`Sample` is immutable Data containing `ground: Travel.GroundSample` and `jump_factor: F32`. Errors distinguish support admission, missing palette, body mismatch, world read/admission failure, and a non-full-cube collider. `error_text` formats them. Each operation returns the original owned world/view, including the render cache, after reads. `update_retained_checked` additionally returns the original support history on rejection. The result-only update API leaves that immutable prior history available to its caller.

Sampling first validates the body position and computes the actual supporting-aware below position with the exact float offset `0x3f000011`. If history contains a cached coordinate, its current block is checked before sampling. A coordinate never certifies a block identity: a removed cached block must still be read and admitted as air. The current and below cells are both read, including when a non-unit current jump factor would select the current value. The ground sample contains the below position and its friction; the jump factor follows the actual current-first unit-factor selection.

Fresh pinned 26.3 Java observations establish friction `0x3f19999a` (0.6f), jump factor `0x3f800000` (1.0f), and absence of fence, wall, and gate classifications for all four admitted blocks. The bridge stores these measured properties for that explicit palette. It does not assign them to arbitrary blocks. Missing sections and unsupported cached/current/below states are explicit errors.

Updates derive the exact primary support slab and optional backward fallback slab from `support.queries_checked`, collect ordered full cubes through `client_world.collect`, and apply the frozen actual distance/tie selection and cache-history rules. Candidate coordinates remain signed Java-int words and geometry remains exact F64. Only canonical unit boxes become candidates; air contributes no collider. The existing bounded collector admits at most 16 cells along each query axis and rejects unsupported states encountered by its checked reads. It neither supplies empty-context shapes for other blocks nor silently treats unloaded terrain as air.

`update_checked` requires the returned transition body to match the world's body bit-for-bit, including position, box, velocity, dimensions, and flags. It passes `Some(transition.displacement)` for every successful admitted move, even zero displacement and even when `position_changed` is false. The actual local-authoritative `Entity.move` support call is outside its position-application gate. `update_with_movement_checked` exposes explicit null history separately: null and a present zero vector have different fallback/cache semantics.

The neutral integration order is: sample the prior world/support; build `PlayerTick.Context` with that sample and explicit resolved attributes, yaw, gravity/sprint/friction flags, and jump strength; run `PlayerTickWorld.tick_checked`; then update support from its successful movement transition. Actual Java updates support inside `Entity.move`, before the later gravity/drag and player metadata phases. Applying this bridge after the returned neutral movement gives the same support state because its selection reads only position, box, grounding, and the resolved displacement. Blocks with mid-move or post-move effects remain outside admission. A caller composing several operations must retain its original view/player/support and restore them if a later phase rejects; this read-only support operator itself preserves its incoming view.

Support reads do not use the render block cache. A trusted direct `Core.write_block` or `Core.apply` may change terrain without incrementing the world's revision. The bridge therefore observes those cells immediately while preserving the incoming render cache. Such callers must still invoke `client_world.invalidate_cache` before relying on a new rendered snapshot, and must maintain the registry/palette contract when changing the engine or registry directly. Checked queued edits update revision through the normal Core boundary.

Run `python3 tools/test_support_world.py` to rebuild and compare, or `--skip-build` only when the saved binary and every compiled dependency hash match. The harness imports production modules only, keeps one affine World and sine Tables, and carries native player/support state across sequences. Its fresh Java adapter observes untouched `Player.aiStep`, `Entity.move`, supporting queries, and sample helpers in the same 39-block checked fixture. Explicit setup edits use Core admission and a tick boundary outside the operator; the separate direct-write regression deliberately bypasses revision. The bounded corpus includes held input/jump, a real step, blocked application gates, seams/ties, negative boundaries, overhang, a successful fallback, null/zero history, queued removal/repair, dynamic registry remapping, and rejection followed by continued owner use.

Ordinary checks and native/oracle comparisons are recorded with source, binary, table, and pinned-JAR provenance in `evidence/support-world-verification.json`. The two ownership laws are ordinary checked equations; whole-module kernel checking inherits the existing Game/JSON formal/ordinary quantity mismatch and must not be reported as a complete kernel proof. The support operations themselves have their separately recorded independent kernel and actual-Java evidence.
