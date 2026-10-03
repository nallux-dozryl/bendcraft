import Base
import ../src/json.bend as J
import ../src/block_model.bend as B
import ../src/block_bake.bend as K
import ../src/mesh_render.bend as M

def object(fields:List<&2,J.Member>) -> J.Value:
  J.JObject{fields}
def text(s:String) -> J.Value:
  J.JString{s}
def word(fuel:Nat,+n:U32,+shift:U32) -> String:
  match fuel:
    case 0n: ""
    case 1n+p: Char.show(J.hex_char(U32.and(U32.shrn(n,U32.to_nat(shift)),15))) ++ word(p,n,U32.sub(shift,4))
def bits(f:F32) -> J.Value:
  text(word(8n,F32.bits(f),28))
def direction(d:B.Direction) -> String:
  match d:
    case B.Down{}: "down"
    case B.Up{}: "up"
    case B.North{}: "north"
    case B.South{}: "south"
    case B.West{}: "west"
    case B.East{}: "east"
def maybe_direction(d:Maybe<&2,B.Direction>) -> J.Value:
  match d:
    case None{}: J.JNull{}
    case Some{v}: text(direction(v))
def layer(l:K.Layer) -> String:
  match l:
    case K.Solid{}: "SOLID"
    case K.Cutout{}: "CUTOUT"
    case K.Translucent{}: "TRANSLUCENT"
def vertex(v:M.Vertex) -> J.Value:
  M.Vertex{M.Vec3{x,y,z},M.UV{u,v}} = v
  object([J.JMember{"position_f32",J.JArray{[bits(x),bits(y),bits(z)]}},J.JMember{"uv_f32",J.JArray{[bits(u),bits(v)]}}])
def quad(+v:K.Baked) -> J.Value:
  K.Baked{a,b,c,d,dir,cf,sprite,slot,tint,emission,override,l,force,animated,ds,ns} = v
  object([J.JMember{"vertices",J.JArray{[vertex(a),vertex(b),vertex(c),vertex(d)]}},
    J.JMember{"direction",text(direction(dir))},J.JMember{"cull",maybe_direction(cf)},
    J.JMember{"sprite",text(sprite)},J.JMember{"slot",J.JNumber{U32.show(slot)}},
    J.JMember{"tint_index",J.JNumber{U32.show(tint)}},J.JMember{"light_emission",J.JNumber{U32.show(emission)}},
    J.JMember{"shade_direction_override",maybe_direction(override)},J.JMember{"layer",text(layer(l))},
    J.JMember{"material_flags",J.JNumber{U32.show(K.flags(v))}},J.JMember{"force_translucent",J.JBool{force}},J.JMember{"animated",J.JBool{animated}},
    J.JMember{"default_directional_brightness_f32",bits(ds)},J.JMember{"nether_directional_brightness_f32",bits(ns)}])
def quads(v:List<&2,K.Baked>) -> List<&2,J.Value>:
  match v:
    case Nil{}: []
    case h <> t: quad(h) <> quads(t)
def outcome(r:Result<&2,&2,K.Error,List<&2,K.Baked>>) -> J.Value:
  match r:
    case Done{v}: object([J.JMember{"status",text("ok")},J.JMember{"quads",J.JArray{quads(v)}}])
    case Fail{K.Unsupported{code}}: object([J.JMember{"status",text("unsupported")},J.JMember{"code",text(code)}])
    case Fail{K.Invalid{code}}: object([J.JMember{"status",text("invalid")},J.JMember{"code",text(code)}])
    case Fail{K.MissingMaterial{name}}: object([J.JMember{"status",text("missing-material")},J.JMember{"reference",text(name)}])
def state(+obj:J.Value) -> Result<&2,&2,B.Error,K.State>:
  do Result<&2,&2,B.Error,K.State>:
    x : U32 <- B.optional_int(J.member(obj,"x"),0,"x")
    y : U32 <- B.optional_int(J.member(obj,"y"),0,"y")
    z : U32 <- B.optional_int(J.member(obj,"z"),0,"z")
    lock : Bool <- B.optional_bool(J.member(obj,"uvlock"),False{},"uvlock")
    Done{K.State{x,y,z,lock}}
def sprite_layer(name:String) -> K.Layer:
  match name:
    case "CUTOUT": K.Cutout{}
    case "TRANSLUCENT": K.Translucent{}
    case _: K.Solid{}
def sprite(+obj:J.Value) -> Result<&2,&2,B.Error,K.Sprite>:
  do Result<&2,&2,B.Error,K.Sprite>:
    slot : U32 <- B.optional_int(J.member(obj,"slot"),0,"slot")
    u0 : F32 <- B.optional_float(J.member(obj,"u0"),0.0,"u0")
    v0 : F32 <- B.optional_float(J.member(obj,"v0"),0.0,"v0")
    u1 : F32 <- B.optional_float(J.member(obj,"u1"),1.0,"u1")
    v1 : F32 <- B.optional_float(J.member(obj,"v1"),1.0,"v1")
    animated : Bool <- B.optional_bool(J.member(obj,"animated"),False{},"animated")
    found : J.Value <- B.required(J.member(obj,"layer"),"layer")
    name : String <- B.strict_string(found,"layer")
    Done{K.Sprite{slot,u0,v0,u1,v1,sprite_layer(name),animated}}
def sprite_members(members:List<&2,J.Member>,map:Map<&2,K.Sprite>) -> Result<&2,&2,B.Error,Map<&2,K.Sprite>>:
  match members:
    case Nil{}: Done{map}
    case J.JMember{name,v} <> tail:
      do Result<&2,&2,B.Error,Map<&2,K.Sprite>>:
        sp : K.Sprite <- sprite(v)
        sprite_members(tail,Map.set(&2,K.Sprite,map,name,sp))
def optional_sprite(v:Maybe<&2,J.Value>) -> Result<&2,&2,B.Error,Maybe<&2,K.Sprite>>:
  match v:
    case None{}: Done{None{}}
    case Some{obj}:
      do Result<&2,&2,B.Error,Maybe<&2,K.Sprite>>:
        sp : K.Sprite <- sprite(obj)
        Done{Some{sp}}
def context(v:J.Value,missing:Maybe<&2,J.Value>) -> Result<&2,&2,B.Error,K.Context>:
  match v:
    case J.JObject{members}:
      do Result<&2,&2,B.Error,K.Context>:
        map : Map<&2,K.Sprite> <- sprite_members(members,MTip{})
        fallback : Maybe<&2,K.Sprite> <- optional_sprite(missing)
        Done{K.Context{map,fallback}}
    case _: B.fail(K.Context,"SpritesObject","sprites")
def execute(+obj:J.Value) -> Result<&2,&2,B.Error,J.Value>:
  do Result<&2,&2,B.Error,J.Value>:
    models : J.Value <- B.required(J.member(obj,"models"),"models")
    lib : B.Library <- B.decode_library(models,B.empty_model())
    root : J.Value <- B.required(J.member(obj,"root"),"root")
    name : String <- B.strict_string(root,"root")
    resolved : B.Resolved <- B.resolve(lib,name)
    st : K.State <- state(obj)
    spr : J.Value <- B.required(J.member(obj,"sprites"),"sprites")
    ctx : K.Context <- context(spr,J.member(obj,"missing"))
    Done{outcome(K.bake(resolved,st,ctx))}
def executed(r:Result<&2,&2,B.Error,J.Value>) -> String:
  match r:
    case Done{v}: J.encode(v)
    case Fail{B.Error{code,path}}: J.encode(object([J.JMember{"status",text("parse-error")},J.JMember{"code",text(code)},J.JMember{"path",text(path)}]))
def parsed(r:Result<&2,&2,String,J.Value>) -> String:
  match r:
    case Done{v}: executed(execute(v))
    case Fail{code}: J.encode(object([J.JMember{"status",text("json-error")},J.JMember{"code",text(code)}]))
def batch(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case input <> rest:
      do IO<Unit>:
        IO.print(parsed(J.parse_with(input,J.Limits{4194304n,512})))
        batch(rest)

def fixtures() -> Bool:
  K.vec_eq(K.transform(K.identity(),B.Vec3{1.0,2.0,3.0}),B.Vec3{1.0,2.0,3.0}) &&
    K.direction_eq(K.rotate_direction(K.State{0,90,0,False{}},B.North{}),B.East{}) &&
    F32.is_eq(K.shade(B.Down{},False{}),0.5)
law identity_transform:
  for +v:B.Vec3
  {K.transform(K.identity(),v) == v : B.Vec3}
def identity_transform(v):
  {==}
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1,String,args))
