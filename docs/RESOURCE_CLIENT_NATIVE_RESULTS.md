# Native resource client: result and launch

The actual saved LocalPlayer backend and resource renderer now compile and run as two Bend processes. The full hidden native suite passed in **75.49 seconds**; root independently replayed the retained outputs with **high confidence**. The backend owns the world, LocalPlayer record, save lease and 50 ms actor. The client receives atomic camera/world samples and loads the real 26.3 JAR through the Bend archive, model, PNG, baker, visibility and mesh pipeline.

See the [native result](../evidence/remote-resource-client-native-r1.json), [root output audit](../evidence/remote-resource-paired-root-audit.json), [cleanup evidence](../evidence/remote-resource-client-lifecycle-r1.json), and one [actual returned-image PPM](../build/remote-resource-client/runtime-stop-marker-r1/renderer-standing/images/0.ppm).

The passed suite covered:

- Six paused LocalPlayer views, three frames each; 250 live-edit frames and three reload frames: **271 independently compared frames / 4,440,064 RGB pixels**.
- Complete Core/LocalPlayer save comparisons, six queued edits, atomic paused samples and the unchanged 18-operation public API; eight retained actual Java LocalPlayer phases.
- Nine malformed/deadline cases through the actual renderer TCP receiver; 12 listed private protocol cases, authentication/lease checks, and silent/partial-record cleanup with fresh epochs and neutral input behavior.
- Four resource/readback failures followed by recovery on the same backend; 100 separate unpaused presentation frames with actual timer advancement and no explicit simulation step or implicit save.
- Cleanup of all 40 registered groups. All 17 backends exited successfully through stdin stop; all 34 public/private listener ports were closed.

The first native attempt passed the standing view but failed a host assertion that expected empty backend stderr. Successful stdin stop deliberately emits exactly `resource backend stopped\n` with exit code 0. The [independent failure decision](../evidence/remote-resource-client-first-failure-decision.json) and [host adoption](../evidence/remote-resource-client-stop-marker-adoption.json) preserve that failed generation. Only the exact stop-marker predicate and consumer provenance/output routing changed; native binaries, scenarios and pixel expectations stayed fixed.

## Retained builds and verification

| Artifact | Route / whole-build time | SHA-256 |
| --- | --- | --- |
| `build/remote-resource-client/backend-native` | Standard native / 236.32 s | `9a779e6f867d42929e45750e7caec73e86795bc5b29e8fd255bb9527398bb878` |
| `build/remote-resource-client/client` | Guarded macOS CPU Window / 462.36 s | `7a5e7632457e33fd04a274ec69ab0d9107730042d7a0ee919d2cadf5a2e47765` |

The historical build commands used the original sealed producer runner, one 600-second whole-group attempt per entry, and no source-drift retry:

```sh
PY=/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" tools/test_remote_resource_client.py --backend-build-only --lead-slot-granted
PYTHONDONTWRITEBYTECODE=1 "$PY" tools/test_remote_resource_client.py --build-only --lead-slot-granted
```

Their retained reports are [backend-build.full.json](../build/remote-resource-client/backend-build.full.json) and [build.full.json](../build/remote-resource-client/build.full.json). The exact host-adopted verification command was:

```sh
PYTHONDONTWRITEBYTECODE=1 /Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/test_remote_resource_client.py --native --lead-slot-granted --consumer-ready build/remote-resource-client/runtime-stop-marker-r1/ready.full.json --backend-build-report build/remote-resource-client/backend-build.full.json
```

This is an already attempted sealed generation, with exclusive output creation and a 120-second outer cap. **It refuses a second run into its existing outputs**; consumer mode also refuses preparation/build/emission. These commands record executed provenance, not clean-checkout reproduction instructions. Binaries, generated registry/sine data, fixture bundles, native caches and the installed official JAR are required local prerequisites and are not all tracked in Git.

## Manual two-process launch

The following instructions are source-derived; they are not an additional runtime result or an automated foreground-testing grant. A normal human client launch can focus the Window and capture input. Automated checks use `BEND_MINECRAFT_LAUNCH_MODE=hidden`.

From the project directory, prepare a separate manual save by copying the verified standing **LocalPlayer bundle**, not an expected image. This is the project's custom NBT bundle, not a vanilla region-world loader. Use two distinct available loopback ports. Generate fresh public/private capabilities and a fresh backend nonce for each backend lifetime:

```sh
cd /Users/chuah/Documents/ChatGPT/bendex/minecraft
mkdir -p build/remote-resource-client/manual
cp -n build/remote-resource-client/view-standing.nbt build/remote-resource-client/manual/world.nbt
(
  umask 077
  cat > build/remote-resource-client/manual/environment <<EOF
export MC_WORLD_PATH="$PWD/build/remote-resource-client/manual/world.nbt"
export MC_WORLD_MISSING=refuse
export MC_BLOCK_REGISTRY="$PWD/generated/reference_blocks.tsv"
export MC_LIVE_PORT=25576
export MC_RENDER_PORT=25577
export MC_DEV_TOKEN="$(/usr/bin/openssl rand -hex 32)"
export MC_RENDER_TOKEN="$(/usr/bin/openssl rand -hex 32)"
export MC_RENDER_EPOCH="$(/usr/bin/openssl rand -hex 16)"
EOF
)
source build/remote-resource-client/manual/environment
unset MC_ATOMIC_PAUSE
build/remote-resource-client/backend-native --threads 2 --gpu off -- --verification-fixture --stdin-control --unpaused --sine generated/reference_mth_sin.f32
```

Keep that terminal's stdin open. Wait for both `server.ready` and `renderer.ready`. `--verification-fixture` is required: pristine worlds receive the finite fixture; loaded terrain/record remain authoritative. Omit `--unpaused` to retain the loaded pause state. The registry must be the generated pinned `reference_blocks.tsv`; the sine table is the verified 262,144-byte file. The private token authenticates one renderer; it is separate from public developer permission. The backend assigns the actual renderer epoch from the fresh boot nonce and a counter.

In a second terminal:

```sh
cd /Users/chuah/Documents/ChatGPT/bendex/minecraft
source build/remote-resource-client/manual/environment
unset BEND_MINECRAFT_LAUNCH_MODE BEND_MINECRAFT_FRAME_DIR
build/remote-resource-client/client --threads 2 --gpu off -- --jar "/Users/chuah/Library/Application Support/minecraft/versions/26.3/26.3.jar"
```

`--frames N` optionally limits presentation. Rendering is 128×128 into a 512×512 native Window. The source maps WASD, Space, left Shift/Control and mouse look; visible physical-input acceptance remains unverified. Optional `BEND_MINECRAFT_FRAME_DIR` must name an existing directory and records the returned CPU Image.

Close the client, then acknowledge a public save from the second terminal before stopping the backend. This Python snippet only exchanges the existing public protocol:

```sh
python3 - <<'PY'
import json, os, socket
with socket.create_connection(('127.0.0.1', int(os.environ['MC_LIVE_PORT'])), timeout=5) as sock:
    with sock.makefile('rb') as reader:
        def call(identifier, operation, arguments):
            sock.sendall((json.dumps({'id': identifier, 'op': operation, 'args': arguments}) + '\n').encode())
            reply = json.loads(reader.readline())
            if reply.get('id') != identifier or reply.get('ok') is not True:
                raise SystemExit('Public request failed: ' + repr(reply))
            return reply['result']
        call('open', 'session.open', {'mode': 'developer', 'token': os.environ['MC_DEV_TOKEN']})
        print(json.dumps(call('save', 'world.save', {})))
PY
```

Only after successful save acknowledgment, type `stop` and Enter in the backend terminal. It releases controls, stops the actor and exits with the exact success marker. Stop, stdin EOF and SIGTERM do not imply a save. Restart using the same manual bundle and fresh capabilities/nonce; `cp -n` preserves an existing manual save.

## Remaining boundaries

This consumer uses explicit air/stone/dirt/oak-planks choices, static normalized solid sprites, white tint/light, integer directional shading and CPU nearest/clamp sampling. It establishes neither a stitched/animated/mipmapped atlas nor biome tint, AO, world lighting, GPU blending/sRGB or vanilla final-frame equivalence. Returned CPU pixels do not prove drawable readback, visible keyboard/mouse capture, full gameplay, UI/inventory or performance parity. The five-second receiver deadline does not bound connect/send/terminal Release; local Window/assets close first, and the host supervisor supplies separate process bounds. Startup loading/drawing may exhaust the 100-pulse lease; strict late-poll races and stale-disconnect scheduling remain source-reviewed boundaries.
