# Native Bend MCP stdio adapter

`mcp.bend` is an actual stdio MCP server. `src/mcp.bend` implements its
JSON-RPC lifecycle, validation, tool mapping, UTF-8 framing and persistent
loopback TCP connection in Bend. It imports the pure JSON/framing modules and
Base IO; it does not import the game engine or call gameplay functions directly.
Python is only an independent integration client and process orchestrator.

The adapter targets [MCP 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/basic),
specifically its [lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle),
[stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
and [tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
contracts. It advertises only `tools: {"listChanged": false}`. Initialization
always selects the supported version `2025-11-25`, including when a client
offers another version; the client decides whether that negotiated version is
acceptable. `notifications/initialized` completes initialization. `ping` works
before and after initialization. Unknown notifications are silent; requests
for unavailable methods receive `-32601`.

## Build and configure

From the project directory, with the pinned Bend 2.0.35 compiler:

```sh
/Users/chuah/.bend/bin/bend server.bend -o build/minecraft-server
/Users/chuah/.bend/bin/bend mcp.bend -o build/minecraft-mcp
```

Start the native live server independently. Its loaded registry input defaults
to `generated/reference_blocks.tsv`; see the live server/registry contracts for
the configured input. Configure the MCP client to launch this executable with
working directory set to the project directory:

```json
{
  "command": "/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/minecraft-mcp",
  "args": ["--threads", "1", "--gpu", "off"],
  "env": {"MC_LIVE_PORT": "47163"}
}
```

`MC_LIVE_PORT` defaults to `47163` and must be an integer from 1 through 65535.
The adapter connects to `127.0.0.1` once at startup and keeps that socket and
its live session for the process lifetime. The native stdio entry point opens
`/dev/stdin`, so the currently verified target is macOS/POSIX.

If `MC_DEV_TOKEN` is configured and nonempty, the adapter authenticates through
the real live `session.open` operation before accepting stdio requests. The live
server must have the same configured token. Authentication failure exits with
a generic stderr diagnostic and empty stdout; credentials are neither logged
nor included in evidence. With no token or an empty token, the session starts
as an observer. Developer-only tool calls retain the live server's permission
checks. This adapter grants no player capability.

## Dynamic tools and request envelopes

Every `tools/list` and `tools/call` obtains the catalog by calling the live
`discover` operation over TCP. It forwards each operation's `name`,
`description` and `input_schema` as MCP `name`, `description` and `inputSchema`.
There is no compiled operation-name whitelist. The verified server currently
discovers 16 operations, including three newly added registry queries; these
list and execute without adapter changes. A future operation appears when the
live server includes a valid descriptor. This does not imply that an operation
implements any behavior beyond the live server's stated contract.

This first adapter exposes the complete live request-envelope schema:

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "tools/call",
  "params": {
    "name": "world.block.set",
    "arguments": {
      "id": "set-1",
      "op": "world.block.set",
      "args": {
        "dimension": "minecraft:overworld",
        "x": -17,
        "y": -1,
        "z": 31,
        "state": 1
      }
    }
  }
}
```

The outer MCP ID and inner live ID have separate meanings. JSON-RPC IDs are
strings or numbers with exact integer values, never null. Decimal/exponent
forms such as `100005.0` and `1000060e-1` are accepted without floating-point
rounding. A provided live `id` follows the live schema, which requires a string.
The adapter forwards it and checks the response correlation.

The advertised schema retains its required `id` and `op` fields unchanged. As
an accepted convenience, omitted `op` is filled with the tool name and omitted
`id` is assigned `mcp-live-N` using a per-connection sequence. Clients following
the advertised schema should provide both. A provided `op` must equal the tool
name. Other envelope and argument validation stays in the live API.

Successful and failed live replies are returned in `structuredContent` as the
entire live response envelope. `content` contains one text item encoding that
same JSON value. A live failure sets `isError: true`, retaining its live error
code. Unknown tool names, malformed MCP parameters and name/op disagreement
are protocol errors (`-32602`). Uninitialized tool requests return `-32002`.
`tools/list` returns the complete catalog and rejects a pagination cursor.

## Framing, shutdown and scope

Stdio uses UTF-8 JSON objects separated by LF, with CRLF accepted. Stdout
contains only JSON-RPC responses followed by LF; diagnostics use stderr.
Arbitrary byte splits, including splits inside UTF-8 codepoints, are retained
until the line is complete. The shared framer permits at most 65536 bytes per
line, excluding LF and including a trailing CR, and at most 16384 Unicode scalar
values after CR removal. The JSON parser independently bounds input at 16384
codepoints. These bounds also apply to live TCP response records; a catalog
that exceeds them fails instead of being silently truncated.

`F.segments` separates LF-ended byte segments and a nonempty final tail.
Processing stdin segments sequentially ensures a valid request before a
malformed later record is dispatched even if both arrive in one read.
Malformed JSON produces `-32700` and processing can continue at the next line.
Malformed UTF-8, an oversized line or incomplete final line produces `-32700`
and closes the adapter. EOF with no partial record closes the file and socket
and exits cleanly. Batch-array requests are unsupported and produce `-32600`.
Notifications produce no response and cannot execute request-only tools.

The adapter processes requests synchronously. It supports no MCP tasks,
subscriptions, server-to-client requests, list-change notifications or request
cancellation. A backend disconnect becomes a cached transport failure:
`tools/list` returns `-32603`, `tools/call` returns an `isError` result with
`LiveTransportError`, and MCP `ping` still works. It does not reconnect. Base's
`recv_bytes` has no wall-clock deadline here, so a connected backend that never
responds can stall the process; terminating that subprocess is the current
client fallback. No timeout capability is claimed.

## Verification and proof boundary

```sh
python3 tools/test_mcp.py
/Users/chuah/.bend/bin/bend tests/framing.bend --verdict
/Users/chuah/.bend/bin/bend mcp.bend --check-only
```

The Python test builds native MCP and a separate `build/mcp-test-server`, starts
the real server on a dynamic loopback port with the fixed integration-test
token, and communicates through actual subprocess pipes and TCP sockets. It
compares discovery against an independently queried TCP catalog, executes
registry extensions, creates/sets/steps/queries/cancels world actions through
two persistent MCP clients, checks observer rejection and invalid arguments,
tests byte-wise Unicode/exact-ID input, malformed record ordering, silent
notifications, authentication failure, backend disconnect and clean EOF.
No internal game calls or MCP SDK server mocks substitute for the transport.
`evidence/mcp-integration.json` records results, source/input/binary/compiler
hashes and the complete checker diagnostic without request bodies or tokens.

The framer verdict checks its stated finite fixtures, including segmentation;
it does not prove universal MCP protocol correctness. Only four mutually
recursive external IO lifetime functions use `@unsafe`:
`receive_next`, `receive`, `read_again`, and `read_loop`. These handle a stream
whose end is controlled externally. Their callers inherit the boundary.
The native entry-point checker honestly reports `SOME PROOFS FAIL` and lists
23 dependent definitions; native build and integration success do not turn
that into a proof. Pure framing, request planning, integer-ID validation and
schema mapping introduce no additional foreign effects or unsafe annotations.

The evidence establishes an implemented MCP transport over the registry,
section and tick foundation. It establishes no full Minecraft gameplay,
rendering, UI, save-format or vanilla multiplayer parity.
