# Boxed resource client generation

This separate entry preserves the first resource-client generation and its
600.083-second emission timeout. The first attempt produced no retained C,
executable or completed build receipt and ran no client scenarios. The new entry
changes the representation crossing the generic presenter; it does not change
the renderer, actor, saved player semantics, resources or independent expected
outputs.

`resource_player_boxed_client.bend` uses
`src/resource_player_boxed_scene.bend`. Recursive `Frame` and affine `Assets`
wrappers contain the complete visibility sample and sole loaded resource owner.
Canonical wrappers have empty tails. The installed compiler's layout rule boxes
recursive records; a source-derived layout analysis counts 21 words for the
unboxed sample and 25 for the unboxed resources, versus one word for each wrapper.
This reduces the generic continuation's representation by 44 words per live
pair. It does not establish that these captures caused the previous timeout or
that the new client builds or runs faster. Boxing adds allocation and indirection.

The snapshot adapter preserves the complete actor/session owner and wraps only
the immutable successful sample. Rendering unwraps a canonical frame and assets,
calls the existing checked world-resource draw function, and wraps exactly its
returned resource owner. A noncanonical frame or asset tail returns the complete
asset owner unchanged with an explicit error. Closing structurally visits every
nested affine asset owner and invokes the existing resource close operation.
The production renderer and all old client sources remain unchanged.

The runner is an exact copy of the frozen first-generation integration runner
with only entry, scene, working/evidence paths and its descriptive docstring
substituted. The lead retained the copy comparison at
`build/root-resource-boxed-runner-audit.json`. Its Java/NBT comparisons, hidden
launch refusal, real TCP/MCP, timer, save/reload, startup recovery and cleanup
obligations remain the same. No test success transfers from the failed build.

Prepare or audit without emission/client execution:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_resource_player_boxed_client.py --prepare
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_resource_player_boxed_client.py --audit
```

After a lead heavy-slot grant, the single guarded build and retained-artifact
suite use:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_resource_player_boxed_client.py --native --lead-slot-granted
```

The build cap remains 600 seconds. Each native launch is bounded and hidden.
The single authorized build of this boxed generation also timed out during C
emission, after 600.066 seconds, without retained C, an executable or completed
build receipt. No native client or integration scenario ran. Its process group
was reaped and both generations' sealed preparation audits still passed. The
original unboxed timeout remains separate and unchanged.

The authorized one-second emitter sample reported a 17.0 GiB physical footprint,
but its mostly unsymbolized frames do not identify a source function or dominant
compiler cost. The 44-word source-derived representation reduction is not a
measured build improvement. Further work requires a concrete compiler diagnostic
before another entry build. Receipts are
`evidence/resource-player-boxed-client-native.json` and
`evidence/resource-player-client-diagnosis-frame-boxing.json`.

Prepared or ordinary-checked code does not establish native behavior, pixels,
visible presentation, focused physical input, UI, audio, multiplayer or complete
gameplay parity. The client still uses the explicitly admitted plain Player
profile, three normalized static resources, four-state palette, CPU rendering
and white light. It has no independent frame pixel readback.
