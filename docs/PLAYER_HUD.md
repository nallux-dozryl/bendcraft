# Saved-player hotbar presentation

`src/player_hud.bend` supplies the remote resource client with a nine-slot
hotbar, selected-slot outline, stack counts and an inverted center crosshair.
The presenter queries `Wire.Inventory` before each draw, including the first
frame, and uses the reply's saved-player selection and first nine slots without
creating display-only inventory contents. The wire validates the full 36-slot
snapshot and the selected 0–8 range.

The presenter keeps the sole affine `RF.Assets` owner. It briefly destructures
the owner, retains immutable texture/catalog lists for the HUD view, restores
`RF.Assets`, renders the world, then applies the HUD before `Window.frame`.
Frame tracing and image CRC reporting use the returned, overlaid image.

The human path projects the overlaid 320×180 logical image to the fixed 960×540
drawable with integer nearest-neighbor mapping. This compensates for Base's
Window shader choosing its Image traversal depth from the drawable's backing
side. Source constant subtrees remain constant destination regions; padding
outside the drawable is zero. Hidden presentation returns the logical image
unchanged. Frame reports record both logical and presentation dimensions;
human frame traces contain the actual 960×540 presented raster.

Stone, dirt and oak planks use the matching loaded resource texture, selected
by its catalog identifier. Texture alpha composites over the slot background.
The icons currently use flat block textures rather than the pinned game's
three-dimensional item models. Counts use an authored 3×5 decimal raster;
this is not a claim of pinned Minecraft font or complete GUI parity.

At 128×128 the hotbar uses 13-pixel slots and occupies `(4,111,119,15)`.
At 320×180 it uses 20-pixel slots and occupies `(69,156,182,22)`. The crosshair
is 13 pixels: two seven-pixel axes with a shared center, inverting the underlying
RGB and producing opaque pixels. The selected outline is one pixel and count
glyphs/shadows are inset to remain visible. Stack count 1 is omitted; admitted
counts 2–64 are shown without abbreviation. Below 11-pixel slots, count text is
hidden; below 5-pixel slots, icons are hidden. Below 40×24 the bar is hidden.
These compact-size choices preserve arithmetic safety and do not establish
accessibility or scaling parity.

The overlay traverses only Image branches intersecting the bar or crosshair
bounding rectangles. Other branches return their original subtree. The source
Image must have no greater depth than the frame's power-of-two backing side;
the current world renderer satisfies this contract.

`HUD.packet_commands(packet, previous_capture)` preserves event order. Captured
digit key-down events 49–57 select hotbar slots 0–8; captured left/right button-down
events issue action 0/1. The click that establishes capture is consumed. An
explicit release resets admission; final focus or capture loss suppresses all
commands from that packet. The presenter sends these commands only after the
whole `Wire.Input` packet is acknowledged. Actions require `ActionReply` and
hotbar selection requires `Ack`; matching epoch/sequence alone does not admit
the wrong reply type.

Human windows are 960×540; guarded automated windows remain 512×512. The entry
point supplies the logical dimensions. No foreground launch is implied by
these source changes.

Focused synthetic checks live in `tests/player_hud.bend`. They probe capture
and release transitions, reply-type rejection, resource identifier mapping,
saved selection/count preservation, literal decimal rasters, selected count
pixels, transparent texture composition, compact layouts and sparse traversal.
Human projection checks include literal edge, padding, crosshair, hotbar and
resource-icon pixel positions, plus constant-region retention.
They perform no Window, socket, Java or saved-world operation. Compile and native
results must be recorded separately from source preparation; OS-input and
pinned-vanilla scene acceptance remain separate work.
