# Laws over the actual production owners and generator functions. These do not
# claim noise/structure/biome parity or a complete proof of every array write.
import Base
import ./superflat_world.bend as SF
import ./superflat_population.bend as P
import ./superflat_player.bend as Player
import ./world_generation_settings.bend as WG
import ./client_world.bend as W
import ./game.bend as G
import ./core.bend as C
import ./section_map.bend as SM
import ./local_phase_runtime.bend as X
import ./schedule.bend as Q
import ./nbt.bend as N
import ./movement.bend as M
import ./section.bend as Section
import ./local_move_history.bend as MH
import ./locomotion.bend as Motion
import ./support.bend as Support
import ./local_move_world.bend as Move
import ./player_fall_history.bend as Fall
import ./section_laws.bend as SectionLaws

def retained_entries(result:List<&1,SM.Entry> & Bool) -> List<&1,SM.Entry>:
  (entries,found) = result
  entries

def retained_sections(result:SM.Sections & Bool) -> SM.Sections:
  (sections,found) = result
  sections

def followed_state(result:W.State & Result<&2,&2,String,Unit>) -> W.State:
  (state,status) = result
  state

def owned_view(state:W.State) -> W.View:
  W.State{engine,body,yaw,pitch,palette,region,cache} = state
  W.View{body,yaw,pitch,palette,region,cache}

def demand_view(result:W.State & Result<&2,&2,String,P.Receipt>) -> W.View:
  (state,status) = result
  owned_view(state)

# Demand population retains every field of the caller's complete View. The
# separate configure operation is solely responsible for region/cache changes.
law demand_preserves_complete_view:
  for state:W.State
  for +settings:WG.Settings
  for policy:SF.ViewPolicy
  for budget:P.Budget
  for stamp:Q.Stamp
  {demand_view(SF.demand(state,settings,policy,budget,stamp)) == owned_view(state) : W.View}

law existing_world_retains_owned_state:
  for engine:G.Engine
  for view:W.View
  for profile:SF.Profile
  {SF.pristine_gate(profile,view,(engine,False{})) == (W.attach(engine,view),Done{SF.Existing{}}) : W.State & Result<&2,&2,String,SF.Outcome>}

law loaded_world_retains_all_fields:
  for state:W.State
  for settings:WG.Settings
  for policy:SF.ViewPolicy
  for budget:P.Budget
  for stamp:Q.Stamp
  {SF.initialize_generated(state,settings,policy,budget,stamp,False{}) == (state,Done{SF.Existing{}}) : W.State & Result<&2,&2,String,SF.Outcome>}

law loaded_player_retains_all_owners:
  for player:X.State
  for settings:WG.Settings
  {Player.initialize(settings,False{},player) == (player,Done{Unit{}}) : X.State & Result<&2,&2,String,Unit>}

type StablePlayer is Type:
  StablePlayer{tables:Motion.Tables,support:Support.State,minor:Move.MinorState,history:Fall.State,
    metadata:X.Metadata,motion_tail:List<&1,MH.State>,tail:List<&1,X.State>}

# A specification projection of every owner and field outside the World.
def stable_player(player:X.State) -> StablePlayer:
  X.State{MH.State{world,support,minor,history,motion_tail},tables,metadata,tail} = player
  StablePlayer{tables,support,minor,history,metadata,motion_tail,tail}

def stable_after(result:X.State & Result<&2,&2,String,Unit>) -> StablePlayer:
  (player,status) = result
  stable_player(player)

law demand_retains_local_player_owners:
  for player:X.State
  for +settings:WG.Settings
  {stable_after(Player.ensure(settings,player)) == stable_player(player) : StablePlayer}

law unsupported_dimension_retains_complete_player:
  for player:X.State
  for +settings:WG.Settings
  for unsupported:{Player.supported_dimension(settings) == False{} : Bool}
  {Player.ensure(settings,player) == (player,Fail{"player world adapter only supports minecraft:overworld"}) : X.State & Result<&2,&2,String,Unit>}

law unsupported_fresh_dimension_retains_complete_player:
  for player:X.State
  for +settings:WG.Settings
  for unsupported:{Player.supported_dimension(settings) == False{} : Bool}
  {Player.initialize(settings,True{},player) == (player,Fail{"player world adapter only supports minecraft:overworld"}) : X.State & Result<&2,&2,String,Unit>}

law wrapped_flat_spawn_is_refused:
  {SF.generator_surface(2147483632,16n) == Fail{"flat spawn surface exceeds signed coordinate representation"} : Result<&2,&2,String,M.Body>}

law configuration_error_preserves_entire_state:
  for state:W.State
  for +message:String
  {SF.configured(state,Fail{message}) == (state,Fail{message}) : W.State & Result<&2,&2,String,Unit>}

law same_configuration_preserves_entire_state:
  for state:W.State
  for actual:W.Bounds
  {SF.configured_equal(state,actual,True{}) == (state,Done{Unit{}}) : W.State & Result<&2,&2,String,Unit>}

# The first change invalidates the cache; an unchanged subsequent follow is
# an identity over that result, including its Body/camera/registry owners.
law follow_composition:
  for state:W.State
  for +actual:W.Bounds
  {SF.configured_equal(followed_state(SF.configured_equal(state,actual,False{})),actual,True{}) == SF.configured_equal(state,actual,False{}) : W.State & Result<&2,&2,String,Unit>}

law present_entries_preserves_owner:
  for entries:List<&1,SM.Entry>
  for +key:String
  {retained_entries(P.present_entries(entries,key)) == entries : List<&1,SM.Entry>}

law present_go_preserves_owner:
  for depth:Nat
  for sections:SM.Sections
  for +bits:U32
  for +key:String
  {retained_sections(P.present_go(depth,sections,bits,key)) == sections : SM.Sections}

law present_preserves_owner:
  for sections:SM.Sections
  for +key:String
  {retained_sections(P.present(sections,key)) == sections : SM.Sections}

def counted_sections(result:SM.Sections & Nat) -> SM.Sections:
  (sections,count) = result
  sections

# The admission prepass retains the whole map, including every existing array
# owner and collision-bucket position; its count does not rebuild the map.
law count_preserves_complete_map:
  for sections:SM.Sections
  {counted_sections(P.count(sections)) == sections : SM.Sections}

law rejected_demand_preserves_core:
  for world:C.World
  for flat:P.Flat
  for region:P.Region
  for stamp:Q.Stamp
  for requested:Nat
  for budget:P.Budget
  {P.populate_gate(flat,region,stamp,requested,budget,world,False{}) == (world,Fail{"invalid or oversized chunk demand"}) : C.World & Result<&2,&2,String,P.Receipt>}

law resident_commit_retains_pending_events_and_clock:
  for tick:Nat
  for time:Nat
  for paused:Bool
  for daylight:Bool
  for revision:Nat
  for count:U32
  for old:SM.Sections
  for sections:SM.Sections
  for pending:List<&2,Q.Pending<C.Mutation>>
  for events:List<&2,C.CoreEvent>
  {P.resident_commit(C.World{tick,time,paused,daylight,revision,count,old,pending,events},sections) ==
    C.World{tick,time,paused,daylight,1n+revision,count,sections,pending,events} : C.World}

law empty_plan_is_whole_world_identity:
  for tick:Nat
  for time:Nat
  for paused:Bool
  for daylight:Bool
  for revision:Nat
  for count:U32
  for sections:SM.Sections
  for pending:List<&2,Q.Pending<C.Mutation>>
  for events:List<&2,C.CoreEvent>
  for flat:P.Flat
  for stamp:Q.Stamp
  for requested:Nat
  for loaded:Nat
  {P.populate_commit(flat,stamp,requested,loaded,[],C.World{tick,time,paused,daylight,revision,count,SM.EmptySections{},pending,events},sections) ==
    (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},Done{P.Receipt{requested,0n,loaded}}) : C.World & Result<&2,&2,String,P.Receipt>}

law first_layer_interval:
  for +height:U32
  for +state:U32
  for rest:List<&2,P.Layer>
  for +offset:U32
  for air:U32
  for within:{U32.is_lt(offset,height) == True{} : Bool}
  {P.layer_at(P.Layer{height,state} <> rest,offset,air) == state : U32}

law outside_dimension_is_air:
  for dimension:String
  for +min_y:U32
  for +height:U32
  for +air:U32
  for layers:List<&2,P.Layer>
  for +y:U32
  for outside:{WG.signed_le(min_y,y) && U32.is_lt(U32.sub(y,min_y),height) == False{} : Bool}
  {P.state_at(P.Flat{dimension,min_y,height,air,layers},y) == air : U32}

# Complete production demand arithmetic at the spawn, including all24 vertical
# sections and one halo section on each side, across four horizontal chunks.
law spawn_demand_complete_columns:
  {SF.demand_region(WG.stone_dirt(N.Word64{0,0}),W.Bounds{4294967292,4294967232,4294967292,8,8,8}) == Done{P.Region{4294967295,4294967295,2,2,4294967291,26}} : Result<&2,&2,String,P.Region>}

law spawn_demand_cardinality:
  {P.region_count(P.Region{4294967295,4294967295,2,2,4294967291,26}) == 104n : Nat}

law minimum_view_neighbor_refused:
  {SF.centered(SF.default_view_policy(),2147483648,0,0) == Fail{"invalid view policy or signed coordinate neighbor halo"} : Result<&2,&2,String,W.Bounds>}

law maximum_view_neighbor_admitted:
  {SF.centered(SF.default_view_policy(),2147483643,0,0) == Done{W.Bounds{2147483639,4294967292,4294967292,8,8,8}} : Result<&2,&2,String,W.Bounds>}

law legacy_generator_never_authorizes_population:
  {WG.base_only(WG.legacy()) == False{} : Bool}

law noise_generator_never_substitutes_flat:
  for seed:N.Word64
  {WG.base_only(WG.normal(seed)) == False{} : Bool}

law future_generation_stamp_refused:
  {P.populate(P.Flat{"minecraft:overworld",4294967232,384,0,[]},P.Region{0,0,1,1,0,1},Q.Stamp{1n,0,0n},P.default_budget(),C.new(2)) ==
    (C.new(2),Fail{"generation stamp violates current clock or event order"}) : C.World & Result<&2,&2,String,P.Receipt>}

# These actual fill boundaries reuse the existing checked Section semantics.
# They certify boundary writes and refusal; they do not masquerade as a proof
# of all4096 successive writes in complete_section.
law invalid_fill_index_preserves_owner:
  for section:Section.Section
  for +flat:P.Flat
  for +index:U32
  for +origin:U32
  for invalid:{U32.is_lt(index,4096) == False{} : Bool}
  {P.fill(1n,index,origin,flat,section) == section : Section.Section}

law origin_fill_read_after_write:
  for initial:U32
  for +flat:P.Flat
  for +origin:U32
  {SectionLaws.section_value(Section.Section.get_index(P.fill(1n,0,origin,flat,Section.Section.new(initial)),0)) ==
    Done{P.state_at(flat,U32.add(origin,0))} : Result<&2,&2,Section.Section.Error,U32>}

law last_fill_read_after_write:
  for initial:U32
  for +flat:P.Flat
  for +origin:U32
  {SectionLaws.section_value(Section.Section.get_index(P.fill(1n,4095,origin,flat,Section.Section.new(initial)),4095)) ==
    Done{P.state_at(flat,U32.add(origin,15))} : Result<&2,&2,Section.Section.Error,U32>}
