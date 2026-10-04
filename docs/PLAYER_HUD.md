# Saved-player hotbar presentation

`src/player_hud.bend` supplies the remote resource client with a nine-slot
hotbar, selected-slot outline, stack counts and an inverted center crosshair.
The presenter queries `Wire.MenuInspect` before each draw, including the first
frame, and uses the authenticated full menu reply's saved-player selection and
first nine main slots. Equipment, crafting, carried contents and result availability
come from the same authoritative menu snapshot. The wire validates its cardinality
and selected 0–8 range. Missing authority causes a presentation error rather than
an invented empty inventory.

The presenter keeps the sole affine `RF.Assets` owner. It briefly destructures
the owner, retains immutable texture/catalog lists for the HUD view, restores
`RF.Assets`, renders the world, then applies the HUD before `Window.frame`.
Frame tracing and image CRC reporting use the returned, overlaid image.

Production presentation separates scene resolution, output dimensions and HUD
scale. The scene is rendered at the configured percentage of the measured
output, resampled when those dimensions differ, and then overlaid with the HUD.
The default human request is 1920×1080 with 100% scene rendering. Automatic HUD
scale is the largest integer 1–4 that leaves at least a 320×180 menu canvas.
Thus 1920×1080 has a 480×270 HUD canvas and 3456×2234 has 864×558. The scale affects
HUD pixels independently of scene rendering. Hidden defaults retain 128×128
output and identity scene projection. Source constant subtrees stay constant
destination regions; projected padding outside the output is zero.

The old fixed 320×180→960×540 function and its literal checks remain compatibility
fixtures. The production presenter calls `HUD.compose` with the current measured
plan. Existing `player-hud-preparation` receipts describe that earlier generation
and do not admit the new resolution/native adapter.

Stone, dirt and oak planks use the matching loaded resource texture, selected
by its catalog identifier. Texture alpha composites over the slot background.
The current three resolved icons use flat block textures. Other catalog items
retain their real identity/count and show the authored availability glyph until
their item-model resource is resolved. Full 1658 item-model rendering remains a
separate resource dependency. Counts use an authored 3×5 decimal raster;
this is not a claim of pinned Minecraft font or complete GUI parity.

At 128×128 the hotbar uses 13-pixel slots and occupies `(4,111,119,15)`.
At 320×180 it uses 20-pixel slots and occupies `(69,156,182,22)`. The crosshair
is 13 pixels: two seven-pixel axes with a shared center, inverting the underlying
RGB and producing opaque pixels. The selected outline is one pixel and count
glyphs/shadows are inset to remain visible. Stack count 1 is omitted; admitted
counts are shown exactly without abbreviation, with maximum stack size supplied
by the verified item catalog. Below 11-pixel slots, count text is
hidden; below 5-pixel slots, icons are hidden. Below 40×24 the bar is hidden.
These compact-size choices preserve arithmetic safety and do not establish
accessibility or scaling parity.

The overlay traverses only Image branches intersecting the bar or crosshair
bounding rectangles. Other branches return their original subtree. The source
Image must have no greater depth than the frame's power-of-two backing side;
the current world renderer satisfies this contract.
When a constant world subtree maps entirely to one logical HUD cell, its
native overlay remains one constant subtree. Scaled flat icons/glyphs therefore
do not require repeated physical-pixel work inside that cell.

`HUD.packet_commands(packet, previous_capture)` preserves event order. Captured
digit key-down events 49–57 select hotbar slots 0–8; captured left/right button-down
events issue action 0/1. The click that establishes capture is consumed. An
explicit release resets admission; final focus or capture loss suppresses all
commands from that packet. The presenter sends these commands only after the
whole `Wire.Input` packet is acknowledged. Actions require `ActionReply` and
hotbar selection requires `Ack`; matching epoch/sequence alone does not admit
the wrong reply type.

The production entry accepts width/height, render percentage, HUD scale,
display-native and fullscreen settings. The project-owned AppKit adapter makes
human windows resizable and measures drawable pixels plus content points each
frame. Mouse/move/scroll positions map from content points to drawable coordinates;
relative Look deltas remain unchanged. Outside pointer coordinates stay outside
for menu hit rejection. The default hidden 128 fixture retains its 512×512 Window;
explicit hidden output settings open the requested extent for measured rendering
tests. See `PLAYER_PRESENTATION.md` for allocation and unproved boundaries.

Focused synthetic checks live in `tests/player_hud.bend`. They probe capture
and release transitions, reply-type rejection, resource identifier mapping,
saved selection/count preservation, literal decimal rasters, selected count
pixels, transparent texture composition, compact layouts and sparse traversal.
Human projection checks include literal edge, padding, crosshair, hotbar and
resource-icon pixel positions, plus constant-region retention.
Production literal checks additionally cover full 1080 output with 50% scene
rendering, independent HUD scale, display-native dimensions, backing allocations,
content-point mapping, outside pointers, count shadows and output padding.
They perform no Window, socket, Java or saved-world operation. Compile and native
results must be recorded separately from source preparation; OS-input and
pinned-vanilla scene acceptance remain separate work.

The seven allocation/interface laws and nine HUD/input/composition laws have
independent kernel PASS receipts in `evidence/player-presentation-proof.json` and
`evidence/player-presentation-input-proof-001.json`. These establish their stated
pure properties; they do not establish native pixels, physical input or menu
transport behavior.
