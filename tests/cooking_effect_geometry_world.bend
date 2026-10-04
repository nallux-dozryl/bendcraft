import Base
import ../src/cooking_effect_geometry_world.bend as P
import ../src/cooking_effect_geometry.bend as G
import ../src/slab_collision.bend as S
import ../src/core.bend as C
import ../src/game.bend as E
import ../src/registry.bend as R
import ../src/world_codec.bend as WC
import ../src/local_collision_world.bend as L
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/vanilla_entity_fields.bend as V
import ../src/json.bend as J
import ./cooking_effect_geometry.bend as T

def raw_closed(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = result
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)
def raw_file(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,4194304)
    raw_closed(result)
def bytes_eq(a:List<&2,U32>,b:List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && bytes_eq(xs,ys)
    case _ _: False{}
def box(a:U32,b:U32) -> A.AABB:
  +lo = F.from_i32(a)
  +hi = F.from_i32(b)
  A.AABB{lo,lo,lo,hi,hi,hi}
def environment(known:Bool) -> L.Environment:
  match known:
    case True{}: L.Environment{L.KnownEmptyEntityCollisions{},L.KnownClearBorderInterior{box(4294967286,10)}}
    case False{}: L.Environment{L.UnresolvedEntityCollisions{},L.UnresolvedWorldBorder{}}
def request(known:Bool,budget:Nat) -> P.Request:
  P.Request{"minecraft:overworld",box(4294967294,2),environment(known),budget,32768}
def encoded(+baseline:List<&2,U32>,catalog:S.Catalog,registry:R.Registry,label:String,result:C.World & Result<&2,&2,String,List<&2,U32>>) -> IO(E.Engine & S.Catalog):
  (world,status) = result
  match status:
    case Fail{error}: IO.die(E.Engine & S.Catalog,2,error)
    case Done{bytes}:
      do IO<E.Engine & S.Catalog>:
        IO.print(label ++ "\towner\t" ++ U32.show(Bool.to_u32(bytes_eq(baseline,bytes))))
        return (E.Engine{world,registry},catalog)
def owners(baseline:List<&2,U32>,label:String,engine:E.Engine,catalog:S.Catalog) -> IO(E.Engine & S.Catalog):
  E.Engine{world,registry} = engine
  encoded(baseline,catalog,registry,label,WC.encode(world,S.pinned_identity()))
def result_text(value:Result<&2,&2,String,G.Context>) -> String:
  match value:
    case Fail{reason}: reason
    case Done{context}: "unexpected-context"
def refusal(+baseline:List<&2,U32>,+label:String,result:E.Engine & S.Catalog & Result<&2,&2,String,G.Context>) -> IO(E.Engine & S.Catalog):
  (engine,catalog,status) = result
  do IO<E.Engine & S.Catalog>:
    IO.print(label ++ "\t" ++ result_text(status))
    owners(baseline,label,engine,catalog)
def budget_refusal(baseline:List<&2,U32>,result:E.Engine & S.Catalog) -> IO(Unit):
  (engine,catalog) = result
  do IO<Unit>:
    final : E.Engine & S.Catalog <- refusal(baseline,"budget",P.capture(engine,catalog,request(True{},0n)))
    return Unit{}
def unresolved_refusal(+baseline:List<&2,U32>,result:E.Engine & S.Catalog) -> IO(Unit):
  (engine,catalog) = result
  do IO<Unit>:
    next : E.Engine & S.Catalog <- refusal(baseline,"unresolved",P.capture(engine,catalog,request(False{},4096n)))
    budget_refusal(baseline,next)
def observed(+baseline:List<&2,U32>,result:E.Engine & S.Catalog & Result<&2,&2,String,G.Context>) -> IO(Unit):
  (engine,catalog,status) = result
  match status:
    case Fail{reason}: IO.die(Unit,2,reason)
    case Done{context}:
      do IO<Unit>:
        T.respond(T.observation(context,V.Vec3{F.from_f32(F32.neg(0.125)),F.from_f32(F32.neg(0.375)),F.from_f32(F32.neg(0.125))}))
        next : E.Engine & S.Catalog <- owners(baseline,"capture",engine,catalog)
        unresolved_refusal(baseline,next)
def loaded(registry:R.Registry,catalog:S.Catalog,+baseline:List<&2,U32>,value:Result<&2,&1,String,WC.Loaded>) -> IO(Unit):
  match value:
    case Fail{reason}: IO.die(Unit,2,reason)
    case Done{WC.Loaded{world,peer}}: observed(baseline,P.capture(E.Engine{world,registry},catalog,request(True{},4096n)))
def catalog_loaded(path:String,result:R.Registry & Result<&2,&1,S.Error,S.Catalog>) -> IO(Unit):
  (registry,status) = result
  match status:
    case Fail{reason}: IO.die(Unit,2,S.error_text(reason))
    case Done{catalog}:
      do IO<Unit>:
        +bytes : List<&2,U32> <- raw_file(path)
        loaded(registry,catalog,bytes,WC.decode(bytes,S.pinned_states(),S.pinned_identity()))
def registry_loaded(catalog:String,path:String,value:Result<&2,&1,R.Error,R.Registry>) -> IO(Unit):
  match value:
    case Fail{reason}: IO.die(Unit,2,R.error_text(reason))
    case Done{registry}:
      do IO<Unit>:
        result : R.Registry & Result<&2,&1,S.Error,S.Catalog> <- S.Catalog.load(registry,catalog)
        catalog_loaded(path,result)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> registry <> catalog <> path <> Nil{}:
      do IO<Unit>:
        value : Result<&2,&1,R.Error,R.Registry> <- R.Registry.load(registry)
        registry_loaded(catalog,path,value)
    case _: IO.die(Unit,2,"expected REGISTRY SLABS WORLD_NBT")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
