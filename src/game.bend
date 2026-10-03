import Base
import ./core.bend as C
import ./json.bend as J
import ./live.bend as L
import ./registry.bend as R

# The simulation and metadata have one owner, retained by the server actor.
type Engine is Type:
  Engine{world: C.World, registry: R.Registry}

type Query is Data:
  Metadata{}
  DecodeState{}
  ResolveState{}

type Extension is Data:
  Extension{query: Query, name: String, fields: List<&2, L.Field>, description: String}

type Resolution is Data:
  Resolution{name: String, assignments: List<&2, R.Assignment>, policy: R.Policy}

def new(registry: R.Registry) -> Engine:
  R.Registry{blocks, names, count, +states} = registry
  Engine{C.new(states), R.Registry{blocks, names, count, states}}

def realtime_step(engine: Engine) -> Engine:
  Engine{world, registry} = engine
  Engine{C.realtime_step(world), registry}

def pack(registry: R.Registry, result: C.World & L.Session & J.Value) -> Engine & L.Session & J.Value:
  (world, session, value) = result
  (Engine{world, registry}, session, value)

def success(engine: Engine, session: L.Session, id: String, value: J.Value) -> Engine & L.Session & J.Value:
  Engine{world, registry} = engine
  pack(registry, L.success(world, session, id, value))

def failure(engine: Engine, session: L.Session, id: String, fault: L.Fault) -> Engine & L.Session & J.Value:
  Engine{world, registry} = engine
  pack(registry, L.failure(world, session, id, fault))

def catalog() -> List<&2, Extension>:
  [Extension{Metadata{}, "registry.block", [L.Field{"name", L.Text{[]}, True{}}], "Return loaded block protocol/state metadata and ordered property domains."},
   Extension{DecodeState{}, "registry.state.decode", [L.Field{"state", L.Unsigned{0, 4294967295}, True{}}], "Resolve a loaded state ID to a block name and exact ordered property assignments."},
   Extension{ResolveState{}, "registry.state.resolve", [L.Field{"name", L.Text{[]}, True{}}, L.Field{"properties", L.StringMap{}, True{}}, L.Field{"policy", L.Text{["exact", "defaults"]}, True{}}], "Resolve a name and string properties to a state ID; choose exact completeness or explicit default expansion."}]

def extension_value(extension: Extension) -> J.Value:
  Extension{query, +name, fields, description} = extension
  L.obj([J.JMember{"name", L.text(name)}, J.JMember{"phase", L.text("query")}, J.JMember{"permitted_mode", L.text("developer")},
    J.JMember{"version", L.text("26.3")}, J.JMember{"status", L.text("implemented-foundation")}, J.JMember{"scheduled", L.boolean(False{})},
    J.JMember{"description", L.text(description)}, J.JMember{"input_schema", L.request_schema(name, fields, False{})}])

def extension_values(extensions: List<&2, Extension>) -> List<&2, J.Value>:
  match extensions:
    case Nil{}: []
    case head <> tail: extension_value(head) <> extension_values(tail)

def discovery() -> J.Value:
  L.obj([J.JMember{"version", L.text("26.3")}, J.JMember{"surface", L.text("registry-section-and-tick-foundation")},
    J.JMember{"operations", J.JArray{List.append(&2, J.Value, L.catalog_values(L.catalog()), extension_values(catalog()))}},
    J.JMember{"subscriptions", L.boolean(False{})}, J.JMember{"batch", L.boolean(False{})}, J.JMember{"player_mode", L.boolean(False{})}])

def lookup(extensions: List<&2, Extension>, +name: String) -> Maybe<&2, Extension>:
  match extensions:
    case Nil{}: None{}
    case +head <> tail:
      Extension{query, actual, fields, description} = head
      J.choose(Maybe<&2, Extension>, Some{head}, lookup(tail, name), String.eq(actual, name))

def property_values(properties: List<&2, R.Property>) -> List<&2, J.Value>:
  match properties:
    case Nil{}: []
    case R.Property{name, values, count, stride} <> tail:
      L.obj([J.JMember{"name", L.text(name)}, J.JMember{"values", J.JArray{L.texts(values)}},
        J.JMember{"count", L.uint(count)}, J.JMember{"stride", L.uint(stride)}]) <> property_values(tail)

def block_value(block: R.Block) -> J.Value:
  R.Block{protocol, name, first, count, default_id, properties} = block
  L.obj([J.JMember{"protocol_id", L.uint(protocol)}, J.JMember{"name", L.text(name)},
    J.JMember{"first_state_id", L.uint(first)}, J.JMember{"state_count", L.uint(count)},
    J.JMember{"default_state_id", L.uint(default_id)}, J.JMember{"properties", J.JArray{property_values(properties)}}])

def assignment_values(assignments: List<&2, R.Assignment>) -> List<&2, J.Member>:
  match assignments:
    case Nil{}: []
    case R.Assignment{name, value} <> tail: J.JMember{name, L.text(value)} <> assignment_values(tail)

def resolved_value(resolved: R.Resolved) -> J.Value:
  R.Resolved{protocol, name, state, assignments} = resolved
  L.obj([J.JMember{"protocol_id", L.uint(protocol)}, J.JMember{"name", L.text(name)},
    J.JMember{"state", L.uint(state)}, J.JMember{"properties", L.obj(assignment_values(assignments))}])

def registry_fault(error: R.Error) -> L.Fault:
  match error:
    case R.InvalidResource{name}: L.bad("InvalidResource", name)
    case R.UnknownBlock{name}: L.bad("UnknownBlock", name)
    case R.InvalidState{state}: L.bad("InvalidState", U32.show(state))
    case R.UnknownProperty{name}: L.bad("UnknownProperty", name)
    case R.DuplicateProperty{name}: L.bad("DuplicateProperty", name)
    case R.MissingProperty{name}: L.bad("MissingProperty", name)
    case R.InvalidValue{property, value}: L.bad("InvalidValue", property ++ "=" ++ value)
    case other: L.bad("RegistryError", R.error_text(other))

def block_result(world: C.World, session: L.Session, id: String, result: R.Registry & Result<&2, &2, R.Error, R.Block>) -> Engine & L.Session & J.Value:
  (registry, status) = result
  match status:
    case Fail{error}: failure(Engine{world, registry}, session, id, registry_fault(error))
    case Done{block}: success(Engine{world, registry}, session, id, block_value(block))

def decoded_result(world: C.World, session: L.Session, id: String, result: R.Registry & Result<&2, &2, R.Error, R.Resolved>) -> Engine & L.Session & J.Value:
  (registry, status) = result
  match status:
    case Fail{error}: failure(Engine{world, registry}, session, id, registry_fault(error))
    case Done{resolved}: success(Engine{world, registry}, session, id, resolved_value(resolved))

def state_result(world: C.World, session: L.Session, id: String, result: R.Registry & Result<&2, &2, R.Error, U32>) -> Engine & L.Session & J.Value:
  (registry, status) = result
  match status:
    case Fail{error}: failure(Engine{world, registry}, session, id, registry_fault(error))
    case Done{state}: success(Engine{world, registry}, session, id, L.obj([J.JMember{"state", L.uint(state)}]))

def assignments(members: List<&2, J.Member>) -> List<&2, R.Assignment>:
  match members:
    case Nil{}: []
    case J.JMember{name, J.JString{value}} <> tail: R.Assignment{name, value} <> assignments(tail)
    case _: []

def properties(value: Maybe<&2, J.Value>) -> List<&2, R.Assignment>:
  match value:
    case Some{J.JObject{members}}: assignments(members)
    case _: []

def decoded_name(result: Result<&2, &2, L.Fault, String>, engine: Engine, session: L.Session, id: String) -> Engine & L.Session & J.Value:
  match result:
    case Fail{fault}: failure(engine, session, id, fault)
    case Done{name}:
      Engine{world, registry} = engine
      block_result(world, session, id, R.Registry.block(registry, name))

def decoded_state(result: Result<&2, &2, L.Fault, U32>, engine: Engine, session: L.Session, id: String) -> Engine & L.Session & J.Value:
  match result:
    case Fail{fault}: failure(engine, session, id, fault)
    case Done{state}:
      Engine{world, registry} = engine
      decoded_result(world, session, id, R.Registry.decode(registry, state))

def resolution(+args: J.Value) -> Result<&2, &2, L.Fault, Resolution>:
  do Result<&2, &2, L.Fault, Resolution>:
    name : String <- L.get_string(args, "name")
    policy : String <- L.get_string(args, "policy")
    return Resolution{name, properties(J.member(args, "properties")), J.choose(R.Policy, R.Exact{}, R.Defaults{}, String.eq(policy, "exact"))}

def decoded_resolution(result: Result<&2, &2, L.Fault, Resolution>, engine: Engine, session: L.Session, id: String) -> Engine & L.Session & J.Value:
  match result:
    case Fail{fault}: failure(engine, session, id, fault)
    case Done{Resolution{name, props, policy}}:
      Engine{world, registry} = engine
      state_result(world, session, id, R.Registry.resolve(registry, name, props, policy))

def execute(query: Query, engine: Engine, session: L.Session, id: String, +args: J.Value) -> Engine & L.Session & J.Value:
  match query:
    case Metadata{}: decoded_name(L.get_string(args, "name"), engine, session, id)
    case DecodeState{}: decoded_state(L.get_number(args, "state", False{}), engine, session, id)
    case ResolveState{}: decoded_resolution(resolution(args), engine, session, id)

def checked(valid: Bool, allowed: Bool, query: Query, engine: Engine, session: L.Session, id: String, args: J.Value) -> Engine & L.Session & J.Value:
  match valid allowed:
    case False{} _: failure(engine, session, id, L.bad("InvalidArguments", "arguments or scheduled at field do not match the operation schema"))
    case True{} False{}: failure(engine, session, id, L.bad("PermissionDenied", "developer capability required"))
    case True{} True{}: execute(query, engine, session, id, args)

def extension(found: Maybe<&2, Extension>, engine: Engine, +session: L.Session, id: String, +args: J.Value, at: Maybe<&2, Nat>) -> Engine & L.Session & J.Value:
  match found:
    case None{}: failure(engine, session, id, L.bad("UnknownOperation", "operation is not implemented"))
    case Some{Extension{query, name, fields, description}}:
      checked(L.validate_args(args, fields) && Maybe.is_none(&2, Nat, at), C.developer(L.capability(session)), query, engine, session, id, args)

def discovery_ready(valid: Bool, engine: Engine, session: L.Session, id: String) -> Engine & L.Session & J.Value:
  match valid:
    case False{}: failure(engine, session, id, L.bad("InvalidArguments", "discover requires empty arguments and no at field"))
    case True{}: success(engine, session, id, discovery())

def dispatch_custom(envelope: L.Envelope, engine: Engine, session: L.Session) -> Engine & L.Session & J.Value:
  L.Envelope{id, op, args, at} = envelope
  match op:
    case "discover":
      discovery_ready(L.validate_args(args, []) && Maybe.is_none(&2, Nat, at), engine, session, id)
    case name: extension(lookup(catalog(), name), engine, session, id, args, at)

def dispatch_chosen(custom: Bool, envelope: L.Envelope, engine: Engine, session: L.Session, token: String, request: J.Value) -> Engine & L.Session & J.Value:
  match custom:
    case False{}:
      Engine{world, registry} = engine
      pack(registry, L.dispatch(world, session, token, request))
    case True{}:
      L.Session{peer, sequence, cap} = session
      dispatch_custom(envelope, engine, L.Session{peer, 1n+sequence, cap})

def dispatch_parsed(parsed: Result<&2, &2, L.Fault, L.Envelope>, engine: Engine, session: L.Session, token: String, request: J.Value) -> Engine & L.Session & J.Value:
  match parsed:
    case Fail{fault}:
      Engine{world, registry} = engine
      pack(registry, L.dispatch(world, session, token, request))
    case Done{+envelope}:
      L.Envelope{id, +op, args, at} = envelope
      dispatch_chosen(String.eq(op, "discover") || Maybe.is_some(&2, Extension, lookup(catalog(), op)), envelope, engine, session, token, request)

def dispatch_inner(engine: Engine, session: L.Session, token: String, +request: J.Value) -> Engine & L.Session & J.Value:
  dispatch_parsed(L.envelope(request), engine, session, token, request)

def dispatch(engine: Engine, session: L.Session, token: String, request: J.Value) -> Engine & L.Session & J.Value:
  dispatch_inner(engine, session, token, request)

def configured_registry(result: Result<&1, &1, U32 & String, String>) -> String:
  match result:
    case Fail{error}: "generated/reference_blocks.tsv"
    case Done{path}: path

def loaded(result: Result<&2, &1, R.Error, R.Registry>) -> IO(Engine):
  match result:
    case Fail{error}: IO.die(Engine, 1, "block registry loading failed: " ++ R.error_text(error))
    case Done{registry}: IO.pure(Engine, new(registry))

def load() -> IO(Engine):
  do IO<Engine>:
    path : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_BLOCK_REGISTRY")
    registry : Result<&2, &1, R.Error, R.Registry> <- R.Registry.load(configured_registry(path))
    loaded(registry)
