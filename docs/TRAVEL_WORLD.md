# Owned finite-world travel

`src/travel_world.bend` joins the checked neutral dry-air travel phases to
the actual owned client world. It retains one `ClientWorld.State` engine and
one affine `Locomotion.Tables`. The operator performs no world tick, queued
mutation, terrain creation, or support sampling. Confidence is high for the
recorded finite fixtures; complete Player ticks and general travel remain
incomplete.

## Checked interface

```bend
travel_checked(state: W.State, tables: L.Tables,
               input: M.Vec3, context: T.Context)
  -> W.State & L.Tables & Result<&2,&2,Error,M.Transition>

type Error is Data:
  PreparationError{cause: T.Error}
  WorldMovementError{cause: String}
  FinishError{cause: T.Error}
```

The input is the exact binary64 input vector. The explicit `Travel.Context`
contains the supporting-block-aware `GroundSample`, current resolved
movement/gravity/friction/drag attributes, degree-valued Player yaw, maximum
step height, sprinting/no-gravity/friction-discard flags, and admitted mode.
The sample and neutral-context facts must be established by the caller.
Neither a last-support block nor a ground resolver is invented here. The
render view's yaw/pitch are independent radians and are retained unchanged.
The Context interface and admission limits are documented in `TRAVEL.md`.

The operation extracts the sole engine and immutable `W.View`, then calls
`Travel.prepare_checked` using the original body and retained Tables owner.
On successful preparation it places `Prepared.body` in an internal world
state and calls `W.move` with exactly `Prepared.requested` and
`Prepared.maximum_step`. This matters because collision restitution must
start with the accelerated velocity. `W.move` performs its checked reads
from owned Core sections, precise initial/step queries, ordered full-cube
collider enumeration, and checked movement.

After successful world movement, the operator calls `Travel.finish_checked`
exactly once. Only that final transition's body is installed in the returned
state. Calling the already combined `Travel.move_checked` here would apply
gravity and drag twice. Successful finishing changes body velocity while
retaining the movement phase's position, box, dimensions, displacement,
collision/ground flags, step outcome, and position-application gate.

Every failure returns the retained Tables owner and sole returned engine
with the complete original view, including its exact original body, camera,
palette, region, and raw snapshot cache. Errors identify the failed phase.
Preparation and finish errors preserve the structured Travel cause; world
query/movement errors retain the existing checked W error string. The
operator never advances the world clock, even when the world is unpaused.
It is an explicit travel call; scheduling it at an actual player tick is the
caller's responsibility.

## World and ownership boundary

World collision reads use the dynamically resolved air, stone, dirt, and
oak-planks palette from `W.new`/`W.fixture`. Air contributes no collision
entry. Missing sections, unsupported states, and queries outside W's finite
16-cell-per-side bounds fail explicitly. The supported world has static
full cubes, no other entities, and no close world border. Context-dependent
shapes and the broader travel branches remain outside this operator.

`W.take` and `W.attach` move the engine while `View is Data` permits retaining
the rollback view. Neither the engine nor Tables is cloned. Since operator
world access is read-only, retaining the original raw snapshot cache is
valid. Trusted external `Core.write_block`/`Core.apply` writes can bypass
revision and still require the explicit W cache invalidation documented in
`CLIENT_WORLD.md`.

Four narrow implementation laws cover rejected preparation retaining world,
view and Tables; rejected world movement restoring the original view;
rejected finishing restoring that view; and body replacement preserving all
other view fields. Bend's ordinary affine/type checker accepts these laws.
Whole-module independent kernel verification inherits the known Game/JSON
checker mismatch; no kernel-validity claim is made for this module.

## Native finite-world verification

```sh
python3 tools/test_travel_world.py
```

The test explicitly creates W's checked 39-block fixture: eight air sections
and 39 stone/dirt/planks cells produced by 47 admitted mutations. For each
bounded case, the Java reference constructs the same block map in its real
finite Level and runs untouched `Player.travel`, inherited LivingEntity
travel, and production `Entity.move`. It observes the actual supporting
position, friction, resolved attributes, float maximum step, accelerated
request, ordered initial/step shapes, post-move body, and finished body.
The Bend caller receives those actual resolved samples and attributes.

Thirty-one bounded cases compare prepared requests/friction/acceleration, both
ordered collision lists including full boxes, exact post-move bodies before
gravity/drag, and exact final installed bodies. Thirty-one supplemental actual
Entity movement observations must equal the Player observer's post-move
body and ordered shapes, and independently check the returned displacement,
step outcome, and position-application gate. Cases exercise airborne and
grounded acceleration, actual sprint attribute changes, modified friction
and drag, dirt and planks steps, negative cell boundaries, signed zero,
tiny requests, finite huge yaw, gravity/no-gravity, and friction discard.
An exactly touching dirt wall with a fully clipped request covers the false
position-application gate, alongside successful movement and step outcomes.
The reference fixture's declared local authority, suppressed bounce, no
other entities, distant border, movement emission NONE, and guarded dry
fluid-section service are described in `TRAVEL.md`; they are not evidence
of full ServerPlayer or saved-chunk execution.

All twelve unsupported modes reject and then successfully travel again
using the same world and Tables owners. Additional failures cover invalid
input, invalid supplied friction, missing sections, unsupported block
states, and an excessive finite query. A separate test injects malformed
finish data into the phase helper and observes rollback after
`finish_checked` rejects it. That is a failure-contract test, not an admitted
Player.travel case. These eighteen failure cases retain the original body,
view, and owners. Returned worlds remain usable for subsequent checked
snapshots, and the same Tables owner continues across requests. Body, all
view/cache fields, clock, pause/daylight flags, revision, pending count, and
event count are observed before and after. Paused and unpaused calls retain
their clocks. A valid registry with reordered state IDs yields the same
physical transition.

Dependency generations, native binary and table fingerprints, ordinary
checks, exact Java execution inputs/outputs, and scoped confidence are
recorded in `evidence/travel-world-verification.json`. The independent
kernel attempt is recorded in `evidence/travel-world-kernel.json`.
