# Complete typed driver example

`mods/examples/time_overhaul.bend` is an executable Bend system replacement, specialized over the same `Server.Driver<State>` transport as the default server. Its owned state is:

```text
State{engine: Game.Engine, ticks_per_pulse: U32, pulses: Nat}
```

The replacement counts every realtime pulse, including while paused. When unpaused, it advances the checked core by its configured number of ticks per 50 ms pulse, applying every intervening tick's queued actions. This changes the simulation policy intentionally. Explicit `simulation.step` remains an exact requested tick count. The mod retains the dynamic registry, shared world ownership, scheduled admission, session capabilities and core operation catalog.

It adds two developer-only operations whose validation and discovery schemas derive from the same field descriptors:

| Operation | Arguments | Behavior |
| --- | --- | --- |
| `mod.time_overhaul.status` | Empty | Return owned pulse count and rate. |
| `mod.time_overhaul.configure` | `ticks_per_pulse`: integer lexeme 1–10 | Replace realtime tick policy immediately. |

Both reject scheduled `at`, unknown fields and invalid types/ranges. Discovery includes 18 tools. The native MCP executable queries this catalog dynamically and requires no mod-name whitelist or recompilation to execute these operations.

Before registry loading or accepting peers, startup validates the runtime JSON manifest against the actual typed `Mods.decode/resolve` and the compiled mod identity/API/side/declared callable roles. The manifest is metadata for already compiled code. It cannot install handlers or change `State`. See [MOD_LIFECYCLE.md](MOD_LIFECYCLE.md) for dependency/order/matching rules, exact gate behavior and negative tests.

From the project directory:

```sh
/Users/chuah/.bend/bin/bend mods/examples/time_overhaul.bend -o build/time-overhaul-server
MC_DEV_TOKEN='choose-a-local-token' build/time-overhaul-server --threads 4 --gpu off
```

It uses the same port/token/registry settings as the default server. `MC_MOD_MANIFEST` optionally selects a replacement manifest path. The example's setting/counter has no restart persistence or hot reload; discovery/status reports that limit.

`python3 tools/test_mod_driver.py` launches this actual native server, two TCP sessions and an actual MCP process. It checks owned state/pause behavior, strict configuration, exact explicit steps, four ticks per realtime pulse, actions due inside a multi-tick pulse, shared state and mod operation discovery/execution through the unchanged adapter. `python3 tools/test_mod_manifest_startup.py` separately verifies valid and rejected startup manifests. Evidence: [mod-driver.json](../evidence/mod-driver.json), [mods-startup.json](../evidence/mods-startup.json).

This demonstrates one complete typed state/transition/dispatcher replacement. It does not establish broad hooks for unimplemented gameplay, rendering, worldgen, players, persistence or mod migration systems. Its native executable inherits the explicit unsafe OS-lifetime loops in the shared server; pure manifest laws have their separate checker/kernel evidence.
