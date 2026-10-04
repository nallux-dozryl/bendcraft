import Base
import ../src/worldgen_density_router.bend as R
import ../src/worldgen_biome_resolver.bend as BR
import ../src/worldgen_density_state.bend as S
import ../src/worldgen_density_ast.bend as A
import ../src/worldgen_density_compile.bend as DC
import ../src/worldgen_density_column.bend as Column
import ../src/worldgen_noise_settings.bend as NS
import ../src/worldgen_noise_settings_codec.bend as NC
import ../src/worldgen_overworld.bend as O
import ../src/world_generation_settings.bend as WG
import ../src/worldgen_climate.bend as C
import ../src/worldgen_climate_codec.bend as CC
import ../src/worldgen_biome.bend as B
import ../src/json.bend as J
import ../src/nbt.bend as N
import ../src/f64.bend as F

# This harness only decodes requests and formats actual production results.
# Density, noise, DAG/cache, quantization and parameter search live in src.
def affine(-A:Data,result:Result<&2,&2,String,A>) -> Result<&2,&1,String,A>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: Done{value}

def text(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{value}: Done{value}
    case _: Fail{"fixture text required"}

def array(value:J.Value) -> Result<&2,&2,String,List<&2,J.Value>>:
  match value:
    case J.JArray{items}: Done{items}
    case _: Fail{"fixture array required"}

def word_field(+root:J.Value,key:String) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    raw : J.Value <- NC.field(root,key)
    return_result : U32 <- CC.word(raw)
    return return_result

def seed(value:J.Value) -> Result<&2,&2,String,N.Word64>:
  match value:
    case J.JArray{hi <> lo <> Nil{}}:
      do Result<&2,&2,String,N.Word64>:
        high : U32 <- CC.word(hi)
        low : U32 <- CC.word(lo)
        return N.Word64{high,low}
    case _: Fail{"fixture seed requires two words"}

def point(value:J.Value) -> Result<&2,&2,String,S.Point>:
  match value:
    case J.JArray{x <> y <> z <> Nil{}}:
      do Result<&2,&2,String,S.Point>:
        x : U32 <- CC.word(x)
        y : U32 <- CC.word(y)
        z : U32 <- CC.word(z)
        return S.Point{x,y,z}
    case _: Fail{"fixture point requires three words"}

def quart_point(value:S.Point) -> B.Quart:
  match value:
    case S.Point{x,y,z}: B.Quart{x,y,z}

def quart(value:J.Value) -> Result<&2,&2,String,B.Quart>:
  do Result<&2,&2,String,B.Quart>:
    value : S.Point <- point(value)
    return quart_point(value)

def request(value:J.Value) -> Result<&2,&2,String,O.ColumnRequest>:
  match value:
    case J.JArray{x <> z <> bottom <> step <> count <> Nil{}}:
      do Result<&2,&2,String,O.ColumnRequest>:
        x : U32 <- CC.word(x)
        z : U32 <- CC.word(z)
        bottom : U32 <- CC.word(bottom)
        step : U32 <- CC.word(step)
        count : U32 <- CC.word(count)
        return O.ColumnRequest{x,z,bottom,step,count}
    case _: Fail{"fixture column requires five words"}

def bits(value:F32) -> String: U32.show(F32.bits(value))

def bits_list(values:List<&2,F32>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: bits(value)
    case value <> rest: bits(value) ++ "," ++ bits_list(rest)

def roots_list(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: U32.show(value)
    case value <> rest: U32.show(value) ++ "," ++ roots_list(rest)

def roots_text(value:Result<&2,&2,String,List<&2,U32>>) -> String:
  match value:
    case Fail{message}: "climate"
    case Done{values}: roots_list(values)

def pool_size(pool:List<&1,S.Slot>) -> List<&1,S.Slot> & U32:
  match pool:
    case Nil{}: ([],0)
    case S.Slot{key,producer} <> rest:
      C.paired(List<&1,S.Slot>,U32,List<&1,S.Slot> & U32,pool_size(rest),
        next => size => (S.Slot{key,producer} <> next,U32.inc(size)))

def policy_text(policy:R.Policy) -> String:
  match policy:
    case R.ContextUnspecified{}: "unspecified"
    case R.NoBlending{}: "no-blending"

def case_nodes(program:A.Program) -> List<&2,A.Node>:
  match program:
    case A.Program{plan,registry,expression,nodes,root}: nodes

def metadata(state:R.State) -> R.State & String:
  match state:
    case R.State{router,+roots,S.State{+program,pool,+cache}}:
      C.paired(List<&1,S.Slot>,U32,R.State & String,pool_size(pool),next => size =>
        (R.State{router,roots,S.State{program,next,cache}},
          "META|" ++ roots_text(R.indices(roots)) ++ "|" ++ roots_list(R.climate_indices(roots)) ++
          "|" ++ U32.show(U32.from_nat(List.length(&2,A.Node,case_nodes(program)))) ++ "|" ++ U32.show(size) ++
          "|" ++ policy_text(R.policy(roots))))

def values_text(result:Result<&2,&2,String,R.Values>) -> String:
  match result:
    case Fail{message}: "FAIL|" ++ message
    case Done{R.Values{s,c,d,e,f,r,t,v}}: "VALUES|" ++ bits_list([s,c,d,e,f,r,t,v])

def long_text(value:F.Word64) -> String:
  match value:
    case F.Word64{hi,lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def target_text(target:B.Target) -> String:
  match target:
    case B.Target{t,h,c,e,d,w}:
      long_text(t) ++ ";" ++ long_text(h) ++ ";" ++ long_text(c) ++ ";" ++
        long_text(e) ++ ";" ++ long_text(d) ++ ";" ++ long_text(w)

def climate_text(result:Result<&2,&2,String,B.Values>) -> String:
  match result:
    case Fail{message}: "FAIL|" ++ message
    case Done{B.Values{+t,+h,+c,+e,+d,+w}}:
      "CLIMATE|" ++ bits_list([t,h,c,e,d,w]) ++ "|" ++ target_text(B.target(B.Values{t,h,c,e,d,w}))

def column_text(result:Result<&2,&2,String,Column.Column>) -> String:
  match result:
    case Fail{message}: "FAIL|" ++ message
    case Done{Column.Column{expression,x,z,bottom,step,values}}:
      "COLUMN|" ++ J.encode(expression) ++ "|" ++ bits_list(values)

def selected_text(result:Result<&2,&2,String,C.Selection>) -> String:
  match result:
    case Fail{message}: "FAIL|" ++ message
    case Done{C.Selection{biome,index,F.Word64{hi,lo}}}:
      "BIOME|" ++ biome ++ "|" ++ U32.show(index) ++ "|" ++ U32.show(hi) ++ "," ++ U32.show(lo)

def pass_data(-A:Data,result:Result<&2,&2,String,A>) -> IO(A):
  match result:
    case Fail{message}: IO.die(A,1,message)
    case Done{value}: IO.pure(A,value)

def router_query(state:R.State,+mode:String,depth:Nat,query:J.Value) -> IO(R.State):
  match mode:
    case "column":
      do IO<R.State>:
        request : O.ColumnRequest <- pass_data(O.ColumnRequest,request(query))
        C.paired(R.State,Result<&2,&2,String,Column.Column>,IO(R.State),R.column(state,request,4096,depth),
          next => result => IO.bind(Unit,R.State,IO.print(column_text(result)),u => IO.pure(R.State,next)))
    case "all":
      do IO<R.State>:
        point : S.Point <- pass_data(S.Point,point(query))
        C.paired(R.State,Result<&2,&2,String,R.Values>,IO(R.State),R.sample(state,depth,point),
          next => result => IO.bind(Unit,R.State,IO.print(values_text(result)),u => IO.pure(R.State,next)))
    case _:
      do IO<R.State>:
        point : S.Point <- pass_data(S.Point,point(query))
        C.paired(R.State,Result<&2,&2,String,B.Values>,IO(R.State),R.climate(state,depth,point),
          next => result => IO.bind(Unit,R.State,IO.print(climate_text(result)),u => IO.pure(R.State,next)))

def router_queries(queries:List<&2,J.Value>,state:R.State,+mode:String,+depth:Nat) -> IO(Unit):
  match queries:
    case Nil{}: IO.pure(Unit,Unit{})
    case query <> rest:
      do IO<Unit>:
        next : R.State <- router_query(state,mode,depth,query)
        router_queries(rest,next,mode,depth)

def biome_queries(queries:List<&2,J.Value>,state:BR.State,+depth:Nat) -> IO(Unit):
  match queries:
    case Nil{}: IO.pure(Unit,Unit{})
    case query <> rest:
      do IO<Unit>:
        quart : B.Quart <- pass_data(B.Quart,quart(query))
        C.paired(BR.State,Result<&2,&2,String,C.Selection>,IO(Unit),BR.sample(state,depth,quart),next => result => (
          do IO<Unit>:
            IO.print(selected_text(result))
            biome_queries(rest,next,depth)))

type Fixture is Type:
  RouterFixture{state:R.State,queries:List<&2,J.Value>,mode:String,depth:Nat}
  BiomeFixture{state:BR.State,queries:List<&2,J.Value>,depth:Nat}

def loaded_preset(+root:J.Value) -> Result<&2,&2,String,C.Loaded>:
  do Result<&2,&2,String,C.Loaded>:
    key_raw : J.Value <- NC.field(root,"preset_key")
    key : String <- text(key_raw)
    definition : J.Value <- NC.field(root,"preset_definition")
    entries : J.Value <- NC.field(root,"preset_entries")
    loaded : C.Loaded <- CC.read(B.LoadedPreset{key,definition},entries,100000n)
    return loaded

def routed(mode:String,route:String,plan:O.Plan,resources:J.Value,limits:DC.Limits,fuel:Nat,queries:List<&2,J.Value>,depth:Nat,+root:J.Value) -> Result<&2,&1,String,Fixture>:
  match route:
    case "biome":
      do Result<&2,&1,String,Fixture>:
        loaded : C.Loaded <- affine(C.Loaded,loaded_preset(root))
        state : BR.State <- BR.initialize(plan,resources,limits,fuel,loaded,200000n)
        return BiomeFixture{state,queries,depth}
    case "unblended":
      do Result<&2,&1,String,Fixture>:
        state : R.State <- R.initialize_climate_unblended(plan,resources,limits,fuel)
        return RouterFixture{state,queries,mode,depth}
    case "climate":
      do Result<&2,&1,String,Fixture>:
        state : R.State <- R.initialize_climate_loaded(plan,resources,limits,fuel)
        return RouterFixture{state,queries,mode,depth}
    case "full-unblended":
      do Result<&2,&1,String,Fixture>:
        state : R.State <- R.initialize_unblended(plan,resources,limits,fuel)
        return RouterFixture{state,queries,mode,depth}
    case _:
      do Result<&2,&1,String,Fixture>:
        state : R.State <- R.initialize_loaded(plan,resources,limits,fuel)
        return RouterFixture{state,queries,mode,depth}

def prepare(+root:J.Value) -> Result<&2,&1,String,Fixture>:
  do Result<&2,&1,String,Fixture>:
    mode_raw : J.Value <- affine(J.Value,NC.field(root,"mode"))
    mode : String <- affine(String,text(mode_raw))
    route_raw : J.Value <- affine(J.Value,NC.field(root,"route"))
    route : String <- affine(String,text(route_raw))
    seed_raw : J.Value <- affine(J.Value,NC.field(root,"seed"))
    seed : N.Word64 <- affine(N.Word64,seed(seed_raw))
    settings_raw : J.Value <- affine(J.Value,NC.field(root,"settings"))
    settings : NS.Settings <- affine(NS.Settings,NC.read("minecraft:overworld",settings_raw))
    plan : O.Plan <- affine(O.Plan,O.prepare(WG.normal(seed),settings))
    resources : J.Value <- affine(J.Value,NC.field(root,"resources"))
    queries_raw : J.Value <- affine(J.Value,NC.field(root,"queries"))
    queries : List<&2,J.Value> <- affine(List<&2,J.Value>,array(queries_raw))
    compile_depth : U32 <- affine(U32,word_field(root,"compile_depth"))
    nodes : U32 <- affine(U32,word_field(root,"nodes"))
    entries : U32 <- affine(U32,word_field(root,"entries"))
    fuel : U32 <- affine(U32,word_field(root,"fuel"))
    depth : U32 <- affine(U32,word_field(root,"depth"))
    result : Fixture <- routed(mode,route,plan,resources,DC.Limits{U32.to_nat(compile_depth),nodes,U32.to_nat(entries)},
      U32.to_nat(fuel),queries,U32.to_nat(depth),root)
    return result

def prepared(result:Result<&2,&1,String,Fixture>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("FAIL|" ++ message)
    case Done{RouterFixture{state,queries,mode,depth}}:
      C.paired(R.State,String,IO(Unit),metadata(state),state => metadata => (
        do IO<Unit>:
          IO.print(metadata)
          router_queries(queries,state,mode,depth)))
    case Done{BiomeFixture{BR.State{router,resolver},queries,depth}}:
      C.paired(R.State,String,IO(Unit),metadata(router),router => metadata => (
        do IO<Unit>:
          IO.print(metadata)
          biome_queries(queries,BR.State{router,resolver},depth)))

def parsed(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("FAIL|" ++ message)
    case Done{root}: prepared(prepare(root))

def loaded(result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,read) = result
  do IO<Unit>:
    File.close(file)
    source : String <- IO.pass(String,read)
    parsed(J.parse_with(source,J.Limits{33554432n,128}))

def file(path:String) -> IO(Unit):
  do IO<Unit>:
    input : File <- IO.try(File,File.open(path,"r"))
    value : File & Result<&1,&1,U32 & String,String> <- File.read(input,33554432)
    loaded(value)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}: file(path)
    case _: IO.die(Unit,2,"one router fixture file required")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
