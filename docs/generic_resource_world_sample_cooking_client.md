# Actual generic cooking client

The changed Generic client uses the existing production cooking protocol and
screen while retaining the Registry, demand ledger, CW resources and native
Window owner. Its initial authority query sends `CookingInspect{0}` and expects
the real cooking reply introduced in Actor022; Actor017 cannot serve this caller.
The public launcher now selects the accepted Actor024/Generic012 pair, including
the lease and cached-recipe repairs and actual cooking, save and cold-reload
acceptance recorded in
[Cooking client delivery](generic_resource_world_sample_cooking_launcher.md).

World use runs through `RemotePresenter.send_game_commands`, which maps the
actual use action to the cooking target query and performs the existing ordinary
block fallback only for its exact refusal. Opening a cooker consumes its real
snapshot and release/capture intents. Cooking input runs before the ordinary
inventory input. While the cooker is open, its events cannot open the ordinary
inventory or become world actions. Closing sends the actual menu ID and waits
for the authoritative response before resuming ordinary input.

Each frame chooses the authority query from the retained cooking state. Its
cooking snapshot supplies the main-inventory HUD; the actual CookingInput screen
draws over the ordinary world image. Icons borrow the existing CW texture and
sprite rows. Unresolved artwork uses the existing explicit missing-icon mark;
this join does not invent coal, food or output textures. Drawing restores the
complete Session and catalog owner. Resource demand and authenticated cold-load
heartbeats remain the existing010 implementation.

The recursive local Config stays closed across native and network callbacks.
Returned Presenter metadata replaces only its value and preserves the original
recursive tail. The complete original source check passed on frozen010
requirements plus only this caller: 5,812 declarations, 5,903 original ordered
entries and zero holes. A separate initial-ownership emission of 35 newly
reachable caller and sender bodies found a maximum reachable segment of 232
words, below the 247-word entry limit. This is not a full native emission verdict.

The source and diagnostic receipt is
[`generic_resource_world_sample_cooking_client.json`](../evidence/generic_resource_world_sample_cooking_client.json).
The changed011 producer reached its established600-second limit while emitting
the historical integer scanner in ownership pass7. No C or native artifact was
produced, and the failure and cleanup remain intact. Changed012 uses the same
frozen010 graph and caller with only the separately native-verified block-model
Bool/scalar admission repair added. Its600-second/8GiB limits are unchanged.
The changed012 whole C emission passed in267.87 seconds. Apple clang17's
default `-O3` invocation failed in backend prologue insertion. The failed native
receipt and crash reproducer are retained. Compiling that exact C with
`-O3 -fno-stack-check` passed in105.05 seconds under the unchanged300-second
native limit. The driver accepts this flag and omits its stack-check option.
The resulting6,986,328-byte renderer is pinned in the receipt; this compilation
does not establish interactive or OS acceptance.

These results and the retained011 failure are recorded in
[`generic_resource_world_sample_cooking_build.json`](../evidence/generic_resource_world_sample_cooking_build.json).
Native compilation, injected callback acceptance and visible OS input acceptance
are separate results. Injected callback acceptance retains the original drawing,
Bend caller, menu and TCP backend; it cannot establish foreground keyboard/mouse
capture or visual usability.
