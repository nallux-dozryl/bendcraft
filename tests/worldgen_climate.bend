import Base
import ../src/worldgen_climate.bend as C
import ../src/worldgen_climate_codec.bend as CC
import ../src/worldgen_biome.bend as B
import ../src/worldgen_noise_settings_codec.bend as NC
import ../src/worldgen_noise_settings.bend as NS
import ../src/world_generation_settings.bend as WG
import ../src/json.bend as J
import ../src/f64.bend as F

# The harness consumes the production decoded-table loader, tree builder,
# prepared biome plan, target quantizer and resolver. It contains no search.
def pass_data(-A:Data,result:Result<&2,&2,String,A>) -> IO(A):
  match result:
    case Fail{message}: IO.die(A,1,message)
    case Done{value}: IO.pure(A,value)

def affine(-A:Data,result:Result<&2,&2,String,A>) -> Result<&2,&1,String,A>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: Done{value}

def array(value:J.Value) -> Result<&2,&2,String,List<&2,J.Value>>:
  match value:
    case J.JArray{items}: Done{items}
    case _: Fail{"fixture array required"}

def text(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{raw}: Done{raw}
    case _: Fail{"fixture string required"}

def flag(value:J.Value) -> Result<&2,&2,String,Bool>:
  match value:
    case J.JBool{raw}: Done{raw}
    case _: Fail{"fixture boolean required"}

def long_words(value:J.Value) -> Result<&2,&2,String,F.Word64>:
  match value:
    case J.JArray{hi <> lo <> Nil{}}:
      do Result<&2,&2,String,F.Word64>:
        high : U32 <- CC.word(hi)
        low : U32 <- CC.word(lo)
        return F.Word64{high,low}
    case _: Fail{"fixture long pair required"}

def target_fields(t:J.Value,h:J.Value,c:J.Value,e:J.Value,d:J.Value,w:J.Value) -> Result<&2,&2,String,B.Target>:
  do Result<&2,&2,String,B.Target>:
    temperature : F.Word64 <- long_words(t)
    humidity : F.Word64 <- long_words(h)
    continentalness : F.Word64 <- long_words(c)
    erosion : F.Word64 <- long_words(e)
    depth : F.Word64 <- long_words(d)
    weirdness : F.Word64 <- long_words(w)
    return B.Target{temperature,humidity,continentalness,erosion,depth,weirdness}

def target(value:J.Value) -> Result<&2,&2,String,B.Target>:
  match value:
    case J.JArray{t <> h <> c <> e <> d <> w <> Nil{}}: target_fields(t,h,c,e,d,w)
    case _: Fail{"fixture target requires six longs"}

def number(value:U32) -> J.Value: J.JNumber{U32.show(value)}

def interval_json(value:C.Interval) -> J.Value:
  match value:
    case C.Interval{F.Word64{a,b},F.Word64{c,d}}: J.JArray{[number(a),number(b),number(c),number(d)]}

def space_json(value:C.Space) -> J.Value:
  match value:
    case C.Space{t,h,c,e,d,w,o}:
      J.JArray{[interval_json(t),interval_json(h),interval_json(c),interval_json(e),
        interval_json(d),interval_json(w),interval_json(o)]}

def node_json(value:C.Tree) -> J.Value:
  match value:
    case C.Leaf{C.Entry{index,space,biome}}: J.JArray{[J.JString{"leaf"},number(index),space_json(space)]}
    case C.Branch{space,+children,nodes}:
      J.JArray{[J.JString{"branch"},number(U32.from_nat(List.length(&2,C.Tree,children))),space_json(space)]}

def children(value:C.Tree,rest:List<&2,C.Tree>) -> List<&2,C.Tree>:
  match value:
    case C.Leaf{entry}: rest
    case C.Branch{space,children,nodes}: List.append(&2,C.Tree,children,rest)

def tree_rows(fuel:Nat,nodes:List<&2,C.Tree>) -> List<&2,J.Value>:
  match fuel nodes:
    case _ Nil{}: Nil{}
    case 0n _: Nil{}
    case 1n+rest +node <> tail: node_json(node) <> tree_rows(rest,children(node,tail))

def history(warm:Bool,resolver:C.Resolver) -> C.Resolver:
  match warm:
    case True{}: resolver
    case False{}:
      match resolver:
        case C.Fixed{biome}: C.Fixed{biome}
        case C.MultiNoise{identity,inputs,entries,tree,last}: C.MultiNoise{identity,inputs,entries,tree,None{}}

def selection_text(value:Result<&2,&2,String,C.Selection>) -> String:
  match value:
    case Fail{message}: "FAIL|" ++ message
    case Done{C.Selection{biome,index,F.Word64{hi,lo}}}:
      "RESULT|" ++ U32.show(index) ++ "|" ++ biome ++ "|" ++ U32.show(hi) ++ "," ++ U32.show(lo)

def run_queries(queries:List<&2,J.Value>,resolver:C.Resolver,+warm:Bool) -> IO(Unit):
  match queries:
    case Nil{}: IO.pure(Unit,Unit{})
    case query <> rest:
      do IO<Unit>:
        point : B.Target <- pass_data(B.Target,target(query))
        result : C.Resolver & Result<&2,&2,String,C.Selection> = C.resolve_target(history(warm,resolver),point)
        C.paired(C.Resolver,Result<&2,&2,String,C.Selection>,IO(Unit),result,next => chosen => (
          do IO<Unit>:
            IO.print(selection_text(chosen))
            run_queries(rest,next,warm)))

def output_tree(resolver:C.Resolver) -> C.Resolver & String:
  match resolver:
    case C.Fixed{+biome}: (C.Fixed{biome},"TREE|[]")
    case C.MultiNoise{identity,inputs,entries,+tree,last}:
      (C.MultiNoise{identity,inputs,entries,tree,last},"TREE|" ++ J.encode(J.JArray{tree_rows(C.tree_size(tree),[tree])}))

type Fixture is Type:
  Fixture{resolver:C.Resolver,queries:List<&2,J.Value>,warm:Bool}

def prepare(+root:J.Value) -> Result<&2,&1,String,Fixture>:
  do Result<&2,&1,String,Fixture>:
    key_raw : J.Value <- affine(J.Value,CC.field(root,"key"))
    +key : String <- affine(String,text(key_raw))
    definition : J.Value <- affine(J.Value,CC.field(root,"definition"))
    entries : J.Value <- affine(J.Value,CC.field(root,"entries"))
    queries_raw : J.Value <- affine(J.Value,CC.field(root,"queries"))
    queries : List<&2,J.Value> <- affine(List<&2,J.Value>,array(queries_raw))
    warm_raw : J.Value <- affine(J.Value,CC.field(root,"warm"))
    warm : Bool <- affine(Bool,flag(warm_raw))
    router_raw : J.Value <- affine(J.Value,CC.field(root,"router"))
    router : NS.Router <- affine(NS.Router,NC.read_router(router_raw))
    +identity : B.LoadedPreset = B.LoadedPreset{key,definition}
    loaded : C.Loaded <- affine(C.Loaded,CC.read(identity,entries,100000n))
    plan : B.Plan <- affine(B.Plan,B.prepare(WG.MultiNoisePreset{key},router,identity))
    resolver : C.Resolver <- C.prepare(plan,loaded,200000n)
    return Fixture{resolver,queries,warm}

def prepared(value:Result<&2,&1,String,Fixture>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{Fixture{resolver,queries,warm}}:
      C.paired(C.Resolver,String,IO(Unit),output_tree(resolver),next => tree => (
        do IO<Unit>:
          IO.print(tree)
          run_queries(queries,next,warm)))

def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{root}: prepared(prepare(root))

def loaded(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,read) = value
  do IO<Unit>:
    File.close(file)
    source : String <- IO.pass(String,read)
    parsed(J.parse_with(source,J.Limits{33554432n,64}))

def file(path:String) -> IO(Unit):
  do IO<Unit>:
    input : File <- IO.try(File,File.open(path,"r"))
    value : File & Result<&1,&1,U32 & String,String> <- File.read(input,33554432)
    loaded(value)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}: file(path)
    case _: IO.die(Unit,2,"one climate fixture file required")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
