# Resource client: prepared Bun graph diagnostic

Status: preparation only, 2026-10-04. No Bun compiler-source module has been loaded in this generation. The dominant phase of the two installed resource-client emitter timeouts remains **unknown**. Confidence is high in the exact runtime binding and archived source identity; source-loading compatibility and the graph outcome are unverified.

The accepted plain-client control failed under Node 23.5 before checking or native graph traversal, with `RangeError: Maximum call stack size exceeded` in `term_higher`. Its sealed [diagnosis](resource-player-client-diagnosis-next.md), source, wrapper, output and receipts are retained byte-for-byte. This proposal changes the runtime and its startup configuration, while retaining the compiler algorithms and graph probe.

## Existing runtime discovery

The installed `/Users/chuah/.bend/bin/bend` is a 63,885,392-byte arm64 Mach-O executable, SHA256 `99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e`. Three captured version-only invocations returned exit zero with empty stderr:

| Argument | Environment adaptation | Actual stdout |
|---|---|---|
| `version` | Remove inherited `BUN_*` and `NODE_*` variables | `bend 2.0.35` |
| `--version` | Same removal, then `BUN_BE_BUN=1` | `1.4.0` |
| `--revision` | Same removal, then `BUN_BE_BUN=1` | `1.4.0+34cbb9a40` |

The executable hash was unchanged before and after those invocations. Embedded strings independently identify Bun 1.4.0 revision `34cbb9a40`, macOS Silicon. The exact executable used by installed Bend therefore supplies the candidate Bun CLI runtime; no runtime was installed or downloaded. Bun documents that `BUN_BE_BUN=1` selects the CLI instead of starting the embedded program, and that embedded flags then do not apply. This is a reason to specify startup policy explicitly. [Bun compiled-executable behavior](https://bun.com/docs/runtime/code-generation-from-strings).

No standalone `bun` was found on PATH or at the recorded Homebrew, user Bun, mise, asdf and system locations. A bounded exact-basename search of the installed Codex runtime, application Resources and known executable directories found one other compiled runtime: `artifact_tool_rpc_daemon-bun`, 84,751,024 bytes, SHA256 `1a198a935dbfaea98daf1c4a14efcb80c79c4374cbc2e2c150da253d9a24d8cc`. Its strings identify Bun 1.3.0 revision `b0a6feca`; it was not invoked or selected. These searches establish only the inspected locations, not the absence of every possible Bun executable on the machine.

## Separate archive and provenance

Ignored archive: `build/resource-player-client-diagnosis-bun/`. Its `source-79df/` contains byte-identical copies of the previous git-extracted `bend.ts`, `comp.ts`, `main.ts`, `comp-probe.ts` and `probe.ts`. The original commit is `79df8d9c40722ee9507a1e253f283b51025f9d6c`. `main.ts` is archived for provenance and is not imported by the probe. There is no Bun `.bend` plugin in this route.

The compiler patch, helper-comparison report, mismatch bodies, comparison script, embedded ranges and 85/99-file manifests are also copied without modification. The original 193-helper comparison remains applicable to these identical bytes: 184 normalized AST matches, eight scoped-name differences and one checker-local function hoist. No behavioral body change was identified in that review; it is not a formal whole-compiler equivalence proof.

The scratch `base.bend` symlink resolves to the exact installed `/Users/chuah/.bend/bend2/base.bend`, SHA256 `c742fae9c49b14f0cc9128429a2c6109364c8a933a142f2c90b9f2e5fd976661`. Both manifests still match their live canonical Bend, native-effect and Base files. A read-only import-line audit found only relative paths and `Base`: plain has 321 relative/50 Base import rows; boxed has 399 relative/64 Base rows. No named or hash-addressed hub import was found. The probe imports local TypeScript modules and Node builtins only; no npm dependency is requested.

## Explicit startup policy

The pinned `probe.bunfig.toml` contains exactly:

```toml
env = false
preload = []

[install]
auto = "disable"
```

The proposed argv includes `--config` with that absolute file, `--no-env-file` and `--no-install`. All three flag strings occur in the exact executable. Bun documents automatic dotenv disabling, a specified config path, and disabling runtime package installation. These current documents support the policy intent; flag-string presence and version-only success do not prove the full source route parses or applies every option. A flag/config refusal in the first control would stop the experiment. [Runtime CLI options](https://bun.com/docs/runtime), [dotenv policy](https://bun.com/docs/runtime/environment-variables), [config fields](https://bun.com/docs/runtime/bunfig).

The wrapper removes every inherited variable whose name starts with `BUN_` or `NODE_`, then sets only `BUN_BE_BUN=1` from those groups. This removes possible preloads, inspector/JSC tuning and Node loader options. It does not change stack settings, set `--smol` or tune the compiler. It retains `HOME` and ordinary environment values, recording only the resulting canonical environment digest and removed names. No token/environment value is published.

The preparation checked 132 candidate paths across the project, scratch source, their ancestors, HOME and the applicable config directory: `bunfig.toml`, `.bunfig.toml`, `package.json`, `tsconfig.json`, `.env` and dotenv variants. All were absent. No dotenv contents were read. The wrapper refuses source loading if any presence or candidate-path set changes. The pinned explicit config has a distinct filename and is the sole admitted config. This guard is conservative; it does not claim an exhaustive model of every Bun configuration lookup.

## Exact proposed experiment

Default, already executed, performs only Python file/hash audits and prints the plan:

```text
PYTHONDONTWRITEBYTECODE=1 python3 build/resource-player-client-diagnosis-bun/run_graph_probe.py
```

Execution remains ungranted. The reviewable future command is:

```text
PYTHONDONTWRITEBYTECODE=1 python3 build/resource-player-client-diagnosis-bun/run_graph_probe.py --root-bun-graph-slot-granted
```

The first subprocess would receive this shell-independent argv with `BUN_BE_BUN=1`, cwd `/Users/chuah/Documents/ChatGPT/bendex/minecraft`:

```text
/Users/chuah/.bend/bin/bend
--config
/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/resource-player-client-diagnosis-bun/probe.bunfig.toml
--no-env-file
--no-install
/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/resource-player-client-diagnosis-bun/source-79df/probe.ts
/Users/chuah/Documents/ChatGPT/bendex/minecraft/player_client.bend
/Users/chuah/Documents/ChatGPT/bendex/minecraft/build/resource-player-client-diagnosis-bun/plain-manifest.full.json
```

Only after an exit-zero, uncapped, pin-preserving plain control would the same argv run for `resource_player_boxed_client.bend` and `boxed-manifest.full.json`. Each process group retains the original 90-second limit, 8,388,608-byte combined output cap, SIGTERM/2-second grace/SIGKILL route, and refusal to overwrite an existing attempt receipt. The first failure stops the wrapper. No automatic retry, third variant or emission probe is included.

Before and after each case the wrapper verifies the previous 20 pins, all 31 archived Node-generation files, the new preparation pins, both 85/99-file manifests, the Base target and ambient-config absence. The unchanged source harness requires exact loader-file membership, `book_valid` with zero holes, exact native roots and a final dependency audit. The instrumented export calls `file_book`, `done_defs` and `fun_of` to report traversal/graph/layout data. It does not call `compile_book`, `emit_body`, effect-source loading, C generation, Clang, the kernel or a client.

## Interpretation and stop conditions

A valid control must contain `load.end`, `check.end`, `native.file_book.end`, `graph.complete` and `post.audit.pass`, with the expected entry/manifest and no diagnostics. Missing phases or an incorrect native-root/manifest result invalidate the experiment even if the process exits zero. The unchanged harness emits these only after the corresponding calls return normally; root review of both receipts remains required before causal use.

If the plain control fails, retain its receipt and do not start boxed. If it passes, the boxed case can distinguish checker/loading growth from native graph traversal and reachable/layout growth. It cannot measure the installed compiler CLI's internal phases, native fact-pass iteration, fusion/emission, final C assembly or Clang work. Exact runtime bytes strengthen the comparison but do not make source-module execution identical to the embedded compiler bundle. No native timing, speedup or causal bottleneck conclusion follows from preparation or from Node's refusal.

Recorded preparation work consists of version-only discovery, bounded filesystem searches, byte-copy/hash comparisons, Python AST validation and the inert default plan. Compiler-source imports, graph execution, emission, native builds, kernel runs, client launches, UI actions and permission requests are all zero for this generation. The compact [preparation receipt](../evidence/resource-player-client-diagnosis-bun-preparation.json) pins the ignored raw reports and proposed argv. The prior Node diagnosis and both native-timeout generations remain unchanged.
