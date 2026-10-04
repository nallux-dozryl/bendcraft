# Reserved player block interaction

`src/player_block_interaction.bend` adds a bounded creative block action to the
actual saved LocalPlayer backend. `execute(engine,record,tables,abilities,held,
capability,sequence,button)` returns the same Engine and sine-table owners plus
`Outcome{changed,message}`. It reads the pose's cached eye height, raw Entity
degree angles, registry and Core world owned by that actor. It never requests a
renderer-selected position or state ID. The product logic remains in Bend.

The ray uses the exact installed 26.3 float degree multiplication and Mth sine
table, then the existing authoritative `fall_reset_world` block DDA. Its creative
reach is five blocks: the Java reference observes the actual Player attribute
base 4.5 and production creative modifier +0.5. Modded attributes, survival
digging, fluid hits and partial/contextual/interactable block shapes remain
outside this consumer. Air, cave air and void air are empty; stone, dirt, oak
planks, grass block and bedrock are admitted full cubes. An unsupported shape or
missing loaded section refuses the action before mutation. A bounded traversal
reads at most 32 cells.

Button 0 replaces the picked full cube with the registry's default air. Button 1
places the selected unmodified stone, dirt or oak-planks stack in the neighboring
face cell. Placement requires an empty admitted shape and a cube that does not
intersect the player's actual body box. Creative stacks are retained. Empty,
modified or unsupported held items, occupied cells and self-intersection return
unsuccessful outcomes. These rules implement the stated restricted domain;
they do not establish general Java placement, use-item or block-update parity.
Held-button repeat/cooldown, neighbor updates, drops and a general game-mode
interaction manager have separate outstanding behavior requirements.

`src/player_core_edit.bend` provides an additive admission boundary while the
existing Core mutation API remains unchanged. It requires a `Player` capability
with peer greater than zero, `maybuild`, a positive sequence, matching current
revision, valid dimension/state and an already loaded section. Only after those
gates does it call `Core.write_block`, followed by `Core.accepted` with the actual
`Stamp{worldTick,reservedPeer,privateSequence}`. Success increments the real Core
revision and emits its normal Applied event, so revision-based world samples
refresh and the existing save transaction persists the edit. Refusals retain
the world and emit no invented successful event.

`Backend.new_reserved` retains the capability supplied by the server's saved
peer reservation. The original `Backend.new` retains Observer and its actions
are denied. The private renderer sends only a button; it cannot supply a peer,
permission, block position or mutation. Action, Hotbar and Inventory share the
existing authenticated lease and strict sequence. Gameplay refusals consume a
sequence and produce ActionReply while leaving the connection usable. Stale,
unauthenticated and malformed protocol requests still fail closed. Public
developer requests retain their own session sequence and capability.

The independent pinned Java fixture
[`reference/player_block_interaction.json`](../reference/player_block_interaction.json)
contains 634 actual method observations: 215 VoxelShape clips, 215 iterable AABB
clips, 133 nearest directions, 70 Entity view vectors and one actual attribute
modifier observation. Two Java runs produced identical raw bytes. The seven
relevant production classes are byte-identical between the installed pinned
client and the official extracted server used for direct calls. The scoped
extraction chain passed in 7.619904 seconds with whole-group cleanup recorded
in `build/player-block-interaction-reference/extraction-chain/`; the compact
receipt is [`evidence/player-block-interaction-reference.json`](../evidence/player-block-interaction-reference.json).

The observed cube clip rejects squared ray length below `1e-7`, samples inside
at `from + delta*0.001`, uses inclusive-minimum/exclusive-maximum occupancy and
otherwise checks planes in X, Y, Z order with strict nearer-than comparisons.
Inside face selection narrows all three direction components to float, scans
Down, Up, North, South, West, East using strict float dot-score comparisons,
starts at Float.MIN_VALUE and defaults to North. These details resolve ties,
short rays and boundary samples without a tolerance heuristic.

Confidence is high for the recorded Java calls. CoreEdit, block interaction and
wire sources pass the ordinary checker; focused interaction assertions also
passed the default Bend JavaScript execution. This is distinct from native
backend break/place/save/reload acceptance. The focused
`tests/player_block_interaction.bend` and
`tests/resource_client_interaction_wire.bend` assertions are prepared for the
single combined native artifact. A direct raw Java replay admits only this
consumer's full-cube geometry domain; multibox/partial-shape observations must
not be counted as implemented. Visible physical-input acceptance remains a
separate recorded client requirement.
