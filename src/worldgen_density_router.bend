import Base
import ./worldgen_density_ast.bend as A
import ./worldgen_density_compile.bend as C
import ./worldgen_density_loader.bend as L
import ./worldgen_density_state.bend as S
import ./worldgen_density.bend as D
import ./worldgen_density_column.bend as Column
import ./worldgen_noise_settings.bend as NS
import ./worldgen_overworld.bend as O
import ./worldgen_biome.bend as B
import ./json.bend as J

# All eight selected expressions lower into one DAG, with one registry memo,
# one seeded producer pool and one point cache. The Program's primary root is
# the actual selected final_density, allowing the existing Column consumer.
type Roots is Data:
  Roots{chunk_surface_level:U32,continents:U32,depth:U32,erosion:U32,
    final_density:U32,ridges:U32,temperature:U32,vegetation:U32}
  ClimateRoots{continents:U32,depth:U32,erosion:U32,ridges:U32,temperature:U32,vegetation:U32}
  UnblendedRoots{roots:Roots}

type Policy is Data:
  ContextUnspecified{}
  NoBlending{}

type Program is Data:
  Program{router:NS.Router,roots:Roots,density:A.Program}

type State is Type:
  State{router:NS.Router,roots:Roots,density:S.State}

type Channel is Data:
  ChunkSurfaceLevel{}
  Continents{}
  Depth{}
  Erosion{}
  FinalDensity{}
  Ridges{}
  Temperature{}
  Vegetation{}

type Values is Data:
  Values{chunk_surface_level:F32,continents:F32,depth:F32,erosion:F32,
    final_density:F32,ridges:F32,temperature:F32,vegetation:F32}

type Lowered is Data:
  Lowered{build:C.Build,indices:List<&2,U32>}

def selected_router(plan:O.Plan) -> NS.Router:
  match plan:
    case O.Plan{generation,NS.Settings{key,bottom,size,sea,legacy,block,fluid,material,router,aquifers,spawn,debug,mobs},random}: router

def expressions(router:NS.Router) -> List<&2,J.Value>:
  match router:
    case NS.Router{surface,continents,depth,erosion,density,ridges,temperature,vegetation}:
      [surface,continents,depth,erosion,density,ridges,temperature,vegetation]

def continued_compile(result:Result<&2,&2,String,C.Step>,
    next:C.Build -> U32 -> Result<&2,&2,String,Lowered>) -> Result<&2,&2,String,Lowered>:
  match result:
    case Fail{message}: Fail{message}
    case Done{C.Step{build,index}}: next(build)(index)

def lower(expressions:List<&2,J.Value>,+registry:A.Registry,+depth:Nat,+capacity:U32,
    build:C.Build,indices:List<&2,U32>) -> Result<&2,&2,String,Lowered>:
  match expressions:
    case Nil{}: Done{Lowered{build,List.reverse(&2,U32,indices)}}
    case value <> rest:
      continued_compile(C.lower(depth,value,registry,[],build,capacity),
        next => index => lower(rest,registry,depth,capacity,next,index <> indices))

def lower_unblended(expressions:List<&2,J.Value>,+registry:A.Registry,+depth:Nat,+capacity:U32,
    build:C.Build,indices:List<&2,U32>) -> Result<&2,&2,String,Lowered>:
  match expressions:
    case Nil{}: Done{Lowered{build,List.reverse(&2,U32,indices)}}
    case value <> rest:
      continued_compile(C.lower_unblended(depth,value,registry,[],build,capacity),
        next => index => lower_unblended(rest,registry,depth,capacity,next,index <> indices))

def assembled(plan:O.Plan,registry:A.Registry,router:NS.Router,lowered:Lowered) -> Result<&2,&2,String,Program>:
  match router lowered:
    case NS.Router{sv,cv,dv,ev,+fv,rv,tv,vv}
        Lowered{C.Build{nodes,references,count},surface <> continents <> depth <> erosion <> +density <> ridges <> temperature <> vegetation <> Nil{}}:
      Done{Program{NS.Router{sv,cv,dv,ev,fv,rv,tv,vv},Roots{surface,continents,depth,erosion,density,ridges,temperature,vegetation},
        A.Program{plan,registry,fv,List.reverse(&2,A.Node,nodes),density}}}
    case _ _: Fail{"density router compilation did not produce eight roots"}

def prepared(plan:O.Plan,registry:A.Registry,router:NS.Router,result:Result<&2,&2,String,Lowered>) -> Result<&2,&2,String,Program>:
  match result:
    case Fail{message}: Fail{message}
    case Done{lowered}: assembled(plan,registry,router,lowered)

def admitted(plan:O.Plan,+registry:A.Registry,+router:NS.Router,depth:Nat,capacity:U32,valid:Bool) -> Result<&2,&2,String,Program>:
  match valid:
    case False{}: Fail{"loaded density router or registry has invalid identities, duplicates or exceeds caller budget"}
    case True{}: prepared(plan,registry,router,lower(expressions(router),registry,depth,capacity,C.Build{[],[],0},[]))

def compile(+plan:O.Plan,+registry:A.Registry,limits:C.Limits) -> Result<&2,&2,String,Program>:
  match limits:
    case C.Limits{depth,nodes,entries}:
      +router = selected_router(plan)
      admitted(plan,registry,router,depth,nodes,NS.router_valid(router) && C.registry_valid(registry,entries))

def climate_expressions(router:NS.Router) -> List<&2,J.Value>:
  match router:
    case NS.Router{surface,continents,depth,erosion,density,ridges,temperature,vegetation}:
      [temperature,vegetation,continents,erosion,depth,ridges]

def assembled_climate(plan:O.Plan,registry:A.Registry,router:NS.Router,lowered:Lowered) -> Result<&2,&2,String,Program>:
  match router lowered:
    case NS.Router{sv,cv,dv,ev,fv,rv,+tv,vv}
        Lowered{C.Build{nodes,references,count},+temperature <> vegetation <> continents <> erosion <> depth <> ridges <> Nil{}}:
      Done{Program{NS.Router{sv,cv,dv,ev,fv,rv,tv,vv},ClimateRoots{continents,depth,erosion,ridges,temperature,vegetation},
        A.Program{plan,registry,tv,List.reverse(&2,A.Node,nodes),temperature}}}
    case _ _: Fail{"density climate compilation did not produce six roots"}

def prepared_climate(plan:O.Plan,registry:A.Registry,router:NS.Router,result:Result<&2,&2,String,Lowered>) -> Result<&2,&2,String,Program>:
  match result:
    case Fail{message}: Fail{message}
    case Done{lowered}: assembled_climate(plan,registry,router,lowered)

def admitted_climate(plan:O.Plan,+registry:A.Registry,+router:NS.Router,depth:Nat,capacity:U32,valid:Bool) -> Result<&2,&2,String,Program>:
  match valid:
    case False{}: Fail{"loaded density router or registry has invalid identities, duplicates or exceeds caller budget"}
    case True{}: prepared_climate(plan,registry,router,lower(climate_expressions(router),registry,depth,capacity,C.Build{[],[],0},[]))

# Six climate roots can be compiled while the surface/final-density graph is
# explicitly unavailable. No absent root receives a substitute node index.
def compile_climate(+plan:O.Plan,+registry:A.Registry,limits:C.Limits) -> Result<&2,&2,String,Program>:
  match limits:
    case C.Limits{depth,nodes,entries}:
      +router = selected_router(plan)
      admitted_climate(plan,registry,router,depth,nodes,NS.router_valid(router) && C.registry_valid(registry,entries))

def marked_unblended(result:Result<&2,&2,String,Program>) -> Result<&2,&2,String,Program>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Program{router,roots,density}}: Done{Program{router,UnblendedRoots{roots},density}}

def admitted_unblended(plan:O.Plan,+registry:A.Registry,+router:NS.Router,depth:Nat,capacity:U32,valid:Bool) -> Result<&2,&2,String,Program>:
  match valid:
    case False{}: Fail{"loaded density router or registry has invalid identities, duplicates or exceeds caller budget"}
    case True{}: marked_unblended(prepared(plan,registry,router,
      lower_unblended(expressions(router),registry,depth,capacity,C.Build{[],[],0},[])))

def compile_unblended(+plan:O.Plan,+registry:A.Registry,limits:C.Limits) -> Result<&2,&2,String,Program>:
  match limits:
    case C.Limits{depth,nodes,entries}:
      +router = selected_router(plan)
      admitted_unblended(plan,registry,router,depth,nodes,NS.router_valid(router) && C.registry_valid(registry,entries))

def admitted_climate_unblended(plan:O.Plan,+registry:A.Registry,+router:NS.Router,depth:Nat,capacity:U32,valid:Bool) -> Result<&2,&2,String,Program>:
  match valid:
    case False{}: Fail{"loaded density router or registry has invalid identities, duplicates or exceeds caller budget"}
    case True{}: marked_unblended(prepared_climate(plan,registry,router,
      lower_unblended(climate_expressions(router),registry,depth,capacity,C.Build{[],[],0},[])))

def compile_climate_unblended(+plan:O.Plan,+registry:A.Registry,limits:C.Limits) -> Result<&2,&2,String,Program>:
  match limits:
    case C.Limits{depth,nodes,entries}:
      +router = selected_router(plan)
      admitted_climate_unblended(plan,registry,router,depth,nodes,NS.router_valid(router) && C.registry_valid(registry,entries))

def loaded_registry(plan:O.Plan,limits:C.Limits,result:Result<&2,&2,String,A.Registry>) -> Result<&2,&2,String,Program>:
  match result:
    case Fail{message}: Fail{message}
    case Done{registry}: compile(plan,registry,limits)

def load(plan:O.Plan,loaded:J.Value,limits:C.Limits) -> Result<&2,&2,String,Program>:
  loaded_registry(plan,limits,L.registry(loaded))

def loaded_unblended_registry(plan:O.Plan,limits:C.Limits,result:Result<&2,&2,String,A.Registry>) -> Result<&2,&2,String,Program>:
  match result:
    case Fail{message}: Fail{message}
    case Done{registry}: compile_unblended(plan,registry,limits)

def load_unblended(plan:O.Plan,loaded:J.Value,limits:C.Limits) -> Result<&2,&2,String,Program>:
  loaded_unblended_registry(plan,limits,L.registry(loaded))

def loaded_climate_registry(plan:O.Plan,limits:C.Limits,result:Result<&2,&2,String,A.Registry>) -> Result<&2,&2,String,Program>:
  match result:
    case Fail{message}: Fail{message}
    case Done{registry}: compile_climate(plan,registry,limits)

def load_climate(plan:O.Plan,loaded:J.Value,limits:C.Limits) -> Result<&2,&2,String,Program>:
  loaded_climate_registry(plan,limits,L.registry(loaded))

def loaded_climate_unblended_registry(plan:O.Plan,limits:C.Limits,result:Result<&2,&2,String,A.Registry>) -> Result<&2,&2,String,Program>:
  match result:
    case Fail{message}: Fail{message}
    case Done{registry}: compile_climate_unblended(plan,registry,limits)

def load_climate_unblended(plan:O.Plan,loaded:J.Value,limits:C.Limits) -> Result<&2,&2,String,Program>:
  loaded_climate_unblended_registry(plan,limits,L.registry(loaded))

def initialized(router:NS.Router,roots:Roots,result:Result<&2,&1,String,S.State>) -> Result<&2,&1,String,State>:
  match result:
    case Fail{message}: Fail{message}
    case Done{density}: Done{State{router,roots,density}}

def initialize(program:Program,fuel:Nat) -> Result<&2,&1,String,State>:
  match program:
    case Program{router,roots,density}: initialized(router,roots,S.initialize(density,fuel))

def initialized_loaded(fuel:Nat,result:Result<&2,&2,String,Program>) -> Result<&2,&1,String,State>:
  match result:
    case Fail{message}: Fail{message}
    case Done{program}: initialize(program,fuel)

def initialize_loaded(plan:O.Plan,loaded:J.Value,limits:C.Limits,fuel:Nat) -> Result<&2,&1,String,State>:
  initialized_loaded(fuel,load(plan,loaded,limits))

def initialize_unblended(plan:O.Plan,loaded:J.Value,limits:C.Limits,fuel:Nat) -> Result<&2,&1,String,State>:
  initialized_loaded(fuel,load_unblended(plan,loaded,limits))

def initialize_climate_loaded(plan:O.Plan,loaded:J.Value,limits:C.Limits,fuel:Nat) -> Result<&2,&1,String,State>:
  initialized_loaded(fuel,load_climate(plan,loaded,limits))

def initialize_climate_unblended(plan:O.Plan,loaded:J.Value,limits:C.Limits,fuel:Nat) -> Result<&2,&1,String,State>:
  initialized_loaded(fuel,load_climate_unblended(plan,loaded,limits))

def policy(roots:Roots) -> Policy:
  match roots:
    case UnblendedRoots{roots}: NoBlending{}
    case _: ContextUnspecified{}

def index(roots:Roots,channel:Channel) -> Maybe<&2,U32>:
  match roots channel:
    case Roots{s,c,d,e,f,r,t,v} ChunkSurfaceLevel{}: Some{s}
    case Roots{s,c,d,e,f,r,t,v} Continents{}: Some{c}
    case Roots{s,c,d,e,f,r,t,v} Depth{}: Some{d}
    case Roots{s,c,d,e,f,r,t,v} Erosion{}: Some{e}
    case Roots{s,c,d,e,f,r,t,v} FinalDensity{}: Some{f}
    case Roots{s,c,d,e,f,r,t,v} Ridges{}: Some{r}
    case Roots{s,c,d,e,f,r,t,v} Temperature{}: Some{t}
    case Roots{s,c,d,e,f,r,t,v} Vegetation{}: Some{v}
    case ClimateRoots{c,d,e,r,t,v} Continents{}: Some{c}
    case ClimateRoots{c,d,e,r,t,v} Depth{}: Some{d}
    case ClimateRoots{c,d,e,r,t,v} Erosion{}: Some{e}
    case ClimateRoots{c,d,e,r,t,v} Ridges{}: Some{r}
    case ClimateRoots{c,d,e,r,t,v} Temperature{}: Some{t}
    case ClimateRoots{c,d,e,r,t,v} Vegetation{}: Some{v}
    case ClimateRoots{c,d,e,r,t,v} _: None{}
    case UnblendedRoots{roots} _: index(roots,channel)

def indices(roots:Roots) -> Result<&2,&2,String,List<&2,U32>>:
  match roots:
    case Roots{s,c,d,e,f,r,t,v}: Done{[s,c,d,e,f,r,t,v]}
    case ClimateRoots{c,d,e,r,t,v}: Fail{"full density router outputs were not compiled"}
    case UnblendedRoots{roots}: indices(roots)

# NoiseRouter.createClimateSampler maps vegetation to humidity, continents to
# continentalness and ridges to weirdness. DensitySampler outputs are F32 in
# pinned26.3; noise coordinates/scales remain F64 in the underlying evaluator.
def climate_indices(roots:Roots) -> List<&2,U32>:
  match roots:
    case Roots{s,c,d,e,f,r,t,v}: [t,v,c,e,d,r]
    case ClimateRoots{c,d,e,r,t,v}: [t,v,c,e,d,r]
    case UnblendedRoots{roots}: climate_indices(roots)

def returned(-A:Data,router:NS.Router,roots:Roots,result:S.State & Result<&2,&2,String,A>) -> State & Result<&2,&2,String,A>:
  match result:
    case Tuple{density,status}: (State{router,roots,density},status)

def evaluate_index(router:NS.Router,roots:Roots,density:S.State,depth:Nat,point:S.Point,selected:Maybe<&2,U32>) -> State & Result<&2,&2,String,F32>:
  match selected:
    case None{}: (State{router,roots,density},Fail{"requested density router output was not compiled"})
    case Some{index}: returned(F32,router,roots,D.evaluate(depth,density,index,point))

def evaluate(state:State,depth:Nat,channel:Channel,point:S.Point) -> State & Result<&2,&2,String,F32>:
  match state:
    case State{router,+roots,density}: evaluate_index(router,roots,density,depth,point,index(roots,channel))

def read_continued(result:S.State & Result<&2,&2,String,F32>,
    next:S.State -> F32 -> S.State & Result<&2,&2,String,List<&2,F32>>) -> S.State & Result<&2,&2,String,List<&2,F32>>:
  match result:
    case Tuple{state,Fail{message}}: (state,Fail{message})
    case Tuple{state,Done{value}}: next(state)(value)

def read_indices(indices:List<&2,U32>,state:S.State,+depth:Nat,+point:S.Point,values:List<&2,F32>) ->
    S.State & Result<&2,&2,String,List<&2,F32>>:
  match indices:
    case Nil{}: (state,Done{List.reverse(&2,F32,values)})
    case index <> rest:
      read_continued(D.evaluate(depth,state,index,point),next => value => read_indices(rest,next,depth,point,value <> values))

def transaction(-A:Data,original:S.Cache,result:S.State & Result<&2,&2,String,A>) -> S.State & Result<&2,&2,String,A>:
  match result:
    case Tuple{S.State{program,pool,cache},Fail{message}}: (S.State{program,pool,original},Fail{message})
    case Tuple{state,Done{value}}: (state,Done{value})

def sample_indices(state:State,indices:List<&2,U32>,depth:Nat,point:S.Point) -> State & Result<&2,&2,String,List<&2,F32>>:
  match state:
    case State{router,roots,S.State{program,pool,+cache}}:
      returned(List<&2,F32>,router,roots,transaction(List<&2,F32>,cache,
        read_indices(indices,S.State{program,pool,cache},depth,point,[])))

def values_result(result:State & Result<&2,&2,String,List<&2,F32>>) -> State & Result<&2,&2,String,Values>:
  match result:
    case Tuple{state,Fail{message}}: (state,Fail{message})
    case Tuple{state,Done{surface <> continents <> depth <> erosion <> density <> ridges <> temperature <> vegetation <> Nil{}}}:
      (state,Done{Values{surface,continents,depth,erosion,density,ridges,temperature,vegetation}})
    case Tuple{state,Done{_}}: (state,Fail{"density router sampling did not produce eight values"})

def sample_admitted(state:State,depth:Nat,point:S.Point,selected:Result<&2,&2,String,List<&2,U32>>) -> State & Result<&2,&2,String,Values>:
  match selected:
    case Fail{message}: (state,Fail{message})
    case Done{indices}: values_result(sample_indices(state,indices,depth,point))

def sample(state:State,depth:Nat,point:S.Point) -> State & Result<&2,&2,String,Values>:
  match state:
    case State{router,+roots,density}: sample_admitted(State{router,roots,density},depth,point,indices(roots))

def climate_result(result:State & Result<&2,&2,String,List<&2,F32>>) -> State & Result<&2,&2,String,B.Values>:
  match result:
    case Tuple{state,Fail{message}}: (state,Fail{message})
    case Tuple{state,Done{temperature <> humidity <> continents <> erosion <> depth <> weirdness <> Nil{}}}:
      (state,Done{B.Values{temperature,humidity,continents,erosion,depth,weirdness}})
    case Tuple{state,Done{_}}: (state,Fail{"density router climate sampling did not produce six values"})

def climate(state:State,depth:Nat,point:S.Point) -> State & Result<&2,&2,String,B.Values>:
  match state:
    case State{router,+roots,density}: climate_result(sample_indices(State{router,roots,density},climate_indices(roots),depth,point))

def column_admitted(state:State,request:O.ColumnRequest,budget:U32,depth:Nat,full:Maybe<&2,U32>) -> State & Result<&2,&2,String,Column.Column>:
  match state full:
    case _ None{}: (state,Fail{"final-density column root was not compiled"})
    case State{router,roots,density} Some{index}:
      returned(Column.Column,router,roots,Column.sample(density,request,budget,depth))

def column(state:State,request:O.ColumnRequest,budget:U32,depth:Nat) -> State & Result<&2,&2,String,Column.Column>:
  match state:
    case State{router,+roots,density}: column_admitted(State{router,roots,density},request,budget,depth,index(roots,FinalDensity{}))
