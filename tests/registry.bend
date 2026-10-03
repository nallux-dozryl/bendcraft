import Base
import ../src/registry.bend as R
import ../src/json.bend as J

def string_value(text: String) -> J.Value:
  J.JString{text}

def strings_json(values: List<&2, String>) -> List<&2, J.Value>:
  match values:
    case Nil{}: Nil{}
    case h <> t: J.JString{h} <> strings_json(t)

def property_value(property: R.Property) -> J.Value:
  match property:
    case R.Property{name, values, count, stride}:
      J.JObject{[J.JMember{"name", J.JString{name}}, J.JMember{"values", J.JArray{strings_json(values)}}, J.JMember{"count", J.JNumber{U32.show(count)}}, J.JMember{"stride", J.JNumber{U32.show(stride)}}]}

def assignment_value(assignment: R.Assignment) -> J.Value:
  match assignment:
    case R.Assignment{name, value}:
      J.JObject{[J.JMember{"name", J.JString{name}}, J.JMember{"value", J.JString{value}}]}

def properties_json(values: List<&2, R.Property>) -> List<&2, J.Value>:
  match values:
    case Nil{}: Nil{}
    case h <> t: property_value(h) <> properties_json(t)

def assignments_json(values: List<&2, R.Assignment>) -> List<&2, J.Value>:
  match values:
    case Nil{}: Nil{}
    case h <> t: assignment_value(h) <> assignments_json(t)

def assignments_text(assignments: List<&2, R.Assignment>) -> String:
  J.encode(J.JArray{assignments_json(assignments)})

def report_id(result: R.Registry & Result<&2, &2, R.Error, U32>) -> R.Registry & String:
  (registry, resolved) = result
  match resolved:
    case Fail{error}: (registry, "error\t" ++ R.error_text(error))
    case Done{state_id}: (registry, "ok\t" ++ U32.show(state_id))

def report_decode(result: R.Registry & Result<&2, &2, R.Error, R.Resolved>) -> R.Registry & String:
  (registry, resolved) = result
  match resolved:
    case Fail{error}: (registry, "error\t" ++ R.error_text(error))
    case Done{R.Resolved{protocol, name, state_id, assignments}}:
      (registry, "ok\t" ++ name ++ "\t" ++ assignments_text(assignments))

def report_block(result: R.Registry & Result<&2, &2, R.Error, R.Block>) -> R.Registry & String:
  (registry, resolved) = result
  match resolved:
    case Fail{error}: (registry, "error\t" ++ R.error_text(error))
    case Done{R.Block{protocol, name, first, count, default_id, properties}}:
      (registry, "meta\t" ++ U32.show(protocol) ++ "\t" ++ U32.show(first) ++ "\t" ++ U32.show(count) ++ "\t" ++ U32.show(default_id) ++ "\t" ++ J.encode(J.JArray{properties_json(properties)}))

def assignment_fields(fields: List<&2, J.Member>) -> Result<&2, &2, R.Error, R.Assignment>:
  match fields:
    case J.JMember{"name", J.JString{name}} <> J.JMember{"value", J.JString{value}} <> Nil{}:
      Done{R.Assignment{name, value}}
    case _: Fail{R.SchemaError{0, "assignment must contain name/value strings"}}

def assignments_add(acc: List<&2, R.Assignment>, result: Result<&2, &2, R.Error, R.Assignment>) -> Result<&2, &2, R.Error, List<&2, R.Assignment>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{assignment}: Done{assignment <> acc}

def assignments_parse(values: List<&2, J.Value>, current: Result<&2, &2, R.Error, List<&2, R.Assignment>>) -> Result<&2, &2, R.Error, List<&2, R.Assignment>>:
  match values current:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{acc}: Done{List.reverse(&2, R.Assignment, acc)}
    case J.JObject{fields} <> rest Done{acc}:
      assignments_parse(rest, assignments_add(acc, assignment_fields(fields)))
    case _ _: Fail{R.SchemaError{0, "assignments must be an object array"}}

def assignments_result(result: Result<&2, &2, String, J.Value>) -> Result<&2, &2, R.Error, List<&2, R.Assignment>>:
  match result:
    case Fail{message}: Fail{R.SchemaError{0, message}}
    case Done{J.JArray{values}}: assignments_parse(values, Done{Nil{}})
    case _: Fail{R.SchemaError{0, "assignments must be an array"}}

def command_resolve(registry: R.Registry, name: String, policy: R.Policy, parsed: Result<&2, &2, R.Error, List<&2, R.Assignment>>) -> R.Registry & String:
  match parsed:
    case Fail{error}: (registry, "error\t" ++ R.error_text(error))
    case Done{assignments}: report_id(R.Registry.resolve(registry, name, assignments, policy))

def command_decode(registry: R.Registry, number: Result<&2, &2, R.Error, U32>) -> R.Registry & String:
  match number:
    case Fail{error}: (registry, "error\t" ++ R.error_text(error))
    case Done{state_id}: report_decode(R.Registry.decode(registry, state_id))

def command_summary(registry: R.Registry) -> R.Registry & String:
  R.Registry{blocks, names, +count, +states} = registry
  (R.Registry{blocks, names, count, states}, "summary\t" ++ U32.show(count) ++ "\t" ++ U32.show(states))

def report_identity(result: R.Registry & Result<&2, &2, String, String>) -> R.Registry & String:
  (registry, result) = result
  match result:
    case Fail{message}: (registry, "identity-error\t" ++ message)
    case Done{hex}: (registry, "identity\t" ++ hex)

# A forged invalid character exercises a real serialization failure. Restore
# the original metadata through the returned owner, then allow later commands.
def forge_block(block: R.Block, code: U32) -> R.Block:
  match block:
    case R.Block{protocol, name, first, count, default_id, properties}:
      R.Block{protocol, name, first, count, default_id, [R.Property{"identity_fixture", [SCon{Chr{code}, SNil{}}], 1, 1}]}

def forged_restore(original: R.Block, pending: R.Registry & Result<&2, &2, String, String>) -> R.Registry & String:
  (registry, result) = pending
  match registry:
    case R.Registry{blocks, names, count, states}:
      report_identity((R.Registry{Array.set(R.Block, blocks, 0, original), names, count, states}, result))

def forged_read(code: U32, names: Map<&2, U32>, count: U32, states: U32, read: Array<R.Block> & R.Block) -> R.Registry & String:
  (blocks, +original) = read
  forged_restore(original, R.Registry.identity(R.Registry{Array.set(R.Block, blocks, 0, forge_block(original, code)), names, count, states}))

def command_forged(registry: R.Registry, code: U32) -> R.Registry & String:
  match registry:
    case R.Registry{blocks, names, count, states}:
      forged_read(code, names, count, states, Array.get(R.Block, blocks, 0))

type CommandKind is Data:
  Summary{}
  Identity{}
  ForgedSurrogate{}
  ForgedRange{}
  Metadata{}
  Decode{}
  Resolve{}
  Invalid{}

def command_kind(text: String) -> CommandKind:
  match text:
    case "summary": Summary{}
    case "identity": Identity{}
    case "identity-forged-surrogate": ForgedSurrogate{}
    case "identity-forged-range": ForgedRange{}
    case "meta": Metadata{}
    case "decode": Decode{}
    case "resolve": Resolve{}
    case _: Invalid{}

def command_policy(registry: R.Registry, name: String, policy: String, assignments: String) -> R.Registry & String:
  match policy:
    case "exact": command_resolve(registry, name, R.Exact{}, assignments_result(J.parse(assignments)))
    case "defaults": command_resolve(registry, name, R.Defaults{}, assignments_result(J.parse(assignments)))
    case _: (registry, "error\tinvalid-command")

def command_parsed(registry: R.Registry, kind: CommandKind, fields: List<&2, String>) -> R.Registry & String:
  match kind fields:
    case Summary{} Nil{}: command_summary(registry)
    case Identity{} Nil{}: report_identity(R.Registry.identity(registry))
    case ForgedSurrogate{} Nil{}: command_forged(registry, 55296)
    case ForgedRange{} Nil{}: command_forged(registry, 1114112)
    case Metadata{} name <> Nil{}: report_block(R.Registry.block(registry, name))
    case Decode{} state <> Nil{}: command_decode(registry, R.number(0, "state ID", state))
    case Resolve{} name <> policy <> assignments <> Nil{}: command_policy(registry, name, policy, assignments)
    case _ _: (registry, "error\tinvalid-command")

def command(registry: R.Registry, fields: List<&2, String>) -> R.Registry & String:
  match fields:
    case operation <> rest: command_parsed(registry, command_kind(operation), rest)
    case _: (registry, "error\tinvalid-command")

def commands(lines: List<&2, String>, previous: R.Registry & String) -> IO(Unit):
  match lines:
    case Nil{}:
      (registry, output) = previous
      IO.print(output)
    case SNil{} <> Nil{}:
      (registry, output) = previous
      IO.print(output)
    case line <> rest:
      (registry, output) = previous
      do IO<Unit>:
        IO.print(output)
        commands(rest, command(registry, String.split(line, '\t')))

# The final empty String.lines element is omitted before command processing.
def commands_first(lines: List<&2, String>, registry: R.Registry) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit, Unit{})
    case SNil{} <> Nil{}: IO.pure(Unit, Unit{})
    case line <> rest: commands(rest, command(registry, String.split(line, '\t')))

def commands_read(registry: R.Registry, result: Result<&2, &2, R.Error, String>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 2, R.error_text(error))
    case Done{text}: commands_first(String.lines(text), registry)

def report_loaded(result: R.Registry & String) -> IO(Unit):
  (registry, output) = result
  IO.print(output)

def loaded(result: Result<&2, &1, R.Error, R.Registry>, mode: String, path: String) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("load-error\t" ++ R.error_text(error))
    case Done{registry}:
      match mode:
        case "batch":
          do IO<Unit>:
            cases : Result<&2, &2, R.Error, String> <- R.read_text(path)
            commands_read(registry, cases)
        case _:
          report_loaded(command(registry, ["summary"]))

def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case registry_path <> mode <> case_path <> Nil{}:
      do IO<Unit>:
        result : Result<&2, &1, R.Error, R.Registry> <- R.Registry.load(registry_path)
        loaded(result, mode, case_path)
    case registry_path <> Nil{}:
      do IO<Unit>:
        result : Result<&2, &1, R.Error, R.Registry> <- R.Registry.load(registry_path)
        loaded(result, "summary", "")
    case _: IO.die(Unit, 2, "usage: registry-tests REGISTRY_TSV [batch QUERY_TSV]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(List.tail(&1, String, args))
