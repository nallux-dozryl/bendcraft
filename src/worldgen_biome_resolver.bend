import Base
import ./worldgen_density_router.bend as R
import ./worldgen_density_ast.bend as A
import ./worldgen_density_state.bend as S
import ./worldgen_density_compile.bend as DC
import ./worldgen_climate.bend as C
import ./worldgen_biome.bend as B
import ./worldgen_overworld.bend as O
import ./worldgen_noise_settings.bend as NS
import ./json.bend as J

# This is the actual production join: one loaded router owner and one loaded
# Climate.ParameterList tree/history. A retained preset name alone is never
# treated as a resolver or replaced with a manufactured parameter table.
type State is Type:
  State{router:R.State,resolver:C.Resolver}

def expressions_equal(first:List<&2,J.Value>,second:List<&2,J.Value>) -> Bool:
  match first second:
    case Nil{} Nil{}: True{}
    case a <> rest_a b <> rest_b:
      String.eq(J.encode(a),J.encode(b)) && expressions_equal(rest_a,rest_b)
    case _ _: False{}

def plan(program:A.Program) -> O.Plan:
  match program:
    case A.Program{plan,registry,expression,nodes,root}: plan

def router_matches(router:NS.Router,generation:O.Plan) -> Bool:
  expressions_equal(R.expressions(router),R.expressions(R.selected_router(generation)))

def prepared(router:R.State,loaded:C.Loaded,budget:Nat,result:Result<&2,&2,String,B.Plan>) ->
    R.State & Result<&2,&1,String,C.Resolver>:
  match result:
    case Fail{message}: (router,Fail{message})
    case Done{biomes}: (router,C.prepare(biomes,loaded,budget))

def admitted(router:R.State,generation:O.Plan,+loaded:C.Loaded,budget:Nat,valid:Bool) ->
    R.State & Result<&2,&1,String,C.Resolver>:
  match loaded valid:
    case _ False{}: (router,Fail{"compiled density router differs from retained generation settings"})
    case C.Loaded{identity,entries} True{}:
      prepared(router,C.Loaded{identity,entries},budget,O.prepare_biomes(generation,identity))

def attach(router:R.State,loaded:C.Loaded,budget:Nat) -> R.State & Result<&2,&1,String,C.Resolver>:
  match router:
    case R.State{+definition,roots,S.State{+program,pool,cache}}:
      admitted(R.State{definition,roots,S.State{program,pool,cache}},plan(program),loaded,budget,
        router_matches(definition,plan(program)))

def attached(result:R.State & Result<&2,&1,String,C.Resolver>) -> Result<&2,&1,String,State>:
  match result:
    case Tuple{router,Fail{message}}: Fail{message}
    case Tuple{router,Done{resolver}}: Done{State{router,resolver}}

def initialized(loaded:C.Loaded,budget:Nat,result:Result<&2,&1,String,R.State>) -> Result<&2,&1,String,State>:
  match result:
    case Fail{message}: Fail{message}
    case Done{router}: attached(attach(router,loaded,budget))

def initialize(plan:O.Plan,resources:J.Value,limits:DC.Limits,sampler_fuel:Nat,loaded:C.Loaded,tree_budget:Nat) ->
    Result<&2,&1,String,State>:
  initialized(loaded,tree_budget,R.initialize_climate_unblended(plan,resources,limits,sampler_fuel))

def block_point(block:B.Block) -> S.Point:
  match block:
    case B.Block{x,y,z}: S.Point{x,y,z}

def point(quart:B.Quart) -> S.Point:
  block_point(B.to_block(quart))

def completed(router:R.State,result:C.Resolver & Result<&2,&2,String,C.Selection>) -> State & Result<&2,&2,String,C.Selection>:
  match result:
    case Tuple{resolver,status}: (State{router,resolver},status)

def climate_completed(resolver:C.Resolver,result:R.State & Result<&2,&2,String,B.Values>) -> State & Result<&2,&2,String,C.Selection>:
  match result:
    case Tuple{router,Fail{message}}: (State{router,resolver},Fail{message})
    case Tuple{router,Done{values}}: completed(router,C.resolve_values(resolver,values))

def restore_router(router:R.State,original:S.Cache) -> R.State:
  match router:
    case R.State{definition,roots,S.State{program,pool,cache}}:
      R.State{definition,roots,S.State{program,pool,original}}

def restore_history(resolver:C.Resolver,original:Maybe<&2,C.Entry>) -> C.Resolver:
  match resolver:
    case C.Fixed{biome}: C.Fixed{biome}
    case C.MultiNoise{identity,inputs,entries,tree,last}: C.MultiNoise{identity,inputs,entries,tree,original}

def transaction(cache:S.Cache,last:Maybe<&2,C.Entry>,result:State & Result<&2,&2,String,C.Selection>) ->
    State & Result<&2,&2,String,C.Selection>:
  match result:
    case Tuple{State{router,resolver},Fail{message}}:
      (State{restore_router(router,cache),restore_history(resolver,last)},Fail{message})
    case Tuple{state,Done{selection}}: (state,Done{selection})

def sample(state:State,depth:Nat,quart:B.Quart) -> State & Result<&2,&2,String,C.Selection>:
  match state:
    case State{router,C.Fixed{+biome}}:
      (State{router,C.Fixed{biome}},Done{C.Selection{biome,0,C.zero()}})
    case State{R.State{definition,roots,S.State{program,pool,+cache}},
        C.MultiNoise{identity,inputs,entries,tree,+last}}:
      transaction(cache,last,climate_completed(C.MultiNoise{identity,inputs,entries,tree,last},
        R.climate(R.State{definition,roots,S.State{program,pool,cache}},depth,point(quart))))
