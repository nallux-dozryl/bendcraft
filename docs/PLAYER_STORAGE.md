# Player bundle integration contract

`player_storage.bend` binds the checked `PlayerRecord` codec to the existing
leased `ExtendedPersistence` atomic bundle. Its namespace is
`bendex:player-record`, schema is 1, and extension budget is 8,192 bytes. The
current runtime admits the overworld only. Unknown schema versions and Core-only
save migration reject before adoption. Fresh initialization uses the existing
finite-scene body convention with neutral metadata and zero degree/view fields;
it does not create terrain or silently initialize missing sections.

`player_session.bend` keeps the sole `Runtime.State` alongside an affine save
shell containing registry identity, configured path, peer high-water mark,
limits, lease, extension budget and catalog. A delegated operation temporarily
transfers the Engine and current `PlayerRecord` into `ExtendedPersistence.State`.
Its transient header contains the sine-table owner, palette/region/render cache,
physical buttons, mouse state, options and last error. It contains neither a body
nor authoritative rotation fields. Returning from a delegated operation
reconstructs the runtime from the record and returns the save shell. A universal
ordinary-checker law states that this transfer preserves every runtime and shell
field; independent kernel verification of this effectful imported module is not
established.

The closed extension catalog currently adds `player.inspect`. It is a read-only
operation returning exact record NBT bytes in a JSON array. The observer can
inspect the admitted neutral state. The existing unavailable player capability
remains unavailable until a real player/abilities binding is implemented. This
operation establishes neither a complete player API nor gameplay permissions.

The session intercepts the actual reserved Core operation `simulation.step`.
Its schema remains strict: one through 1,000 ticks, developer capability, no
scheduled `at` field, one session sequence increment. It advances Core and then
player physics once per individual tick, so due queued edits affect the correct
player step. Other operations, discovery, authentication and `world.save` use
the existing closed extension dispatcher. The save path is therefore the same
leased bundle publication path for Core plus the checked player projection.
A failed physics phase retains the Core clock/edits and restores the previous
player view, metadata, support and controller, as specified by Runtime.

Startup receives a checked `ExtendedPersistence.Ready<PlayerRecord>` and the
pinned sine Tables. It resolves the four-state palette, restores the validated
saved body/metadata/support/degrees/view projection, and clears physical held
keys and mouse history. The save lease is explicitly released if palette or
player restoration fails. Ordinary checks reach the explicit inherited
native/foreign boundaries. Two complete native session runs now pass, each with
13 independently exact whole-bundle saves, 119 startup refusals and 99 actual
MCP exchanges. They cover queued edits interleaved with measured Java physics,
save/restart, transient retention/reset, authorization, sequencing, lease and
temporary-file recovery. Five additional real SIGKILL stage tests exercise the
leased publication primitive over independently encoded bundle pairs; their
hook is separate from the quiet production Session save. See
`PLAYER_SESSION.md` and its native/reproduction/audit evidence. The full imported
kernel refuses at inherited unsafe/foreign boundaries and remains unverified.

The current motion driver is the explicit plain Player aiStep projection.
LocalPlayer's apply-input override, full entity/client/server tick phases,
inventory/equipment/abilities, all dimensions and vanilla save compatibility
remain required integration work. These custom modules are not vanilla
`player.dat` implementations.
