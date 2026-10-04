import Base
import ./superflat_world_laws.bend as Laws
import ./superflat_world.bend as SF
import ./superflat_population.bend as P
import ./superflat_player.bend as Player
import ./world_generation_settings.bend as WG
import ./client_world.bend as W
import ./game.bend as G
import ./core.bend as C
import ./schedule.bend as Q
import ./section_map.bend as SM
import ./section.bend as Section
import ./local_phase_runtime.bend as X
import ./local_move_history.bend as MH
import ./section_proof.bend as SectionProof
import ./section_laws.bend as SectionLaws
import ./registry.bend as B
import ./superflat_resolver.bend as Resolver
import ./locomotion.bend as Motion
import ./support.bend as Support
import ./local_move_world.bend as Move
import ./player_fall_history.bend as Fall

def attached_view(-engine:G.Engine,view:W.View) ->
    {Laws.owned_view(W.attach(engine,view)) == view : W.View}:
  match view:
    case W.View{body,yaw,pitch,palette,region,cache}: {==}

def populated_view(view:W.View,-registry:B.Registry,result:C.World & Result<&2,&2,String,P.Receipt>) ->
    {Laws.demand_view(SF.demand_populated(view,registry,result)) == view : W.View}:
  match result:
    case Tuple{world,status}: attached_view(G.Engine{world,registry},view)

def resolved_view(world:C.World,view:W.View,+region:P.Region,+budget:P.Budget,+stamp:Q.Stamp,
    result:B.Registry & Result<&2,&2,String,P.Flat>) ->
    {Laws.demand_view(SF.demand_resolved(world,view,region,budget,stamp,result)) == view : W.View}:
  match result:
    case Tuple{registry,Fail{message}}: attached_view(G.Engine{world,registry},view)
    case Tuple{registry,Done{flat}}: populated_view(view,registry,P.populate(flat,region,stamp,budget,world))

def rectangle_view(+settings:WG.Settings,+budget:P.Budget,+stamp:Q.Stamp,engine:G.Engine,view:W.View,
    result:Result<&2,&2,String,P.Region>) ->
    {Laws.demand_view(SF.demand_rectangle(settings,budget,stamp,engine,view,result)) == view : W.View}:
  match engine result:
    case G.Engine{world,registry} Fail{message}: attached_view(G.Engine{world,registry},view)
    case G.Engine{world,registry} Done{region}:
      resolved_view(world,view,region,budget,stamp,Resolver.resolve(registry,settings))

def planned_view(state:W.State,+settings:WG.Settings,+budget:P.Budget,+stamp:Q.Stamp,
    result:Result<&2,&2,String,W.Bounds>) ->
    {Laws.demand_view(SF.demand_planned(state,settings,budget,stamp,result)) == Laws.owned_view(state) : W.View}:
  match state result:
    case W.State{engine,body,yaw,pitch,palette,region,cache} Fail{message}: {==}
    case W.State{engine,body,yaw,pitch,palette,region,cache} Done{bounds}:
      rectangle_view(settings,budget,stamp,engine,W.View{body,yaw,pitch,palette,region,cache},SF.demand_region(settings,bounds))

def supported_view(state:W.State,+settings:WG.Settings,+policy:SF.ViewPolicy,+budget:P.Budget,+stamp:Q.Stamp,supported:Bool) ->
    {Laws.demand_view(SF.demand_supported(state,settings,policy,budget,stamp,supported)) == Laws.owned_view(state) : W.View}:
  match state supported:
    case W.State{engine,body,yaw,pitch,palette,region,cache} False{}: {==}
    case W.State{engine,+body,yaw,pitch,palette,region,cache} True{}:
      planned_view(W.State{engine,body,yaw,pitch,palette,region,cache},settings,budget,stamp,SF.production_region(policy,body))

def Laws.demand_preserves_complete_view(state,settings,policy,budget,stamp):
  supported_view(state,settings,policy,budget,stamp,WG.base_only(settings))

def Laws.existing_world_retains_owned_state(engine,view,profile):
  match engine:
    case G.Engine{world,registry}: {==}

def Laws.loaded_world_retains_all_fields(state,settings,policy,budget,stamp):
  {==}

def Laws.loaded_player_retains_all_owners(player,settings):
  match player:
    case X.State{MH.State{world,support,minor,history,motion_tail},tables,metadata,tail}: {==}

def stable_query_projection(-tables:Motion.Tables,-metadata:X.Metadata,-tail:List<&1,X.State>,-support:Support.State,
    -minor:Move.MinorState,-history:Fall.State,-motion_tail:List<&1,MH.State>,result:W.State & Result<&2,&2,String,Unit>) ->
    {Laws.stable_after(X.query_finished(Result<&2,&2,String,Unit>,tables,metadata,tail,support,minor,history,motion_tail,result)) ==
      Laws.StablePlayer{tables,support,minor,history,metadata,motion_tail,tail} : Laws.StablePlayer}:
  match result:
    case Tuple{world,status}: {==}

def supported_local_owners(player:X.State,+settings:WG.Settings,supported:Bool) ->
    {Laws.stable_after(Player.ensure_supported(settings,player,supported)) == Laws.stable_player(player) : Laws.StablePlayer}:
  match player supported:
    case X.State{MH.State{world,support,minor,history,motion_tail},tables,metadata,tail} False{}: {==}
    case X.State{MH.State{world,support,minor,history,motion_tail},tables,metadata,tail} True{}:
      stable_query_projection(tables,metadata,tail,support,minor,history,motion_tail,
        SF.ensure_current(world,settings,SF.default_view_policy(),P.default_budget()))

def Laws.demand_retains_local_player_owners(player,settings):
  supported_local_owners(player,settings,Player.supported_dimension(settings))

def Laws.unsupported_dimension_retains_complete_player(player,settings,unsupported):
  %Equal.sym(Bool,Player.supported_dimension(settings),False{},unsupported) :
    {Player.ensure_supported(settings,player,_) == (player,Fail{"player world adapter only supports minecraft:overworld"}) : X.State & Result<&2,&2,String,Unit>}
  {==}

def Laws.unsupported_fresh_dimension_retains_complete_player(player,settings,unsupported):
  %Equal.sym(Bool,Player.supported_dimension(settings),False{},unsupported) :
    {Player.initialize_supported(settings,player,_) == (player,Fail{"player world adapter only supports minecraft:overworld"}) : X.State & Result<&2,&2,String,Unit>}
  {==}

def Laws.wrapped_flat_spawn_is_refused():
  {==}

def Laws.configuration_error_preserves_entire_state(state,message):
  match state:
    case W.State{engine,body,yaw,pitch,palette,region,cache}: {==}

def Laws.same_configuration_preserves_entire_state(state,actual):
  match state:
    case W.State{engine,body,yaw,pitch,palette,region,cache}: {==}

def Laws.follow_composition(state,actual):
  match state:
    case W.State{engine,body,yaw,pitch,palette,region,cache}: {==}

# The witness pairs the found flag with equality of the whole returned pair.
# Induction consumes each owner once; every value used only in an equation is
# erased. The public laws then project this evidence to exact owner identity.
def entries_owned_step(-head:SM.Entry,-rest:List<&1,SM.Entry>,-key:String,+hit:Bool,
    result:Exists(Bool,b => {P.present_entries(rest,key) == (rest,b) : List<&1,SM.Entry> & Bool})) ->
    Exists(Bool,b => {P.entries_keep(head,hit,P.present_entries(rest,key)) == (head <> rest,b) : List<&1,SM.Entry> & Bool}):
  match result:
    case Tuple{+found,evidence}:
      (hit || found,
        (%Equal.sym(List<&1,SM.Entry> & Bool,P.present_entries(rest,key),(rest,found),evidence) :
          {P.entries_keep(head,hit,_) == (head <> rest,hit || found) : List<&1,SM.Entry> & Bool}
        {==}))

def entries_owned(entries:List<&1,SM.Entry>,+key:String) ->
    Exists(Bool,b => {P.present_entries(entries,key) == (entries,b) : List<&1,SM.Entry> & Bool}):
  match entries:
    case Nil{}: (False{},{==})
    case SM.Entry{+candidate,section} <> rest:
      entries_owned_step(SM.Entry{candidate,section},rest,key,String.eq(candidate,key),entries_owned(rest,key))

def entries_project_owned(-entries:List<&1,SM.Entry>,-key:String,
    result:Exists(Bool,b => {P.present_entries(entries,key) == (entries,b) : List<&1,SM.Entry> & Bool})) ->
    {Laws.retained_entries(P.present_entries(entries,key)) == entries : List<&1,SM.Entry>}:
  match result:
    case Tuple{found,evidence}:
      %Equal.sym(List<&1,SM.Entry> & Bool,P.present_entries(entries,key),(entries,found),evidence) :
        {Laws.retained_entries(_) == entries : List<&1,SM.Entry>}
      {==}

def Laws.present_entries_preserves_owner(entries,key):
  entries_project_owned(entries,key,entries_owned(entries,key))

def bucket_owned(-entries:List<&1,SM.Entry>,-key:String,
    result:Exists(Bool,b => {P.present_entries(entries,key) == (entries,b) : List<&1,SM.Entry> & Bool})) ->
    Exists(Bool,b => {P.present_bucket(P.present_entries(entries,key)) == (SM.Bucket{entries},b) : SM.Sections & Bool}):
  match result:
    case Tuple{found,evidence}:
      (found,
        (%Equal.sym(List<&1,SM.Entry> & Bool,P.present_entries(entries,key),(entries,found),evidence) :
          {P.present_bucket(_) == (SM.Bucket{entries},found) : SM.Sections & Bool}
        {==}))

def lo_owned(-depth:Nat,-lo:SM.Sections,-hi:SM.Sections,-bits:U32,-key:String,
    result:Exists(Bool,b => {P.present_go(depth,lo,bits,key) == (lo,b) : SM.Sections & Bool})) ->
    Exists(Bool,b => {P.present_lo(hi,P.present_go(depth,lo,bits,key)) == (SM.Branch{lo,hi},b) : SM.Sections & Bool}):
  match result:
    case Tuple{found,evidence}:
      (found,
        (%Equal.sym(SM.Sections & Bool,P.present_go(depth,lo,bits,key),(lo,found),evidence) :
          {P.present_lo(hi,_) == (SM.Branch{lo,hi},found) : SM.Sections & Bool}
        {==}))

def hi_owned(-depth:Nat,-lo:SM.Sections,-hi:SM.Sections,-bits:U32,-key:String,
    result:Exists(Bool,b => {P.present_go(depth,hi,bits,key) == (hi,b) : SM.Sections & Bool})) ->
    Exists(Bool,b => {P.present_hi(lo,P.present_go(depth,hi,bits,key)) == (SM.Branch{lo,hi},b) : SM.Sections & Bool}):
  match result:
    case Tuple{found,evidence}:
      (found,
        (%Equal.sym(SM.Sections & Bool,P.present_go(depth,hi,bits,key),(hi,found),evidence) :
          {P.present_hi(lo,_) == (SM.Branch{lo,hi},found) : SM.Sections & Bool}
        {==}))

def branch_owned(-depth:Nat,lo:SM.Sections,hi:SM.Sections,-bits:U32,-key:String,low:Bool,
    left:(@l:SM.Sections -> Exists(Bool,b => {P.present_go(depth,l,bits,key) == (l,b) : SM.Sections & Bool})),
    right:(@h:SM.Sections -> Exists(Bool,b => {P.present_go(depth,h,bits,key) == (h,b) : SM.Sections & Bool}))) ->
    Exists(Bool,b => {P.present_branch(low,lo,hi,l => P.present_go(depth,l,bits,key),h => P.present_go(depth,h,bits,key)) ==
      (SM.Branch{lo,hi},b) : SM.Sections & Bool}):
  match low:
    case True{}: lo_owned(depth,lo,hi,bits,key,left(lo))
    case False{}: hi_owned(depth,lo,hi,bits,key,right(hi))

def go_owned(+depth:Nat,sections:SM.Sections,+bits:U32,+key:String) ->
    Exists(Bool,b => {P.present_go(depth,sections,bits,key) == (sections,b) : SM.Sections & Bool}):
  match depth sections:
    case _ SM.EmptySections{}: (False{},{==})
    case 0n SM.Bucket{entries}: bucket_owned(entries,key,entries_owned(entries,key))
    case 1n+rest SM.Branch{lo,hi}:
      branch_owned(rest,lo,hi,U32.shr(bits),key,U32.is_eq(U32.and(bits,1),0),
        l => go_owned(rest,l,U32.shr(bits),key),h => go_owned(rest,h,U32.shr(bits),key))
    case 0n SM.Branch{lo,hi}: (False{},{==})
    case 1n+rest SM.Bucket{entries}: (False{},{==})

def sections_project_owned(-depth:Nat,-sections:SM.Sections,-bits:U32,-key:String,
    result:Exists(Bool,b => {P.present_go(depth,sections,bits,key) == (sections,b) : SM.Sections & Bool})) ->
    {Laws.retained_sections(P.present_go(depth,sections,bits,key)) == sections : SM.Sections}:
  match result:
    case Tuple{found,evidence}:
      %Equal.sym(SM.Sections & Bool,P.present_go(depth,sections,bits,key),(sections,found),evidence) :
        {Laws.retained_sections(_) == sections : SM.Sections}
      {==}

def Laws.present_go_preserves_owner(depth,sections,bits,key):
  sections_project_owned(depth,sections,bits,key,go_owned(depth,sections,bits,key))

def Laws.present_preserves_owner(sections,key):
  Laws.present_go_preserves_owner(32n,sections,SM.hash(key),key)

def counted_entry_owned(-head:SM.Entry,-rest:List<&1,SM.Entry>,
    result:Exists(Nat,n => {P.count_entries(rest) == (rest,n) : List<&1,SM.Entry> & Nat})) ->
    Exists(Nat,n => {P.counted_entry(head,P.count_entries(rest)) == (head <> rest,n) : List<&1,SM.Entry> & Nat}):
  match result:
    case Tuple{+count,evidence}:
      (1n+count,
        (%Equal.sym(List<&1,SM.Entry> & Nat,P.count_entries(rest),(rest,count),evidence) :
          {P.counted_entry(head,_) == (head <> rest,1n+count) : List<&1,SM.Entry> & Nat}
        {==}))

def counted_entries_owned(entries:List<&1,SM.Entry>) ->
    Exists(Nat,n => {P.count_entries(entries) == (entries,n) : List<&1,SM.Entry> & Nat}):
  match entries:
    case Nil{}: (0n,{==})
    case head <> rest: counted_entry_owned(head,rest,counted_entries_owned(rest))

def counted_bucket_owned(-entries:List<&1,SM.Entry>,
    result:Exists(Nat,n => {P.count_entries(entries) == (entries,n) : List<&1,SM.Entry> & Nat})) ->
    Exists(Nat,n => {P.count_bucket(entries) == (SM.Bucket{entries},n) : SM.Sections & Nat}):
  match result:
    case Tuple{count,evidence}:
      (count,
        (%Equal.sym(List<&1,SM.Entry> & Nat,P.count_entries(entries),(entries,count),evidence) :
          {P.count_bucket_result(_) == (SM.Bucket{entries},count) : SM.Sections & Nat}
        {==}))

def counted_branch_owned(-lo:SM.Sections,-hi:SM.Sections,
    left:Exists(Nat,n => {P.count(lo) == (lo,n) : SM.Sections & Nat}),
    right:Exists(Nat,n => {P.count(hi) == (hi,n) : SM.Sections & Nat})) ->
    Exists(Nat,n => {P.counted_branch(P.count(lo),P.count(hi)) == (SM.Branch{lo,hi},n) : SM.Sections & Nat}):
  match left right:
    case Tuple{+a,left_ok} Tuple{+b,right_ok}:
      (Nat.add(a,b),
        (%Equal.sym(SM.Sections & Nat,P.count(lo),(lo,a),left_ok) :
          {P.counted_branch(_,P.count(hi)) == (SM.Branch{lo,hi},Nat.add(a,b)) : SM.Sections & Nat}
        %Equal.sym(SM.Sections & Nat,P.count(hi),(hi,b),right_ok) :
          {P.counted_branch((lo,a),_) == (SM.Branch{lo,hi},Nat.add(a,b)) : SM.Sections & Nat}
        {==}))

def counted_owned(sections:SM.Sections) ->
    Exists(Nat,n => {P.count(sections) == (sections,n) : SM.Sections & Nat}):
  match sections:
    case SM.EmptySections{}: (0n,{==})
    case SM.Bucket{entries}: counted_bucket_owned(entries,counted_entries_owned(entries))
    case SM.Branch{lo,hi}: counted_branch_owned(lo,hi,counted_owned(lo),counted_owned(hi))

def counted_project_owned(-sections:SM.Sections,
    result:Exists(Nat,n => {P.count(sections) == (sections,n) : SM.Sections & Nat})) ->
    {Laws.counted_sections(P.count(sections)) == sections : SM.Sections}:
  match result:
    case Tuple{count,evidence}:
      %Equal.sym(SM.Sections & Nat,P.count(sections),(sections,count),evidence) :
        {Laws.counted_sections(_) == sections : SM.Sections}
      {==}

def Laws.count_preserves_complete_map(sections):
  counted_project_owned(sections,counted_owned(sections))

def Laws.rejected_demand_preserves_core(world,flat,region,stamp,requested,budget):
  match world:
    case C.World{tick,time,paused,daylight,revision,count,sections,pending,events}: {==}

def Laws.resident_commit_retains_pending_events_and_clock(tick,time,paused,daylight,revision,count,old,sections,pending,events):
  {==}

def Laws.empty_plan_is_whole_world_identity(tick,time,paused,daylight,revision,count,sections,pending,events,flat,stamp,requested,loaded):
  {==}

def Laws.first_layer_interval(height,state,rest,offset,air,within):
  %Equal.sym(Bool,U32.is_lt(offset,height),True{},within) :
    {P.layer_at_gate(offset,height,state,_,o => P.layer_at(rest,o,air)) == state : U32}
  {==}

def Laws.outside_dimension_is_air(dimension,min_y,height,air,layers,y,outside):
  %Equal.sym(Bool,WG.signed_le(min_y,y) && U32.is_lt(U32.sub(y,min_y),height),False{},outside) :
    {P.state_at_gate(layers,air,U32.sub(y,min_y),_) == air : U32}
  {==}

def Laws.spawn_demand_complete_columns():
  {==}

def Laws.spawn_demand_cardinality():
  {==}

def Laws.minimum_view_neighbor_refused():
  {==}

def Laws.maximum_view_neighbor_admitted():
  {==}

def Laws.legacy_generator_never_authorizes_population():
  {==}

def Laws.noise_generator_never_substitutes_flat(seed):
  {==}

def Laws.future_generation_stamp_refused():
  {==}


def Laws.invalid_fill_index_preserves_owner(section,flat,index,origin,invalid):
  %Equal.sym(Section.Section & Result<&2,&2,Section.Section.Error,Unit>,
    Section.Section.set_index(section,index,P.state_at(flat,U32.add(origin,U32.div(index,256)))),
    (section,Fail{Section.BadIndex{index}}),
    SectionLaws.set_index_rejects(section,index,P.state_at(flat,U32.add(origin,U32.div(index,256))),invalid)) :
    {P.fill_result(_) == section : Section.Section}
  {==}

def Laws.origin_fill_read_after_write(initial,flat,origin):
  SectionLaws.origin_read_after_write(initial,P.state_at(flat,U32.add(origin,0)))

def Laws.last_fill_read_after_write(initial,flat,origin):
  SectionLaws.last_read_after_write(initial,P.state_at(flat,U32.add(origin,15)))
