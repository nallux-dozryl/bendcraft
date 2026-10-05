# Player cooking menu

The cooking player adapter moves the existing cooking `CW.State` and existing
`I.State` through one transaction. It owns neither a Core copy nor another held
inventory. The actor keeps only a transient authenticated handle: menu ID,
player peer, block position/kind and per-position incarnation. There is no
restored menu handle after a save/reload.

`player_cooking_menu.open` receives a server-assigned ID and actual retained
player access. `dispatch` handles `MenuInspect`, `MenuPickup` (buttons0/1),
`MenuQuickMove` and `MenuClose`. Both take a complete correlated-reply admission
callback. It runs on the combined prospective furnace/player snapshot before
**either** owner commits. Refusal preserves the actual Core, ordered store,
furnace backing, complete player backing, raw saved abilities and menu state.
The Session join is Motion's `cooking_inventory_query` and leaf
`with_inventory_owner`; neither serializes or copies the owned Core.

The actual FurnaceMenu has39 slots: input/fuel/output0..2, main9..35 at menu3..29,
and hotbar0..8 at menu30..38. Equipment, temporary crafting cells and carried
remain in their authoritative player positions. Left/right pickup and quick
move are grounded in26 retained untouched Java26.3 menu observations. Output
quick move searches the player range in reverse; input/fuel searches forward.
Matching stacks merge before the first empty slot. Smeltable player items route
to input before fuel, and other items move between main/hotbar. Manual empty
bucket placement has capacity1. A nonempty compatible carried stack does not
extract the output slot in the observed pickup route.

`CWSlots.FurnaceTakeCount` is additive. It obtains exact component admission,
uses existing `FS.put_snapshot` and commits through `FA.commit`, preserving
hidden backing. Original Take/Set APIs stay intact. Furnace `RecipesUsed` is
retained: the actual Java output award requires ServerPlayer and the real
furnace block entity. This adapter does not clear recipe uses or invent XP/RNG
entities; the world award/entity consumer remains a dependency.

Open/slot mutation requires the retained nonzero Player peer, actual
`may_interact`, dimension, resident matching block owner and exact incarnation.
Vanilla stillValid uses a strict eye-to-block-AABB distance less than
`(actual block_interaction_range +4)^2`, after same block-entity identity.
The recorded default attribute is4.5; an eye at x9.5 beside BlockPos.ZERO is
refused. A loaded attribute override needs its actual attribute authority,
or an explicit unsupported refusal. Closing validates bound peer/menu ID and
can return the carried item even after moving out of range. It delegates the
existing real inventory return path; absent capacity and a real drop owner,
close refuses and retains every item/menu field.

`player_cooking_menu_campfire.use` has no GUI: it uses the actual selected slot
or offhand and saved instabuild. The retained CA placement path consumes one
item or keeps the creative hand, preserving its exact initialized patch. It
preflights the prospective player reply, then dispatches against actual resident
Core/campfire state. A world-use ray must select an authoritative target; this
adapter does not infer a target from a renderer or shadow inventory.
`use_hands` implements normal main-to-offhand order in the same actual owners,
inspected player snapshot, target and Access. Initialized component admission
and the supported campfire recipe domain classify the main hand before any
reply callback or publication. Only a valid empty/nonrecipe hand falls through;
security, malformed metadata, unsupported recipe domains, full campfires and
publication refusal do not. The final unchanged-owner no-input result is the
explicit `cooking-menu:campfire-hand-pass` message. Explicit `use(...,True)`
remains the offhand-only authority path. This avoids a second network request
with a different camera ray or target.

The new pure cooking screen receives the correlated full snapshot and actual
resolved resource icons. It uses the observed176x166 layout and native-to-logical
mapping through the existing viewport. Resize invalidates stored hover/pointer
coordinates; a too-small window shows RESIZE WINDOW and permits close without
sending a slot mutation. A missing furnace body retains all36 player cells and
marks only the three unavailable entity slots, so refusal does not hide items. Mouse0/1 sends Pickup; held sided Shift
sends QuickMove; E/Escape requests close. It retains modifier holds across
same-open acknowledgements and suppresses repeated held/pending actions. Focus
loss clears holds/hover and releases controls/capture while retaining an in-flight
request. Close refusals reconcile the still-open server handle and are visible. An OS
window-close request defers behind a pending action, then requests the actual
MenuClose. Only a correlated closed snapshot emits Quit; refusal keeps the
window/menu available so the player can make inventory space. Ordinary closed
world mouse and close events pass to the existing world controller. Progress
uses the raw timer words as signed Java ints, F32 division and the observed
clamp; lit duration0 uses the observed200 fallback.
A late close reply cannot capture unless the presenter freshly verifies native
focus. Carried rendering uses the actual native pointer producer; the controller
owns pointer metadata, not a cursor stack. Missing resource bindings retain the
existing explicit missing-icon mark. Hover shows the actual item identifier and
count. Coal/potato/cooked-food item textures are not yet supplied by the current
resource owner; no invented icon or localized-name parity is claimed.

Integration reservations: native-controls owns the additive cooking Wire codec,
real server ray target, client adapter and Presenter join. Motion owns actual
Session/Access/incarnation publication. Root owns the next coherent actor/client
artifact. Current public017/008 remains unchanged. Source and narrow receiver
verification do not by themselves establish a usable native cooking client;
that requires the joined authenticated event/reply/render/save boundary.

Evidence: `reference/player_cooking_menu.json` records26 menu cases, class hashes,
normal LocalPlayer initialization and raw receiver receipts. Its explicit
SimpleContainer/recipe-property fixtures do not establish furnace clock or XP
behavior. `tools/test_player_cooking_menu.py` compares those counts/routing while
separately checking full backing/profile/Core retention. It reuses the existing
cooking context and bounded runner; no historical corpus replay is required.

The current focused preparation contains26 Java furnace cases,9 full-owner
refusals,2 prior-handle/open-refusal regressions and14 single/two-hand campfire
guards. The retained campfire Java receiver passed a null entity: its False/True
case suffix distinguishes ordinary/soul campfires, not survival/creative.
Creative hand retention is grounded separately in the pinned
`ItemStack.consumeAndReturn`/`Entity.hasInfiniteMaterials` bytecode and is tested
as a production guard; it is not relabeled as a Java creative receiver observation.
Screen source check032 and focused receiver035 passed with empty stderr.
The scoped native receiver now passes all51 owner cases and28 synthetic
controller cases, including exact Java routing/counts, both real backing arrays,
raw status words, complete Core bytes and the new same-owner hand fallback.
One negative input was corrected because the inherited fixture explicitly has a
stone campfire recipe; the original observation is retained, and only the corrected
dirt input was rerun on the same binary. Source emission40.8957s/native compile
21.6502s, initial51-case receiver20.8621s, corrected single input11.5305s and
controller0.2301s are recorded in `evidence/player-cooking-menu-native.json`.
These are not isolated operation latency measurements or OS/native-window input
acceptance. Independent production theorem checks remain separately pending.

A later pinned class-bytecode inspection found a concrete display correction:
the flame requires signed `lit_time_remaining > 0`, uses
`ceil(clamped_ratio * 13) + 1` pixels and ends at panel y50; the cooking arrow
uses `ceil(clamped_ratio * 24)`. The working screen and six literal pixel-span
guards implement that correction. The existing51/28 receipt and frozen actor020
retain the earlier source. Focused generation003 now passes34 native synthetic
controller/pixel cases, including the six new spans, in0.6908seconds. Its complete
original source check, emission and compile passed; its exact150-file compiled
closure is retained. A subsequent unrelated item-component-effects source edit
is recorded explicitly in the receipt, so this is not a certification of the
entire current working import graph. The unchanged51 owner cases were not
replayed. See `evidence/player-cooking-menu-screen-native-003.json`. This display
correction preserves all four raw authoritative timer words and makes no OS
input or complete vanilla-resource appearance claim.
