# Authoritative foundation server

`server.bend` runs the checked Bend core and dynamic block registry behind a real persistent loopback TCP interface. It is developer foundation tooling with ephemeral state. `persistence_server.bend` adds the checked leased foundation save wrapper, and `persistent_client.bend` uses that same wrapper in the client instrument. Player synchronization, vanilla protocol sessions, gameplay, terrain and subscriptions remain unimplemented.

From the `minecraft` directory:

```sh
/Users/chuah/.bend/bin/bend server.bend -o build/minecraft-server
MC_DEV_TOKEN='choose-a-local-token' build/minecraft-server --threads 4 --gpu off
```

`MC_LIVE_PORT` optionally selects an integer port from 1 through 65535, default 47163. The address is `127.0.0.1`. `MC_DEV_TOKEN` must be nonempty; the token is never printed. `MC_BLOCK_REGISTRY` optionally selects a validated TSV, default `generated/reference_blocks.tsv`. Loading errors terminate startup before accepting peers. State bounds come from the loaded registry, rather than a fixed vanilla count.

Requests and responses are UTF-8 JSON records separated by LF; CRLF requests are accepted. One connection retains its session identity/capability and receives responses in request order. Separate connections get increasing peer IDs. See [LIVE.md](LIVE.md) for the envelope and core operation semantics and [FRAMING.md](FRAMING.md) for strict byte/scalar limits. A malformed JSON record receives an error while retaining the connection; invalid UTF-8 or an oversized record closes that connection. A valid preceding request is applied even when a later malformed frame arrives in the same receive batch.

The default loaded engine exposes the 13 core operations plus:

| Operation | Strict arguments | Result |
| --- | --- | --- |
| `registry.block` | `name: string` | Protocol ID, first/count/default state IDs and ordered domains/strides. |
| `registry.state.decode` | `state: U32 integer lexeme` | Protocol ID, name, state and string property object. |
| `registry.state.resolve` | `name: string`, `properties: object<string,string>`, `policy: "exact" or "defaults"` | Resolved state ID. |

These three queries require developer capability and reject `at`. Exact resolution requires every property; defaults explicitly fills omissions from the declared default state. Unknown names/properties, invalid values and out-of-range IDs return typed faults. Discovery is public and describes the actual 16-operation catalog, with strict schemas generated from the same field descriptors used for validation. Registry metadata does not imply block behavior.

One actor owns the affine `Game.Engine{world,registry}`. Connections submit `Message.Request` values and wait on single-response channels. The request mailbox holds 64 entries and backpressure is provided by Base channels. Pure dispatch and tick functions run in the owning actor. The initial world is paused. Realtime pulses use 50 ms monotonic deadlines advanced from the previous deadline; they honor pause state. Explicit stepping is independent of pause. Scheduled mutations retain tick/peer/sequence ordering and are checked both at admission and application where necessary.

`Server.Driver<State>{step,dispatch}` is a compile-time typed replacement boundary. A mod can replace the complete owned `State`, tick transition and operation dispatcher; the shared socket/session/framing machinery does not require a foreign plugin. Raw constructors remain module-visible, so callers must use validated registry/core constructors and preserve their invariants. The default driver calls `Game.realtime_step` and `Game.dispatch`. Only OS-driven actor, timer, accept and receive lifetimes use `@unsafe`; these functions are excluded from pure proof claims.

`EffectfulDriver<State>` retains the same sole State owner while an operation
performs checked IO, including durable save publication. `start_handle` and
`start_effectful_from_peer` return a duplicable `Handle<State>` channel
capability. `local_call(State,A,handle,query)` serializes a trusted compiled
owner-retaining query with TCP requests and pulses; it does not create a second
world or provide network authorization. `stop` acknowledges actor/mailbox/timer
shutdown. A parked accept operation is currently released by explicit process
exit in the finite client. Peer allocation admits U32 maximum once, closes the
listener afterwards and preserves existing connections, rather than wrapping.

`tools/test_server_local.py` and `tools/test_server_peer.py` record actual local
query/TCP ordering and peer-exhaustion behavior. These checks are separate from
the eight-client integration corpus below.

`python3 tools/test_server.py` launches the actual native server and eight independent TCP connections. It tests shared edits, ordering, future/cancelled actions, signed boundaries, rollback and application rejection events, capability checks, UTF-8 splitting, malformed-record isolation, concurrent reads and realtime/pause behavior. Registry expectations come from explicit hash-verified official Java state records. Evidence: [server-integration.json](../evidence/server-integration.json). This is transport and foundation integration evidence, not vanilla multiplayer equivalence.
