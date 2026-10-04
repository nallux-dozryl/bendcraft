# Player inventory consumer

The native `remote_resource_client` inventory controller is a pure Bend module,
`src/player_inventory_screen.bend`. Its `Frame` retains the full server
`I.MenuSnapshot` and pinned item catalog. It owns input latches, UI references,
filter and request state; the server owns every stack, including the carried
stack. Native integration is a presenter join, not a web interface.

## Actual state and topology

The verified Java 26.3 `InventoryMenu` has 46 slots: crafting output0, four
crafting inputs1–4, head/chest/legs/feet5–8, main inventory9–35, hotbar36–44,
offhand45. The durable equipment backing additionally retains BODY and SADDLE
without inventing player-menu cells for them. The main 36 snapshot is an explicit
legacy projection. Full menu replies retain all 43 durable slots, four temporary
crafting slots, carried stack, output availability, selected slot, seven saved
ability values and menu revision.

The item table has 1658 registry rows, including air. Runtime definitions come
from the verified `generated/reference_item_metadata.tsv`; the controller
browses every enabled non-air default item. Stack limits come from actual table
metadata. Equipment admission derives from observed default equippable
components. Modified component patches remain a required item-component
consumer, rather than being interpreted as unmodified defaults.

Crafting output `None` means that the recipe derivation consumer is absent. The
screen marks this explicitly. It never manufactures an empty output stack.
Crafting and carried items are ephemeral menu ownership and are excluded from
the version 3 durable codec. MenuClose now plans carried-item return before the
four crafting inputs, using the pinned Java receiver's insertion order. It
commits the complete owned inventory only if every temporary item fits and
every item count is conserved. Otherwise it retains all slots, the derived
result, abilities and open menu. The actor has no item-entity/drop ownership
consumer, so the capacity-exhausted world-drop branch remains an explicit
refusal. Save itself still refuses nonempty temporary ownership. Successful
close clears the derived output cache; it never inserts that cache as an item.
See `docs/PLAYER_INVENTORY_CLOSE.md` for the executed receiver scope and complete
ownership contracts. Version 3 stores equipment, complete saved ability fields and
typed world-generation settings; legacy/default and eligible version 2 payload
bytes remain exact.

## Interaction and integration

`step_frame(frame, viewport, event, focused, captured)` returns a `Decision`:
the retained authority frame, ordered typed intents and whether world controls
must consume this event. `acknowledge(frame, latest, accepted)` installs the
complete correlated reply and returns a decision. The presenter must validate
wire epoch, sequence and snapshot before calling it. No optimistic stack update
occurs locally.

E opens through MenuOpen. E/Escape requests MenuClose. The menu stays open and
capture remains released until the server accepts close; a refused close keeps
its owned stacks visible. Opening and closing consume their triggering event.
Key repeats and held mouse buttons are latched. Focus loss releases controls,
closes the local interface, clears references and retains the in-flight request;
its later reply cannot recapture an unfocused window. While the menu is open,
movement, relative Look and scroll events are consumed. A captured host cannot
emit a menu mutation until actual capture is released.

`observed(controller, snapshot)` reconciles the authority's open flag only while
focused, idle and holding a structurally valid snapshot. It retains every latch,
reference and pending request otherwise. `synchronize_authority` combines this
observation with current host focus/capture, and `step` uses that composition
before each event. Refocusing into a server-open menu therefore releases capture
and consumes world input. A fresh host status must still gate any delayed
presenter request to recapture the mouse.

The PLAYER tab issues typed left/right Pickup clicks to actual menu indices.
The MOVE tab is an explicitly custom direct slot-to-slot workflow: choose a
main-inventory source and target, then transfer all or one. It creates no owned
cursor stack and makes no vanilla click-parity claim. ITEMS shows 45 creative
palette cells, table-backed pagination and an ASCII identifier filter. Palette
selection followed by a main/hotbar target emits Acquire with the observed
maximum or one; server instabuild is authoritative. Digit keys emit Select.

The block/backend owner implements additive private Transfer6, Acquire7,
MenuInspect8, MenuOpen9, MenuClose10, MenuClick11 and Select12 commands.
MenuReply6 carries the exact accepted/refused result and latest full actor
snapshot; ordinary inventory movement is Player-authorized without a maybuild
restriction. Old public/main interfaces remain separate. QuickMove, Swap,
Clone, Throw, QuickCraft and PickupAll are typed protocol kinds; their remaining
runtime semantics, recipes, item effects and world-drop authority are explicit
implementation dependencies, not three-item product limits.

## Presenter contract

`Viewport{width,height,native_width,native_height}` uses logical HUD dimensions
and actual drawable dimensions. The presenter first converts native content
points to drawable pixels; relative Look deltas remain unchanged. Both hit
mapping and native painting use floor(pixel*logical/native), with strict bounds
including outside drag sentinels. Logical menu layout remains independent of
internal scene render scale. `draw_native` overlays the menu after scene
resampling, preserving sharp slots, counts and text at HUD scale.

`prepare(frame, item_icons, legacy_icons)` accepts actual resource/model textures
keyed by item identity. The established three block textures are a real-resource
fallback. Every unresolved model is marked visibly and remains acquirable by
actual authority. All 1658 item models, player preview, translated resource fonts
and native visual acceptance are concrete presenter/resource dependencies.
The custom compact pixel alphabet and gray beveled structure establish a native
interface but do not establish vanilla pixel parity.

## Verification boundary

`player_inventory_screen_laws/proof` bind production event/reply paths to full
snapshot/catalog retention, repeated focus-loss composition and owned inventory
refusal/open-close behavior. The observation gate retains the entire controller
when authority cannot be admitted. All nine production laws passed the
independent kernel with zero proof holes or omitted dependencies in
`build/player-inventory-screen/selective-export-002`. Successful transfer arithmetic reuses the actual
existing `inventory_laws/proof` kernel; there is no separate menu arithmetic
model or axiom. Whole-array successful transfer conservation is still exercised
by independent fixtures rather than claimed from a new tiny projection.

`tests/player_inventory_screen.bend` and
`tools/test_player_inventory_screen.py` provide literal controller snapshots,
27 controller cases, 46 native slot-hit cases and all 1658 real table definitions,
including their default component identity and stack limit.
The host helper accepts an admitted executor callback and never builds or
launches processes independently. Source checks, independent-kernel verdicts,
native fixture execution and OS capture/render checks are distinct receipts.
No UI/native test has been run merely by preparing these files.

The existing `tools/test_player_inventory.py` now also provides independent
format 3 fixture construction with `inventory_full_root`/`inventory_full_bytes`
and a separate `parse_inventory_full` durable projection. These retain the
seven equipment stacks, all five additional ability fields as raw words and
the exact standalone generation bytes. The legacy/version 2 comparator remains
unchanged. This host preparation does not constitute a production codec or
atomic-save/cold-reload verdict.
