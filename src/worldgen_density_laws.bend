import Base
import ./worldgen_density_ast.bend as A
import ./worldgen_density_compile.bend as C
import ./worldgen_density_state.bend as S
import ./worldgen_density.bend as D
import ./worldgen_overworld.bend as O
import ./worldgen_seed.bend as WS
import ./json.bend as J
import ./f64.bend as F
import ./worldgen_density_loader.bend as Loader
import ./worldgen_density_column.bend as Column

# Complete mutable cache is tracked separately from the immutable saved Program
# and affine seeded producer pool. No array, slot or list position is omitted.
type Owner is Type:
  Owner{program:A.Program,pool:List<&1,S.Slot>}

def owner(state:S.State) -> Owner:
  match state:
    case S.State{program,pool,cache}: Owner{program,pool}

def returned_state(result:S.State & Result<&2,&2,String,F32>) -> S.State:
  (state,status) = result
  state

def returned_owner(result:S.State & Result<&2,&2,String,F32>) -> Owner:
  owner(returned_state(result))

def state_cache(state:S.State) -> S.Cache:
  match state:
    case S.State{program,pool,cache}: cache

def returned_cache(result:S.State & Result<&2,&2,String,F32>) -> S.Cache:
  state_cache(returned_state(result))

def cache_point(cache:S.Cache) -> Maybe<&2,S.Point>:
  match cache:
    case S.Cache{point,values}: point

def failure(result:S.State & Result<&2,&2,String,F32>) -> Maybe<&2,String>:
  match result:
    case Tuple{state,Fail{message}}: Some{message}
    case Tuple{state,Done{value}}: None{}

def producer_owner(result:S.Producer & F32) -> S.Producer:
  (producer,value) = result
  producer

def pool_owner(result:List<&1,S.Slot> & Result<&2,&2,String,F32>) -> List<&1,S.Slot>:
  (pool,status) = result
  pool

def column_state(result:S.State & Result<&2,&2,String,Column.Column>) -> S.State:
  (state,status) = result
  state

def column_owner(result:S.State & Result<&2,&2,String,Column.Column>) -> Owner:
  owner(column_state(result))

def column_cache(result:S.State & Result<&2,&2,String,Column.Column>) -> S.Cache:
  state_cache(column_state(result))

def column_failure(result:S.State & Result<&2,&2,String,Column.Column>) -> Maybe<&2,String>:
  match result:
    case Tuple{state,Fail{message}}: Some{message}
    case Tuple{state,Done{column}}: None{}

law zero_depth_run_retains_complete_state:
  for state:S.State
  for index:U32
  for point:S.Point
  {D.run(0n,state,index,point) ==
    (state,Fail{"density evaluation exceeds caller depth budget"}) :
    S.State & Result<&2,&2,String,F32>}

law zero_depth_evaluation_retains_complete_original_state:
  for state:S.State
  for index:U32
  for point:S.Point
  {D.evaluate(0n,state,index,point) ==
    (state,Fail{"density evaluation exceeds caller depth budget"}) :
    S.State & Result<&2,&2,String,F32>}

law refused_evaluation_restores_complete_original_cache:
  for depth:Nat
  for state:S.State
  for index:U32
  for point:S.Point
  for message:String
  for failed:{failure(D.evaluate(depth,state,index,point)) == Some{message} : Maybe<&2,String>}
  {returned_cache(D.evaluate(depth,state,index,point)) == state_cache(state) : S.Cache}

law every_producer_read_retains_complete_noise_owner:
  for producer:S.Producer
  for +x:F.F64
  for +y:F.F64
  for +z:F.F64
  {producer_owner(S.producer_get(producer,x,y,z)) == producer : S.Producer}

law every_pool_lookup_retains_complete_ordered_pool:
  for +fuel:Nat
  for pool:List<&1,S.Slot>
  for +key:S.Key
  for +x:F.F64
  for +y:F.F64
  for +z:F.F64
  {pool_owner(S.pool_get(fuel,pool,key,x,y,z)) == pool : List<&1,S.Slot>}

law actual_density_noise_read_retains_complete_state:
  for state:S.State
  for key:S.Key
  for x:F.F64
  for y:F.F64
  for z:F.F64
  {returned_state(D.noise(state,key,x,y,z)) == state : S.State}

law cache_hit_retains_complete_state_without_child_reads:
  for state:S.State
  for index:U32
  for point:S.Point
  for node:Maybe<&2,A.Operation>
  for value:F32
  for one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>
  for two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>
  for three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>
  {D.cached(state,index,point,node,Some{value},one,two,three) == (state,Done{value}) :
    S.State & Result<&2,&2,String,F32>}

law missing_node_retains_complete_state_and_diagnostic:
  for state:S.State
  for index:U32
  for point:S.Point
  for one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>
  for two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>
  for three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>
  {D.indexed(state,index,point,None{},one,two,three) ==
    (state,Fail{"density DAG node index is absent"}) : S.State & Result<&2,&2,String,F32>}

law refused_node_value_does_not_modify_cache_or_pool:
  for state:S.State
  for index:U32
  for message:String
  {D.cache_value(state,index,Fail{message}) == (state,Fail{message}) :
    S.State & Result<&2,&2,String,F32>}

law stored_node_value_preserves_complete_owner_and_prior_values:
  for program:A.Program
  for pool:List<&1,S.Slot>
  for point:Maybe<&2,S.Point>
  for values:List<&2,S.Value>
  for index:U32
  for +value:F32
  {D.cache_value(S.State{program,pool,S.Cache{point,values}},index,Done{value}) ==
    (S.State{program,pool,S.Cache{point,S.Value{index,value} <> values}},Done{value}) :
    S.State & Result<&2,&2,String,F32>}

law changed_sample_point_discards_previous_node_values:
  for +cache:S.Cache
  for +point:S.Point
  for different:{D.cached_point(point,cache_point(cache)) == False{} : Bool}
  {D.select_cache(cache,point) == S.Cache{Some{point},[]} : S.Cache}

law compiled_program_retains_complete_loaded_inputs_and_node_order:
  for plan:O.Plan
  for registry:A.Registry
  for expression:J.Value
  for nodes:List<&2,A.Node>
  for references:List<&2,C.Memo>
  for count:U32
  for index:U32
  {C.prepared(plan,registry,expression,Done{C.Step{C.Build{nodes,references,count},index}}) ==
    Done{A.Program{plan,registry,expression,List.reverse(&2,A.Node,nodes),index}} :
    Result<&2,&2,String,A.Program>}

law invalid_loaded_registry_refuses_before_density_lowering:
  for plan:O.Plan
  for +registry:A.Registry
  for expression:J.Value
  for depth:Nat
  for capacity:U32
  for +entries:Nat
  for invalid:{C.registry_valid(registry,entries) == False{} : Bool}
  {C.compile(plan,registry,expression,C.Limits{depth,capacity,entries}) ==
    Fail{"loaded density/noise registry has invalid identities, duplicates or exceeds caller budget"} :
    Result<&2,&2,String,A.Program>}

law exhausted_reference_depth_refuses_unread_expression:
  for original:J.Value
  for registry:A.Registry
  for path:List<&2,String>
  for build:C.Build
  for capacity:U32
  {C.lower(0n,original,registry,path,build,capacity) ==
    Fail{"density expression exceeds caller reference/depth budget"} : Result<&2,&2,String,C.Step>}

law memo_hit_retains_complete_build_without_loading_registry:
  for key:String
  for path:List<&2,String>
  for build:C.Build
  for definitions:List<&2,A.Binding>
  for index:U32
  for recurse:J.Value -> List<&2,String> -> C.Build -> Result<&2,&2,String,C.Step>
  {C.reference_memo(key,path,build,definitions,Some{index},recurse) ==
    Done{C.Step{build,index}} : Result<&2,&2,String,C.Step>}

law cycle_refusal_precedes_loaded_reference_lowering:
  for +key:String
  for path:List<&2,String>
  for build:C.Build
  for loaded:Maybe<&2,J.Value>
  for recurse:J.Value -> List<&2,String> -> C.Build -> Result<&2,&2,String,C.Step>
  {C.reference_loaded(key,path,build,loaded,True{},recurse) ==
    Fail{"density registry reference cycle at " ++ key} : Result<&2,&2,String,C.Step>}

law absent_loaded_reference_has_precise_diagnostic:
  for +key:String
  for path:List<&2,String>
  for build:C.Build
  for recurse:J.Value -> List<&2,String> -> C.Build -> Result<&2,&2,String,C.Step>
  {C.reference_loaded(key,path,build,None{},False{},recurse) ==
    Fail{"missing loaded density definition: " ++ key} : Result<&2,&2,String,C.Step>}

law missing_normal_noise_definition_cannot_create_fallback_producer:
  for root:WS.Root
  for +name:String
  for fuel:Nat
  {S.normal_defined(root,name,fuel,None{}) ==
    Fail{"missing loaded normal-noise definition: " ++ name} : Result<&2,&1,String,S.Producer>}

law every_bounded_run_retains_complete_program_and_ordered_pool:
  for +depth:Nat
  for state:S.State
  for +index:U32
  for +point:S.Point
  {returned_owner(D.run(depth,state,index,point)) == owner(state) : Owner}

law every_evaluation_retains_complete_program_and_ordered_pool:
  for depth:Nat
  for state:S.State
  for index:U32
  for +point:S.Point
  {returned_owner(D.evaluate(depth,state,index,point)) == owner(state) : Owner}

law loaded_compile_failure_is_not_replaced_by_a_program:
  for plan:O.Plan
  for expression:J.Value
  for limits:C.Limits
  for message:String
  {Loader.compile_registry(plan,expression,limits,Fail{message}) == Fail{message} :
    Result<&2,&2,String,A.Program>}

law loaded_initialization_failure_is_not_replaced_by_a_state:
  for fuel:Nat
  for message:String
  {Loader.initialize_compiled(fuel,Fail{message}) == Fail{message} : Result<&2,&1,String,S.State>}

law loaded_compilation_uses_the_actual_registry_compiler:
  for plan:O.Plan
  for expression:J.Value
  for limits:C.Limits
  for registry:A.Registry
  {Loader.compile_registry(plan,expression,limits,Done{registry}) ==
    C.compile(plan,registry,expression,limits) : Result<&2,&2,String,A.Program>}

law loaded_initialization_uses_the_actual_seeded_pool_factory:
  for fuel:Nat
  for program:A.Program
  {Loader.initialize_compiled(fuel,Done{program}) == S.initialize(program,fuel) :
    Result<&2,&1,String,S.State>}

law loaded_json_binding_conversion_preserves_actual_lookup:
  for members:List<&2,J.Member>
  for +key:String
  {C.lookup(Loader.bindings(members),key) == J.member(J.JObject{members},key) : Maybe<&2,J.Value>}

law actual_reference_memo_hit_retains_build_and_avoids_missing_registry:
  for +key:String
  for path:List<&2,String>
  for nodes:List<&2,A.Node>
  for +memos:List<&2,C.Memo>
  for count:U32
  for definitions:List<&2,A.Binding>
  for noises:List<&2,A.Binding>
  for +index:U32
  for recurse:J.Value -> List<&2,String> -> C.Build -> Result<&2,&2,String,C.Step>
  for hit:{C.lookup_memo(memos,key) == Some{index} : Maybe<&2,U32>}
  {C.reference(key,path,C.Build{nodes,memos,count},A.Registry{definitions,noises},recurse) ==
    Done{C.Step{C.Build{nodes,memos,count},index}} : Result<&2,&2,String,C.Step>}

law named_reference_retains_lowered_nodes_and_exact_memo_identity:
  for +key:String
  for nodes:List<&2,A.Node>
  for references:List<&2,C.Memo>
  for count:U32
  for +index:U32
  {C.named(key,Done{C.Step{C.Build{nodes,references,count},index}}) ==
    Done{C.Step{C.Build{nodes,C.Memo{key,index} <> references,count},index}} : Result<&2,&2,String,C.Step>}

law compiled_failure_retains_precise_diagnostic:
  for plan:O.Plan
  for registry:A.Registry
  for expression:J.Value
  for message:String
  {C.prepared(plan,registry,expression,Fail{message}) == Fail{message} : Result<&2,&2,String,A.Program>}

law initialized_pool_retains_complete_program_and_original_factory_order:
  for program:A.Program
  for keys:List<&2,S.Key>
  for pool:List<&1,S.Slot>
  {S.prepared(program,Done{S.Factory{keys,pool}}) ==
    Done{S.State{program,List.reverse(&1,S.Slot,pool),S.Cache{None{},[]}}} : Result<&2,&1,String,S.State>}

law every_density_column_loop_retains_complete_program_and_ordered_pool:
  for count:Nat
  for state:S.State
  for +depth:Nat
  for +index:U32
  for +expression:J.Value
  for +x:U32
  for +z:U32
  for +bottom:U32
  for +step:U32
  for y:U32
  for values:List<&2,F32>
  {column_owner(Column.sample_loop(count,state,depth,index,expression,x,z,bottom,step,y,values)) ==
    owner(state) : Owner}

law every_density_column_request_retains_complete_program_and_ordered_pool:
  for state:S.State
  for +request:O.ColumnRequest
  for budget:U32
  for depth:Nat
  {column_owner(Column.sample(state,request,budget,depth)) == owner(state) : Owner}

law refused_density_column_restores_complete_original_cache:
  for state:S.State
  for +request:O.ColumnRequest
  for budget:U32
  for depth:Nat
  for message:String
  for failed:{column_failure(Column.sample(state,request,budget,depth)) == Some{message} : Maybe<&2,String>}
  {column_cache(Column.sample(state,request,budget,depth)) == state_cache(state) : S.Cache}

law invalid_density_column_request_retains_complete_original_state:
  for state:S.State
  for +request:O.ColumnRequest
  for +budget:U32
  for depth:Nat
  for invalid:{O.request_valid(request,budget) == False{} : Bool}
  {Column.sample(state,request,budget,depth) ==
    (state,Fail{"column density request exceeds signed-coordinate or sample budget"}) :
    S.State & Result<&2,&2,String,Column.Column>}

law zero_count_column_retains_state_and_original_value_order:
  for state:S.State
  for depth:Nat
  for index:U32
  for expression:J.Value
  for x:U32
  for z:U32
  for bottom:U32
  for step:U32
  for y:U32
  for values:List<&2,F32>
  {Column.sample_loop(0n,state,depth,index,expression,x,z,bottom,step,y,values) ==
    (state,Done{Column.Column{expression,x,z,bottom,step,List.reverse(&2,F32,values)}}) :
    S.State & Result<&2,&2,String,Column.Column>}
