import Base
import ../src/extended_persistence.bend as E
import ../src/persistence.bend as P
import ../src/world_codec.bend as W
import ../src/nbt.bend as N
import ../src/game.bend as G
import ../src/core.bend as C
import ../src/live.bend as L
import ../src/json.bend as J

# This owned Array fixture exercises the extension ABI; it is not player state.
type Extra is Type:
  Extra{cells: Array<U32>, generation: U32, blocked: Bool}

def initial(u: Unit) -> Result<&2, &1, String, Extra>:
  Done{Extra{[0 : U32*8n], 0, False{}}}

def refuse_legacy(u: Unit) -> Result<&2, &1, String, Extra>:
  Fail{"core-only snapshot requires an explicitly enabled extension migration"}

def array_join_results(left: Array<U32>, right: Array<U32>, first: Result<&2, &2, String, List<&2, U32>>, second: Result<&2, &2, String, List<&2, U32>>) -> Array<U32> & Result<&2, &2, String, List<&2, U32>>:
  (ANode{left, right}, (do Result<&2, &2, String, List<&2, U32>>:
    l : List<&2, U32> <- first
    r : List<&2, U32> <- second
    return List.append(&2, U32, l, r)))

def array_join(first: Array<U32> & Result<&2, &2, String, List<&2, U32>>, second: Array<U32> & Result<&2, &2, String, List<&2, U32>>) -> Array<U32> & Result<&2, &2, String, List<&2, U32>>:
  (left, l) = first
  (right, r) = second
  array_join_results(left, right, l, r)

def array_values(depth: Nat, cells: Array<U32>) -> Array<U32> & Result<&2, &2, String, List<&2, U32>>:
  match depth cells:
    case 0n ALeaf{+value}: (ALeaf{value}, Done{[value]})
    case 1n+ +n ANode{left, right}: array_join(array_values(n, left), array_values(n, right))
    case _ other: (other, Fail{"fixture requires exactly eight balanced Array cells"})

def payload_root(cells: List<&2, U32>, generation: U32) -> N.Root:
  N.Root{W.text("bendex:fixture-array"), N.Compound{[W.named("cells", N.IntArray{cells}), W.named("generation", N.Int{generation})]}}

def encoded_values(+generation: U32, blocked: Bool, values: Array<U32> & Result<&2, &2, String, List<&2, U32>>) -> Extra & Result<&2, &2, String, List<&2, U32>>:
  (cells, result) = values
  (Extra{cells, generation, blocked}, (do Result<&2, &2, String, List<&2, U32>>:
    bytes : List<&2, U32> <- result
    N.encode_with(N.Limits{65536, 4, 8}, payload_root(bytes, generation))))

def encode(extra: Extra) -> Extra & Result<&2, &2, String, List<&2, U32>>:
  match extra:
    case Extra{cells, generation, True{}}: (Extra{cells, generation, True{}}, Fail{"fixture extension encode blocked"})
    case Extra{cells, +generation, False{}}: encoded_values(generation, False{}, array_values(3n, cells))

def decoded_cells(generation: U32, value: N.Value) -> Result<&2, &1, String, Extra>:
  match value:
    case N.IntArray{a <> b <> c <> d <> e <> f <> g <> h <> Nil{}}:
      Done{Extra{ANode{ANode{ANode{ALeaf{a}, ALeaf{b}}, ANode{ALeaf{c}, ALeaf{d}}}, ANode{ANode{ALeaf{e}, ALeaf{f}}, ANode{ALeaf{g}, ALeaf{h}}}}, generation, False{}}}
    case _: Fail{"fixture cells require IntArray of exactly eight U32 values"}

def decoded_fields(generation: Result<&2, &2, String, U32>, cells: N.Value) -> Result<&2, &1, String, Extra>:
  match generation:
    case Fail{message}: Fail{message}
    case Done{value}: decoded_cells(value, cells)

def decoded_members(schema: U32, fields: Result<&2, &2, String, List<&2, W.Field>>) -> Result<&2, &1, String, Extra>:
  match schema fields:
    case _ Fail{message}: Fail{message}
    case 1 Done{+fs}: decoded_cells(0, W.field(fs, "cells"))
    case 2 Done{+fs}: decoded_fields(W.int_value(W.field(fs, "generation")), W.field(fs, "cells"))
    case _ _: Fail{"unsupported fixture schema version"}

def decoded_root(+schema: U32, value: N.Value, name: Result<&2, &2, String, String>) -> Result<&2, &1, String, Extra>:
  match name:
    case Fail{message}: Fail{message}
    case Done{"bendex:fixture-array"}:
      decoded_members(schema, W.fields(W.default_limits(), value, N.choose(List<&2, String>, ["cells"], ["cells", "generation"], U32.is_eq(schema, 1))))
    case Done{other}: Fail{"wrong fixture extension root name"}

def decoded(schema: U32, root: Result<&2, &2, String, N.Root>) -> Result<&2, &1, String, Extra>:
  match root:
    case Fail{message}: Fail{message}
    case Done{N.Root{name, value}}: decoded_root(schema, value, W.read_text(W.default_limits(), name))

def decode(schema: U32, bytes: List<&2, U32>) -> Result<&2, &1, String, Extra>:
  match schema:
    case 1: decoded(1, N.decode_with(N.Limits{65536, 4, 8}, bytes))
    case 2: decoded(2, N.decode_with(N.Limits{65536, 4, 8}, bytes))
    case _: Fail{"unsupported fixture schema version"}

law checked_unknown_schema:
  {decode(3, []) == Fail{"unsupported fixture schema version"} : Result<&2, &1, String, Extra>}

def checked_unknown_schema():
  {==}

law checked_array_error_owner:
  {encode(Extra{ANode{ALeaf{17}, ALeaf{18}}, 7, False{}}) ==
    (Extra{ANode{ALeaf{17}, ALeaf{18}}, 7, False{}}, Fail{"fixture requires exactly eight balanced Array cells"}) : Extra & Result<&2, &2, String, List<&2, U32>>}

def checked_array_error_owner():
  {==}

# Closed hooks are constructed from preceding fully defined checked functions.
def codec() -> E.Codec<Extra>:
  E.Codec{"bendex:fixture-array", 2, encode, decode, initial, refuse_legacy}

def explicit_core_init_codec() -> E.Codec<Extra>:
  E.Codec{"bendex:fixture-array", 2, encode, decode, initial, initial}

def fields(op: String) -> List<&2, L.Field>:
  match op:
    case "extra.set": [L.Field{"index", L.Unsigned{0, 7}, True{}}, L.Field{"value", L.Unsigned{0, 4294967295}, True{}}]
    case "extra.block": [L.Field{"blocked", L.Boolean{}, True{}}]
    case _: []

def catalog(u: Unit) -> List<&2, E.Operation>:
  [E.Operation{"extra.get", L.Public{}, [], "Read the fixture's owned eight cells, generation and encode-block flag."},
   E.Operation{"extra.set", L.DeveloperOnly{}, fields("extra.set"), "Update one checked fixture cell and advance its generation without U32 wrap."},
   E.Operation{"extra.block", L.DeveloperOnly{}, fields("extra.block"), "Toggle an explicit fixture encoding failure; the blocked flag is never persisted."}]

def numbers(values: List<&2, U32>) -> List<&2, J.Value>:
  match values:
    case Nil{}: []
    case h <> t: L.uint(h) <> numbers(t)

def fault_values(result: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, L.Fault, List<&2, U32>>:
  match result:
    case Fail{message}: Fail{L.bad("InvalidExtra", message)}
    case Done{values}: Done{values}

def snapshot_result(engine: G.Engine, +generation: U32, +blocked: Bool, values: Array<U32> & Result<&2, &2, String, List<&2, U32>>) -> G.Engine & Extra & Result<&2, &2, L.Fault, J.Value>:
  (cells, result) = values
  (engine, Extra{cells, generation, blocked}, (do Result<&2, &2, L.Fault, J.Value>:
    values : List<&2, U32> <- fault_values(result)
    return L.obj([J.JMember{"cells", J.JArray{numbers(values)}}, J.JMember{"generation", L.uint(generation)}, J.JMember{"blocked", L.boolean(blocked)}])))

def snapshot(engine: G.Engine, extra: Extra) -> G.Engine & Extra & Result<&2, &2, L.Fault, J.Value>:
  Extra{cells, generation, blocked} = extra
  snapshot_result(engine, generation, blocked, array_values(3n, cells))

def set_ready(exhausted: Bool, engine: G.Engine, extra: Extra, index: U32, value: U32) -> G.Engine & Extra & Result<&2, &2, L.Fault, J.Value>:
  match exhausted:
    case True{}: (engine, extra, Fail{L.bad("GenerationExhausted", "fixture generation range exhausted")})
    case False{}:
      Extra{cells, generation, blocked} = extra
      snapshot(engine, Extra{Array.set(U32, cells, index, value), U32.inc(generation), blocked})

def set_values(args: Result<&2, &2, L.Fault, W.Both<U32, U32>>, engine: G.Engine, extra: Extra) -> G.Engine & Extra & Result<&2, &2, L.Fault, J.Value>:
  match args:
    case Fail{fault}: (engine, extra, Fail{fault})
    case Done{W.Both{index, value}}:
      Extra{cells, +generation, blocked} = extra
      set_ready(U32.is_eq(generation, 4294967295), engine, Extra{cells, generation, blocked}, index, value)

def set_args(+args: J.Value) -> Result<&2, &2, L.Fault, W.Both<U32, U32>>:
  do Result<&2, &2, L.Fault, W.Both<U32, U32>>:
    index : U32 <- L.get_number(args, "index", False{})
    value : U32 <- L.get_number(args, "value", False{})
    return W.Both{index, value}

def block_value(value: Result<&2, &2, L.Fault, Bool>, engine: G.Engine, extra: Extra) -> G.Engine & Extra & Result<&2, &2, L.Fault, J.Value>:
  match value:
    case Fail{fault}: (engine, extra, Fail{fault})
    case Done{blocked}:
      Extra{cells, generation, old} = extra
      snapshot(engine, Extra{cells, generation, blocked})

def execute(op: String, engine: G.Engine, extra: Extra, args: J.Value) -> G.Engine & Extra & Result<&2, &2, L.Fault, J.Value>:
  match op:
    case "extra.get": snapshot(engine, extra)
    case "extra.set": set_values(set_args(args), engine, extra)
    case "extra.block": block_value(L.get_bool(args, "blocked"), engine, extra)
    case _: (engine, extra, Fail{L.bad("UnknownOperation", "unknown compiled fixture extension")})

def dispatch(engine: G.Engine, extra: Extra, session: L.Session, envelope: L.Envelope) -> G.Engine & Extra & Result<&2, &2, L.Fault, J.Value>:
  L.Envelope{id, op, args, at} = envelope
  execute(op, engine, extra, args)

def operations() -> E.Operations<Extra>:
  E.Operations{catalog, dispatch}

# Test-entry choices are compiled closed compositions, not externally loaded code.
def reserved_catalog(u: Unit) -> List<&2, E.Operation>:
  [E.Operation{"world.save", L.Public{}, [], "reserved interception fixture"}]

def duplicate_catalog(u: Unit) -> List<&2, E.Operation>:
  [E.Operation{"extra.get", L.Public{}, [], "first"}, E.Operation{"extra.get", L.Public{}, [], "duplicate"}]

def invalid_catalog(u: Unit) -> List<&2, E.Operation>:
  [E.Operation{"extra.bad", L.Public{}, [L.Field{"value", L.Unsigned{8, 7}, True{}}], "invalid schema fixture"}]

def bad_namespace_codec() -> E.Codec<Extra>:
  E.Codec{"../outside", 2, encode, decode, initial, refuse_legacy}

def bad_schema_codec() -> E.Codec<Extra>:
  E.Codec{"bendex:fixture-array", 0, encode, decode, initial, refuse_legacy}

def failed_initial(u: Unit) -> Result<&2, &1, String, Extra>:
  Fail{"explicit fixture initialization rejection"}

def failed_initial_codec() -> E.Codec<Extra>:
  E.Codec{"bendex:fixture-array", 2, encode, decode, failed_initial, refuse_legacy}

def reserved_operations() -> E.Operations<Extra>:
  E.Operations{reserved_catalog, dispatch}

def duplicate_operations() -> E.Operations<Extra>:
  E.Operations{duplicate_catalog, dispatch}

def invalid_operations() -> E.Operations<Extra>:
  E.Operations{invalid_catalog, dispatch}

# Finite codec/owner and migration probes; real IO lives in the independent runner.
def migration_ok(result: Result<&2, &1, String, Extra>) -> Bool:
  match result:
    case Done{Extra{cells, 0, False{}}}: True{}
    case _: False{}

def migration_bytes(result: Result<&2, &2, String, List<&2, U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: migration_ok(decode(1, bytes))

def cell_zero(pair: Array<U32> & U32) -> Bool:
  (cells, value) = pair
  U32.is_eq(value, 0)

def blocked_owner(result: Extra & Result<&2, &2, String, List<&2, U32>>) -> Bool:
  match result:
    case Tuple{Extra{cells, 7, True{}}, Fail{"fixture extension encode blocked"}}:
      cell_zero(cells[5])
    case _: False{}

def legacy_failed(result: Result<&2, &1, String, Extra>) -> Bool:
  match result:
    case Fail{message}: True{}
    case _: False{}

def regressions() -> Bool:
  E.valid_catalog(128n, catalog(Unit{}), []) && Bool.not(E.valid_catalog(128n, [E.Operation{"world.save", L.Public{}, [], "collision"}], [])) &&
  blocked_owner(encode(Extra{[0 : U32*8n], 7, True{}})) && legacy_failed(refuse_legacy(Unit{})) &&
  migration_bytes(N.encode(N.Root{W.text("bendex:fixture-array"), N.Compound{[W.named("cells", N.IntArray{[0, 1, 2, 3, 4, 5, 6, 4294967295]})]}})) &&
  Bool.not(E.valid_name("../world")) && E.valid_name("bendex:fixture-array")

def main() -> IO(Unit):
  IO.print(N.choose(String, "regressions\tpass", "regressions\tFAIL", regressions()))
