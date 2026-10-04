import Base
import ./worldgen_density_router.bend as R
import ./worldgen_density_ast.bend as A
import ./worldgen_density_compile.bend as C
import ./worldgen_density_state.bend as S
import ./worldgen_density_laws.bend as DL
import ./worldgen_density.bend as D
import ./worldgen_density_column.bend as Column
import ./worldgen_noise_settings.bend as NS
import ./worldgen_overworld.bend as O
import ./worldgen_biome.bend as B
import ./json.bend as J

type Owner is Type:
  Owner{router:NS.Router,roots:R.Roots,density:DL.Owner}

def owner(state:R.State) -> Owner:
  match state:
    case R.State{router,roots,density}: Owner{router,roots,DL.owner(density)}

def density_owner(-A:Data,result:S.State & Result<&2,&2,String,A>) -> DL.Owner:
  (state,status) = result
  DL.owner(state)

def returned_owner(-A:Data,result:R.State & Result<&2,&2,String,A>) -> Owner:
  (state,status) = result
  owner(state)

law eight_root_assembly_retains_loaded_registry_node_order_and_primary_final_density:
  for plan:O.Plan
  for registry:A.Registry
  for surface:J.Value
  for continents:J.Value
  for depth:J.Value
  for erosion:J.Value
  for +final:J.Value
  for ridges:J.Value
  for temperature:J.Value
  for vegetation:J.Value
  for nodes:List<&2,A.Node>
  for memo:List<&2,C.Memo>
  for count:U32
  for s:U32
  for c:U32
  for d:U32
  for e:U32
  for +f:U32
  for r:U32
  for t:U32
  for v:U32
  {R.assembled(plan,registry,NS.Router{surface,continents,depth,erosion,final,ridges,temperature,vegetation},
    R.Lowered{C.Build{nodes,memo,count},[s,c,d,e,f,r,t,v]}) ==
    Done{R.Program{NS.Router{surface,continents,depth,erosion,final,ridges,temperature,vegetation},R.Roots{s,c,d,e,f,r,t,v},
      A.Program{plan,registry,final,List.reverse(&2,A.Node,nodes),f}}} : Result<&2,&2,String,R.Program>}

law climate_root_assembly_retains_uncompiled_router_expressions:
  for plan:O.Plan
  for registry:A.Registry
  for surface:J.Value
  for continents:J.Value
  for depth:J.Value
  for erosion:J.Value
  for final:J.Value
  for ridges:J.Value
  for +temperature:J.Value
  for vegetation:J.Value
  for nodes:List<&2,A.Node>
  for memo:List<&2,C.Memo>
  for count:U32
  for c:U32
  for d:U32
  for e:U32
  for r:U32
  for +t:U32
  for v:U32
  {R.assembled_climate(plan,registry,NS.Router{surface,continents,depth,erosion,final,ridges,temperature,vegetation},
    R.Lowered{C.Build{nodes,memo,count},[t,v,c,e,d,r]}) ==
    Done{R.Program{NS.Router{surface,continents,depth,erosion,final,ridges,temperature,vegetation},R.ClimateRoots{c,d,e,r,t,v},
      A.Program{plan,registry,temperature,List.reverse(&2,A.Node,nodes),t}}} : Result<&2,&2,String,R.Program>}

law successive_roots_use_the_actual_returned_shared_build:
  for rest:List<&2,J.Value>
  for registry:A.Registry
  for depth:Nat
  for capacity:U32
  for build:C.Build
  for index:U32
  for previous:List<&2,U32>
  {R.continued_compile(Done{C.Step{build,index}},next => index => R.lower(rest,registry,depth,capacity,next,index <> previous)) ==
    R.lower(rest,registry,depth,capacity,build,index <> previous) : Result<&2,&2,String,R.Lowered>}

law root_compile_refusal_preserves_diagnostic:
  for continuation:C.Build -> U32 -> Result<&2,&2,String,R.Lowered>
  for message:String
  {R.continued_compile(Fail{message},continuation) == Fail{message} : Result<&2,&2,String,R.Lowered>}

law actual_failed_root_lowering_reaches_the_router_without_substitution:
  for expression:J.Value
  for rest:List<&2,J.Value>
  for +registry:A.Registry
  for +depth:Nat
  for +capacity:U32
  for build:C.Build
  for previous:List<&2,U32>
  for +message:String
  for failed:{C.lower(depth,expression,registry,[],build,capacity) == Fail{message} : Result<&2,&2,String,C.Step>}
  {R.lower(expression <> rest,registry,depth,capacity,build,previous) == Fail{message} : Result<&2,&2,String,R.Lowered>}

law loaded_registry_refusal_has_no_replacement_program:
  for plan:O.Plan
  for limits:C.Limits
  for message:String
  {R.loaded_registry(plan,limits,Fail{message}) == Fail{message} : Result<&2,&2,String,R.Program>}

law loaded_climate_registry_refusal_has_no_replacement_program:
  for plan:O.Plan
  for limits:C.Limits
  for message:String
  {R.loaded_climate_registry(plan,limits,Fail{message}) == Fail{message} : Result<&2,&2,String,R.Program>}

law seeded_factory_returns_the_one_actual_shared_owner:
  for router:NS.Router
  for roots:R.Roots
  for state:S.State
  {R.initialized(router,roots,Done{state}) == Done{R.State{router,roots,state}} : Result<&2,&1,String,R.State>}

law seeded_factory_refusal_has_no_replacement_owner:
  for router:NS.Router
  for roots:R.Roots
  for message:String
  {R.initialized(router,roots,Fail{message}) == Fail{message} : Result<&2,&1,String,R.State>}

law explicit_unblended_policy_retains_complete_selected_program:
  for router:NS.Router
  for roots:R.Roots
  for program:A.Program
  {R.marked_unblended(Done{R.Program{router,roots,program}}) ==
    Done{R.Program{router,R.UnblendedRoots{roots},program}} : Result<&2,&2,String,R.Program>}

law explicit_unblended_owner_exposes_its_policy:
  for roots:R.Roots
  {R.policy(R.UnblendedRoots{roots}) == R.NoBlending{} : R.Policy}

law absent_channel_retains_complete_affine_state:
  for router:NS.Router
  for roots:R.Roots
  for state:S.State
  for depth:Nat
  for point:S.Point
  {R.evaluate_index(router,roots,state,depth,point,None{}) ==
    (R.State{router,roots,state},Fail{"requested density router output was not compiled"}) :
    R.State & Result<&2,&2,String,F32>}

law zero_depth_channel_retains_complete_affine_state:
  for router:NS.Router
  for roots:R.Roots
  for state:S.State
  for point:S.Point
  for index:U32
  {R.evaluate_index(router,roots,state,0n,point,Some{index}) ==
    (R.State{router,roots,state},Fail{"density evaluation exceeds caller depth budget"}) :
    R.State & Result<&2,&2,String,F32>}

law every_root_read_retains_complete_program_and_ordered_pool:
  for indices:List<&2,U32>
  for state:S.State
  for +depth:Nat
  for +point:S.Point
  for values:List<&2,F32>
  {density_owner(List<&2,F32>,R.read_indices(indices,state,depth,point,values)) == DL.owner(state) : DL.Owner}

law every_router_root_batch_retains_complete_loaded_owner:
  for state:R.State
  for indices:List<&2,U32>
  for depth:Nat
  for point:S.Point
  {returned_owner(List<&2,F32>,R.sample_indices(state,indices,depth,point)) == owner(state) : Owner}

law failed_root_batch_restores_complete_cache:
  for original:S.Cache
  for program:A.Program
  for pool:List<&1,S.Slot>
  for changed:S.Cache
  for message:String
  {R.transaction(List<&2,F32>,original,(S.State{program,pool,changed},Fail{message})) ==
    (S.State{program,pool,original},Fail{message}) : S.State & Result<&2,&2,String,List<&2,F32>>}

law six_axis_binding_matches_the_actual_router_names:
  for s:U32
  for c:U32
  for d:U32
  for e:U32
  for f:U32
  for r:U32
  for t:U32
  for v:U32
  {R.climate_indices(R.Roots{s,c,d,e,f,r,t,v}) == [t,v,c,e,d,r] : List<&2,U32>}

law climate_only_binding_matches_the_actual_router_names:
  for c:U32
  for d:U32
  for e:U32
  for r:U32
  for t:U32
  for v:U32
  {R.climate_indices(R.ClimateRoots{c,d,e,r,t,v}) == [t,v,c,e,d,r] : List<&2,U32>}

law sampled_climate_values_keep_the_actual_axis_order:
  for state:R.State
  for temperature:F32
  for humidity:F32
  for continents:F32
  for erosion:F32
  for depth:F32
  for weirdness:F32
  {R.climate_result((state,Done{[temperature,humidity,continents,erosion,depth,weirdness]})) ==
    (state,Done{B.Values{temperature,humidity,continents,erosion,depth,weirdness}}) : R.State & Result<&2,&2,String,B.Values>}

law climate_only_state_cannot_publish_a_final_density_column:
  for router:NS.Router
  for c:U32
  for d:U32
  for e:U32
  for r:U32
  for t:U32
  for v:U32
  for density:S.State
  for request:O.ColumnRequest
  for budget:U32
  for depth:Nat
  {R.column(R.State{router,R.ClimateRoots{c,d,e,r,t,v},density},request,budget,depth) ==
    (R.State{router,R.ClimateRoots{c,d,e,r,t,v},density},Fail{"final-density column root was not compiled"}) :
    R.State & Result<&2,&2,String,Column.Column>}

law full_router_column_uses_the_existing_actual_density_column_facade:
  for router:NS.Router
  for s:U32
  for c:U32
  for d:U32
  for e:U32
  for f:U32
  for r:U32
  for t:U32
  for v:U32
  for density:S.State
  for request:O.ColumnRequest
  for budget:U32
  for depth:Nat
  {R.column(R.State{router,R.Roots{s,c,d,e,f,r,t,v},density},request,budget,depth) ==
    R.returned(Column.Column,router,R.Roots{s,c,d,e,f,r,t,v},Column.sample(density,request,budget,depth)) :
    R.State & Result<&2,&2,String,Column.Column>}
