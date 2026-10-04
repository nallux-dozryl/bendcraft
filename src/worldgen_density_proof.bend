import Base
import ./worldgen_density_laws.bend as Laws
import ./worldgen_density_ast.bend as A
import ./worldgen_density_compile.bend as C
import ./worldgen_density_state.bend as S
import ./worldgen_density.bend as D
import ./worldgen_density_spline.bend as SP
import ./worldgen_density_spline_eval.bend as SE
import ./worldgen_density_minmax.bend as MM
import ./worldgen_density_noise.bend as DN
import ./worldgen_density_noise_proof.bend as DNProof
import ./worldgen_density_noise_laws.bend as DNLaws
import ./worldgen_noise_proof.bend as NoiseProof
import ./worldgen_noise_laws.bend as NoiseLaws
import ./worldgen_blended_noise.bend as BL
import ./worldgen_perlin_noise.bend as P
import ./f64.bend as F
import ./worldgen_density_loader.bend as Loader
import ./json.bend as J
import ./worldgen_density_column.bend as Column
import ./worldgen_overworld.bend as O

def ProducerWitness(-original:S.Producer,-actual:S.Producer & F32) -> Type:
  Exists(S.Producer & F32,r =>
    {actual == r : S.Producer & F32} & {Laws.producer_owner(r) == original : S.Producer})

def normal_pair(-original:DN.Noise,-x:F.F64,-y:F.F64,-z:F.F64,actual:DN.Noise & F32,
    evidence:{DN.get(original,x,y,z) == actual : DN.Noise & F32} &
      {DNLaws.noise_owner(actual) == original : DN.Noise}) ->
    ProducerWitness(S.Normal{original},S.producer_get(S.Normal{original},x,y,z)):
  match actual evidence:
    case Tuple{next,value} Tuple{same,retained}:
      ((S.Normal{next},value),
        ((%Equal.sym(DN.Noise & F32,DN.get(original,x,y,z),(next,value),same) :
          {P.paired(DN.Noise,F32,S.Producer & F32,_,noise => value => (S.Normal{noise},value)) ==
            (S.Normal{next},value) : S.Producer & F32}
        {==}),
        (%Equal.sym(DN.Noise,next,original,retained) : {S.Normal{_} == S.Normal{original} : S.Producer}
        {==})))

def normal_result(-original:DN.Noise,-x:F.F64,-y:F.F64,-z:F.F64,
    result:DNProof.NoiseWitness(original,DN.get(original,x,y,z))) ->
    ProducerWitness(S.Normal{original},S.producer_get(S.Normal{original},x,y,z)):
  match result:
    case Tuple{actual,evidence}: normal_pair(original,x,y,z,actual,evidence)

def base_pair(-original:BL.Blended,-x:F.F64,-y:F.F64,-z:F.F64,actual:BL.Blended & F32,
    evidence:{BL.get(original,False{},x,y,z) == actual : BL.Blended & F32} &
      {NoiseLaws.state_owner(BL.Blended,F32,actual) == original : BL.Blended}) ->
    ProducerWitness(S.Base{original},S.producer_get(S.Base{original},x,y,z)):
  match actual evidence:
    case Tuple{next,value} Tuple{same,retained}:
      ((S.Base{next},value),
        ((%Equal.sym(BL.Blended & F32,BL.get(original,False{},x,y,z),(next,value),same) :
          {P.paired(BL.Blended,F32,S.Producer & F32,_,noise => value => (S.Base{noise},value)) ==
            (S.Base{next},value) : S.Producer & F32}
        {==}),
        (%Equal.sym(BL.Blended,next,original,retained) : {S.Base{_} == S.Base{original} : S.Producer}
        {==})))

def base_result(-original:BL.Blended,-x:F.F64,-y:F.F64,-z:F.F64,
    result:NoiseProof.StateWitness(BL.Blended,F32,original,BL.get(original,False{},x,y,z))) ->
    ProducerWitness(S.Base{original},S.producer_get(S.Base{original},x,y,z)):
  match result:
    case Tuple{actual,evidence}: base_pair(original,x,y,z,actual,evidence)

def producer_owned(producer:S.Producer,+x:F.F64,+y:F.F64,+z:F.F64) ->
    ProducerWitness(producer,S.producer_get(producer,x,y,z)):
  match producer:
    case S.Normal{noise}: normal_result(noise,x,y,z,DNProof.noise_owned(noise,x,y,z))
    case S.Base{noise}: base_result(noise,x,y,z,NoiseProof.blended_owned(noise,False{},x,y,z))

def producer_project_pair(-producer:S.Producer,-x:F.F64,-y:F.F64,-z:F.F64,-actual:S.Producer & F32,
    evidence:{S.producer_get(producer,x,y,z) == actual : S.Producer & F32} &
      {Laws.producer_owner(actual) == producer : S.Producer}) ->
    {Laws.producer_owner(S.producer_get(producer,x,y,z)) == producer : S.Producer}:
  match evidence:
    case Tuple{same,retained}:
      %Equal.sym(S.Producer & F32,S.producer_get(producer,x,y,z),actual,same) :
        {Laws.producer_owner(_) == producer : S.Producer}
      retained

def producer_project(-producer:S.Producer,-x:F.F64,-y:F.F64,-z:F.F64,
    result:ProducerWitness(producer,S.producer_get(producer,x,y,z))) ->
    {Laws.producer_owner(S.producer_get(producer,x,y,z)) == producer : S.Producer}:
  match result:
    case Tuple{actual,evidence}: producer_project_pair(producer,x,y,z,actual,evidence)

def Laws.every_producer_read_retains_complete_noise_owner(producer,x,y,z):
  producer_project(producer,x,y,z,producer_owned(producer,x,y,z))

def PoolWitness(-original:List<&1,S.Slot>,-actual:List<&1,S.Slot> & Result<&2,&2,String,F32>) -> Type:
  Exists(List<&1,S.Slot> & Result<&2,&2,String,F32>,r =>
    {actual == r : List<&1,S.Slot> & Result<&2,&2,String,F32>} &
      {Laws.pool_owner(r) == original : List<&1,S.Slot>})

def pool_hit_pair(key:S.Key,rest:List<&1,S.Slot>,-producer:S.Producer,
    -left:Nat,-target:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,actual:S.Producer & F32,
    evidence:{S.producer_get(producer,x,y,z) == actual : S.Producer & F32} &
      {Laws.producer_owner(actual) == producer : S.Producer}) ->
    PoolWitness(S.Slot{key,producer} <> rest,
      S.slot_read(key,producer,rest,x,y,z,True{},next => S.pool_get(left,next,target,x,y,z))):
  match actual evidence:
    case Tuple{next,value} Tuple{same,retained}:
      ((S.Slot{key,next} <> rest,Done{value}),
        ((%Equal.sym(S.Producer & F32,S.producer_get(producer,x,y,z),(next,value),same) :
          {S.slot_found(key,rest,_) == (S.Slot{key,next} <> rest,Done{value}) :
            List<&1,S.Slot> & Result<&2,&2,String,F32>}
        {==}),
        (%Equal.sym(S.Producer,next,producer,retained) :
          {S.Slot{key,_} <> rest == S.Slot{key,producer} <> rest : List<&1,S.Slot>}
        {==})))

def pool_hit(key:S.Key,rest:List<&1,S.Slot>,-producer:S.Producer,
    -left:Nat,-target:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    result:ProducerWitness(producer,S.producer_get(producer,x,y,z))) ->
    PoolWitness(S.Slot{key,producer} <> rest,
      S.slot_read(key,producer,rest,x,y,z,True{},next => S.pool_get(left,next,target,x,y,z))):
  match result:
    case Tuple{actual,evidence}: pool_hit_pair(key,rest,producer,left,target,x,y,z,actual,evidence)

def pool_miss_pair(key:S.Key,producer:S.Producer,-rest:List<&1,S.Slot>,
    -left:Nat,-target:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    actual:List<&1,S.Slot> & Result<&2,&2,String,F32>,
    evidence:{S.pool_get(left,rest,target,x,y,z) == actual : List<&1,S.Slot> & Result<&2,&2,String,F32>} &
      {Laws.pool_owner(actual) == rest : List<&1,S.Slot>}) ->
    PoolWitness(S.Slot{key,producer} <> rest,
      S.slot_read(key,producer,rest,x,y,z,False{},next => S.pool_get(left,next,target,x,y,z))):
  match actual evidence:
    case Tuple{next,status} Tuple{same,retained}:
      ((S.Slot{key,producer} <> next,status),
        ((%Equal.sym(List<&1,S.Slot> & Result<&2,&2,String,F32>,
          S.pool_get(left,rest,target,x,y,z),(next,status),same) :
          {S.slot_missed(key,producer,_) == (S.Slot{key,producer} <> next,status) :
            List<&1,S.Slot> & Result<&2,&2,String,F32>}
        {==}),
        (%Equal.sym(List<&1,S.Slot>,next,rest,retained) :
          {S.Slot{key,producer} <> _ == S.Slot{key,producer} <> rest : List<&1,S.Slot>}
        {==})))

def pool_miss(key:S.Key,producer:S.Producer,-rest:List<&1,S.Slot>,
    -left:Nat,-target:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    result:PoolWitness(rest,S.pool_get(left,rest,target,x,y,z))) ->
    PoolWitness(S.Slot{key,producer} <> rest,
      S.slot_read(key,producer,rest,x,y,z,False{},next => S.pool_get(left,next,target,x,y,z))):
  match result:
    case Tuple{actual,evidence}: pool_miss_pair(key,producer,rest,left,target,x,y,z,actual,evidence)

def pool_slot(left:Nat,key:S.Key,producer:S.Producer,rest:List<&1,S.Slot>,
    +target:S.Key,+x:F.F64,+y:F.F64,+z:F.F64,found:Bool,
    recurse:(@next:List<&1,S.Slot> -> PoolWitness(next,S.pool_get(left,next,target,x,y,z)))) ->
    PoolWitness(S.Slot{key,producer} <> rest,
      S.slot_read(key,producer,rest,x,y,z,found,next => S.pool_get(left,next,target,x,y,z))):
  match found:
    case True{}: pool_hit(key,rest,producer,left,target,x,y,z,producer_owned(producer,x,y,z))
    case False{}: pool_miss(key,producer,rest,left,target,x,y,z,recurse(rest))

def pool_owned(+fuel:Nat,pool:List<&1,S.Slot>,+target:S.Key,+x:F.F64,+y:F.F64,+z:F.F64) ->
    PoolWitness(pool,S.pool_get(fuel,pool,target,x,y,z)):
  match fuel pool:
    case 0n Nil{}:
      (([],Fail{"density seeded-noise lookup exceeds caller budget"}),({==},{==}))
    case 0n S.Slot{key,producer} <> rest:
      ((S.Slot{key,producer} <> rest,Fail{"density seeded-noise lookup exceeds caller budget"}),({==},{==}))
    case 1n+left Nil{}:
      (([],Fail{"density node has no initialized seeded-noise owner"}),({==},{==}))
    case 1n+ +left S.Slot{+key,producer} <> rest:
      pool_slot(left,key,producer,rest,target,x,y,z,S.key_equal(key,target),
        next => pool_owned(left,next,target,x,y,z))

def pool_project_pair(-fuel:Nat,-pool:List<&1,S.Slot>,-key:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    -actual:List<&1,S.Slot> & Result<&2,&2,String,F32>,
    evidence:{S.pool_get(fuel,pool,key,x,y,z) == actual : List<&1,S.Slot> & Result<&2,&2,String,F32>} &
      {Laws.pool_owner(actual) == pool : List<&1,S.Slot>}) ->
    {Laws.pool_owner(S.pool_get(fuel,pool,key,x,y,z)) == pool : List<&1,S.Slot>}:
  match evidence:
    case Tuple{same,retained}:
      %Equal.sym(List<&1,S.Slot> & Result<&2,&2,String,F32>,S.pool_get(fuel,pool,key,x,y,z),actual,same) :
        {Laws.pool_owner(_) == pool : List<&1,S.Slot>}
      retained

def pool_project(-fuel:Nat,-pool:List<&1,S.Slot>,-key:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    result:PoolWitness(pool,S.pool_get(fuel,pool,key,x,y,z))) ->
    {Laws.pool_owner(S.pool_get(fuel,pool,key,x,y,z)) == pool : List<&1,S.Slot>}:
  match result:
    case Tuple{actual,evidence}: pool_project_pair(fuel,pool,key,x,y,z,actual,evidence)

def Laws.every_pool_lookup_retains_complete_ordered_pool(fuel,pool,key,x,y,z):
  pool_project(fuel,pool,key,x,y,z,pool_owned(fuel,pool,key,x,y,z))

def StateWitness(-original:S.State,-actual:S.State & Result<&2,&2,String,F32>) -> Type:
  Exists(S.State & Result<&2,&2,String,F32>,r =>
    {actual == r : S.State & Result<&2,&2,String,F32>} & {Laws.returned_state(r) == original : S.State})

def noise_pair(program:A.Program,cache:S.Cache,-pool:List<&1,S.Slot>,
    -key:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    actual:List<&1,S.Slot> & Result<&2,&2,String,F32>,
    evidence:{S.pool_get(List.length(&2,A.Node,D.case_nodes(program)),pool,key,x,y,z) == actual :
      List<&1,S.Slot> & Result<&2,&2,String,F32>} & {Laws.pool_owner(actual) == pool : List<&1,S.Slot>}) ->
    StateWitness(S.State{program,pool,cache},D.noise(S.State{program,pool,cache},key,x,y,z)):
  match actual evidence:
    case Tuple{next,status} Tuple{same,retained}:
      ((S.State{program,next,cache},status),
        ((%Equal.sym(List<&1,S.Slot> & Result<&2,&2,String,F32>,
          S.pool_get(List.length(&2,A.Node,D.case_nodes(program)),pool,key,x,y,z),(next,status),same) :
          {D.produced(program,cache,_) == (S.State{program,next,cache},status) :
            S.State & Result<&2,&2,String,F32>}
        {==}),
        (%Equal.sym(List<&1,S.Slot>,next,pool,retained) :
          {S.State{program,_,cache} == S.State{program,pool,cache} : S.State}
        {==})))

def noise_result(program:A.Program,cache:S.Cache,-pool:List<&1,S.Slot>,
    -key:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    result:PoolWitness(pool,S.pool_get(List.length(&2,A.Node,D.case_nodes(program)),pool,key,x,y,z))) ->
    StateWitness(S.State{program,pool,cache},D.noise(S.State{program,pool,cache},key,x,y,z)):
  match result:
    case Tuple{actual,evidence}: noise_pair(program,cache,pool,key,x,y,z,actual,evidence)

def noise_owned(state:S.State,+key:S.Key,+x:F.F64,+y:F.F64,+z:F.F64) ->
    StateWitness(state,D.noise(state,key,x,y,z)):
  match state:
    case S.State{+program,pool,cache}:
      noise_result(program,cache,pool,key,x,y,z,
        pool_owned(List.length(&2,A.Node,D.case_nodes(program)),pool,key,x,y,z))

def noise_project_pair(-state:S.State,-key:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    -actual:S.State & Result<&2,&2,String,F32>,
    evidence:{D.noise(state,key,x,y,z) == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_state(actual) == state : S.State}) ->
    {Laws.returned_state(D.noise(state,key,x,y,z)) == state : S.State}:
  match evidence:
    case Tuple{same,retained}:
      %Equal.sym(S.State & Result<&2,&2,String,F32>,D.noise(state,key,x,y,z),actual,same) :
        {Laws.returned_state(_) == state : S.State}
      retained

def noise_project(-state:S.State,-key:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    result:StateWitness(state,D.noise(state,key,x,y,z))) ->
    {Laws.returned_state(D.noise(state,key,x,y,z)) == state : S.State}:
  match result:
    case Tuple{actual,evidence}: noise_project_pair(state,key,x,y,z,actual,evidence)

def Laws.actual_density_noise_read_retains_complete_state(state,key,x,y,z):
  noise_project(state,key,x,y,z,noise_owned(state,key,x,y,z))

def Laws.zero_depth_run_retains_complete_state(state,index,point):
  match state:
    case S.State{program,pool,cache}: {==}

def Laws.zero_depth_evaluation_retains_complete_original_state(state,index,point):
  match state:
    case S.State{program,pool,cache}: {==}

def failure_truth(value:Maybe<&2,String>) -> Data:
  match value:
    case None{}: Unit
    case Some{message}: Empty

def none_is_not_failure(-message:String,contradiction:{None{} == Some{message} : Maybe<&2,String>}) -> Empty:
  %contradiction : failure_truth(_)
  Unit{}

def TransactionWitness(-original:S.Cache,-actual:S.State & Result<&2,&2,String,F32>) -> Type:
  Exists(S.State & Result<&2,&2,String,F32>,r =>
    {actual == r : S.State & Result<&2,&2,String,F32>} &
    (@message:String -> @failed:{Laws.failure(r) == Some{message} : Maybe<&2,String>} ->
      {Laws.returned_cache(r) == original : S.Cache}))

def transaction_owned(original:S.Cache,result:S.State & Result<&2,&2,String,F32>) ->
    TransactionWitness(original,D.transaction(original,result)):
  match result:
    case Tuple{S.State{program,pool,cache},Fail{message}}:
      ((S.State{program,pool,original},Fail{message}),({==},other => failed => {==}))
    case Tuple{state,Done{value}}:
      ((state,Done{value}),({==},message => failed =>
        Empty.absurd({Laws.state_cache(state) == original : S.Cache},none_is_not_failure(message,failed))))

def evaluation_cache_owned(depth:Nat,state:S.State,index:U32,+point:S.Point) ->
    TransactionWitness(Laws.state_cache(state),D.evaluate(depth,state,index,point)):
  match state:
    case S.State{program,pool,+cache}:
      transaction_owned(cache,D.run(depth,S.State{program,pool,D.select_cache(cache,point)},index,point))

def failure_transport(-cache:S.Cache,-before:S.State & Result<&2,&2,String,F32>,
    -after:S.State & Result<&2,&2,String,F32>,-message:String,
    same:{before == after : S.State & Result<&2,&2,String,F32>},
    retained:(@failed:{Laws.failure(after) == Some{message} : Maybe<&2,String>} ->
      {Laws.returned_cache(after) == cache : S.Cache})) ->
    (@failed:{Laws.failure(before) == Some{message} : Maybe<&2,String>} ->
      {Laws.returned_cache(before) == cache : S.Cache}):
  %Equal.sym(S.State & Result<&2,&2,String,F32>,before,after,same) :
    (@failed:{Laws.failure(_) == Some{message} : Maybe<&2,String>} ->
      {Laws.returned_cache(_) == cache : S.Cache})
  retained

def failed_pair(-depth:Nat,-state:S.State,-index:U32,-point:S.Point,message:String,
    -actual:S.State & Result<&2,&2,String,F32>,
    evidence:{D.evaluate(depth,state,index,point) == actual : S.State & Result<&2,&2,String,F32>} &
      (@other:String -> @failed:{Laws.failure(actual) == Some{other} : Maybe<&2,String>} ->
        {Laws.returned_cache(actual) == Laws.state_cache(state) : S.Cache}),
    failed:{Laws.failure(D.evaluate(depth,state,index,point)) == Some{message} : Maybe<&2,String>}) ->
    {Laws.returned_cache(D.evaluate(depth,state,index,point)) == Laws.state_cache(state) : S.Cache}:
  match evidence:
    case Tuple{same,retained}:
      failure_transport(Laws.state_cache(state),D.evaluate(depth,state,index,point),actual,message,same,retained(message))(failed)

def failed_result(-depth:Nat,-state:S.State,-index:U32,-point:S.Point,message:String,
    result:TransactionWitness(Laws.state_cache(state),D.evaluate(depth,state,index,point)),
    failed:{Laws.failure(D.evaluate(depth,state,index,point)) == Some{message} : Maybe<&2,String>}) ->
    {Laws.returned_cache(D.evaluate(depth,state,index,point)) == Laws.state_cache(state) : S.Cache}:
  match result:
    case Tuple{actual,evidence}: failed_pair(depth,state,index,point,message,actual,evidence,failed)

def Laws.refused_evaluation_restores_complete_original_cache(depth,state,index,point,message,failed):
  failed_result(depth,state,index,point,message,evaluation_cache_owned(depth,state,index,point),failed)

def Laws.cache_hit_retains_complete_state_without_child_reads(state,index,point,node,value,one,two,three): {==}

def Laws.missing_node_retains_complete_state_and_diagnostic(state,index,point,one,two,three): {==}

def Laws.refused_node_value_does_not_modify_cache_or_pool(state,index,message):
  match state:
    case S.State{program,pool,S.Cache{point,values}}: {==}

def Laws.stored_node_value_preserves_complete_owner_and_prior_values(program,pool,point,values,index,value): {==}

def changed_point(cache:S.Cache,+point:S.Point,
    different:{D.cached_point(point,Laws.cache_point(cache)) == False{} : Bool}) ->
    {D.select_cache(cache,point) == S.Cache{Some{point},[]} : S.Cache}:
  match cache:
    case S.Cache{cached,values}:
      %Equal.sym(Bool,D.cached_point(point,cached),False{},different) :
        {D.cache_for(S.Cache{cached,values},point,_) == S.Cache{Some{point},[]} : S.Cache}
      {==}

def Laws.changed_sample_point_discards_previous_node_values(cache,point,different):
  changed_point(cache,point,different)

def Laws.compiled_program_retains_complete_loaded_inputs_and_node_order(plan,registry,expression,nodes,references,count,index): {==}

def Laws.invalid_loaded_registry_refuses_before_density_lowering(plan,registry,expression,depth,capacity,entries,invalid):
  %Equal.sym(Bool,C.registry_valid(registry,entries),False{},invalid) :
    {C.admitted(plan,registry,expression,depth,capacity,_) ==
      Fail{"loaded density/noise registry has invalid identities, duplicates or exceeds caller budget"} :
      Result<&2,&2,String,A.Program>}
  {==}

def Laws.exhausted_reference_depth_refuses_unread_expression(original,registry,path,build,capacity): {==}

def Laws.memo_hit_retains_complete_build_without_loading_registry(key,path,build,definitions,index,recurse): {==}

def Laws.cycle_refusal_precedes_loaded_reference_lowering(key,path,build,loaded,recurse):
  match loaded:
    case None{}: {==}
    case Some{value}: {==}

def Laws.absent_loaded_reference_has_precise_diagnostic(key,path,build,recurse): {==}

def Laws.missing_normal_noise_definition_cannot_create_fallback_producer(root,name,fuel): {==}

# These proof combinators carry the actual returned affine pair. The erased
# expressions name production calls; no alternate evaluator or sampler exists.
def EvalWitness(-original:Laws.Owner,-actual:S.State & Result<&2,&2,String,F32>) -> Type:
  Exists(S.State & Result<&2,&2,String,F32>,r =>
    {actual == r : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_owner(r) == original : Laws.Owner})

def retarget_pair(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    -after:S.State & Result<&2,&2,String,F32>,
    same:{before == after : S.State & Result<&2,&2,String,F32>},
    actual:S.State & Result<&2,&2,String,F32>,
    evidence:{after == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_owner(actual) == original : Laws.Owner}) -> EvalWitness(original,before):
  match evidence:
    case Tuple{after_same,retained}:
      (actual,(Equal.trans(S.State & Result<&2,&2,String,F32>,before,after,actual,same,after_same),retained))

def retarget(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    -after:S.State & Result<&2,&2,String,F32>,
    same:{before == after : S.State & Result<&2,&2,String,F32>},
    result:EvalWitness(original,after)) -> EvalWitness(original,before):
  match result:
    case Tuple{actual,evidence}: retarget_pair(original,before,after,same,actual,evidence)

def reown_pair(-original:Laws.Owner,-current:Laws.Owner,-expression:S.State & Result<&2,&2,String,F32>,
    retained:{current == original : Laws.Owner},actual:S.State & Result<&2,&2,String,F32>,
    evidence:{expression == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_owner(actual) == current : Laws.Owner}) -> EvalWitness(original,expression):
  match evidence:
    case Tuple{same,owned}:
      (actual,(same,Equal.trans(Laws.Owner,Laws.returned_owner(actual),current,original,owned,retained)))

def reown(-original:Laws.Owner,-current:Laws.Owner,-expression:S.State & Result<&2,&2,String,F32>,
    retained:{current == original : Laws.Owner},result:EvalWitness(current,expression)) ->
    EvalWitness(original,expression):
  match result:
    case Tuple{actual,evidence}: reown_pair(original,current,expression,retained,actual,evidence)

def mapped_pair(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    -transform:S.State & Result<&2,&2,String,F32> -> S.State & Result<&2,&2,String,F32>,
    actual:S.State & Result<&2,&2,String,F32>,
    evidence:{before == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_owner(actual) == original : Laws.Owner},
    step:(@result:S.State & Result<&2,&2,String,F32> -> EvalWitness(Laws.returned_owner(result),transform(result)))) ->
    EvalWitness(original,transform(before)):
  match evidence:
    case Tuple{same,retained}:
      retarget(original,transform(before),transform(actual),
        Equal.cong(S.State & Result<&2,&2,String,F32>,S.State & Result<&2,&2,String,F32>,transform,before,actual,same),
        reown(original,Laws.returned_owner(actual),transform(actual),retained,step(actual)))

def mapped(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    -transform:S.State & Result<&2,&2,String,F32> -> S.State & Result<&2,&2,String,F32>,
    result:EvalWitness(original,before),
    step:(@actual:S.State & Result<&2,&2,String,F32> -> EvalWitness(Laws.returned_owner(actual),transform(actual)))) ->
    EvalWitness(original,transform(before)):
  match result:
    case Tuple{actual,evidence}: mapped_pair(original,before,transform,actual,evidence,step)

def transformed_owned(kind:A.Unary,result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),D.transformed(kind,result)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{value}}: ((state,Done{D.unary(kind,value)}),({==},{==}))

def combined_owned(kind:A.Binary,left:F32,rc:Bool,result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),D.combined(kind,left,rc,result)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{right}}: ((state,D.binary(kind,left,right,rc)),({==},{==}))

def clamped_owned(low:F32,high:F32,result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),D.clamped(low,high,result)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{value}}: ((state,Done{D.clamp(value,low,high)}),({==},{==}))

def lerped_owned(alpha:F32,first:F32,result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),D.lerped(alpha,first,result)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{second}}: ((state,Done{P.lerp(alpha,first,second)}),({==},{==}))

def shifted_value_owned(result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),D.shifted_value(result)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{value}}: ((state,Done{F32.mul(value,4.0)}),({==},{==}))

def remembered_owned(index:U32,result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),D.remembered(index,result)):
  match result:
    case Tuple{S.State{program,pool,S.Cache{point,values}},Fail{message}}:
      ((S.State{program,pool,S.Cache{point,values}},Fail{message}),({==},{==}))
    case Tuple{S.State{program,pool,S.Cache{point,values}},Done{+value}}:
      ((S.State{program,pool,S.Cache{point,S.Value{index,value} <> values}},Done{value}),({==},{==}))

def transaction_owner(original:S.Cache,result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),D.transaction(original,result)):
  match result:
    case Tuple{S.State{program,pool,cache},Fail{message}}:
      ((S.State{program,pool,original},Fail{message}),({==},{==}))
    case Tuple{S.State{program,pool,cache},Done{value}}:
      ((S.State{program,pool,cache},Done{value}),({==},{==}))

def continued_pair(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    -next:S.State -> F32 -> S.State & Result<&2,&2,String,F32>,actual:S.State & Result<&2,&2,String,F32>,
    evidence:{before == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_owner(actual) == original : Laws.Owner},
    continuation:(@state:S.State -> @value:F32 -> EvalWitness(Laws.owner(state),next(state)(value)))) ->
    EvalWitness(original,D.continued(before,next)):
  match actual evidence:
    case Tuple{state,Fail{message}} Tuple{same,retained}:
      ((state,Fail{message}),
        ((%Equal.sym(S.State & Result<&2,&2,String,F32>,before,(state,Fail{message}),same) :
          {D.continued(_,next) == (state,Fail{message}) : S.State & Result<&2,&2,String,F32>}
        {==}),retained))
    case Tuple{state,Done{value}} Tuple{same,retained}:
      retarget(original,D.continued(before,next),next(state)(value),
        Equal.cong(S.State & Result<&2,&2,String,F32>,S.State & Result<&2,&2,String,F32>,
          result => D.continued(result,next),before,(state,Done{value}),same),
        reown(original,Laws.owner(state),next(state)(value),retained,continuation(state)(value)))

def continued_owned(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    -next:S.State -> F32 -> S.State & Result<&2,&2,String,F32>,result:EvalWitness(original,before),
    continuation:(@state:S.State -> @value:F32 -> EvalWitness(Laws.owner(state),next(state)(value)))) ->
    EvalWitness(original,D.continued(before,next)):
  match result:
    case Tuple{actual,evidence}: continued_pair(original,before,next,actual,evidence,continuation)

def ReadWitness(-reader:S.State -> U32 -> S.State & Result<&2,&2,String,F32>) -> Type:
  @state:S.State -> @index:U32 -> EvalWitness(Laws.owner(state),reader(state)(index))

def binary_second_owned(kind:A.Binary,left:F32,+right:U32,rc:Bool,state:S.State,skip:Bool,
    -read:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,read_owned:ReadWitness(read)) ->
    EvalWitness(Laws.owner(state),D.binary_second(kind,left,right,rc,state,skip,read)):
  match skip:
    case True{}: ((state,Done{0.0}),({==},{==}))
    case False{}:
      mapped(Laws.owner(state),read(state)(right),result => D.combined(kind,left,rc,result),
        read_owned(state)(right),result => combined_owned(kind,left,rc,result))

def lerp_branch_owned(+alpha:F32,+first:U32,+second:U32,state:S.State,zero:Bool,one:Bool,
    -read_first:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_second:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    first_owned:ReadWitness(read_first),second_owned:ReadWitness(read_second)) ->
    EvalWitness(Laws.owner(state),D.lerp_branch(alpha,first,second,state,zero,one,read_first,read_second)):
  match zero one:
    case True{} True{}: first_owned(state)(first)
    case True{} False{}: first_owned(state)(first)
    case False{} True{}: second_owned(state)(second)
    case False{} False{}:
      continued_owned(Laws.owner(state),read_first(state)(first),
        state => value => D.lerped(alpha,value,read_second(state)(second)),first_owned(state)(first),
        state => value => mapped(Laws.owner(state),read_second(state)(second),
          result => D.lerped(alpha,value,result),second_owned(state)(second),result => lerped_owned(alpha,value,result)))

def choice_owned(state:S.State,+inside:U32,+outside:U32,selected:Bool,
    -read_inside:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_outside:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    inside_owned:ReadWitness(read_inside),outside_owned:ReadWitness(read_outside)) ->
    EvalWitness(Laws.owner(state),D.choice_branch(state,inside,outside,selected,read_inside,read_outside)):
  match selected:
    case True{}: inside_owned(state)(inside)
    case False{}: outside_owned(state)(outside)

# A whole-State noise witness strengthens the evaluator's immutable-owner
# contract. The proof consumes the actual returned state only once.
def noise_owner_pair(-state:S.State,-key:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    actual:S.State & Result<&2,&2,String,F32>,
    evidence:{D.noise(state,key,x,y,z) == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_state(actual) == state : S.State}) ->
    EvalWitness(Laws.owner(state),D.noise(state,key,x,y,z)):
  match evidence:
    case Tuple{same,retained}:
      (actual,(same,Equal.cong(S.State,Laws.Owner,Laws.owner,Laws.returned_state(actual),state,retained)))

def noise_owner_result(-state:S.State,-key:S.Key,-x:F.F64,-y:F.F64,-z:F.F64,
    result:StateWitness(state,D.noise(state,key,x,y,z))) ->
    EvalWitness(Laws.owner(state),D.noise(state,key,x,y,z)):
  match result:
    case Tuple{actual,evidence}: noise_owner_pair(state,key,x,y,z,actual,evidence)

def noise_owner(state:S.State,+key:S.Key,+x:F.F64,+y:F.F64,+z:F.F64) ->
    EvalWitness(Laws.owner(state),D.noise(state,key,x,y,z)):
  noise_owner_result(state,key,x,y,z,noise_owned(state,key,x,y,z))

def shifted_noise_owned(state:S.State,+key:String,+xz:F.F64,+ys:F.F64,point:S.Point,
    +sx:F32,+sy:F32,+sz:F32,mode:A.NoiseMode) ->
    EvalWitness(Laws.owner(state),D.shifted_noise(state,key,xz,ys,point,sx,sy,sz,mode)):
  match point mode:
    case S.Point{x,y,z} A.Plain{}:
      noise_owner(state,S.NormalKey{key},F.mul(F.from_i32(x),xz),F.mul(F.from_i32(y),ys),F.mul(F.from_i32(z),xz))
    case S.Point{x,y,z} A.ShiftedXZ{}:
      noise_owner(state,S.NormalKey{key},F.add(F.mul(F.from_i32(x),xz),F.from_f32(sx)),
        F.mul(F.from_i32(y),ys),F.add(F.mul(F.from_i32(z),xz),F.from_f32(sz)))
    case S.Point{x,y,z} A.ShiftedXYZ{}:
      noise_owner(state,S.NormalKey{key},F.add(F.mul(F.from_i32(x),xz),F.from_f32(sx)),
        F.add(F.mul(F.from_i32(y),ys),F.from_f32(sy)),F.add(F.mul(F.from_i32(z),xz),F.from_f32(sz)))

def shift_owned(state:S.State,+key:String,point:S.Point,is_a:Bool) ->
    EvalWitness(Laws.owner(state),D.shift(state,key,point,is_a)):
  match point is_a:
    case S.Point{x,y,z} True{}:
      mapped(Laws.owner(state),D.noise(state,S.NormalKey{key},
        F.mul(F.from_i32(x),F.F64{1070596096,0}),P.zero(),F.mul(F.from_i32(z),F.F64{1070596096,0})),
        D.shifted_value,
        noise_owner(state,S.NormalKey{key},F.mul(F.from_i32(x),F.F64{1070596096,0}),P.zero(),F.mul(F.from_i32(z),F.F64{1070596096,0})),
        shifted_value_owned)
    case S.Point{x,y,z} False{}:
      mapped(Laws.owner(state),D.noise(state,S.NormalKey{key},
        F.mul(F.from_i32(z),F.F64{1070596096,0}),F.mul(F.from_i32(x),F.F64{1070596096,0}),P.zero()),
        D.shifted_value,
        noise_owner(state,S.NormalKey{key},F.mul(F.from_i32(z),F.F64{1070596096,0}),F.mul(F.from_i32(x),F.F64{1070596096,0}),P.zero()),
        shifted_value_owned)

# The reusable scalar continuations remain literal production expressions.
# Generalizing these as erased affine function arguments loses their quantity
# in the kernel's eta comparison, so they have concrete returned-pair bridges.
def binary_first_pair(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    +kind:A.Binary,+right:U32,+lc:Bool,+rc:Bool,
    -read:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    actual:S.State & Result<&2,&2,String,F32>,
    evidence:{before == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_owner(actual) == original : Laws.Owner},read_owned:ReadWitness(read)) ->
    EvalWitness(original,D.continued(before,state => +value =>
      D.binary_second(kind,value,right,rc && Bool.not(lc),state,D.multiply_skip(kind,value,lc,rc),read))):
  match actual evidence:
    case Tuple{state,Fail{message}} Tuple{same,retained}:
      ((state,Fail{message}),
        ((%Equal.sym(S.State & Result<&2,&2,String,F32>,before,(state,Fail{message}),same) :
          {D.continued(_,state => +value =>
            D.binary_second(kind,value,right,rc && Bool.not(lc),state,D.multiply_skip(kind,value,lc,rc),read)) ==
            (state,Fail{message}) : S.State & Result<&2,&2,String,F32>}
        {==}),retained))
    case Tuple{state,Done{+value}} Tuple{same,retained}:
      retarget(original,D.continued(before,state => +value =>
        D.binary_second(kind,value,right,rc && Bool.not(lc),state,D.multiply_skip(kind,value,lc,rc),read)),
        D.binary_second(kind,value,right,rc && Bool.not(lc),state,D.multiply_skip(kind,value,lc,rc),read),
        Equal.cong(S.State & Result<&2,&2,String,F32>,S.State & Result<&2,&2,String,F32>,
          result => D.continued(result,state => +value =>
            D.binary_second(kind,value,right,rc && Bool.not(lc),state,D.multiply_skip(kind,value,lc,rc),read)),
          before,(state,Done{value}),same),
        reown(original,Laws.owner(state),D.binary_second(kind,value,right,rc && Bool.not(lc),state,D.multiply_skip(kind,value,lc,rc),read),
          retained,binary_second_owned(kind,value,right,rc && Bool.not(lc),state,D.multiply_skip(kind,value,lc,rc),read,read_owned)))

def binary_first(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    +kind:A.Binary,+right:U32,+lc:Bool,+rc:Bool,
    -read:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    result:EvalWitness(original,before),read_owned:ReadWitness(read)) ->
    EvalWitness(original,D.continued(before,state => +value =>
      D.binary_second(kind,value,right,rc && Bool.not(lc),state,D.multiply_skip(kind,value,lc,rc),read))):
  match result:
    case Tuple{actual,evidence}: binary_first_pair(original,before,kind,right,lc,rc,read,actual,evidence,read_owned)

def lerp_first_pair(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    +first:U32,+second:U32,
    -read_first:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_second:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    actual:S.State & Result<&2,&2,String,F32>,
    evidence:{before == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_owner(actual) == original : Laws.Owner},
    first_owned:ReadWitness(read_first),second_owned:ReadWitness(read_second)) ->
    EvalWitness(original,D.continued(before,state => +value =>
      D.lerp_branch(value,first,second,state,F32.is_eq(value,0.0),F32.is_eq(value,1.0),read_first,read_second))):
  match actual evidence:
    case Tuple{state,Fail{message}} Tuple{same,retained}:
      ((state,Fail{message}),
        ((%Equal.sym(S.State & Result<&2,&2,String,F32>,before,(state,Fail{message}),same) :
          {D.continued(_,state => +value =>
            D.lerp_branch(value,first,second,state,F32.is_eq(value,0.0),F32.is_eq(value,1.0),read_first,read_second)) ==
            (state,Fail{message}) : S.State & Result<&2,&2,String,F32>}
        {==}),retained))
    case Tuple{state,Done{+value}} Tuple{same,retained}:
      retarget(original,D.continued(before,state => +value =>
        D.lerp_branch(value,first,second,state,F32.is_eq(value,0.0),F32.is_eq(value,1.0),read_first,read_second)),
        D.lerp_branch(value,first,second,state,F32.is_eq(value,0.0),F32.is_eq(value,1.0),read_first,read_second),
        Equal.cong(S.State & Result<&2,&2,String,F32>,S.State & Result<&2,&2,String,F32>,
          result => D.continued(result,state => +value =>
            D.lerp_branch(value,first,second,state,F32.is_eq(value,0.0),F32.is_eq(value,1.0),read_first,read_second)),
          before,(state,Done{value}),same),
        reown(original,Laws.owner(state),D.lerp_branch(value,first,second,state,F32.is_eq(value,0.0),F32.is_eq(value,1.0),read_first,read_second),
          retained,lerp_branch_owned(value,first,second,state,F32.is_eq(value,0.0),F32.is_eq(value,1.0),read_first,read_second,first_owned,second_owned)))

def lerp_first(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    +first:U32,+second:U32,
    -read_first:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_second:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    result:EvalWitness(original,before),first_owned:ReadWitness(read_first),second_owned:ReadWitness(read_second)) ->
    EvalWitness(original,D.continued(before,state => +value =>
      D.lerp_branch(value,first,second,state,F32.is_eq(value,0.0),F32.is_eq(value,1.0),read_first,read_second))):
  match result:
    case Tuple{actual,evidence}: lerp_first_pair(original,before,first,second,read_first,read_second,actual,evidence,first_owned,second_owned)

def choice_first_pair(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    +low:F32,+high:F32,+inside:U32,+outside:U32,
    -read_inside:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_outside:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    actual:S.State & Result<&2,&2,String,F32>,
    evidence:{before == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_owner(actual) == original : Laws.Owner},
    inside_owned:ReadWitness(read_inside),outside_owned:ReadWitness(read_outside)) ->
    EvalWitness(original,D.continued(before,state => +value =>
      D.choice_branch(state,inside,outside,F32.is_ge(value,low) && F32.is_lt(value,high),read_inside,read_outside))):
  match actual evidence:
    case Tuple{state,Fail{message}} Tuple{same,retained}:
      ((state,Fail{message}),
        ((%Equal.sym(S.State & Result<&2,&2,String,F32>,before,(state,Fail{message}),same) :
          {D.continued(_,state => +value =>
            D.choice_branch(state,inside,outside,F32.is_ge(value,low) && F32.is_lt(value,high),read_inside,read_outside)) ==
            (state,Fail{message}) : S.State & Result<&2,&2,String,F32>}
        {==}),retained))
    case Tuple{state,Done{+value}} Tuple{same,retained}:
      retarget(original,D.continued(before,state => +value =>
        D.choice_branch(state,inside,outside,F32.is_ge(value,low) && F32.is_lt(value,high),read_inside,read_outside)),
        D.choice_branch(state,inside,outside,F32.is_ge(value,low) && F32.is_lt(value,high),read_inside,read_outside),
        Equal.cong(S.State & Result<&2,&2,String,F32>,S.State & Result<&2,&2,String,F32>,
          result => D.continued(result,state => +value =>
            D.choice_branch(state,inside,outside,F32.is_ge(value,low) && F32.is_lt(value,high),read_inside,read_outside)),
          before,(state,Done{value}),same),
        reown(original,Laws.owner(state),D.choice_branch(state,inside,outside,F32.is_ge(value,low) && F32.is_lt(value,high),read_inside,read_outside),
          retained,choice_owned(state,inside,outside,F32.is_ge(value,low) && F32.is_lt(value,high),read_inside,read_outside,inside_owned,outside_owned)))

def choice_first(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    +low:F32,+high:F32,+inside:U32,+outside:U32,
    -read_inside:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_outside:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    result:EvalWitness(original,before),inside_owned:ReadWitness(read_inside),outside_owned:ReadWitness(read_outside)) ->
    EvalWitness(original,D.continued(before,state => +value =>
      D.choice_branch(state,inside,outside,F32.is_ge(value,low) && F32.is_lt(value,high),read_inside,read_outside))):
  match result:
    case Tuple{actual,evidence}: choice_first_pair(original,before,low,high,inside,outside,read_inside,read_outside,actual,evidence,inside_owned,outside_owned)

# These witnesses compose actual MinMax callbacks and spline layer callbacks.
# They retain the complete program and ordered pool, while permitting cache
# changes and arbitrary returned values or diagnostics.
def minmax_combined_owned(kind:A.Binary,first:F32,result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),MM.combined(S.State,kind,first,result)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{value}}: ((state,MM.combine(kind,first,value)),({==},{==}))

def minmax_constant_owned(kind:A.Binary,constant:F32,result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),MM.constant_combined(S.State,kind,constant,result)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{value}}: ((state,MM.combine(kind,value,constant)),({==},{==}))

def minmax_second_owned(+kind:A.Binary,state:S.State,+first:F32,+right:U32,skip:Bool,
    -read:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,read_owned:ReadWitness(read)) ->
    EvalWitness(Laws.owner(state),MM.second(S.State,kind,state,first,right,skip,read)):
  match skip:
    case True{}: ((state,Done{first}),({==},{==}))
    case False{}:
      mapped(Laws.owner(state),read(state)(right),result => MM.combined(S.State,kind,first,result),
        read_owned(state)(right),result => minmax_combined_owned(kind,first,result))

def minmax_first_owned(+kind:A.Binary,+right:U32,+bound:F32,result:S.State & Result<&2,&2,String,F32>,
    -read:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,read_owned:ReadWitness(read)) ->
    EvalWitness(Laws.returned_owner(result),MM.first(S.State,kind,right,bound,result,read)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{+value}}:
      minmax_second_owned(kind,state,value,right,MM.skip(kind,value,bound),read,read_owned)

def minmax_owned(+kind:A.Binary,+left:U32,+right:U32,mode:A.MinMaxMode,state:S.State,
    -read_left:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_right:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    left_owned:ReadWitness(read_left),right_owned:ReadWitness(read_right)) ->
    EvalWitness(Laws.owner(state),MM.step(S.State,kind,left,right,mode,state,read_left,read_right)):
  match mode:
    case A.ReadLeft{}: left_owned(state)(left)
    case A.ReadRight{}: right_owned(state)(right)
    case A.ConstantLeft{+value}:
      mapped(Laws.owner(state),read_right(state)(right),result => MM.constant_combined(S.State,kind,value,result),
        right_owned(state)(right),result => minmax_constant_owned(kind,value,result))
    case A.ConstantRight{+value}:
      mapped(Laws.owner(state),read_left(state)(left),result => MM.constant_combined(S.State,kind,value,result),
        left_owned(state)(left),result => minmax_constant_owned(kind,value,result))
    case A.BoundedRight{+bound}:
      mapped(Laws.owner(state),read_left(state)(left),result => MM.first(S.State,kind,right,bound,result,read_right),
        left_owned(state)(left),result => minmax_first_owned(kind,right,bound,result,read_right,right_owned))

def SplineReadWitness(-reader:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>) -> Type:
  @tree:SP.Tree<U32> -> @state:S.State -> EvalWitness(Laws.owner(state),reader(tree)(state))

def spline_extended_owned(x:F32,location:F32,derivative:F32,result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),SE.extended(S.State,x,location,derivative,result)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{value}}: ((state,Done{SP.extend(x,location,value,derivative)}),({==},{==}))

def spline_interpolated_owned(x:F32,l0:F32,l1:F32,v0:F32,d0:F32,d1:F32,result:S.State & Result<&2,&2,String,F32>) ->
    EvalWitness(Laws.returned_owner(result),SE.interpolated(S.State,x,l0,l1,v0,d0,d1,result)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{v1}}: ((state,Done{SP.hermite(x,l0,l1,v0,v1,d0,d1)}),({==},{==}))

def spline_endpoint_owned(state:S.State,+x:F32,point:Maybe<&2,SP.Point<U32>>,
    -read:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,read_owned:SplineReadWitness(read)) ->
    EvalWitness(Laws.owner(state),SE.endpoint(S.State,state,x,point,read)):
  match point:
    case None{}: ((state,Fail{"density spline selected point is absent"}),({==},{==}))
    case Some{SP.Point{+location,+value,+derivative}}:
      mapped(Laws.owner(state),read(value)(state),result => SE.extended(S.State,x,location,derivative,result),
        read_owned(value)(state),result => spline_extended_owned(x,location,derivative,result))

def spline_left_owned(+x:F32,+l0:F32,+l1:F32,+v1:SP.Tree<U32>,+d0:F32,+d1:F32,
    result:S.State & Result<&2,&2,String,F32>,
    -read:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,read_owned:SplineReadWitness(read)) ->
    EvalWitness(Laws.returned_owner(result),SE.segment_left(S.State,x,l0,l1,v1,d0,d1,result,read)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{+v0}}:
      mapped(Laws.owner(state),read(v1)(state),next => SE.interpolated(S.State,x,l0,l1,v0,d0,d1,next),
        read_owned(v1)(state),next => spline_interpolated_owned(x,l0,l1,v0,d0,d1,next))

def spline_segment_owned(state:S.State,+x:F32,left:Maybe<&2,SP.Point<U32>>,right:Maybe<&2,SP.Point<U32>>,
    -read_left:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    -read_right:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    left_owned:SplineReadWitness(read_left),right_owned:SplineReadWitness(read_right)) ->
    EvalWitness(Laws.owner(state),SE.segment(S.State,state,x,left,right,read_left,read_right)):
  match left right:
    case Some{SP.Point{+l0,+v0,+d0}} Some{SP.Point{+l1,+v1,+d1}}:
      mapped(Laws.owner(state),read_left(v0)(state),result => SE.segment_left(S.State,x,l0,l1,v1,d0,d1,result,read_right),
        left_owned(v0)(state),result => spline_left_owned(x,l0,l1,v1,d0,d1,result,read_right,right_owned))
    case None{} None{}: ((state,Fail{"density spline selected point is absent"}),({==},{==}))
    case None{} Some{point}: ((state,Fail{"density spline selected point is absent"}),({==},{==}))
    case Some{point} None{}: ((state,Fail{"density spline selected point is absent"}),({==},{==}))

def spline_selection_owned(state:S.State,+x:F32,+points:List<&2,SP.Point<U32>>,selected:Result<&2,&2,String,SP.Selection>,
    -read_one:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    -read_left:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    -read_right:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    one_owned:SplineReadWitness(read_one),left_owned:SplineReadWitness(read_left),right_owned:SplineReadWitness(read_right)) ->
    EvalWitness(Laws.owner(state),SE.selection(S.State,state,x,points,selected,read_one,read_left,read_right)):
  match selected:
    case Fail{message}: ((state,Fail{message}),({==},{==}))
    case Done{SP.Endpoint{index}}:
      spline_endpoint_owned(state,x,SP.point_at(U32,points,index),read_one,one_owned)
    case Done{SP.Segment{left,right}}:
      spline_segment_owned(state,x,SP.point_at(U32,points,left),SP.point_at(U32,points,right),read_left,read_right,left_owned,right_owned)

def spline_coordinate_owned(+points:List<&2,SP.Point<U32>>,result:S.State & Result<&2,&2,String,F32>,
    -read_one:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    -read_left:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    -read_right:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    one_owned:SplineReadWitness(read_one),left_owned:SplineReadWitness(read_left),right_owned:SplineReadWitness(read_right)) ->
    EvalWitness(Laws.returned_owner(result),SE.coordinate(S.State,points,result,read_one,read_left,read_right)):
  match result:
    case Tuple{state,Fail{message}}: ((state,Fail{message}),({==},{==}))
    case Tuple{state,Done{+x}}:
      spline_selection_owned(state,x,points,SP.select(U32,points,x),read_one,read_left,read_right,one_owned,left_owned,right_owned)

def spline_step_owned(tree:SP.Tree<U32>,state:S.State,
    -read_coordinate:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_one:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    -read_left:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    -read_right:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    coordinate_owned:ReadWitness(read_coordinate),one_owned:SplineReadWitness(read_one),
    left_owned:SplineReadWitness(read_left),right_owned:SplineReadWitness(read_right)) ->
    EvalWitness(Laws.owner(state),SE.step(S.State,tree,state,read_coordinate,read_one,read_left,read_right)):
  match tree:
    case SP.Constant{value}: ((state,Done{value}),({==},{==}))
    case SP.Multi{+index,+points}:
      mapped(Laws.owner(state),read_coordinate(state)(index),result => SE.coordinate(S.State,points,result,read_one,read_left,read_right),
        coordinate_owned(state)(index),result => spline_coordinate_owned(points,result,read_one,read_left,read_right,one_owned,left_owned,right_owned))

def operation_owned(operation:A.Operation,state:S.State,+point:S.Point,
    -read_one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    one_owned:ReadWitness(read_one),two_owned:ReadWitness(read_two),three_owned:ReadWitness(read_three)) ->
    EvalWitness(Laws.owner(state),D.operation(operation,state,point,read_one,read_two,read_three)):
  match operation:
    case A.OpConstant{value}: ((state,Done{value}),({==},{==}))
    case A.OpUnary{+kind,+input}:
      mapped(Laws.owner(state),read_one(state)(input),result => D.transformed(kind,result),
        one_owned(state)(input),result => transformed_owned(kind,result))
    case A.OpBinary{+kind,+left,+right,+lc,+rc}:
      binary_first(Laws.owner(state),read_one(state)(left),kind,right,lc,rc,read_two,
        one_owned(state)(left),two_owned)
    case A.OpGradient{axis,from,to,fv,tv}: ((state,Done{D.gradient(axis,from,to,fv,tv,point)}),({==},{==}))
    case A.OpClamp{+input,+low,+high}:
      mapped(Laws.owner(state),read_one(state)(input),result => D.clamped(low,high,result),
        one_owned(state)(input),result => clamped_owned(low,high,result))
    case A.OpLerp{+alpha,+first,+second}:
      lerp_first(Laws.owner(state),read_one(state)(alpha),first,second,read_two,read_three,
        one_owned(state)(alpha),two_owned,three_owned)
    case A.OpRangeChoice{+input,+low,+high,+inside,+outside}:
      choice_first(Laws.owner(state),read_one(state)(input),low,high,inside,outside,read_two,read_three,
        one_owned(state)(input),two_owned,three_owned)
    case A.OpCache{input}: one_owned(state)(input)
    case A.OpBaseNoise{config}:
      noise_owner(state,S.BaseKey{config},F.from_i32(D.coordinate(A.X{},point)),
        F.from_i32(D.coordinate(A.Y{},point)),F.from_i32(D.coordinate(A.Z{},point)))
    case A.OpNoise{key,xz,y,+sx,+sy,+sz,mode}:
      continued_owned(Laws.owner(state),read_one(state)(sx),state => x_shift =>
        D.continued(read_two(state)(sy),state => y_shift =>
          D.continued(read_three(state)(sz),state => z_shift => D.shifted_noise(state,key,xz,y,point,x_shift,y_shift,z_shift,mode))),
        one_owned(state)(sx),state => x_shift =>
          continued_owned(Laws.owner(state),read_two(state)(sy),state => y_shift =>
            D.continued(read_three(state)(sz),state => z_shift => D.shifted_noise(state,key,xz,y,point,x_shift,y_shift,z_shift,mode)),
            two_owned(state)(sy),state => y_shift =>
              continued_owned(Laws.owner(state),read_three(state)(sz),state => z_shift =>
                D.shifted_noise(state,key,xz,y,point,x_shift,y_shift,z_shift,mode),
                three_owned(state)(sz),state => z_shift => shifted_noise_owned(state,key,xz,y,point,x_shift,y_shift,z_shift,mode))))
    case A.OpShiftA{key}: shift_owned(state,key,point,True{})
    case A.OpShiftB{key}: shift_owned(state,key,point,False{})
    case A.OpMinMax{kind,left,right,mode}: minmax_owned(kind,left,right,mode,state,read_one,read_two,one_owned,two_owned)
    case A.OpBlendAlpha{}: ((state,Done{1.0}),({==},{==}))
    case A.OpBlendOffset{}: ((state,Done{0.0}),({==},{==}))
    case A.OpBlendDensity{input}: one_owned(state)(input)
    case A.OpSpline{tree}: ((state,Fail{"density spline requires the structural evaluator work route"}),({==},{==}))

def indexed_owned(state:S.State,+index:U32,+point:S.Point,found:Maybe<&2,A.Operation>,
    -read_one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    one_owned:ReadWitness(read_one),two_owned:ReadWitness(read_two),three_owned:ReadWitness(read_three)) ->
    EvalWitness(Laws.owner(state),D.indexed(state,index,point,found,read_one,read_two,read_three)):
  match found:
    case None{}: ((state,Fail{"density DAG node index is absent"}),({==},{==}))
    case Some{+op}:
      mapped(Laws.owner(state),D.operation(op,state,point,read_one,read_two,read_three),
        result => D.remembered(index,result),operation_owned(op,state,point,read_one,read_two,read_three,one_owned,two_owned,three_owned),
        result => remembered_owned(index,result))

def cached_owned(state:S.State,index:U32,point:S.Point,node:Maybe<&2,A.Operation>,hit:Maybe<&2,F32>,
    -read_one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    one_owned:ReadWitness(read_one),two_owned:ReadWitness(read_two),three_owned:ReadWitness(read_three)) ->
    EvalWitness(Laws.owner(state),D.cached(state,index,point,node,hit,read_one,read_two,read_three)):
  match hit:
    case Some{value}: ((state,Done{value}),({==},{==}))
    case None{}: indexed_owned(state,index,point,node,read_one,read_two,read_three,one_owned,two_owned,three_owned)

def work_indexed_owned(state:S.State,+index:U32,+point:S.Point,+found:Maybe<&2,A.Operation>,
    -read_one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_spline:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    one_owned:ReadWitness(read_one),two_owned:ReadWitness(read_two),three_owned:ReadWitness(read_three),
    spline_owned:SplineReadWitness(read_spline)) ->
    EvalWitness(Laws.owner(state),D.work_indexed(state,index,point,found,read_one,read_two,read_three,read_spline)):
  match found:
    case Some{A.OpSpline{+tree}}:
      mapped(Laws.owner(state),read_spline(tree)(state),result => D.remembered(index,result),
        spline_owned(tree)(state),result => remembered_owned(index,result))
    case None{}: indexed_owned(state,index,point,None{},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpConstant{value}}: indexed_owned(state,index,point,Some{A.OpConstant{value}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpUnary{kind,input}}: indexed_owned(state,index,point,Some{A.OpUnary{kind,input}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpBinary{kind,left,right,lc,rc}}: indexed_owned(state,index,point,Some{A.OpBinary{kind,left,right,lc,rc}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpGradient{axis,from,to,fv,tv}}: indexed_owned(state,index,point,Some{A.OpGradient{axis,from,to,fv,tv}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpClamp{input,low,high}}: indexed_owned(state,index,point,Some{A.OpClamp{input,low,high}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpLerp{alpha,first,second}}: indexed_owned(state,index,point,Some{A.OpLerp{alpha,first,second}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpRangeChoice{input,low,high,inside,outside}}: indexed_owned(state,index,point,Some{A.OpRangeChoice{input,low,high,inside,outside}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpCache{input}}: indexed_owned(state,index,point,Some{A.OpCache{input}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpBaseNoise{config}}: indexed_owned(state,index,point,Some{A.OpBaseNoise{config}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpNoise{key,xz,y,sx,sy,sz,mode}}: indexed_owned(state,index,point,Some{A.OpNoise{key,xz,y,sx,sy,sz,mode}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpShiftA{key}}: indexed_owned(state,index,point,Some{A.OpShiftA{key}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpShiftB{key}}: indexed_owned(state,index,point,Some{A.OpShiftB{key}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpMinMax{kind,left,right,mode}}: indexed_owned(state,index,point,Some{A.OpMinMax{kind,left,right,mode}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpBlendAlpha{}}: indexed_owned(state,index,point,Some{A.OpBlendAlpha{}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpBlendOffset{}}: indexed_owned(state,index,point,Some{A.OpBlendOffset{}},read_one,read_two,read_three,one_owned,two_owned,three_owned)
    case Some{A.OpBlendDensity{input}}: indexed_owned(state,index,point,Some{A.OpBlendDensity{input}},read_one,read_two,read_three,one_owned,two_owned,three_owned)

def work_cached_owned(state:S.State,index:U32,point:S.Point,node:Maybe<&2,A.Operation>,hit:Maybe<&2,F32>,
    -read_one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    -read_spline:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>,
    one_owned:ReadWitness(read_one),two_owned:ReadWitness(read_two),three_owned:ReadWitness(read_three),
    spline_owned:SplineReadWitness(read_spline)) ->
    EvalWitness(Laws.owner(state),D.work_cached(state,index,point,node,hit,read_one,read_two,read_three,read_spline)):
  match hit:
    case Some{value}: ((state,Done{value}),({==},{==}))
    case None{}: work_indexed_owned(state,index,point,node,read_one,read_two,read_three,read_spline,one_owned,two_owned,three_owned,spline_owned)

# The only induction measure is the actual caller's depth. Recursive witnesses
# name D.work itself for arbitrary complete states, node indices and spline
# trees. Each callback receives the same complete affine state interface.
def work_owned(+depth:Nat,state:S.State,task:D.Work,+point:S.Point) ->
    EvalWitness(Laws.owner(state),D.work(depth,state,task,point)):
  match depth state task:
    case 0n _ _: ((state,Fail{"density evaluation exceeds caller depth budget"}),({==},{==}))
    case 1n+ +left S.State{+program,pool,S.Cache{cached_point,+values}} D.NodeWork{+index}:
      work_cached_owned(S.State{program,pool,S.Cache{cached_point,values}},index,point,
        D.located(D.case_nodes(program),index),D.value_lookup(values,index),
        state => child => D.work(left,state,D.NodeWork{child},point),
        state => child => D.work(left,state,D.NodeWork{child},point),
        state => child => D.work(left,state,D.NodeWork{child},point),
        tree => state => D.work(left,state,D.SplineWork{tree},point),
        state => child => work_owned(left,state,D.NodeWork{child},point),
        state => child => work_owned(left,state,D.NodeWork{child},point),
        state => child => work_owned(left,state,D.NodeWork{child},point),
        tree => state => work_owned(left,state,D.SplineWork{tree},point))
    case 1n+ +left _ D.SplineWork{tree}:
      spline_step_owned(tree,state,
        state => child => D.work(left,state,D.NodeWork{child},point),
        tree => state => D.work(left,state,D.SplineWork{tree},point),
        tree => state => D.work(left,state,D.SplineWork{tree},point),
        tree => state => D.work(left,state,D.SplineWork{tree},point),
        state => child => work_owned(left,state,D.NodeWork{child},point),
        tree => state => work_owned(left,state,D.SplineWork{tree},point),
        tree => state => work_owned(left,state,D.SplineWork{tree},point),
        tree => state => work_owned(left,state,D.SplineWork{tree},point))

def run_owned(depth:Nat,state:S.State,index:U32,point:S.Point) ->
    EvalWitness(Laws.owner(state),D.run(depth,state,index,point)):
  work_owned(depth,state,D.NodeWork{index},point)

def evaluate_owned(depth:Nat,state:S.State,index:U32,+point:S.Point) ->
    EvalWitness(Laws.owner(state),D.evaluate(depth,state,index,point)):
  match state:
    case S.State{+program,pool,+cache}:
      mapped(Laws.Owner{program,pool},D.run(depth,S.State{program,pool,D.select_cache(cache,point)},index,point),
        result => D.transaction(cache,result),run_owned(depth,S.State{program,pool,D.select_cache(cache,point)},index,point),
        result => transaction_owner(cache,result))

def eval_project_pair(-original:Laws.Owner,-expression:S.State & Result<&2,&2,String,F32>,
    -actual:S.State & Result<&2,&2,String,F32>,
    evidence:{expression == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_owner(actual) == original : Laws.Owner}) ->
    {Laws.returned_owner(expression) == original : Laws.Owner}:
  match evidence:
    case Tuple{same,retained}:
      %Equal.sym(S.State & Result<&2,&2,String,F32>,expression,actual,same) :
        {Laws.returned_owner(_) == original : Laws.Owner}
      retained

def eval_project(-original:Laws.Owner,-expression:S.State & Result<&2,&2,String,F32>,
    result:EvalWitness(original,expression)) -> {Laws.returned_owner(expression) == original : Laws.Owner}:
  match result:
    case Tuple{actual,evidence}: eval_project_pair(original,expression,actual,evidence)

def Laws.every_bounded_run_retains_complete_program_and_ordered_pool(depth,state,index,point):
  eval_project(Laws.owner(state),D.run(depth,state,index,point),run_owned(depth,state,index,point))

def Laws.every_evaluation_retains_complete_program_and_ordered_pool(depth,state,index,point):
  eval_project(Laws.owner(state),D.evaluate(depth,state,index,point),evaluate_owned(depth,state,index,point))

def Laws.loaded_compile_failure_is_not_replaced_by_a_program(plan,expression,limits,message): {==}
def Laws.loaded_initialization_failure_is_not_replaced_by_a_state(fuel,message): {==}
def Laws.loaded_compilation_uses_the_actual_registry_compiler(plan,expression,limits,registry): {==}
def Laws.loaded_initialization_uses_the_actual_seeded_pool_factory(fuel,program): {==}



def lookup_choice(condition:Bool,-yes:Maybe<&2,J.Value>,-no:Maybe<&2,J.Value>) ->
    {Bool.pick(Maybe<&2,J.Value>,condition,yes,no) == J.choose(Maybe<&2,J.Value>,yes,no,condition) : Maybe<&2,J.Value>}:
  match condition:
    case True{}: {==}
    case False{}: {==}

def loaded_lookup(members:List<&2,J.Member>,+key:String) ->
    {C.lookup(Loader.bindings(members),key) == J.member(J.JObject{members},key) : Maybe<&2,J.Value>}:
  match members:
    case Nil{}: {==}
    case J.JMember{+name,+value} <> rest:
      %loaded_lookup(rest,key) :
        {Bool.pick(Maybe<&2,J.Value>,String.eq(name,key),Some{value},C.lookup(Loader.bindings(rest),key)) ==
          J.choose(Maybe<&2,J.Value>,Some{value},_,String.eq(name,key)) : Maybe<&2,J.Value>}
      lookup_choice(String.eq(name,key),Some{value},C.lookup(Loader.bindings(rest),key))

def Laws.loaded_json_binding_conversion_preserves_actual_lookup(members,key): loaded_lookup(members,key)

def Laws.actual_reference_memo_hit_retains_build_and_avoids_missing_registry(key,path,nodes,memos,count,definitions,noises,index,recurse,hit):
  %Equal.sym(Maybe<&2,U32>,C.lookup_memo(memos,key),Some{index},hit) :
    {C.reference_memo(key,path,C.Build{nodes,memos,count},definitions,_,recurse) ==
      Done{C.Step{C.Build{nodes,memos,count},index}} : Result<&2,&2,String,C.Step>}
  {==}

def Laws.named_reference_retains_lowered_nodes_and_exact_memo_identity(key,nodes,references,count,index): {==}
def Laws.compiled_failure_retains_precise_diagnostic(plan,registry,expression,message): {==}
def Laws.initialized_pool_retains_complete_program_and_original_factory_order(program,keys,pool): {==}

# The loaded-DAG column consumer composes the same actual evaluator witness;
# its separate whole-column transaction rolls back the complete original cache.
def ColumnWitness(-original:Laws.Owner,-actual:S.State & Result<&2,&2,String,Column.Column>) -> Type:
  Exists(S.State & Result<&2,&2,String,Column.Column>,r =>
    {actual == r : S.State & Result<&2,&2,String,Column.Column>} &
      {Laws.column_owner(r) == original : Laws.Owner})

def column_retarget_pair(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,Column.Column>,
    -after:S.State & Result<&2,&2,String,Column.Column>,
    same:{before == after : S.State & Result<&2,&2,String,Column.Column>},
    actual:S.State & Result<&2,&2,String,Column.Column>,
    evidence:{after == actual : S.State & Result<&2,&2,String,Column.Column>} &
      {Laws.column_owner(actual) == original : Laws.Owner}) -> ColumnWitness(original,before):
  match evidence:
    case Tuple{after_same,retained}:
      (actual,(Equal.trans(S.State & Result<&2,&2,String,Column.Column>,before,after,actual,same,after_same),retained))

def column_retarget(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,Column.Column>,
    -after:S.State & Result<&2,&2,String,Column.Column>,
    same:{before == after : S.State & Result<&2,&2,String,Column.Column>},
    result:ColumnWitness(original,after)) -> ColumnWitness(original,before):
  match result:
    case Tuple{actual,evidence}: column_retarget_pair(original,before,after,same,actual,evidence)

def column_reown_pair(-original:Laws.Owner,-current:Laws.Owner,-expression:S.State & Result<&2,&2,String,Column.Column>,
    retained:{current == original : Laws.Owner},actual:S.State & Result<&2,&2,String,Column.Column>,
    evidence:{expression == actual : S.State & Result<&2,&2,String,Column.Column>} &
      {Laws.column_owner(actual) == current : Laws.Owner}) -> ColumnWitness(original,expression):
  match evidence:
    case Tuple{same,owned}:
      (actual,(same,Equal.trans(Laws.Owner,Laws.column_owner(actual),current,original,owned,retained)))

def column_reown(-original:Laws.Owner,-current:Laws.Owner,-expression:S.State & Result<&2,&2,String,Column.Column>,
    retained:{current == original : Laws.Owner},result:ColumnWitness(current,expression)) ->
    ColumnWitness(original,expression):
  match result:
    case Tuple{actual,evidence}: column_reown_pair(original,current,expression,retained,actual,evidence)

def column_continued_pair(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    -next:S.State -> F32 -> S.State & Result<&2,&2,String,Column.Column>,actual:S.State & Result<&2,&2,String,F32>,
    evidence:{before == actual : S.State & Result<&2,&2,String,F32>} &
      {Laws.returned_owner(actual) == original : Laws.Owner},
    continuation:(@state:S.State -> @value:F32 -> ColumnWitness(Laws.owner(state),next(state)(value)))) ->
    ColumnWitness(original,Column.continued(before,next)):
  match actual evidence:
    case Tuple{state,Fail{message}} Tuple{same,retained}:
      ((state,Fail{message}),
        ((%Equal.sym(S.State & Result<&2,&2,String,F32>,before,(state,Fail{message}),same) :
          {Column.continued(_,next) == (state,Fail{message}) : S.State & Result<&2,&2,String,Column.Column>}
        {==}),retained))
    case Tuple{state,Done{value}} Tuple{same,retained}:
      column_retarget(original,Column.continued(before,next),next(state)(value),
        Equal.cong(S.State & Result<&2,&2,String,F32>,S.State & Result<&2,&2,String,Column.Column>,
          result => Column.continued(result,next),before,(state,Done{value}),same),
        column_reown(original,Laws.owner(state),next(state)(value),retained,continuation(state)(value)))

def column_continued_owned(-original:Laws.Owner,-before:S.State & Result<&2,&2,String,F32>,
    -next:S.State -> F32 -> S.State & Result<&2,&2,String,Column.Column>,result:EvalWitness(original,before),
    continuation:(@state:S.State -> @value:F32 -> ColumnWitness(Laws.owner(state),next(state)(value)))) ->
    ColumnWitness(original,Column.continued(before,next)):
  match result:
    case Tuple{actual,evidence}: column_continued_pair(original,before,next,actual,evidence,continuation)

def column_loop_owned(count:Nat,state:S.State,+depth:Nat,+index:U32,+expression:J.Value,
    +x:U32,+z:U32,+bottom:U32,+step:U32,+y:U32,+values:List<&2,F32>) ->
    ColumnWitness(Laws.owner(state),Column.sample_loop(count,state,depth,index,expression,x,z,bottom,step,y,values)):
  match count:
    case 0n: ((state,Done{Column.Column{expression,x,z,bottom,step,List.reverse(&2,F32,values)}}),({==},{==}))
    case 1n+rest:
      column_continued_owned(Laws.owner(state),D.evaluate(depth,state,index,S.Point{x,y,z}),
        state => value => Column.sample_loop(rest,state,depth,index,expression,x,z,bottom,step,U32.add(y,step),value <> values),
        evaluate_owned(depth,state,index,S.Point{x,y,z}),
        state => value => column_loop_owned(rest,state,depth,index,expression,x,z,bottom,step,U32.add(y,step),value <> values))

def column_transaction_owner(original:S.Cache,result:S.State & Result<&2,&2,String,Column.Column>) ->
    ColumnWitness(Laws.column_owner(result),Column.transaction(original,result)):
  match result:
    case Tuple{S.State{program,pool,cache},Fail{message}}:
      ((S.State{program,pool,original},Fail{message}),({==},{==}))
    case Tuple{S.State{program,pool,cache},Done{column}}:
      ((S.State{program,pool,cache},Done{column}),({==},{==}))

def column_committed_pair(-original:Laws.Owner,+cache:S.Cache,-before:S.State & Result<&2,&2,String,Column.Column>,
    actual:S.State & Result<&2,&2,String,Column.Column>,
    evidence:{before == actual : S.State & Result<&2,&2,String,Column.Column>} &
      {Laws.column_owner(actual) == original : Laws.Owner}) -> ColumnWitness(original,Column.transaction(cache,before)):
  match evidence:
    case Tuple{same,retained}:
      column_retarget(original,Column.transaction(cache,before),Column.transaction(cache,actual),
        Equal.cong(S.State & Result<&2,&2,String,Column.Column>,S.State & Result<&2,&2,String,Column.Column>,
          result => Column.transaction(cache,result),before,actual,same),
        column_reown(original,Laws.column_owner(actual),Column.transaction(cache,actual),retained,column_transaction_owner(cache,actual)))

def column_committed(-original:Laws.Owner,+cache:S.Cache,-before:S.State & Result<&2,&2,String,Column.Column>,
    result:ColumnWitness(original,before)) -> ColumnWitness(original,Column.transaction(cache,before)):
  match result:
    case Tuple{actual,evidence}: column_committed_pair(original,cache,before,actual,evidence)

def column_admitted_owned(state:S.State,request:O.ColumnRequest,depth:Nat,valid:Bool) ->
    ColumnWitness(Laws.owner(state),Column.admitted(state,request,depth,valid)):
  match state request valid:
    case S.State{A.Program{plan,registry,expression,nodes,index},pool,cache} O.ColumnRequest{x,z,bottom,step,count} False{}:
      ((S.State{A.Program{plan,registry,expression,nodes,index},pool,cache},
        Fail{"column density request exceeds signed-coordinate or sample budget"}),({==},{==}))
    case S.State{A.Program{+plan,+registry,+expression,+nodes,+index},pool,+cache} O.ColumnRequest{+x,+z,+bottom,+step,+count} True{}:
      column_committed(Laws.Owner{A.Program{plan,registry,expression,nodes,index},pool},cache,
        Column.sample_loop(U32.to_nat(count),S.State{A.Program{plan,registry,expression,nodes,index},pool,cache},
          depth,index,expression,x,z,bottom,step,bottom,[]),
        column_loop_owned(U32.to_nat(count),S.State{A.Program{plan,registry,expression,nodes,index},pool,cache},
          depth,index,expression,x,z,bottom,step,bottom,[]))

def column_owned(state:S.State,+request:O.ColumnRequest,+budget:U32,depth:Nat) ->
    ColumnWitness(Laws.owner(state),Column.sample(state,request,budget,depth)):
  column_admitted_owned(state,request,depth,O.request_valid(request,budget))

def column_project_pair(-original:Laws.Owner,-expression:S.State & Result<&2,&2,String,Column.Column>,
    -actual:S.State & Result<&2,&2,String,Column.Column>,
    evidence:{expression == actual : S.State & Result<&2,&2,String,Column.Column>} &
      {Laws.column_owner(actual) == original : Laws.Owner}) ->
    {Laws.column_owner(expression) == original : Laws.Owner}:
  match evidence:
    case Tuple{same,retained}:
      %Equal.sym(S.State & Result<&2,&2,String,Column.Column>,expression,actual,same) :
        {Laws.column_owner(_) == original : Laws.Owner}
      retained

def column_project(-original:Laws.Owner,-expression:S.State & Result<&2,&2,String,Column.Column>,
    result:ColumnWitness(original,expression)) -> {Laws.column_owner(expression) == original : Laws.Owner}:
  match result:
    case Tuple{actual,evidence}: column_project_pair(original,expression,actual,evidence)

def Laws.every_density_column_loop_retains_complete_program_and_ordered_pool(count,state,depth,index,expression,x,z,bottom,step,y,values):
  column_project(Laws.owner(state),Column.sample_loop(count,state,depth,index,expression,x,z,bottom,step,y,values),
    column_loop_owned(count,state,depth,index,expression,x,z,bottom,step,y,values))

def Laws.every_density_column_request_retains_complete_program_and_ordered_pool(state,request,budget,depth):
  column_project(Laws.owner(state),Column.sample(state,request,budget,depth),column_owned(state,request,budget,depth))

def ColumnTransactionWitness(-original:S.Cache,-actual:S.State & Result<&2,&2,String,Column.Column>) -> Type:
  Exists(S.State & Result<&2,&2,String,Column.Column>,r =>
    {actual == r : S.State & Result<&2,&2,String,Column.Column>} &
    (@message:String -> @failed:{Laws.column_failure(r) == Some{message} : Maybe<&2,String>} ->
      {Laws.column_cache(r) == original : S.Cache}))

def column_transaction_cache_owned(original:S.Cache,result:S.State & Result<&2,&2,String,Column.Column>) ->
    ColumnTransactionWitness(original,Column.transaction(original,result)):
  match result:
    case Tuple{S.State{program,pool,cache},Fail{message}}:
      ((S.State{program,pool,original},Fail{message}),({==},other => failed => {==}))
    case Tuple{state,Done{column}}:
      ((state,Done{column}),({==},message => failed =>
        Empty.absurd({Laws.state_cache(state) == original : S.Cache},none_is_not_failure(message,failed))))

def column_admitted_cache_owned(state:S.State,request:O.ColumnRequest,depth:Nat,valid:Bool) ->
    ColumnTransactionWitness(Laws.state_cache(state),Column.admitted(state,request,depth,valid)):
  match state request valid:
    case S.State{A.Program{plan,registry,expression,nodes,index},pool,cache} O.ColumnRequest{x,z,bottom,step,count} False{}:
      ((S.State{A.Program{plan,registry,expression,nodes,index},pool,cache},
        Fail{"column density request exceeds signed-coordinate or sample budget"}),({==},message => failed => {==}))
    case S.State{A.Program{+plan,+registry,+expression,+nodes,+index},pool,+cache} O.ColumnRequest{x,z,+bottom,step,count} True{}:
      column_transaction_cache_owned(cache,Column.sample_loop(U32.to_nat(count),
        S.State{A.Program{plan,registry,expression,nodes,index},pool,cache},depth,index,expression,x,z,bottom,step,bottom,[]))

def column_cache_owned(state:S.State,+request:O.ColumnRequest,+budget:U32,depth:Nat) ->
    ColumnTransactionWitness(Laws.state_cache(state),Column.sample(state,request,budget,depth)):
  column_admitted_cache_owned(state,request,depth,O.request_valid(request,budget))

def column_failure_transport(-cache:S.Cache,-before:S.State & Result<&2,&2,String,Column.Column>,
    -after:S.State & Result<&2,&2,String,Column.Column>,-message:String,
    same:{before == after : S.State & Result<&2,&2,String,Column.Column>},
    retained:(@failed:{Laws.column_failure(after) == Some{message} : Maybe<&2,String>} ->
      {Laws.column_cache(after) == cache : S.Cache})) ->
    (@failed:{Laws.column_failure(before) == Some{message} : Maybe<&2,String>} ->
      {Laws.column_cache(before) == cache : S.Cache}):
  %Equal.sym(S.State & Result<&2,&2,String,Column.Column>,before,after,same) :
    (@failed:{Laws.column_failure(_) == Some{message} : Maybe<&2,String>} ->
      {Laws.column_cache(_) == cache : S.Cache})
  retained

def column_failed_pair(-state:S.State,-request:O.ColumnRequest,-budget:U32,-depth:Nat,message:String,
    -actual:S.State & Result<&2,&2,String,Column.Column>,
    evidence:{Column.sample(state,request,budget,depth) == actual : S.State & Result<&2,&2,String,Column.Column>} &
      (@other:String -> @failed:{Laws.column_failure(actual) == Some{other} : Maybe<&2,String>} ->
        {Laws.column_cache(actual) == Laws.state_cache(state) : S.Cache}),
    failed:{Laws.column_failure(Column.sample(state,request,budget,depth)) == Some{message} : Maybe<&2,String>}) ->
    {Laws.column_cache(Column.sample(state,request,budget,depth)) == Laws.state_cache(state) : S.Cache}:
  match evidence:
    case Tuple{same,retained}:
      column_failure_transport(Laws.state_cache(state),Column.sample(state,request,budget,depth),actual,message,same,retained(message))(failed)

def column_failed_result(-state:S.State,-request:O.ColumnRequest,-budget:U32,-depth:Nat,message:String,
    result:ColumnTransactionWitness(Laws.state_cache(state),Column.sample(state,request,budget,depth)),
    failed:{Laws.column_failure(Column.sample(state,request,budget,depth)) == Some{message} : Maybe<&2,String>}) ->
    {Laws.column_cache(Column.sample(state,request,budget,depth)) == Laws.state_cache(state) : S.Cache}:
  match result:
    case Tuple{actual,evidence}: column_failed_pair(state,request,budget,depth,message,actual,evidence,failed)

def Laws.refused_density_column_restores_complete_original_cache(state,request,budget,depth,message,failed):
  column_failed_result(state,request,budget,depth,message,column_cache_owned(state,request,budget,depth),failed)

def column_invalid(state:S.State,request:O.ColumnRequest,depth:Nat) ->
    {Column.admitted(state,request,depth,False{}) ==
      (state,Fail{"column density request exceeds signed-coordinate or sample budget"}) : S.State & Result<&2,&2,String,Column.Column>}:
  match state request:
    case S.State{A.Program{plan,registry,expression,nodes,index},pool,cache} O.ColumnRequest{x,z,bottom,step,count}: {==}

def Laws.invalid_density_column_request_retains_complete_original_state(state,request,budget,depth,invalid):
  %Equal.sym(Bool,O.request_valid(request,budget),False{},invalid) :
    {Column.admitted(state,request,depth,_) ==
      (state,Fail{"column density request exceeds signed-coordinate or sample budget"}) : S.State & Result<&2,&2,String,Column.Column>}
  column_invalid(state,request,depth)

def Laws.zero_count_column_retains_state_and_original_value_order(state,depth,index,expression,x,z,bottom,step,y,values): {==}
