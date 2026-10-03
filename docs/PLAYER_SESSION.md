# Saved player session integration

Confidence is **high for the recorded custom-bundle and neutral player scenarios**. Two complete native runs passed against the same immutable artifacts: 13 independently exact bundle saves and 119 startup refusals per run, 14 ready server processes, 16 MCP bridge processes, 99 MCP requests/responses and 83 raw TCP requests in the live-session lane. Each run also executed all five real publication-stage SIGKILL interruptions. The complete behavioral manifests agree after excluding elapsed times and process IDs. `evidence/player-session-native.json`, `evidence/player-session-reproduction.json` and `evidence/player-session-audit.json` record the observations and generation audit.

The source/harness reaches the ordinary checker's declared unsafe/foreign boundary (79 dependent definitions), with no preceding type/proof diagnostic. The optional full-import `--verdict` attempt refused at that boundary in 2.776 seconds; it did not reach an independent full-source kernel proof. `evidence/player-session-kernel.json` records this refusal, not a kernel pass.

Production `PlayerStorage.codec()` is a closed `ExtendedPersistence.Codec<PlayerRecord.Record>` named `bendex:player-record`, schema 1. Its extension ceiling is 8192 bytes. It admits only `minecraft:overworld`, rejects Core-only saves without an explicit migration, and uses the already verified custom raw motion/look record. Java does not define this enclosing bundle or its API.

`PlayerSession.State{player,shell}` retains one affine runtime owner and one save-policy/lease shell. `to_bundle` temporarily transfers its Core Engine and checked player record into the leased extension bundle. The transient header holds tables, palette/region/cache, physical keys/mouse/options and the last runtime error; it contains no second body or authoritative look owner. `from_bundle` restores those fields. `new` adopts the loaded bundle only after palette setup and checked runtime restoration, and clears ephemeral physical input. Startup failure explicitly releases the lease before refusal.

The actual reserved `simulation.step` is intercepted by `PlayerSession.dispatch`. Its envelope must contain a strict unsigned integer lexeme `ticks` in 1..1000, no scheduled `at`, and developer capability. Decimal/exponent spellings such as `1.0` and `1e0` fail the strict tick schema. Argument validation precedes permission validation. Each tick applies due Core edits before one player physics update through `Runtime.advance`. Other operations retain the existing Core, registry and save routes. `player.inspect` is a public read-only operation returning canonical typed NBT bytes; `world.clock` requires developer capability. Observer and developer sessions remain the admitted capabilities; a real player/abilities binding is still unavailable.

Every physically parsed JSON request that reaches dispatch consumes one session sequence, including an invalid envelope (missing ID, nonstring operation, nonobject arguments, or invalid `at`). Session delegates these failures through Live's existing increment-before-envelope-validation path. Syntax failures and duplicate JSON object members are rejected earlier by the strict transport parser as `invalid_json`, consume no dispatched sequence, and leave the Core/player unchanged. Peer highwater and the admitted operation's one-sequence identity remain exact across save/restart.

The standalone harness imports production modules only. Its driver calls actual `SupportWorld.sample_checked`/`update_checked`, with the measured neutral Player attributes: movement speed binary64 0.1, gravity 0.08, friction/air-drag modifiers 1, jump strength 0.42 and maximum step binary32 0.6. This tests the declared plain Player neutral dry-air projection, not LocalPlayer's override or arbitrary equipment, abilities, fluids, effects or environments.

The explicit `scene` test mode initializes the existing 39-block scene only when Core has tick/revision zero, empty sections, no pending edits and no events. The fixture itself yields Core tick 1/revision 47 and eight sections. Only that initialization installs a held-forward button and nonzero mouse history/accumulation. A saved world must retain its loaded body, support, look, clock and pending queue. `fixture.transient` is a separate read-only raw-TCP harness instrument exposing physical fields and the last error; it is absent from production MCP discovery and is not a shipped player API mutation.

The independent physical NBT oracle composes exact canonical Core bytes from `tools/test_world_codec.py` and exact record bytes from `tools/test_player_record.py`. Current/past degree words and their current binary32 radian projections remain raw-bit checked. The independently encoded 110 corrupt startup fixtures include malformed bundle/Core/record fields/types, missing/duplicate members, namespaces/schemas/version/registry, truncation/trailing bytes, byte ceilings, nonfinite look, projection mismatch, exhausted peer allocation and the two known but currently unsupported player dimensions. A post-codec palette failure is tested separately.

Six actual pinned Java Player.aiStep calls were measured twice with identical outputs using the official verified server/library artifacts. The fixture supplies the same neutral environment and world blocks, observes production movement and support calls, and changes declared collider blocks immediately before individual ticks. Five of those observed outputs are direct expectations for the live test: two held-input ticks, one unsaved tick after removal, and two released-input ticks after restart with removal/restoration on distinct Core ticks. The remaining third held tick supplies an additional stable reference observation. The tool only adapts fixture services and observations; production Java aiStep/movement/support methods are not replaced. All extracted Java source/classpath/runtime fingerprints and input/output hashes are retained, and optional reuse requires their exact agreement.

The actual native integration checks passed:

- TCP and MCP discovery, exact `player.inspect` bytes, observer/developer authorization, unavailable player capability, strict tick bounds/lexemes/extra arguments/`at`, single sequence consumption for every dispatched JSON request (including invalid envelopes), and malformed physical JSON sequence retention.
- Physical keys/mouse retained across uninterrupted delegation, malformed calls, ticking and saves; reset after restart. Body/support/raw look, signed metadata and pending clock remain exact.
- Actual paused scene edits interleaved with physics, checked against the Java observations; explicit driver failure retains player/controller state while Core advances. Tick bounds 1 and 1000 are exercised in that declared failure lane.
- Exact whole Core+Record bundle bytes after acknowledged durable save, unsaved mutation then real SIGKILL/restart, peer highwater restoration, unchanged lock-file inode, concurrent lease refusal and exclusive temporary-file collision followed by same-owner recovery/save.
- Fresh creation and paused exact-body/look restore under the controlled four-material registry; a separate fresh/inspect/save lane loads the full official 35,723-state registry.

A separately labeled primitive interruption lane runs the actual leased `AtomicFile.publish_with` over independently encoded old/new Core+Record bundle bytes. Its closed test hook pauses after Created, Written, Synced, Published and DirectorySynced. Real SIGKILL at each point must expose a complete old or new pair, retain the expected orphan temporary when publication has not occurred, and permit an actual Session restart/save. This does not insert a stage hook into production Session/E.save, whose ordinary quiet publication path is tested separately. Process termination does not establish power-loss behavior.

The final source generation stayed unchanged through both builds and all comparisons: Session `e4d515442e9446aa308dee68630ef48755565562a2441052f54d3e422416e6d2`, Storage `0873c24a2dc4b2a0e3c573f6a11ca313aa7b807457b4447e21c3f9c053bbb445`, harness `875f19ad80a1ac719a2ea9bf5a83df95539115580dc51835a97f9db8d1dbc5cf`, and the 47-file local source closure. The final Python runner is `e6a634f0a3cbcd9729e76ad006fcba849a21cba938862dc0130fd2b3c68fd440`. Initial runner assertions incorrectly assumed stdout diagnostics, observer access to `world.clock`, no sequence consumption for malformed dispatched envelopes, and dispatch-level duplicate-member rejection. Actual execution and the production declarations corrected those assertions; no production source, Bend harness, neutral driver, physics fixture or native executable changed. The two complete passing runs used the corrected runner.

The server executable is `e5a8c39d31cf50d3123de472e0a685b67f6b850f9a06b5d8d7d7630db1c416ad`; its emitted C is `68011c1c7e470147f062391610403105db511c034867d633dc1f97ddabf04b5e`. The MCP executable is `f0191cb9401e1ff47990ada221fb8051a94ad9942d4c857d28ef764b9e955281`; its emitted C is `51a4624b9491083ae0af3069217a94274b400196b97b169ce3a060fd1d6321f5`. The keyed build receipts validate 1,676 server dependencies and 1,630 MCP dependencies, compiler identity, immutable artifact paths and current aliases before and after execution. Both receipts pin Bend executable SHA256 `99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e`; native compilation uses Apple clang 17.0.0. Twenty-four independent deep-copy receipt mutations fail admission, with no shared file corruption.

The quiet production `Session` → `ExtendedPersistence` → `AtomicFile.publish` path passed acknowledged durable saves, exclusive-create collision rollback, owner reuse and actual unsaved-state SIGKILL recovery. The separate stage-hook lane exercises the real leased primitive publication operation over independently encoded bundles: Created/Written/Synced retain the complete old generation; Published/DirectorySynced expose the complete new generation. It validates startup/save recovery and lock inode retention at each point. These are separate measured lanes; the stage hook is not inserted into production Session save.

Reproduce reference extraction, schema corpus and source fingerprinting without a native build:

```sh
python3 tools/test_player_session.py --preflight
```

Reuse already measured ignored Java output only after validating every pinned source/runtime/artifact and output hash:

```sh
python3 tools/test_player_session.py --preflight --reuse-reference
```

With a build slot, the runner builds the session entry and MCP bridge sequentially, each with a 600-second process-group bound. It verifies immutable compiler/toolchain/transitive-source/emitted-C/cache generations before all executions:

```sh
python3 tools/test_player_session.py --build-only
python3 tools/test_player_session.py --skip-build
```

The server entry accepts `VERIFIED_SINE_TABLE_PATH MODE` (`normal`, `scene` or `fail-context`) after runtime flags and `--`. The primitive entry accepts `atomic PATH SUFFIX PAYLOAD_PATH` and pauses only under the explicit `MC_ATOMIC_PAUSE` test environment. All input bundles, output files, Java classes/observations, native artifacts and receipts remain under ignored `build/player-session`/`build/native-cache`; committed evidence contains summaries and hashes.

No native window, real OS physical input/presentation, vanilla save compatibility, unrestricted physics or whole-game acceptance is established by these session tests. No independent full-source kernel claim is made for the transport/durability/lease foreign boundaries.
