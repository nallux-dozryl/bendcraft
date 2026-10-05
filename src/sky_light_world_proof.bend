import Base
import ./sky_light_world.bend as W
import ./sky_light.bend as S
import ./block_light.bend as B
import ./block_light_world.bend as BW
import ./block_light_registry.bend as R
import ./core.bend as C
import ./section_map.bend as M
import ./section.bend as Section
import ./schedule.bend as Q
import ./sky_light_world_laws.bend as L

def keys_entry_owned(+key:String,-section:Section.Section,-rest:List<&1,M.Entry>,
    result:Exists(List<&2,String>,keys => {BW.keys_entries(rest) == (rest,keys) : List<&1,M.Entry> & List<&2,String>})) ->
    Exists(List<&2,String>,keys => {BW.keys_entries(M.Entry{key,section} <> rest) == (M.Entry{key,section} <> rest,keys) : List<&1,M.Entry> & List<&2,String>}):
  match result:
    case Tuple{+keys,evidence}:
      (key <> keys,
        (%Equal.sym(List<&1,M.Entry> & List<&2,String>,BW.keys_entries(rest),(rest,keys),evidence) :
          {BW.keys_entry(key,section,_) == (M.Entry{key,section} <> rest,key <> keys) : List<&1,M.Entry> & List<&2,String>}
        {==}))

def keys_entries_owned(entries:List<&1,M.Entry>) ->
    Exists(List<&2,String>,keys => {BW.keys_entries(entries) == (entries,keys) : List<&1,M.Entry> & List<&2,String>}):
  match entries:
    case Nil{}: ([],{==})
    case M.Entry{key,section} <> rest: keys_entry_owned(key,section,rest,keys_entries_owned(rest))

def keys_bucket_owned(-entries:List<&1,M.Entry>,
    result:Exists(List<&2,String>,keys => {BW.keys_entries(entries) == (entries,keys) : List<&1,M.Entry> & List<&2,String>})) ->
    Exists(List<&2,String>,keys => {BW.section_keys(M.Bucket{entries}) == (M.Bucket{entries},keys) : M.Sections & List<&2,String>}):
  match result:
    case Tuple{+keys,evidence}:
      (keys,
        (%Equal.sym(List<&1,M.Entry> & List<&2,String>,BW.keys_entries(entries),(entries,keys),evidence) :
          {BW.keys_leaf(_) == (M.Bucket{entries},keys) : M.Sections & List<&2,String>}
        {==}))

def keys_branch_owned(-lo:M.Sections,-hi:M.Sections,
    left:Exists(List<&2,String>,keys => {BW.section_keys(lo) == (lo,keys) : M.Sections & List<&2,String>}),
    right:Exists(List<&2,String>,keys => {BW.section_keys(hi) == (hi,keys) : M.Sections & List<&2,String>})) ->
    Exists(List<&2,String>,keys => {BW.section_keys(M.Branch{lo,hi}) == (M.Branch{lo,hi},keys) : M.Sections & List<&2,String>}):
  match left right:
    case Tuple{+a,left_ok} Tuple{+b,right_ok}:
      (List.append(&2,String,a,b),
        (%Equal.sym(M.Sections & List<&2,String>,BW.section_keys(lo),(lo,a),left_ok) :
          {BW.keys_branch(_,BW.section_keys(hi)) == (M.Branch{lo,hi},List.append(&2,String,a,b)) : M.Sections & List<&2,String>}
        %Equal.sym(M.Sections & List<&2,String>,BW.section_keys(hi),(hi,b),right_ok) :
          {BW.keys_branch((lo,a),_) == (M.Branch{lo,hi},List.append(&2,String,a,b)) : M.Sections & List<&2,String>}
        {==}))

def L.enumeration_returns_exact_affine_section_owner(sections):
  match sections:
    case M.EmptySections{}: ([],{==})
    case M.Bucket{entries}: keys_bucket_owned(entries,keys_entries_owned(entries))
    case M.Branch{lo,hi}: keys_branch_owned(lo,hi,
      L.enumeration_returns_exact_affine_section_owner(lo),L.enumeration_returns_exact_affine_section_owner(hi))

def begin_owned(-tick:Nat,-time:Nat,-paused:Bool,-daylight:Bool,-revision:Nat,-count:U32,
    -sections:M.Sections,-pending:List<&2,Q.Pending<C.Mutation>>,-events:List<&2,C.CoreEvent>,
    result:Exists(List<&2,String>,keys => {BW.section_keys(sections) == (sections,keys) : M.Sections & List<&2,String>})) ->
    Exists(List<&2,String>,keys => {
      W.begin(C.World{tick,time,paused,daylight,revision,count,sections,pending,events}) ==
      (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},
        W.State{S.new(),W.Enumerate{keys},[],[],[],None{}}) : C.World & W.State}):
  match result:
    case Tuple{+keys,evidence}:
      (keys,
        (%Equal.sym(M.Sections & List<&2,String>,BW.section_keys(sections),(sections,keys),evidence) :
          {W.begin_keys(C.World{tick,time,paused,daylight,revision,count,M.EmptySections{},pending,events},_) ==
            (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},
              W.State{S.new(),W.Enumerate{keys},[],[],[],None{}}) : C.World & W.State}
        {==}))

def L.begin_returns_complete_original_core_and_fresh_sidecar(world):
  match world:
    case C.World{tick,time,paused,daylight,revision,count,sections,pending,events}:
      begin_owned(tick,time,paused,daylight,revision,count,sections,pending,events,
        L.enumeration_returns_exact_affine_section_owner(sections))

def L.zero_load_budget_preserves_both_complete_owners(catalog,world,state): {==}
def L.ready_load_preserves_both_owners_for_any_budget(catalog,budget,world,light,chunks,domains,repairs,revision):
  match budget:
    case 0n: {==}
    case 1n+rest: {==}

def L.bootstrap_advance_preserves_complete_sidecar(catalog,budget,light,phase,chunks,domains,repairs,revision,not_ready):
  match phase:
    case W.Enumerate{keys}: {==}
    case W.Loading{todo,active}: {==}
    case W.Sources{todo,active,fresh}: {==}
    case W.Seeding{todo,index}: {==}
    case W.Republishing{todo,active}: {==}
    case W.Injecting{todo,active}: {==}
    case W.Ready{}:
      Empty.absurd({W.advance(~R.Catalog,~R.occludes,catalog,budget,W.State{light,W.Ready{},chunks,domains,repairs,revision}) ==
        (W.State{light,W.Ready{},chunks,domains,repairs,revision},W.Bootstrap{}) : W.State & W.Progress},not_ready({==}))

def L.bootstrap_sampling_preserves_both_complete_owners(positions,world,light,phase,chunks,domains,repairs,revision,not_ready):
  match phase:
    case W.Enumerate{keys}: {==}
    case W.Loading{todo,active}: {==}
    case W.Sources{todo,active,fresh}: {==}
    case W.Seeding{todo,index}: {==}
    case W.Republishing{todo,active}: {==}
    case W.Injecting{todo,active}: {==}
    case W.Ready{}:
      Empty.absurd({W.sample_batch(positions,world,W.State{light,W.Ready{},chunks,domains,repairs,revision}) ==
        (world,(W.State{light,W.Ready{},chunks,domains,repairs,revision},Fail{W.LoadingInProgress{}})) :
        C.World & (W.State & Result<&2,&2,W.Error,W.FrameSamples>)},not_ready({==}))

def L.bootstrap_refresh_preserves_both_complete_owners(catalog,position,world,light,phase,chunks,domains,repairs,revision,not_ready):
  match phase:
    case W.Enumerate{keys}: {==}
    case W.Loading{todo,active}: {==}
    case W.Sources{todo,active,fresh}: {==}
    case W.Seeding{todo,index}: {==}
    case W.Republishing{todo,active}: {==}
    case W.Injecting{todo,active}: {==}
    case W.Ready{}:
      Empty.absurd({W.refresh_block(~R.Catalog,~R.properties,catalog,position,world,W.State{light,W.Ready{},chunks,domains,repairs,revision}) ==
        (world,(W.State{light,W.Ready{},chunks,domains,repairs,revision},Fail{W.LoadingInProgress{}})) :
        C.World & (W.State & Result<&2,&2,W.Error,Unit>)},not_ready({==}))

def L.missing_revision_sampling_preserves_both_complete_owners(positions,world,light,chunks,domains,repairs):
  match world:
    case C.World{tick,time,paused,daylight,current,count,sections,pending,events}: {==}

def L.stale_revision_sampling_preserves_both_complete_owners(positions,tick,time,paused,daylight,current,count,sections,pending,events,light,chunks,domains,repairs,saved,stale):
  %Equal.sym(Bool,Nat.is_eq(saved,current),False{},stale) :
    {W.sample_revision(positions,C.World{tick,time,paused,daylight,current,count,sections,pending,events},
        W.State{light,W.Ready{},chunks,domains,repairs,Some{saved}},
        C.Clock{tick,time,paused,daylight,current,Q.length(C.Mutation,pending)},_) ==
      (C.World{tick,time,paused,daylight,current,count,sections,pending,events},
        (W.State{light,W.Ready{},chunks,domains,repairs,Some{saved}},Fail{W.StaleRevision{}})) :
      C.World & (W.State & Result<&2,&2,W.Error,W.FrameSamples>)}
  {==}

def L.pending_light_sampling_preserves_both_complete_owners(positions,tick,time,paused,daylight,current,count,sections,pending,events,cells,front,back,queued,remaining,columns,chunks,domains,repairs,saved,admitted):
  %Equal.sym(Bool,Nat.is_eq(saved,current),True{},admitted) :
    {W.sample_revision(positions,C.World{tick,time,paused,daylight,current,count,sections,pending,events},
        W.State{S.State{B.State{cells,front,back,queued,1n+remaining},columns},W.Ready{},chunks,domains,repairs,Some{saved}},
        C.Clock{tick,time,paused,daylight,current,Q.length(C.Mutation,pending)},_) ==
      (C.World{tick,time,paused,daylight,current,count,sections,pending,events},
        (W.State{S.State{B.State{cells,front,back,queued,1n+remaining},columns},W.Ready{},chunks,domains,repairs,Some{saved}},
          Fail{W.LightPending{1n+remaining}})) : C.World & (W.State & Result<&2,&2,W.Error,W.FrameSamples>)}
  {==}

def L.core_read_failure_refresh_preserves_entire_sidecar(catalog,position,world,returned,light,chunks,domains,repairs,revision,error,failed):
  %Equal.sym(C.World & Result<&2,&2,C.Error,U32>,C.read_block(world,position),(returned,Fail{error}),failed) :
    {W.refresh_read(~R.Catalog,~R.properties,catalog,W.State{light,W.Ready{},chunks,domains,repairs,revision},position,_) ==
      (returned,(W.State{light,W.Ready{},chunks,domains,repairs,revision},Fail{W.CoreFailure{error}})) :
      C.World & (W.State & Result<&2,&2,W.Error,Unit>)}
  {==}

def L.descriptor_failure_refresh_preserves_both_complete_owners(world,state,position,error,chunk):
  match state chunk:
    case W.State{light,phase,chunks,domains,repairs,revision} None{}: {==}
    case W.State{light,phase,chunks,domains,repairs,revision} Some{found}: {==}
def L.missing_chunk_refresh_preserves_both_complete_owners(world,state,position,descriptor):
  match state:
    case W.State{light,phase,chunks,domains,repairs,revision}: {==}
def L.unknown_section_cannot_fabricate_empty_loaded_cells(world,light,position,todo,chunks,domains,repairs,revision,chunk):
  match chunk:
    case None{}: {==}
    case Some{found}: {==}
def L.missing_scan_cell_preserves_complete_sidecar(catalog,light,todo,fresh,position,minimum,height,remaining,above,enabled,chunks,domains,repairs,revision): {==}
def L.blocked_source_scan_retains_complete_stored_light_field(field,columns,phase,chunks,domains,repairs,revision,todo,fresh,dimension,x,y,z,minimum,height,remaining,above,enabled,below): {==}
def L.enabled_refresh_schedules_column_repair_and_invalidates_revision(world,ignored,light,phase,chunks,domains,repairs,revision,top): {==}
def L.deferred_source_completion_republishes_before_ready(catalog,world,light,chunks,domains,repairs,revision): {==}
def L.completed_republication_returns_core_and_accepts_current_revision(tick,time,paused,daylight,current,count,sections,pending,events,light,chunks,domains,repairs,revision): {==}
def L.absent_core_section_remains_unknown_in_observation(position,key,level):
  match level:
    case None{}: {==}
    case Some{value}: {==}
def L.known_core_cell_without_sky_cell_is_residency_failure(position,id): {==}
def L.refused_core_mutation_does_not_publish_sky_work(catalog,mutation,state,world,error): {==}

def disabled_columns_read_owned(-field:B.State,+position:C.Position,-rest:List<&2,C.Position>,
    read:Map<&2,Maybe<&2,S.Column>> & Maybe<&2,S.Column>,
    induction:(@columns:Map<&2,Maybe<&2,S.Column>> ->
      {L.stored_field(W.columns_enabled(rest,False{},S.State{field,columns})) == field : B.State})) ->
    {L.stored_field(B.paired(S.State,Maybe<&2,S.Column>,S.State,
      S.column_read(S.State{field,MTip{}},read),light => found =>
        W.columns_enabled(rest,False{},W.column_enabled(light,position,False{},found)))) == field : B.State}:
  match read:
    case Tuple{columns,None{}}: induction(columns)
    case Tuple{columns,Some{S.Column{lowest,enabled,minimum,height}}}:
      induction(Map.set(&2,Maybe<&2,S.Column>,columns,S.column_key(position),Some{S.Column{lowest,False{},minimum,height}}))

def L.disabling_columns_retains_complete_stored_field(positions,field,columns):
  match positions:
    case Nil{}: {==}
    case +position <> rest:
      disabled_columns_read_owned(field,position,rest,
        Map.get(Maybe<&2,S.Column>,None{},columns,S.column_key(position)),
        columns => L.disabling_columns_retains_complete_stored_field(rest,field,columns))

def L.disabling_chunk_retains_complete_stored_field(field,columns,phase,chunks,domains,repairs,revision,position,found):
  match found:
    case None{}: {==}
    case Some{W.Chunk{origin,bounds,enabled}}:
      match bounds:
        case W.Bounds{minimum,height,air,sky}:
          L.disabling_columns_retains_complete_stored_field(
            W.chunk_columns(W.Chunk{origin,W.Bounds{minimum,height,air,sky},enabled}),field,columns)

def L.actual_disabling_retains_complete_stored_field(field,columns,phase,chunks,domains,repairs,revision,position):
  match phase:
    case W.Ready{}:
      L.disabling_chunk_retains_complete_stored_field(field,columns,W.Ready{},chunks,domains,repairs,revision,
        position,W.find_chunk(position,chunks))
    case W.Enumerate{keys}: {==}
    case W.Loading{todo,active}: {==}
    case W.Sources{todo,active,fresh}: {==}
    case W.Seeding{todo,index}: {==}
    case W.Republishing{todo,active}: {==}
    case W.Injecting{todo,active}: {==}

def L.source_propagation_chunk_starts_injection_with_retained_light_owner(light,phase,chunks,domains,repairs,revision,position,chunk): {==}
