import Base
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as Registry
import ../src/player_block_interaction.bend as BI
import ../src/movement.bend as Movement
import ../src/f64.bend as Double
import ../src/schedule.bend as Q
import ../src/local_player_cooking.bend as K
import ../src/local_player_cooking_edit.bend as E
import ../src/local_player_cooking_entity_owner.bend as Owner
import ../src/local_player_cooking_geometry_owner.bend as Geometry
import ../src/local_player_cooking_publication_owner.bend as Publisher
import ../src/cooking_effect_publication.bend as Publication
import ../src/cooking_effect_publication_journal.bend as Journal
import ../src/local_player_cooking_incarnation_guard.bend as Incarnation
import ../src/cooking_effect_entities_model.bend as Model
import ../src/local_collision_world.bend as Collision
import ../src/slab_collision.bend as Slab
import ../src/random.bend as Random
import ../src/block_light.bend as L
import ../src/block_light_world.bend as W
import ../src/block_light_registry.bend as LR
import ../src/cooking_world.bend as CW
import ../src/cooking_world_store.bend as S
import ../src/cooking_world_bindings.bend as B
import ../src/cooking_recipe.bend as Recipe
import ../src/furnace_authority.bend as F
import ../src/furnace_authority_fuel.bend as Fuel
import ../src/campfire_authority_items.bend as AI
import ../src/crafting_recipe.bend as Craft
import ../src/inventory.bend as Inv
import ../src/cooking_block_entity_codec.bend as CB
import ../src/cooking_block_entity_codec_items.bend as Items
import ../src/nbt.bend as N
import ./cooking_world_lifecycle.bend as Life
import ./core_refusal.bend as Raw

def position(x:U32) -> C.Position: Life.position(x)
def slot(name:String,count:U32) -> Inv.Slot: Life.stack(name,count)
def unit_equal(a:Unit,b:Unit) -> Bool: True{}
def nat_equal(a:Nat,b:Nat) -> Bool: Nat.is_eq(a,b)
def bool_equal(a:Bool,b:Bool) -> Bool: Raw.bool_equal(a,b)

# Compare the complete actual trie representation, including node bit and leaf
# order. Queries are insufficient evidence for retention of these owners.
def map_equal(~A:Data,~equal:A -> A -> Bool,a:Map<&2,A>,b:Map<&2,A>) -> Bool:
  match a b:
    case MTip{} MTip{}: True{}
    case MLeaf{x,v} MLeaf{y,w}: String.eq(x,y) && equal(v,w)
    case MNode{x,lo,hi} MNode{y,other_lo,other_hi}:
      Nat.is_eq(x,y) && map_equal(~A,~equal,lo,other_lo) && map_equal(~A,~equal,hi,other_hi)
    case _ _: False{}
def cell_equal(a:Maybe<&2,L.Cell>,b:Maybe<&2,L.Cell>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{L.Cell{L.Descriptor{s,e,d},level}} Some{L.Cell{L.Descriptor{ss,ee,dd},other}}:
      U32.is_eq(s,ss) && U32.is_eq(e,ee) && U32.is_eq(d,dd) && U32.is_eq(level,other)
    case _ _: False{}
def binding_equal(a:Maybe<&2,B.Binding>,b:Maybe<&2,B.Binding>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{B.Binding{s,n,k,l,d,b}} Some{B.Binding{ss,nn,kk,ll,dd,bb}}:
      U32.is_eq(s,ss) && String.eq(n,nn) && B.same_family(k,kk) && bool_equal(l,ll) && U32.is_eq(d,dd) && U32.is_eq(b,bb)
    case _ _: False{}
def registry_entry_equal(a:Maybe<&2,LR.Entry>,b:Maybe<&2,LR.Entry>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{LR.Entry{e,d,LR.Faces{a,b,c,f,g,h}}} Some{LR.Entry{ee,dd,LR.Faces{aa,bb,cc,ff,gg,hh}}}:
      U32.is_eq(e,ee) && U32.is_eq(d,dd) && U32.is_eq(a,aa) && U32.is_eq(b,bb) && U32.is_eq(c,cc) && U32.is_eq(f,ff) && U32.is_eq(g,gg) && U32.is_eq(h,hh)
    case _ _: False{}
def light_cells() -> Map<&2,Maybe<&2,L.Cell>>:
  Map.set(&2,Maybe<&2,L.Cell>,Map.set(&2,Maybe<&2,L.Cell>,MTip{},"unknown-marker",None{}),
    L.key(position(0)),Some{L.Cell{L.Descriptor{1,13,0},7}})
def light() -> L.State:
  L.State{light_cells(),[position(3)],[position(2)],MLeaf{"queued-marker",Unit{}},99n}
def light_valid(owner:L.State) -> Bool:
  match owner:
    case L.State{cells,C.Position{"minecraft:overworld",3,0,0} <> Nil{},C.Position{"minecraft:overworld",2,0,0} <> Nil{},queued,99n}:
      map_equal(~Maybe<&2,L.Cell>,~cell_equal,cells,light_cells()) &&
        map_equal(~Unit,~unit_equal,queued,MLeaf{"queued-marker",Unit{}})
    case _: False{}
def descriptors() -> Map<&2,Maybe<&2,LR.Entry>>:
  Map.set(&2,Maybe<&2,LR.Entry>,Map.set(&2,Maybe<&2,LR.Entry>,MTip{},"0",
    Some{LR.Entry{0,0,LR.Faces{0,0,0,0,0,0}}}),"1",Some{LR.Entry{13,0,LR.Faces{0,0,0,0,0,0}}})
def edit_descriptors() -> Map<&2,Maybe<&2,LR.Entry>>:
  Map.set(&2,Maybe<&2,LR.Entry>,Map.set(&2,Maybe<&2,LR.Entry>,descriptors(),"2",
    Some{LR.Entry{13,0,LR.Faces{0,0,0,0,0,0}}}),"3",Some{LR.Entry{0,0,LR.Faces{0,0,0,0,0,0}}})
def context() -> K.Context:
  K.Context{LR.Catalog{"lifecycle-fixture",4,1,edit_descriptors(),MTip{}},
    MLeaf{L.key(W.origin(position(0))),True{}},Life.context(),[]}
def recipes_valid(catalog:Recipe.Catalog) -> Bool:
  match catalog:
    case Recipe.Catalog{Recipe.Cooking{"fixture:smelt",Recipe.Smelting{},Craft.AnyOf{Craft.Item{"minecraft:iron_ore"} <> Nil{}},output,200,xp} <> Nil{},Nil{},Nil{}}:
      Recipe.slot_equal(output,slot("minecraft:iron_ingot",1)) && U32.is_eq(F32.bits(xp),1056964608)
    case _: False{}
def bindings_valid(values:Map<&2,Maybe<&2,B.Binding>>,catalog:B.Catalog) -> Bool:
  B.Catalog{identity,count,expected} = catalog
  map_equal(~Maybe<&2,B.Binding>,~binding_equal,values,expected)


def context_valid(value:K.Context) -> Bool:
  match value:
    case K.Context{LR.Catalog{"lifecycle-fixture",4,1,states,MTip{}},enabled,
      CW.Context{B.Catalog{"lifecycle-fixture",4,bindings},AI.Context{recipes,Nil{},MTip{}},Fuel.Catalog{Nil{},Nil{},Nil{},Nil{},Nil{},Nil{}},64n},Nil{}}:
      map_equal(~Maybe<&2,LR.Entry>,~registry_entry_equal,states,edit_descriptors()) &&
        map_equal(~Bool,~bool_equal,enabled,MLeaf{L.key(W.origin(position(0))),True{}}) &&
        bindings_valid(bindings,Life.bindings()) && recipes_valid(recipes)
    case _: False{}

def furnace_padded(owner:F.State) -> F.State:
  F.State{Inv.Inventory{cells,length},frame} = owner
  F.State{Inv.Inventory{Array.set(Inv.Slot,cells,3,slot("minecraft:dirt",6)),length},frame}
def furnace() -> F.State: furnace_padded(F.install(Life.snapshot()))
def furnace_valid(owner:F.State) -> Bool:
  match owner:
    case F.State{Inv.Inventory{ANode{ANode{ALeaf{a},ALeaf{b}},ANode{ALeaf{c},ALeaf{d}}},3},
      F.Frame{Recipe.Smelting{},11,13,17,19,speed,Some{"fixture:smelt"},F.Use{"fixture:smelt",2} <> Nil{}}}:
      Recipe.slot_equal(a,slot("minecraft:iron_ore",2)) && Recipe.slot_equal(b,slot("minecraft:coal",1)) &&
        Recipe.slot_equal(c,slot("minecraft:iron_ingot",3)) && Recipe.slot_equal(d,slot("minecraft:dirt",6)) && U32.is_eq(F32.bits(speed),1065353216)
    case _: False{}
def entries(first_state:U32) -> List<&1,S.Entry>:
  [S.Entry{position(0),Life.furnace(first_state,False{}),S.Furnace{furnace()}},
   S.Entry{position(1),Life.furnace(1,False{}),S.Furnace{furnace()}}]
def entry_valid(entry:S.Entry,state:U32,x:U32) -> Bool:
  match entry:
    case S.Entry{p,B.Binding{id,name,B.Furnace{Recipe.Smelting{}},False{},1,2},S.Furnace{owner}}:
      B.equal_position(p,position(x)) && U32.is_eq(id,state) && String.eq(name,"minecraft:furnace") && furnace_valid(owner)
    case _: False{}
def entries_valid(values:List<&1,S.Entry>,first_state:U32) -> Bool:
  match values:
    case a <> b <> Nil{}: entry_valid(a,first_state,0) && entry_valid(b,1,1)
    case _: False{}
def details() -> CB.Details:
  CB.Details{N.Text{[55296,0,97]},[N.Member{N.Text{[65,0,56320]},N.Float{2147483648}},
    N.Member{N.Text{[65,0,56320]},N.Int{4294967295}}],[],Items.Admission{[],[]},9}
def details_valid(value:CB.Details) -> Bool:
  match value:
    case CB.Details{N.Text{high <> 0 <> 97 <> Nil{}},N.Member{N.Text{65 <> 0 <> low <> Nil{}},N.Float{floating}} <>
      N.Member{N.Text{65 <> 0 <> second_low <> Nil{}},N.Int{integer}} <> Nil{},Nil{},Items.Admission{Nil{},Nil{}},9}:
      U32.is_eq(high,55296) && U32.is_eq(low,56320) && U32.is_eq(second_low,56320) &&
        U32.is_eq(floating,2147483648) && U32.is_eq(integer,4294967295)
    case _: False{}
def body_details_valid(values:List<&2,K.BodyDetails>) -> Bool:
  match values:
    case K.BodyDetails{a,first} <> K.BodyDetails{b,second} <> Nil{}:
      B.equal_position(a,position(0)) && B.equal_position(b,position(1)) && details_valid(first) && details_valid(second)
    case _: False{}
def incarnations() -> Map<&2,Nat>:
  Map.set(&2,Nat,Map.set(&2,Nat,MTip{},B.key(position(0)),10n),B.key(position(1)),6n)
def counted_incarnations(first:Nat) -> Map<&2,Nat>:
  Map.set(&2,Nat,Map.set(&2,Nat,MTip{},B.key(position(0)),first),B.key(position(1)),6n)
def publisher() -> Publisher.Carrier:
  Publisher.Bound{Publication.Context{Life.bindings()},Journal.State{Journal.View{17n,
    [Journal.DirtyChunk{Journal.chunk(position(1)),17n}],
    Some{Journal.Receipt{position(1),Journal.Source{position(1),Life.furnace(1,False{}),6n},Journal.chunk(position(1)),17n}}}},
    [Publisher.Unbound{}]}
def publisher_valid(value:Publisher.Carrier) -> Bool:
  match value:
    case Publisher.Bound{Publication.Context{B.Catalog{"lifecycle-fixture",4,bindings}},
      Journal.State{Journal.View{17n,Journal.DirtyChunk{+chunk,17n} <> Nil{},
        Some{Journal.Receipt{+p,Journal.Source{other,binding,6n},target,17n}}}},Publisher.Unbound{} <> Nil{}}:
      bindings_valid(bindings,Life.bindings()) && Journal.chunk_equal(chunk,Journal.chunk(position(1))) &&
        Journal.chunk_equal(target,chunk) && B.equal_position(p,position(1)) && B.equal_position(other,p) &&
        binding_equal(Some{binding},Some{Life.furnace(1,False{})})
    case _: False{}
def carrier() -> Owner.Carrier:
  Owner.Bound{Model.Context{AI.Context{Life.recipes(),[],MTip{}},Model.Limits{7n,11n,13n},[41]},
    Model.State{Random.Xoroshiro{Random.Bits64{4294967295,0},Random.Bits64{2147483648,99}},Random.Bits64{17,23},99,123n,[]},
    [Random.Bits64{2147483648,4294967295},Random.Bits64{0,7}],
    Some{Geometry.Owner{Slab.Catalog{ANode{ALeaf{Slab.Entry{1,Slab.TopSlab{},True{}}},ALeaf{Slab.Entry{2,Slab.BottomSlab{},False{}}}},1,4,"geometry-marker"},
      Collision.Environment{Collision.UnresolvedEntityCollisions{},Collision.UnresolvedWorldBorder{}}}},publisher()}
def carrier_valid(value:Owner.Carrier) -> Bool:
  match value:
    case Owner.Bound{Model.Context{AI.Context{recipes,Nil{},MTip{}},Model.Limits{7n,11n,13n},41 <> Nil{}},
      Model.State{Random.Xoroshiro{Random.Bits64{first,0},Random.Bits64{second,99}},Random.Bits64{17,23},99,123n,Nil{}},
      Random.Bits64{clock_high,clock_low} <> Random.Bits64{0,7} <> Nil{},
      Some{Geometry.Owner{Slab.Catalog{ANode{ALeaf{Slab.Entry{1,Slab.TopSlab{},True{}}},ALeaf{Slab.Entry{2,Slab.BottomSlab{},False{}}}},1,4,"geometry-marker"},
        Collision.Environment{Collision.UnresolvedEntityCollisions{},Collision.UnresolvedWorldBorder{}}}},publication}:
      recipes_valid(recipes) && U32.is_eq(first,4294967295) && U32.is_eq(second,2147483648) &&
        U32.is_eq(clock_high,2147483648) && U32.is_eq(clock_low,4294967295) && publisher_valid(publication)
    case _: False{}
def sidecar(first_state:U32,tail:List<&1,K.Sidecar>) -> K.Sidecar:
  K.Initialized{context(),light(),None{},entries(first_state),CW.Idle{},[],[S.Dirty{position(1)}],
    [K.BodyDetails{position(0),details()},K.BodyDetails{position(1),details()}],incarnations(),5n,carrier(),tail}
def counted_sidecar(first_state:U32,first:Nat,tail:List<&1,K.Sidecar>) -> K.Sidecar:
  K.Initialized{context(),light(),None{},entries(first_state),CW.Idle{},[],[S.Dirty{position(1)}],
    [K.BodyDetails{position(0),details()},K.BodyDetails{position(1),details()}],counted_incarnations(first),5n,carrier(),tail}
def tail_valid(values:List<&1,K.Sidecar>,expected:Bool) -> Bool:
  match values expected:
    case Nil{} False{}: True{}
    case K.Uninitialized{} <> Nil{} True{}: True{}
    case _ _: False{}
def retained_count(value:K.Sidecar,first_state:U32,first:Nat,has_tail:Bool) -> Bool:
  match value:
    case K.Initialized{context,light,None{},entries,CW.Idle{},Nil{},S.Dirty{p} <> Nil{},details,values,5n,owner,tail}:
      context_valid(context) && light_valid(light) && entries_valid(entries,first_state) && B.equal_position(p,position(1)) &&
        body_details_valid(details) && map_equal(~Nat,~nat_equal,values,counted_incarnations(first)) && carrier_valid(owner) && tail_valid(tail,has_tail)
    case _: False{}
def retained(value:K.Sidecar,first_state:U32,has_tail:Bool) -> Bool:
  retained_count(value,first_state,10n,has_tail)

def guard(label:String,okay:Bool) -> IO(Unit): Life.guard(label,okay)
def refused_images(label:String,expected:String,first_state:U32,has_tail:Bool,before:Raw.WorldImage,sidecar:K.Sidecar,
    world:C.World,after:Raw.WorldImage,status:Result<&2,&2,String,Unit>) -> IO(Unit):
  match status:
    case Done{unit}: IO.die(Unit,3,"unexpected accepted edit: " ++ label)
    case Fail{message}:
      guard(label,String.eq(message,expected) && Raw.worlds_equal(before,after) && retained(sidecar,first_state,has_tail))
def refused_observed(label:String,expected:String,first_state:U32,has_tail:Bool,before:Raw.WorldImage,sidecar:K.Sidecar,
    status:Result<&2,&2,String,Unit>,result:C.World & Raw.WorldImage) -> IO(Unit):
  (world,after) = result
  refused_images(label,expected,first_state,has_tail,before,sidecar,world,after,status)
def refused(label:String,expected:String,first_state:U32,has_tail:Bool,before:Raw.WorldImage,
    result:C.World & K.Sidecar & Result<&2,&2,String,Unit>) -> IO(Unit):
  (world,sidecar,status) = result
  refused_observed(label,expected,first_state,has_tail,before,sidecar,status,Raw.world_image(world))
def refused_world(kind:U32,world:C.World,before:Raw.WorldImage) -> IO(Unit):
  match kind:
    case 0: refused("stale revision retains complete Core and sidecar","local-cooking:interaction:stale-revision",1,False{},before,E.player_edit(world,sidecar(1,[]),C.Player{17},position(0),0,6n,19n,True{}))
    case 1: refused("disabled build retains complete Core and sidecar","local-cooking:interaction:permission-denied",1,False{},before,E.player_edit(world,sidecar(1,[]),C.Player{17},position(0),0,7n,19n,False{}))
    case 2: refused("observer retains complete Core and sidecar","local-cooking:interaction:permission-denied",1,False{},before,E.player_edit(world,sidecar(1,[]),C.Observer{},position(0),0,7n,19n,True{}))
    case 3: refused("invalid peer retains complete Core and sidecar","local-cooking:interaction:permission-denied",1,False{},before,E.player_edit(world,sidecar(1,[]),C.Player{0},position(0),0,7n,19n,True{}))
    case 4: refused("residency mismatch retains complete Core and sidecar","local-cooking:entity-mismatch:minecraft:overworld/0/0/0",2,False{},before,E.player_edit(world,sidecar(2,[]),C.Player{17},position(0),0,7n,19n,True{}))
    case 5: refused("missing section retains complete Core and sidecar","local-cooking:interaction:invalid-core-edit",1,False{},before,E.player_edit(world,sidecar(1,[]),C.Player{17},position(32),0,7n,19n,True{}))
    case _: refused("recursive tail retains complete Core and sidecar","local-cooking:noncanonical-sidecar-tail",1,True{},before,E.player_edit(world,sidecar(1,[K.Uninitialized{}]),C.Player{17},position(0),0,7n,19n,True{}))
def refused_ready(kind:U32,result:C.World & Raw.WorldImage) -> IO(Unit):
  (world,before) = result
  refused_world(kind,world,before)
def marked_world(next:C.World -> IO(Unit),world:C.World) -> IO(Unit):
  C.World{tick,time,paused,daylight,revision,count,sections,pending,events} = world
  next(C.World{29n,13499n,False{},False{},7n,count,sections,
    [Q.Pending{Q.Stamp{100n,31,37n},C.DaylightSet{True{}}}],
    [C.Applied{Q.Stamp{11n,5,13n},3n}]})

def marked(next:C.World -> IO(Unit),result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(Unit):
  (world,status) = result
  match status:
    case Fail{error}: IO.die(Unit,3,"fixture second furnace write failed")
    case Done{unit}: marked_world(next,world)
def initial_owner(next:C.World -> IO(Unit),owner:CW.State) -> IO(Unit):
  CW.State{W.State{world,light,loading},entries,phase,keys} = owner
  marked(next,C.write_block(world,position(1),1))


def initial(next:C.World -> IO(Unit)) -> IO(Unit):
  Life.initial(owner => initial_owner(next,owner))

def accepted_details(values:List<&2,K.BodyDetails>) -> Bool:
  match values:
    case K.BodyDetails{p,d} <> Nil{}: B.equal_position(p,position(1)) && details_valid(d)
    case _: False{}
def accepted_effects(values:List<&2,S.Effect>) -> Bool:
  match values:
    case S.Dirty{p} <> rest: B.equal_position(p,position(1)) && Life.original_intents(rest)
    case _: False{}
def accepted_entries(values:List<&1,S.Entry>) -> Bool:
  match values:
    case head <> Nil{}: entry_valid(head,1,1)
    case _: False{}
def accepted_cell(pending:Nat,result:Map<&2,Maybe<&2,L.Cell>> & Maybe<&2,L.Cell>) -> Bool:
  match result:
    case (cells,Some{L.Cell{L.Descriptor{0,0,0},7}}): Nat.is_eq(pending,106n)
    case _: False{}

def accepted_light(owner:L.State) -> Bool:
  L.State{cells,front,back,queued,pending} = owner
  accepted_cell(pending,Map.get(Maybe<&2,L.Cell>,None{},cells,L.key(position(0))))

def accepted_sidecar_count(first:Nat,value:K.Sidecar) -> IO(Unit):
  match value:
    case K.Initialized{context,light,None{},entries,CW.Idle{},Nil{},effects,details,incarnations,5n,owner,Nil{}}:
      do IO<Unit>:
        guard("furnace teardown retains unrelated owner and exact ordered prior/drop/XP intents",context_valid(context) && accepted_entries(entries) && accepted_effects(effects))
        guard("successful reset removes only old physical Details and increments only its incarnation",accepted_details(details) &&
          map_equal(~Nat,~nat_equal,incarnations,counted_incarnations(first)))
        guard("successful edit publishes actual air descriptor and pending light work",accepted_light(light))
        guard("successful edit retains complete entity RNG clock and geometry carrier",carrier_valid(owner))
    case _: IO.die(Unit,3,"accepted sidecar shape changed")
def accepted_core_count(first:Nat,sidecar:K.Sidecar,result:C.World & Raw.WorldImage) -> IO(Unit):
  (world,image) = result
  match image:
    case Raw.WorldImage{29n,time,False{},False{},8n,4,tree,pending,C.Applied{Q.Stamp{29n,17,19n},8n} <> old}:
      do IO<Unit>:
        guard("successful edit records current tick actual peer and sequence",Nat.is_eq(time,13499n) && Raw.pending_equal(pending,[Q.Pending{Q.Stamp{100n,31,37n},C.DaylightSet{True{}}}]) &&
          Raw.events_equal(old,[C.Applied{Q.Stamp{11n,5,13n},3n}]))
        Life.final_block(C.read_block(world,position(0)),0)
        accepted_sidecar_count(first,sidecar)
    case _: IO.die(Unit,3,"accepted Core clock/stamp changed")
def accepted(result:C.World & K.Sidecar & Result<&2,&2,String,Unit>) -> IO(Unit):
  (world,sidecar,status) = result
  match status:
    case Fail{message}: IO.die(Unit,3,"furnace player break refused: " ++ message)
    case Done{unit}: accepted_core_count(11n,sidecar,Raw.world_image(world))
def accepted_core(sidecar:K.Sidecar,result:C.World & Raw.WorldImage) -> IO(Unit):
  accepted_core_count(11n,sidecar,result)

def max_refused_images(label:String,expected:String,has_tail:Bool,before:Raw.WorldImage,
    sidecar:K.Sidecar,world:C.World,after:Raw.WorldImage,status:Result<&2,&2,String,Unit>) -> IO(Unit):
  match status:
    case Done{unit}: IO.die(Unit,3,"unexpected MAX edit acceptance: " ++ label)
    case Fail{message}: guard(label,String.eq(message,expected) && Raw.worlds_equal(before,after) &&
      retained_count(sidecar,1,Incarnation.maximum(),has_tail))
def max_refused_observed(label:String,expected:String,has_tail:Bool,before:Raw.WorldImage,
    sidecar:K.Sidecar,status:Result<&2,&2,String,Unit>,result:C.World & Raw.WorldImage) -> IO(Unit):
  (world,after) = result
  max_refused_images(label,expected,has_tail,before,sidecar,world,after,status)
def max_refused(label:String,expected:String,has_tail:Bool,before:Raw.WorldImage,
    result:C.World & K.Sidecar & Result<&2,&2,String,Unit>) -> IO(Unit):
  (world,sidecar,status) = result
  max_refused_observed(label,expected,has_tail,before,sidecar,status,Raw.world_image(world))
def max_refusal_world(kind:U32,world:C.World,before:Raw.WorldImage) -> IO(Unit):
  match kind:
    case 0: max_refused("MAX teardown refuses before every Core and sidecar owner changes","local-cooking:authority:incarnation-exhausted",False{},before,
      E.player_edit(world,counted_sidecar(1,Incarnation.maximum(),[]),C.Player{17},position(0),0,7n,19n,True{}))
    case 1: max_refused("MAX replacement refuses before every Core and sidecar owner changes","local-cooking:authority:incarnation-exhausted",False{},before,
      E.player_edit(world,counted_sidecar(1,Incarnation.maximum(),[]),C.Player{17},position(0),3,7n,19n,True{}))
    case 2: max_refused("MAX stale revision keeps original refusal precedence","local-cooking:interaction:stale-revision",False{},before,
      E.player_edit(world,counted_sidecar(1,Incarnation.maximum(),[]),C.Player{17},position(0),0,6n,19n,True{}))
    case 3: max_refused("MAX zero sequence keeps original refusal precedence","local-cooking:interaction:invalid-sequence",False{},before,
      E.player_edit(world,counted_sidecar(1,Incarnation.maximum(),[]),C.Player{17},position(0),0,7n,0n,True{}))
    case 4: max_refused("MAX permission refusal retains arbitrary publisher and complete owners","local-cooking:interaction:permission-denied",False{},before,
      E.player_edit(world,counted_sidecar(1,Incarnation.maximum(),[]),C.Player{17},position(0),0,7n,19n,False{}))
    case _: max_refused("MAX recursive tail keeps original refusal precedence","local-cooking:noncanonical-sidecar-tail",True{},before,
      E.player_edit(world,counted_sidecar(1,Incarnation.maximum(),[K.Uninitialized{}]),C.Player{17},position(0),0,7n,19n,True{}))
def max_refusal(kind:U32,result:C.World & Raw.WorldImage) -> IO(Unit):
  (world,before) = result
  max_refusal_world(kind,world,before)

def retained_binding(entry:S.Entry,state:U32,lit:Bool) -> Bool:
  match entry:
    case S.Entry{p,B.Binding{id,name,B.Furnace{Recipe.Smelting{}},actual,1,2},S.Furnace{owner}}:
      B.equal_position(p,position(0)) && U32.is_eq(id,state) && String.eq(name,"minecraft:furnace") &&
        bool_equal(actual,lit) && furnace_valid(owner)
    case _: False{}
def max_kept_sidecar(state:U32,lit:Bool,value:K.Sidecar) -> Bool:
  match value:
    case K.Initialized{context,light,None{},a <> b <> Nil{},CW.Idle{},Nil{},S.Dirty{p} <> Nil{},details,values,5n,owner,Nil{}}:
      context_valid(context) && retained_binding(a,state,lit) && entry_valid(b,1,1) &&
        B.equal_position(p,position(1)) && body_details_valid(details) &&
        map_equal(~Nat,~nat_equal,values,counted_incarnations(Incarnation.maximum())) && carrier_valid(owner)
    case _: False{}
def max_kept_core(label:String,+state:U32,lit:Bool,sidecar:K.Sidecar,result:C.World & Raw.WorldImage) -> IO(Unit):
  (world,image) = result
  match image:
    case Raw.WorldImage{29n,time,False{},False{},8n,4,tree,pending,C.Applied{Q.Stamp{29n,17,19n},8n} <> old}:
      do IO<Unit>:
        guard(label,Nat.is_eq(time,13499n) && Raw.pending_equal(pending,[Q.Pending{Q.Stamp{100n,31,37n},C.DaylightSet{True{}}}]) &&
          Raw.events_equal(old,[C.Applied{Q.Stamp{11n,5,13n},3n}]) && max_kept_sidecar(state,lit,sidecar))
        Life.final_block(C.read_block(world,position(0)),state)
    case _: IO.die(Unit,3,"MAX same-owner Core stamp changed")
def max_kept(label:String,state:U32,lit:Bool,result:C.World & K.Sidecar & Result<&2,&2,String,Unit>) -> IO(Unit):
  (world,sidecar,status) = result
  match status:
    case Fail{message}: IO.die(Unit,3,"MAX same-owner update refused: " ++ message)
    case Done{unit}: max_kept_core(label,state,lit,sidecar,Raw.world_image(world))
def near_max(result:C.World & K.Sidecar & Result<&2,&2,String,Unit>) -> IO(Unit):
  (world,sidecar,status) = result
  match status:
    case Fail{message}: IO.die(Unit,3,"MAX-1 teardown refused: " ++ message)
    case Done{unit}: accepted_core_count(Incarnation.maximum(),sidecar,Raw.world_image(world))

# Registry IDs are explicitly synthetic fixture IDs. Production ray picking
# still performs the actual Registry lookup and authoritative Core read. The
# three admitted furnace outlines are grounded separately in the pinned JAR.
def ray_edited(result:G.Engine & K.Sidecar & BI.Outcome) -> IO(Unit):
  (G.Engine{world,registry},sidecar,BI.Outcome{changed,message}) = result
  do IO<Unit>:
    guard("actual ray callback accepts exactly one furnace break",changed && String.eq(message,""))
    accepted_core(sidecar,Raw.world_image(world))

def ray_picked(sidecar:K.Sidecar,result:G.Engine & Result<&2,&2,String,Maybe<&2,BI.Hit>>) -> IO(Unit):
  (engine,status) = result
  match status:
    case Fail{message}: IO.die(Unit,3,"actual furnace ray refused: " ++ message)
    case Done{None{}}: IO.die(Unit,3,"actual furnace ray missed")
    case Done{Some{+hit}}:
      match hit:
        case BI.Hit{point,1,BI.South{},Movement.Vec3{Double.F64{x,0},Double.F64{y,0},Double.F64{z,0}},False{}}:
          do IO<Unit>:
            guard("actual DDA and pinned full cube outline select furnace south face",B.equal_position(point,position(0)) &&
              U32.is_eq(x,1071644672) && U32.is_eq(y,1071644672) && U32.is_eq(z,1072693248))
            ray_edited(BI.break_block_with_owner(K.Sidecar,E.edit,sidecar,BI.Authority{C.Player{17},19n,True{}},engine,hit))
        case _: IO.die(Unit,3,"actual furnace ray returned wrong position/state/face/point")

def ray_registry(world:C.World,result:Result<&2,&1,Registry.Error,Registry.Registry>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,3,"synthetic furnace registry refused")
    case Done{registry}:
      +half = Double.from_f32(0.5)
      ray_picked(sidecar(1,[]),BI.pick(G.Engine{world,registry},Movement.Vec3{half,half,Double.from_f32(2.5)},
        Movement.Vec3{half,half,Double.from_f32(F32.neg(2.5))}))

def ray_break(world:C.World) -> IO(Unit):
  ray_registry(world,Registry.Registry.parse("block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n0\tminecraft:air\t0\t1\t0\t[]\n1\tminecraft:furnace\t1\t2\t1\t[{\"name\":\"lit\",\"values\":[\"false\",\"true\"]}]\n2\tminecraft:smoker\t3\t1\t3\t[]\n"))

def main() -> IO(Unit):
  do IO<Unit>:
    initial(world => refused_ready(0,Raw.world_image(world)))
    initial(world => refused_ready(1,Raw.world_image(world)))
    initial(world => refused_ready(2,Raw.world_image(world)))
    initial(world => refused_ready(3,Raw.world_image(world)))
    initial(world => refused_ready(4,Raw.world_image(world)))
    initial(world => refused_ready(5,Raw.world_image(world)))
    initial(world => refused_ready(6,Raw.world_image(world)))
    initial(world => accepted(E.player_edit(world,sidecar(1,[]),C.Player{17},position(0),0,7n,19n,True{})))
    guard("pinned furnace outline families admitted while campfire remains unsupported",BI.supported_cube("minecraft:furnace") &&
      BI.supported_cube("minecraft:smoker") && BI.supported_cube("minecraft:blast_furnace") && Bool.not(BI.supported_cube("minecraft:campfire")))
    initial(ray_break)
    guard("incarnation limit is exact native MAX48",String.eq(Nat.show(Incarnation.maximum()),"281474976710655"))
    initial(world => max_refusal(0,Raw.world_image(world)))
    initial(world => max_refusal(1,Raw.world_image(world)))
    initial(world => max_refusal(2,Raw.world_image(world)))
    initial(world => max_refusal(3,Raw.world_image(world)))
    initial(world => max_refusal(4,Raw.world_image(world)))
    initial(world => max_refusal(5,Raw.world_image(world)))
    initial(world => max_kept("MAX identical block accepts actual edit without resetting physical owner",1,False{},
      E.player_edit(world,counted_sidecar(1,Incarnation.maximum(),[]),C.Player{17},position(0),1,7n,19n,True{})))
    initial(world => max_kept("MAX LIT update accepts without resetting physical owner",2,True{},
      E.player_edit(world,counted_sidecar(1,Incarnation.maximum(),[]),C.Player{17},position(0),2,7n,19n,True{})))
    initial(world => near_max(E.player_edit(world,counted_sidecar(1,Nat.sub(Incarnation.maximum(),1n),[]),C.Player{17},position(0),0,7n,19n,True{})))
