import Base
import ../src/resource_catalog_world.bend as W
import ../src/resource_frame.bend as F
import ../src/resource_block_catalog.bend as C
import ../src/registry.bend as G
import ../src/world_mesh.bend as WM
import ../src/mesh_render.bend as M
import ../src/client_render.bend as R
import ../src/json.bend as J
import ./resource_block_catalog.bend as H

# This observer decodes test commands and serializes the actual production
# frame adapter. All registry/load/selection/bake/mesh/render work is imported.
def raw(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}

def tints(values:List<&2,J.Value>) -> List<&2,WM.Tint>:
  match values:
    case Nil{}: []
    case +value <> rest:
      WM.Tint{H.integer(J.member(value,"index"),0),H.integer(J.member(value,"color"),4294967295)} <> tints(rest)

def appearance(+value:J.Value) -> WM.Appearance:
  WM.Appearance{tints(H.values(J.member(value,"tints"))),H.integer(J.member(value,"light"),4294967295),
    M.Clamp{},M.Back{},False{},128}

def instances(values:List<&2,J.Value>) -> List<&2,W.Instance>:
  match values:
    case Nil{}: []
    case +value <> rest:
      W.Instance{R.Block{raw(H.integer(J.member(value,"x"),0)),raw(H.integer(J.member(value,"y"),0)),
        raw(H.integer(J.member(value,"z"),0)),H.integer(J.member(value,"state"),0),0},
        C.Selection{H.ticket(J.member(value,"ticket")),H.tickets(H.members(J.member(value,"parts")),MTip{})},appearance(value)} <> instances(rest)

def frame(+value:J.Value,identity:String) -> W.Frame:
  W.Frame{H.string(J.member(value,"identity"),identity),7n,9n,instances(H.values(J.member(value,"instances"))),
    R.Camera{0.0,0.0,0.0,raw(H.integer(J.member(value,"yaw"),0)),raw(H.integer(J.member(value,"pitch"),0))}}

def limits(+value:J.Value) -> WM.Limits:
  WM.Limits{H.integer(J.member(value,"blocks"),4096),H.integer(J.member(value,"bindings"),1024),
    H.integer(J.member(value,"quads"),4096),H.integer(J.member(value,"translucent"),64),H.integer(J.member(value,"tints"),256)}

def vertex(value:M.Vertex) -> J.Value:
  M.Vertex{M.Vec3{x,y,z},M.UV{u,v}} = value
  J.JArray{H.numbers([F32.bits(x),F32.bits(y),F32.bits(z),F32.bits(u),F32.bits(v)])}

def quad(value:M.Quad) -> J.Value:
  M.Quad{a,b,c,d,M.Material{texture,tint,light,shade,mode,address},cull,order} = value
  H.obj([J.JMember{"vertices",J.JArray{[vertex(a),vertex(b),vertex(c),vertex(d)]}},
    J.JMember{"texture",H.number(texture)},J.JMember{"tint",H.number(tint)},J.JMember{"order",H.number(order)}])

def quads(values:List<&2,M.Quad>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: quad(value) <> quads(rest)

def scene_status(value:Result<&2,&2,C.Error,M.Scene>) -> J.Value:
  match value:
    case Fail{error}: H.obj(H.error(error))
    case Done{M.Scene{camera,+values,settings}}:
      H.obj([J.JMember{"status",H.text("ok")},J.JMember{"count",J.JNumber{Nat.show(List.length(&2,M.Quad,values))}},
        J.JMember{"quads",J.JArray{quads(values)}}])

def pixels(value:Result<&2,&2,C.Error,Image>,width:U32,height:U32) -> J.Value:
  match value:
    case Fail{error}: H.obj(H.error(error))
    case Done{image}: H.obj([J.JMember{"status",H.text("ok")},
      J.JMember{"pixels",J.JArray{H.numbers(R.pixels_of(image,width,height))}}])

def observed_info(value:W.Assets & W.Info,config:J.Value,scene:J.Value,status:Result<&2,&2,C.Error,Image>,width:U32,height:U32) -> W.Assets & J.Value:
  (assets,W.Info{catalog,count}) = value
  (assets,H.obj([J.JMember{"name",H.text(H.string(J.member(config,"name"),""))},
    J.JMember{"scene",scene},J.JMember{"render",pixels(status,width,height)},
    J.JMember{"retained_identity",H.text(W.catalog_identity(catalog))},J.JMember{"retained_textures",H.number(count)}]))

def observed(value:W.Assets & Result<&2,&2,C.Error,Image>,config:J.Value,scene:J.Value,width:U32,height:U32) -> W.Assets & J.Value:
  (assets,status) = value
  observed_info(F.catalog_info(assets),config,scene,status,width,height)

def tested(value:W.Assets & W.Info,+config:J.Value) -> W.Assets & J.Value:
  (assets,W.Info{+catalog,+textures}) = value
  +width = H.integer(J.member(config,"width"),31)
  +height = H.integer(J.member(config,"height"),17)
  +input = frame(config,W.catalog_identity(catalog))
  +budget = limits(config)
  observed(F.catalog_draw(input,assets,width,height,budget),config,
    scene_status(W.scene(input,catalog,textures,WM.frame(width,height),budget)),width,height)

def printed(value:W.Assets & J.Value) -> IO(W.Assets):
  (assets,report) = value
  do IO<W.Assets>:
    IO.print(J.encode(report))
    return assets

def frames(values:List<&2,J.Value>,assets:W.Assets) -> IO(W.Assets):
  match values:
    case Nil{}: IO.pure(W.Assets,assets)
    case value <> rest:
      do IO<W.Assets>:
        assets:W.Assets <- printed(tested(F.catalog_info(assets),value))
        frames(rest,assets)

def loaded_info(value:W.Assets & W.Info,+config:J.Value,after:J.Value) -> IO(Unit):
  (assets,W.Info{+catalog,count}) = value
  do IO<Unit>:
    IO.print(J.encode(H.obj([J.JMember{"status",H.text("loaded")},J.JMember{"registry_after",after},
      J.JMember{"registry_identity",H.text(W.catalog_identity(catalog))},J.JMember{"textures",H.number(count)}])))
    assets:W.Assets <- frames(H.values(J.member(config,"frames")),assets)
    F.catalog_close(assets)

def loaded_status(status:Result<&2,&1,C.Error,W.Assets>,+config:J.Value,after:J.Value) -> IO(Unit):
  match status:
    case Fail{error}: IO.print(J.encode(H.obj(J.JMember{"registry_after",after} <> H.error(error))))
    case Done{assets}: loaded_info(F.catalog_info(assets),config,after)

def loaded(value:G.Registry & Result<&2,&1,C.Error,W.Assets>,config:J.Value) -> IO(Unit):
  (registry,status) = value
  loaded_status(status,config,H.registry_after(G.Registry.decode(registry,0)))

def registry_ready(value:Result<&2,&1,G.Error,G.Registry>,+config:J.Value) -> IO(Unit):
  match value:
    case Fail{error}: IO.die(Unit,1,G.error_text(error))
    case Done{registry}:
      do IO<Unit>:
        value:G.Registry & Result<&2,&1,C.Error,W.Assets> <- F.catalog_load(H.string(J.member(config,"jar"),""),registry,
          H.requests(J.member(config,"requests")),H.policy(J.member(config,"layers")),H.limits(config))
        loaded(value,config)

def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{error}: IO.die(Unit,1,error)
    case Done{+config}:
      do IO<Unit>:
        value:Result<&2,&1,G.Error,G.Registry> <- G.Registry.load(H.string(J.member(config,"registry"),"generated/reference_blocks.tsv"))
        registry_ready(value,config)

def arguments(values:List<String>) -> IO(Unit):
  match values:
    case exe <> config <> Nil{}: parsed(J.parse(config))
    case _: IO.die(Unit,1,"expected one catalog world test configuration")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
