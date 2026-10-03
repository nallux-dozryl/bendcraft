# Logical keyboard input

`src/player_input.bend` maps seven logical buttons to the actual 26.3
`KeyboardInput.tick` movement vector. Forward/backward and left/right cancel
when both or neither are held. Cardinal impulses retain exact ±1f/+0f; diagonal
impulses are exactly ±`0x3f3504f3`, from actual float normalization. Jump, shift
and sprint stay in the button record and do not change this vector. Forward
impulse uses the actual strict `>1.0E-5f` test. This is a complete implementation
of this finite logical input projection, with no claim about LocalPlayer's
later slowdown, pose, ability, sprint or field-assignment rules.

`Buttons` retains all seven flags. `sample` returns the unchanged buttons,
`Vector{left,forward}` and `has_forward`. `Bindings` explicitly supplies seven
U32 event codes; `key` applies both press and release, updates every duplicate
binding and tolerates repeats without accumulating movement. `clear` releases
every button; `make_jump` sets jump without changing the others. `from_mask`
and `mask` expose the seven low bits. OS keyboard mappings and focus/capture
remain a caller boundary and require visible acceptance evidence.

The diagonal specialization applies only to the nine movement vectors produced
by these logical buttons. It does not purport to normalize arbitrary float
vectors. Five narrow laws cover cancellation, selected/unselected event
updates, clearing and injected-jump field retention.

`python3 tools/test_player_input.py` calls untouched actual KeyboardInput.tick
and ClientInput methods twice for all 128 button combinations, using controlled
KeyMapping state without opening a window or creating a Minecraft instance.
The native harness also checks independent logical press/release expectations
against those actual Java numeric outputs, including duplicate bindings,
high unsigned codes, repeats and chained held states. These checks cannot
substitute for real OS input or continuous player simulation. Exact observed
scope, provenance, source/binary hashes and confidence are in
`evidence/player-input-verification.json`.
