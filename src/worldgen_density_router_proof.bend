import Base
import ./worldgen_density_router_laws.bend as L
import ./worldgen_density_router.bend as R
import ./worldgen_density_state.bend as S
import ./worldgen_density.bend as D
import ./worldgen_density_compile.bend as C
import ./worldgen_noise_settings.bend as NS
import ./worldgen_density_laws.bend as DL
import ./worldgen_density_proof.bend as DP

def L.eight_root_assembly_retains_loaded_registry_node_order_and_primary_final_density(plan,registry,surface,continents,depth,erosion,final,ridges,temperature,vegetation,nodes,memo,count,s,c,d,e,f,r,t,v): {==}
def L.climate_root_assembly_retains_uncompiled_router_expressions(plan,registry,surface,continents,depth,erosion,final,ridges,temperature,vegetation,nodes,memo,count,c,d,e,r,t,v): {==}
def L.successive_roots_use_the_actual_returned_shared_build(rest,registry,depth,capacity,build,index,previous): {==}
def L.root_compile_refusal_preserves_diagnostic(continuation,message): {==}
def L.actual_failed_root_lowering_reaches_the_router_without_substitution(expression,rest,registry,depth,capacity,build,previous,message,failed):
  %Equal.sym(Result<&2,&2,String,C.Step>,C.lower(depth,expression,registry,[],build,capacity),Fail{message},failed) :
    {R.continued_compile(_,next => index => R.lower(rest,registry,depth,capacity,next,index <> previous)) ==
      Fail{message} : Result<&2,&2,String,R.Lowered>}
  {==}
def L.loaded_registry_refusal_has_no_replacement_program(plan,limits,message): {==}
def L.loaded_climate_registry_refusal_has_no_replacement_program(plan,limits,message): {==}
def L.seeded_factory_returns_the_one_actual_shared_owner(router,roots,state): {==}
def L.seeded_factory_refusal_has_no_replacement_owner(router,roots,message): {==}
def L.explicit_unblended_policy_retains_complete_selected_program(router,roots,program): {==}
def L.explicit_unblended_owner_exposes_its_policy(roots): {==}
def L.absent_channel_retains_complete_affine_state(router,roots,state,depth,point): {==}
def L.zero_depth_channel_retains_complete_affine_state(router,roots,state,point,index):
  match state:
    case S.State{program,pool,cache}: {==}

def ListWitness(-original:DL.Owner,-actual:S.State & Result<&2,&2,String,List<&2,F32>>) -> Type:
  Exists(S.State & Result<&2,&2,String,List<&2,F32>>,r =>
    {actual == r : S.State & Result<&2,&2,String,List<&2,F32>>} &
      {L.density_owner(List<&2,F32>,r) == original : DL.Owner})

def successful_tail_pair(-original:DL.Owner,-current:DL.Owner,
    -before:S.State & Result<&2,&2,String,F32>,
    -next:S.State -> F32 -> S.State & Result<&2,&2,String,List<&2,F32>>,
    -state:S.State,-value:F32,
    scalar_same:{before == (state,Done{value}) : S.State & Result<&2,&2,String,F32>},
    retained:{current == original : DL.Owner},actual:S.State & Result<&2,&2,String,List<&2,F32>>,
    evidence:{next(state)(value) == actual : S.State & Result<&2,&2,String,List<&2,F32>>} &
      {L.density_owner(List<&2,F32>,actual) == current : DL.Owner}) ->
    ListWitness(original,R.read_continued(before,next)):
  match evidence:
    case Tuple{same,owned}:
      (actual,((%Equal.sym(S.State & Result<&2,&2,String,F32>,before,(state,Done{value}),scalar_same) :
        {R.read_continued(_,next) == actual : S.State & Result<&2,&2,String,List<&2,F32>>}
        same),Equal.trans(DL.Owner,L.density_owner(List<&2,F32>,actual),current,original,owned,retained)))

def successful_tail(-original:DL.Owner,-current:DL.Owner,
    -before:S.State & Result<&2,&2,String,F32>,
    -next:S.State -> F32 -> S.State & Result<&2,&2,String,List<&2,F32>>,
    -state:S.State,-value:F32,
    scalar_same:{before == (state,Done{value}) : S.State & Result<&2,&2,String,F32>},
    retained:{current == original : DL.Owner},result:ListWitness(current,next(state)(value))) ->
    ListWitness(original,R.read_continued(before,next)):
  match result:
    case Tuple{actual,evidence}: successful_tail_pair(original,current,before,next,state,value,scalar_same,retained,actual,evidence)

def read_step_pair(-original:DL.Owner,-before:S.State & Result<&2,&2,String,F32>,
    -next:S.State -> F32 -> S.State & Result<&2,&2,String,List<&2,F32>>,
    continued:@state:S.State -> @value:F32 -> ListWitness(DL.owner(state),next(state)(value)),
    actual:S.State & Result<&2,&2,String,F32>,
    evidence:{before == actual : S.State & Result<&2,&2,String,F32>} & {DL.returned_owner(actual) == original : DL.Owner}) ->
    ListWitness(original,R.read_continued(before,next)):
  match actual evidence:
    case Tuple{state,Fail{message}} Tuple{same,retained}:
      ((state,Fail{message}),((%Equal.sym(S.State & Result<&2,&2,String,F32>,before,(state,Fail{message}),same) :
        {R.read_continued(_,next) == (state,Fail{message}) : S.State & Result<&2,&2,String,List<&2,F32>>}
        {==}),retained))
    case Tuple{state,Done{value}} Tuple{same,retained}:
      successful_tail(original,DL.owner(state),before,next,state,value,same,retained,continued(state)(value))

def read_step(-original:DL.Owner,-before:S.State & Result<&2,&2,String,F32>,
    -next:S.State -> F32 -> S.State & Result<&2,&2,String,List<&2,F32>>,
    continued:@state:S.State -> @value:F32 -> ListWitness(DL.owner(state),next(state)(value)),
    result:DP.EvalWitness(original,before)) -> ListWitness(original,R.read_continued(before,next)):
  match result:
    case Tuple{actual,evidence}: read_step_pair(original,before,next,continued,actual,evidence)

# Induction is over the actual finite list of selected root indices. Each step
# uses the independently proved production evaluator's complete affine owner.
def read_owned(indices:List<&2,U32>,state:S.State,+depth:Nat,+point:S.Point,+values:List<&2,F32>) ->
    ListWitness(DL.owner(state),R.read_indices(indices,state,depth,point,values)):
  match indices:
    case Nil{}: ((state,Done{List.reverse(&2,F32,values)}),({==},{==}))
    case +index <> +rest:
      read_step(DL.owner(state),D.evaluate(depth,state,index,point),
        state => value => R.read_indices(rest,state,depth,point,value <> values),
        state => value => read_owned(rest,state,depth,point,value <> values),DP.evaluate_owned(depth,state,index,point))

def project_pair(-original:DL.Owner,-expression:S.State & Result<&2,&2,String,List<&2,F32>>,
    -actual:S.State & Result<&2,&2,String,List<&2,F32>>,
    evidence:{expression == actual : S.State & Result<&2,&2,String,List<&2,F32>>} &
      {L.density_owner(List<&2,F32>,actual) == original : DL.Owner}) ->
    {L.density_owner(List<&2,F32>,expression) == original : DL.Owner}:
  match evidence:
    case Tuple{same,retained}:
      %Equal.sym(S.State & Result<&2,&2,String,List<&2,F32>>,expression,actual,same) :
        {L.density_owner(List<&2,F32>,_) == original : DL.Owner}
      retained

def project(-original:DL.Owner,-expression:S.State & Result<&2,&2,String,List<&2,F32>>,
    result:ListWitness(original,expression)) -> {L.density_owner(List<&2,F32>,expression) == original : DL.Owner}:
  match result:
    case Tuple{actual,evidence}: project_pair(original,expression,actual,evidence)

def L.every_root_read_retains_complete_program_and_ordered_pool(indices,state,depth,point,values):
  project(DL.owner(state),R.read_indices(indices,state,depth,point,values),read_owned(indices,state,depth,point,values))

def wrapped_owner(router:NS.Router,roots:R.Roots,cache:S.Cache,result:S.State & Result<&2,&2,String,List<&2,F32>>) ->
    {L.returned_owner(List<&2,F32>,R.returned(List<&2,F32>,router,roots,R.transaction(List<&2,F32>,cache,result))) ==
      L.Owner{router,roots,L.density_owner(List<&2,F32>,result)} : L.Owner}:
  match result:
    case Tuple{S.State{program,pool,changed},Fail{message}}: {==}
    case Tuple{state,Done{values}}: {==}

def batch_pair(router:NS.Router,roots:R.Roots,cache:S.Cache,-original:DL.Owner,
    -expression:S.State & Result<&2,&2,String,List<&2,F32>>,
    actual:S.State & Result<&2,&2,String,List<&2,F32>>,
    evidence:{expression == actual : S.State & Result<&2,&2,String,List<&2,F32>>} &
      {L.density_owner(List<&2,F32>,actual) == original : DL.Owner}) ->
    {L.returned_owner(List<&2,F32>,R.returned(List<&2,F32>,router,roots,
      R.transaction(List<&2,F32>,cache,expression))) == L.Owner{router,roots,original} : L.Owner}:
  match evidence:
    case Tuple{same,retained}:
      %Equal.sym(S.State & Result<&2,&2,String,List<&2,F32>>,expression,actual,same) :
        {L.returned_owner(List<&2,F32>,R.returned(List<&2,F32>,router,roots,
          R.transaction(List<&2,F32>,cache,_))) == L.Owner{router,roots,original} : L.Owner}
      %retained :
        {L.returned_owner(List<&2,F32>,R.returned(List<&2,F32>,router,roots,
          R.transaction(List<&2,F32>,cache,actual))) == L.Owner{router,roots,_} : L.Owner}
      wrapped_owner(router,roots,cache,actual)

def batch_project(router:NS.Router,roots:R.Roots,cache:S.Cache,-original:DL.Owner,
    -expression:S.State & Result<&2,&2,String,List<&2,F32>>,result:ListWitness(original,expression)) ->
    {L.returned_owner(List<&2,F32>,R.returned(List<&2,F32>,router,roots,
      R.transaction(List<&2,F32>,cache,expression))) == L.Owner{router,roots,original} : L.Owner}:
  match result:
    case Tuple{actual,evidence}: batch_pair(router,roots,cache,original,expression,actual,evidence)

def L.every_router_root_batch_retains_complete_loaded_owner(state,indices,depth,point):
  match state:
    case R.State{router,roots,S.State{program,pool,+cache}}:
      batch_project(router,roots,cache,DL.owner(S.State{program,pool,cache}),
        R.read_indices(indices,S.State{program,pool,cache},depth,point,[]),
        read_owned(indices,S.State{program,pool,cache},depth,point,[]))

def L.failed_root_batch_restores_complete_cache(original,program,pool,changed,message): {==}
def L.six_axis_binding_matches_the_actual_router_names(s,c,d,e,f,r,t,v): {==}
def L.climate_only_binding_matches_the_actual_router_names(c,d,e,r,t,v): {==}
def L.sampled_climate_values_keep_the_actual_axis_order(state,temperature,humidity,continents,erosion,depth,weirdness): {==}
def L.climate_only_state_cannot_publish_a_final_density_column(router,c,d,e,r,t,v,density,request,budget,depth): {==}
def L.full_router_column_uses_the_existing_actual_density_column_facade(router,s,c,d,e,f,r,t,v,density,request,budget,depth): {==}
