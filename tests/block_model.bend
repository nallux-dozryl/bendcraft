import Base
import ../src/json.bend as J
import ../src/block_model.bend as M

def text(value: String) -> J.Value:
  J.JString{value}

def number(value: U32) -> J.Value:
  J.JNumber{U32.show(value)}

def object(members: List<&2, J.Member>) -> J.Value:
  J.JObject{members}

def hex_word(fuel: Nat, +value: U32, +shift: U32) -> String:
  match fuel:
    case 0n: ""
    case 1n+p:
      Char.show(J.hex_char(U32.and(U32.shrn(value, U32.to_nat(shift)), 15))) ++ hex_word(p, value, U32.sub(shift, 4))

def bits(value: F32) -> J.Value:
  match value:
    case F32{word}: text(hex_word(8n, U32{word}, 28))

def vector(value: M.Vec3) -> J.Value:
  match value:
    case M.Vec3{x, y, z}: J.JArray{bits(x) <> bits(y) <> bits(z) <> Nil{}}

def direction(value: M.Direction) -> String:
  match value:
    case M.Down{}: "down"
    case M.Up{}: "up"
    case M.North{}: "north"
    case M.South{}: "south"
    case M.West{}: "west"
    case M.East{}: "east"

def maybe_direction(value: Maybe<&2, M.Direction>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{d}: text(direction(d))

def maybe_string(value: Maybe<&2, String>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{s}: text(s)

def maybe_bool(value: Maybe<&2, Bool>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{b}: J.JBool{b}

def light(value: M.GuiLight) -> J.Value:
  match value:
    case M.Side{}: text("side")
    case M.Front{}: text("front")

def maybe_light(value: Maybe<&2, M.GuiLight>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{v}: light(v)

def uv(value: Maybe<&2, M.UV>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{M.UV{u0, v0, u1, v1}}: J.JArray{bits(u0) <> bits(v0) <> bits(u1) <> bits(v1) <> Nil{}}

def axis(value: M.Axis) -> J.Value:
  match value:
    case M.X{}: text("x")
    case M.Y{}: text("y")
    case M.Z{}: text("z")

def rotation_value(value: M.RotationValue) -> J.Value:
  match value:
    case M.SingleAxis{a, angle}:
      object(J.JMember{"kind", text("axis")} <> J.JMember{"axis", axis(a)} <> J.JMember{"angle", bits(angle)} <> Nil{})
    case M.Euler{angles}: object(J.JMember{"kind", text("euler")} <> J.JMember{"angles", vector(angles)} <> Nil{})

def rotation(value: Maybe<&2, M.Rotation>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{M.Rotation{origin, v, rescale}}:
      object(J.JMember{"origin", vector(origin)} <> J.JMember{"value", rotation_value(v)} <>
        J.JMember{"rescale", J.JBool{rescale}} <> Nil{})

def face(value: M.Face) -> J.Member:
  match value:
    case M.Face{d, cull, coords, turn, texture, tint}:
      J.JMember{direction(d), object(J.JMember{"cull", maybe_direction(cull)} <>
        J.JMember{"uv", uv(coords)} <> J.JMember{"rotation", number(turn)} <>
        J.JMember{"texture", text(texture)} <> J.JMember{"tint_index", number(tint)} <> Nil{})}

def faces(values: List<&2, M.Face>) -> List<&2, J.Member>:
  match values:
    case Nil{}: Nil{}
    case h <> t: face(h) <> faces(t)

def element(value: M.Element) -> J.Value:
  match value:
    case M.Element{from, to, rot, fs, emission, shade}:
      object(J.JMember{"from", vector(from)} <> J.JMember{"to", vector(to)} <>
        J.JMember{"rotation", rotation(rot)} <> J.JMember{"faces", object(faces(fs))} <>
        J.JMember{"light_emission", number(emission)} <> J.JMember{"shade_direction_override", maybe_direction(shade)} <> Nil{})

def elements(values: List<&2, M.Element>) -> List<&2, J.Value>:
  match values:
    case Nil{}: Nil{}
    case h <> t: element(h) <> elements(t)

def maybe_elements(values: Maybe<&2, List<&2, M.Element>>) -> J.Value:
  match values:
    case None{}: J.JNull{}
    case Some{vs}: J.JArray{elements(vs)}

def transform(value: M.Transform) -> J.Value:
  match value:
    case M.Transform{r, t, s}:
      object(J.JMember{"rotation", vector(r)} <> J.JMember{"translation", vector(t)} <> J.JMember{"scale", vector(s)} <> Nil{})

def display_fields(names: List<&2, String>, +transforms: Map<&2, M.Transform>) -> List<&2, J.Member>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest:
      J.JMember{name, transform(M.map_value(M.Transform, Map.get(M.Transform, M.identity_transform(), transforms, name)))} <>
        display_fields(rest, transforms)

def display(value: M.Display) -> J.Value:
  match value:
    case M.Display{transforms}: object(display_fields(M.display_names(), transforms))

def maybe_display(value: Maybe<&2, M.Display>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{v}: display(v)

def texture(value: M.Texture) -> J.Value:
  match value:
    case M.Sprite{M.Material{sprite, force}}:
      object(J.JMember{"kind", text("sprite")} <> J.JMember{"sprite", text(sprite)} <>
        J.JMember{"force_translucent", J.JBool{force}} <> Nil{})
    case M.Alias{slot}: object(J.JMember{"kind", text("alias")} <> J.JMember{"slot", text(slot)} <> Nil{})

def texture_fields(names: List<&2, String>, +textures: Map<&2, M.Texture>) -> List<&2, J.Member>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest:
      J.JMember{name, texture(M.map_value(M.Texture, Map.get(M.Texture, M.Alias{""}, textures, name)))} <>
        texture_fields(rest, textures)

def model(value: M.Model) -> J.Value:
  match value:
    case M.Model{parent, es, ao, gui, transforms, +textures}:
      object(J.JMember{"parent", maybe_string(parent)} <> J.JMember{"elements", maybe_elements(es)} <>
        J.JMember{"ambient_occlusion", maybe_bool(ao)} <> J.JMember{"gui_light", maybe_light(gui)} <>
        J.JMember{"display", maybe_display(transforms)} <>
        J.JMember{"textures", object(texture_fields(Map.keys(&2, M.Texture, textures), textures))} <> Nil{})

def report(result: Result<&2, &2, M.Error, M.Model>) -> String:
  match result:
    case Fail{M.Error{code, path}}: "error\t" ++ code ++ "\t" ++ path
    case Done{value}: "ok\t" ++ J.encode(model(value))

def parsed(result: Result<&2, &2, String, J.Value>) -> String:
  match result:
    case Fail{message}: "json-error\t" ++ message
    case Done{value}: report(M.decode(value))

def material(value: Maybe<&2, M.Material>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{M.Material{sprite, force}}:
      object(J.JMember{"sprite", text(sprite)} <> J.JMember{"force_translucent", J.JBool{force}} <> Nil{})

def query_list(values: List<&2, J.Value>, +model: M.Resolved) -> List<&2, J.Member>:
  match values:
    case J.JString{+slot} <> rest:
      J.JMember{slot, material(M.material(model, slot))} <> query_list(rest, model)
    case _: Nil{}

def material_queries(values: J.Value, model: M.Resolved) -> List<&2, J.Member>:
  match values:
    case J.JArray{vs}: query_list(vs, model)
    case _: Nil{}

def query_value(found: Maybe<&2, J.Value>) -> J.Value:
  match found:
    case None{}: J.JArray{Nil{}}
    case Some{value}: value

def resolved(value: M.Resolved, queries: J.Value) -> J.Value:
  match value:
    case M.Resolved{+id, +parent, +es, +present, +ao, +gui, +transforms, +textures, +diagnostics}:
      +model : M.Resolved = M.Resolved{id, parent, es, present, ao, gui, transforms, textures, diagnostics}
      object(J.JMember{"id", text(id)} <> J.JMember{"parent", maybe_string(parent)} <>
        J.JMember{"elements", J.JArray{elements(es)}} <> J.JMember{"geometry_present", J.JBool{present}} <>
        J.JMember{"ambient_occlusion", J.JBool{ao}} <> J.JMember{"gui_light", light(gui)} <>
        J.JMember{"display", display(transforms)} <> J.JMember{"materials", object(material_queries(queries, model))} <> Nil{})

def resolved_fields(names: List<&2, String>, +models: Map<&2, M.Resolved>, +queries: J.Value, +fallback: M.Resolved) -> List<&2, J.Member>:
  match names:
    case Nil{}: Nil{}
    case +id <> rest:
      J.JMember{id, resolved(M.map_value(M.Resolved, Map.get(M.Resolved, fallback, models, id)), query_value(J.member(queries, id)))} <>
        resolved_fields(rest, models, queries, fallback)

def graph_json(value: M.Graph, queries: J.Value) -> J.Value:
  match value:
    case M.Graph{+models, errors}:
      fallback : M.Resolved = M.Resolved{"", None{}, Nil{}, False{}, True{}, M.Side{}, M.Display{MTip{}}, MTip{}, Nil{}}
      object(resolved_fields(Map.keys(&2, M.Resolved, models), models, queries, fallback))

def strings(values: List<&2, J.Value>) -> Result<&2, &2, M.Error, List<&2, String>>:
  match values:
    case Nil{}: Done{Nil{}}
    case J.JString{s} <> rest:
      do Result<&2, &2, M.Error, List<&2, String>>:
        tail : List<&2, String> <- strings(rest)
        Done{s <> tail}
    case _: M.fail(List<&2, String>, "ExpectedStringRoots", "roots")

def roots(value: J.Value) -> Result<&2, &2, M.Error, List<&2, String>>:
  match value:
    case J.JArray{values}: strings(values)
    case _: M.fail(List<&2, String>, "ExpectedRootArray", "roots")

def graph(value: J.Value) -> Result<&2, &2, M.Error, J.Value>:
  do Result<&2, &2, M.Error, J.Value>:
    +obj : J.Value <- M.object(value, "test.graph")
    model_values : J.Value <- M.required(J.member(obj, "models"), "models")
    library : M.Library <- M.decode_library(model_values, M.empty_model())
    root_values : J.Value <- M.required(J.member(obj, "roots"), "roots")
    names : List<&2, String> <- roots(root_values)
    queries : J.Value <- M.required(J.member(obj, "queries"), "queries")
    resolved : M.Graph <- M.resolve_graph(library, names)
    Done{graph_json(resolved, queries)}

def graph_report(result: Result<&2, &2, M.Error, J.Value>) -> String:
  match result:
    case Fail{M.Error{code, path}}: "error\t" ++ code ++ "\t" ++ path
    case Done{value}: "ok\t" ++ J.encode(value)

def graph_parsed(result: Result<&2, &2, String, J.Value>) -> String:
  match result:
    case Fail{message}: "json-error\t" ++ message
    case Done{value}: graph_report(graph(value))

def empty_decoded(result: Result<&2, &2, M.Error, M.Model>) -> Bool:
  match result:
    case Done{M.Model{None{}, None{}, None{}, None{}, None{}, MTip{}}}: True{}
    case _: False{}

def texture_rejected(result: Result<&2, &2, M.Error, M.Texture>) -> Bool:
  match result:
    case Fail{M.Error{"ExpectedTextureStringOrObject", "textures.all"}}: True{}
    case _: False{}

def quarter(result: Result<&2, &2, M.Error, U32>) -> Bool:
  match result:
    case Done{270}: True{}
    case _: False{}

def fixtures() -> Bool:
  empty_decoded(M.decode(J.JObject{Nil{}})) &&
    texture_rejected(M.texture(J.JBool{True{}}, "textures.all")) &&
    quarter(M.face_rotation(4294967206, "rotation"))

law finite_data_examples:
  {fixtures() == True{} : Bool}

def finite_data_examples():
  {==}

def batch(inputs: List<String>) -> IO(Unit):
  match inputs:
    case Nil{}: IO.pure(Unit, Unit{})
    case input <> rest:
      do IO<Unit>:
        IO.print(parsed(J.parse_with(input, J.Limits{4194304n, 512})))
        batch(rest)

def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.print(J.choose(String, "model-fixtures\tpass", "model-fixtures\tFAIL", fixtures()))
    case "graph" <> input <> Nil{}: IO.print(graph_parsed(J.parse_with(input, J.Limits{4194304n, 512})))
    case inputs: batch(inputs)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(List.tail(&1, String, args))
