import Base
import ./local_player_cooking_incarnation_guard_laws.bend as Laws
import ./local_player_cooking_incarnation_guard.bend as G
import ./core.bend as C
import ./section_map.bend as M
import ./section_map_update.bend as U
import ./cooking_world_bindings.bend as B
import ./cooking_world.bend as CW
import ./block_light_world.bend as W
import ./section.bend as Section

def Laws.prospective_left_owner(hi,result):
  match result:
    case (lo,status): {==}

def Laws.prospective_right_owner(lo,result):
  match result:
    case (hi,status): {==}

def bucket_owner(result:List<&1,M.Entry> & Bool) -> List<&1,M.Entry>:
  (entries,present) = result
  entries
def BucketWitness(-entries:List<&1,M.Entry>,-key:String) -> Type:
  Exists(List<&1,M.Entry> & Bool,actual =>
    {U.contains(entries,key) == actual : List<&1,M.Entry> & Bool} &
    {bucket_owner(actual) == entries : List<&1,M.Entry>})
def bucket_pair(+candidate:String,section:Section.Section,-tail:List<&1,M.Entry>,+key:String,
    actual:List<&1,M.Entry> & Bool,
    evidence:{U.contains(tail,key) == actual : List<&1,M.Entry> & Bool} &
      {bucket_owner(actual) == tail : List<&1,M.Entry>}) -> BucketWitness(M.Entry{candidate,section} <> tail,key):
  match actual evidence:
    case Tuple{rest,+present} Tuple{exact,retained}:
      ((M.Entry{candidate,section} <> rest,String.eq(candidate,key) || present),
        ((%Equal.sym(List<&1,M.Entry> & Bool,U.contains(tail,key),(rest,present),exact) :
          {U.presence_head(M.Entry{candidate,section},String.eq(candidate,key),_) ==
            (M.Entry{candidate,section} <> rest,String.eq(candidate,key) || present) : List<&1,M.Entry> & Bool}
        {==}),
        (%Equal.sym(List<&1,M.Entry>,rest,tail,retained) :
          {M.Entry{candidate,section} <> _ == M.Entry{candidate,section} <> tail : List<&1,M.Entry>}
        {==})))
def bucket_returned(candidate:String,section:Section.Section,-tail:List<&1,M.Entry>,key:String,
    result:BucketWitness(tail,key)) -> BucketWitness(M.Entry{candidate,section} <> tail,key):
  match result:
    case (actual,evidence): bucket_pair(candidate,section,tail,key,actual,evidence)
def bucket_witness(entries:List<&1,M.Entry>,+key:String) -> BucketWitness(entries,key):
  match entries:
    case Nil{}: (([],False{}),({==},{==}))
    case M.Entry{candidate,section} <> tail: bucket_returned(candidate,section,tail,key,bucket_witness(tail,key))

def RouteWitness(-route:List<&2,Bool>,-owner:M.Sections,-key:String,-creating:Bool) -> Type:
  Exists(M.Sections & Result<&2,&2,C.Error,Unit>,actual =>
    {C.prospective_route(route,owner,key,creating) == actual : M.Sections & Result<&2,&2,C.Error,Unit>} &
    {Laws.sections(actual) == owner : M.Sections})
def route_bucket_pair(-original:List<&1,M.Entry>,+key:String,+creating:Bool,
    actual:List<&1,M.Entry> & Bool,
    evidence:{U.contains(original,key) == actual : List<&1,M.Entry> & Bool} &
      {bucket_owner(actual) == original : List<&1,M.Entry>}) -> RouteWitness([],M.Bucket{original},key,creating):
  match actual evidence:
    case Tuple{entries,+present} Tuple{exact,retained}:
      ((M.Bucket{entries},C.prospective_present(creating,key,present)),
        ((%Equal.sym(List<&1,M.Entry> & Bool,U.contains(original,key),(entries,present),exact) :
          {C.prospective_bucket(creating,key,_) == (M.Bucket{entries},C.prospective_present(creating,key,present)) :
            M.Sections & Result<&2,&2,C.Error,Unit>}
        {==}),
        (%Equal.sym(List<&1,M.Entry>,entries,original,retained) :
          {M.Bucket{_} == M.Bucket{original} : M.Sections}
        {==})))
def route_bucket(-original:List<&1,M.Entry>,key:String,creating:Bool,result:BucketWitness(original,key)) ->
    RouteWitness([],M.Bucket{original},key,creating):
  match result:
    case (actual,evidence): route_bucket_pair(original,key,creating,actual,evidence)
def left_pair(-route:List<&2,Bool>,-original:M.Sections,hi:M.Sections,-key:String,-creating:Bool,
    actual:M.Sections & Result<&2,&2,C.Error,Unit>,
    evidence:{C.prospective_route(route,original,key,creating) == actual : M.Sections & Result<&2,&2,C.Error,Unit>} &
      {Laws.sections(actual) == original : M.Sections}) -> RouteWitness(False{} <> route,M.Branch{original,hi},key,creating):
  match actual evidence:
    case Tuple{lo,+status} Tuple{exact,retained}:
      ((M.Branch{lo,hi},status),
        ((%Equal.sym(M.Sections & Result<&2,&2,C.Error,Unit>,C.prospective_route(route,original,key,creating),(lo,status),exact) :
          {C.prospective_left(hi,_) == (M.Branch{lo,hi},status) : M.Sections & Result<&2,&2,C.Error,Unit>}
        {==}),
        (%Equal.sym(M.Sections,lo,original,retained) :
          {M.Branch{_,hi} == M.Branch{original,hi} : M.Sections}
        {==})))
def left_returned(-route:List<&2,Bool>,-original:M.Sections,hi:M.Sections,-key:String,-creating:Bool,
    result:RouteWitness(route,original,key,creating)) -> RouteWitness(False{} <> route,M.Branch{original,hi},key,creating):
  match result:
    case (actual,evidence): left_pair(route,original,hi,key,creating,actual,evidence)
def right_pair(-route:List<&2,Bool>,lo:M.Sections,-original:M.Sections,-key:String,-creating:Bool,
    actual:M.Sections & Result<&2,&2,C.Error,Unit>,
    evidence:{C.prospective_route(route,original,key,creating) == actual : M.Sections & Result<&2,&2,C.Error,Unit>} &
      {Laws.sections(actual) == original : M.Sections}) -> RouteWitness(True{} <> route,M.Branch{lo,original},key,creating):
  match actual evidence:
    case Tuple{hi,+status} Tuple{exact,retained}:
      ((M.Branch{lo,hi},status),
        ((%Equal.sym(M.Sections & Result<&2,&2,C.Error,Unit>,C.prospective_route(route,original,key,creating),(hi,status),exact) :
          {C.prospective_right(lo,_) == (M.Branch{lo,hi},status) : M.Sections & Result<&2,&2,C.Error,Unit>}
        {==}),
        (%Equal.sym(M.Sections,hi,original,retained) :
          {M.Branch{lo,_} == M.Branch{lo,original} : M.Sections}
        {==})))
def right_returned(-route:List<&2,Bool>,lo:M.Sections,-original:M.Sections,-key:String,-creating:Bool,
    result:RouteWitness(route,original,key,creating)) -> RouteWitness(True{} <> route,M.Branch{lo,original},key,creating):
  match result:
    case (actual,evidence): right_pair(route,lo,original,key,creating,actual,evidence)
def route_witness(route:List<&2,Bool>,owner:M.Sections,+key:String,+creating:Bool) -> RouteWitness(route,owner,key,creating):
  match route owner:
    case Nil{} M.Bucket{entries}: route_bucket(entries,key,creating,bucket_witness(entries,key))
    case False{} <> rest M.Branch{lo,hi}: left_returned(rest,lo,hi,key,creating,route_witness(rest,lo,key,creating))
    case True{} <> rest M.Branch{lo,hi}: right_returned(rest,lo,hi,key,creating,route_witness(rest,hi,key,creating))
    case Nil{} M.EmptySections{}: ((M.EmptySections{},C.prospective_present(creating,key,False{})),({==},{==}))
    case Nil{} M.Branch{lo,hi}: ((M.Branch{lo,hi},C.prospective_malformed(creating,key)),({==},{==}))
    case False{} <> rest M.EmptySections{}: ((M.EmptySections{},C.prospective_present(creating,key,False{})),({==},{==}))
    case True{} <> rest M.EmptySections{}: ((M.EmptySections{},C.prospective_present(creating,key,False{})),({==},{==}))
    case False{} <> rest M.Bucket{entries}: ((M.Bucket{entries},C.prospective_malformed(creating,key)),({==},{==}))
    case True{} <> rest M.Bucket{entries}: ((M.Bucket{entries},C.prospective_malformed(creating,key)),({==},{==}))
def route_project_pair(-route:List<&2,Bool>,-owner:M.Sections,-key:String,-creating:Bool,
    actual:M.Sections & Result<&2,&2,C.Error,Unit>,
    evidence:{C.prospective_route(route,owner,key,creating) == actual : M.Sections & Result<&2,&2,C.Error,Unit>} &
      {Laws.sections(actual) == owner : M.Sections}) ->
    {Laws.sections(C.prospective_route(route,owner,key,creating)) == owner : M.Sections}:
  match evidence:
    case (exact,retained):
      %Equal.sym(M.Sections & Result<&2,&2,C.Error,Unit>,C.prospective_route(route,owner,key,creating),actual,exact) :
        {Laws.sections(_) == owner : M.Sections}
      retained
def route_project(-route:List<&2,Bool>,-owner:M.Sections,-key:String,-creating:Bool,result:RouteWitness(route,owner,key,creating)) ->
    {Laws.sections(C.prospective_route(route,owner,key,creating)) == owner : M.Sections}:
  match result:
    case (actual,evidence): route_project_pair(route,owner,key,creating,actual,evidence)
def Laws.every_actual_admission_path_retains_complete_trie(route,owner,key,creating):
  route_project(route,owner,key,creating,route_witness(route,owner,key,creating))

def Laws.created_key_overlay_retains_complete_world(world,key,creating): {==}
def Laws.rejected_application_cannot_advance_lifecycle_scan(operation,scan,error):
  match scan:
    case G.Scan{values,incarnations,skip}: {==}

def Laws.same_block_change_has_no_owner_reset(candidate,previous,position,next,rest,same):
  %Equal.sym(Bool,B.same_block(previous,next),True{},same) :
    {G.changed(_,candidate,position,B.Cooking{next},rest) ==
      G.Change{G.Header{candidate,next} <> rest,None{}} : G.Change}
  {==}

def Laws.exhaustion_branch_refuses_before_increment(key,values,incarnations,current): {==}
def Laws.acknowledged_reset_preserves_counter_map(remaining,position,values,incarnations): {==}
def Laws.refused_scan_cancels_all_later_due_admission(operations,statuses,message):
  match operations statuses:
    case Nil{} Nil{}: {==}
    case Nil{} status <> tail: {==}
    case operation <> rest Nil{}: {==}
    case operation <> rest status <> tail: {==}
def Laws.guard_refusal_retains_complete_cooking_world(views,light,loading,entries,phase,keys,future,ops,world,text): {==}

def Laws.prepared_guard_failure_precedes_all_clock_and_due_publication(views,future,ops,incarnations,acknowledged,world,light,loading,entries,phase,keys,text,refused):
  %Equal.sym(C.World & Result<&2,&2,String,Unit>,G.check(world,views,CW.incarnation_operations(ops),incarnations,acknowledged),
    (world,Fail{text}),refused) :
    {CW.owned_guarded(views,light,loading,entries,phase,keys,future,ops,_) ==
      (CW.State{W.State{world,light,loading},entries,phase,keys},Fail{CW.Authority{text}}) :
      CW.State & Result<&2,&2,CW.Error,Unit>}
  {==}
