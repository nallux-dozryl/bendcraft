import Base
import ../src/remote_resource_backend.bend as B
import ../src/player_crafting_session_adapter.bend as CS
import ../src/player_crafting_authority.bend as A
import ../src/player_crafting_authority_components.bend as Components
import ../src/crafting_recipe.bend as R
import ../src/player_inventory.bend as I
import ../src/inventory.bend as Inv
import ../src/player_item_catalog.bend as Catalog
import ../src/player_item_definitions.bend as D
import ../src/local_player_session.bend as S
import ../src/local_player_runtime.bend as Runtime
import ../src/local_phase_runtime.bend as X
import ../src/client_world.bend as W
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as Registry
import ../src/locomotion.bend as L
import ../src/movement.bend as Motion
import ../src/f64.bend as F
import ../src/persistence.bend as Persistence
import ../src/world_lock.bend as Lock
import ../src/world_generation_settings.bend as Generation
import ../src/json.bend as J
import ../src/section_map.bend as SectionMap
import ./core_refusal.bend as CoreImage

# These fixtures call the production Backend menu gates and Session adapter.
# The complete original64-cell inventory and whole raw Core are observed.
def cells(slots:Array<Inv.Slot>) -> Array<Inv.Slot> & List<&2,Inv.Slot>:
  match slots:
    case ALeaf{+slot}: (ALeaf{slot},[slot])
    case ANode{left,right}:
      W.paired(Array<Inv.Slot>,List<&2,Inv.Slot>,Array<Inv.Slot> & List<&2,Inv.Slot>,cells(left),left => before =>
        W.paired(Array<Inv.Slot>,List<&2,Inv.Slot>,Array<Inv.Slot> & List<&2,Inv.Slot>,cells(right),right => after =>
          (ANode{left,right},List.append(&2,Inv.Slot,before,after))))

def inventory_cells(selected:U32,abilities:I.Abilities,profile:I.Profile,length:U32,result:Array<Inv.Slot> & List<&2,Inv.Slot>) -> I.State & List<&2,Inv.Slot>:
  (slots,image) = result
  (I.State{Inv.Inventory{slots,length},selected,abilities,profile},image)

def inventory_image(state:I.State) -> I.State & List<&2,Inv.Slot>:
  I.State{Inv.Inventory{slots,length},selected,abilities,profile} = state
  inventory_cells(selected,abilities,profile,length,cells(slots))

def world_image(registry:Registry.Registry,body:Motion.Body,yaw:F32,pitch:F32,palette:Maybe<&2,W.Palette>,region:W.Bounds,cache:Maybe<&2,W.SnapshotCache>,result:C.World & CoreImage.WorldImage) -> W.State & CoreImage.WorldImage:
  (world,image) = result
  (W.State{G.Engine{world,registry},body,yaw,pitch,palette,region,cache},image)

def observed_world(state:W.State) -> W.State & CoreImage.WorldImage:
  W.State{G.Engine{world,registry},body,yaw,pitch,palette,region,cache} = state
  world_image(registry,body,yaw,pitch,palette,region,cache,CoreImage.world_image(world))

def session_world(state:S.State) -> S.State & CoreImage.WorldImage:
  S.query(CoreImage.WorldImage,state,player => X.query(CoreImage.WorldImage,player,observed_world))

# Typed observations of the actual returned owners. Wire preflight/correlation
# is tested separately by item_component_wire_transport; this fixture directly
# exercises Backend and does not import unrelated generic Frame codecs.
def number(value:U32) -> J.Value: J.JNumber{U32.show(value)}
def slot(value:Inv.Slot) -> J.Value:
  match value:
    case Inv.InvEmpty{}: J.JArray{[number(0)]}
    case Inv.InvStack{Inv.ItemKey{name,components},count}:
      J.JArray{[number(1),J.JString{name},J.JString{components},number(count)]}

def slot_values(values:List<&2,Inv.Slot>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> tail: slot(head) <> slot_values(tail)

def slots(values:List<&2,Inv.Slot>) -> J.Value: J.JArray{slot_values(values)}

def main_value(value:I.Snapshot) -> J.Value:
  I.Snapshot{selected,values,I.Abilities{instabuild,maybuild}} = value
  J.JArray{[number(selected),J.JBool{instabuild},J.JBool{maybuild},slots(values)]}

def output_value(value:Maybe<&2,Inv.Slot>) -> J.Value:
  match value:
    case None{}: J.JArray{[number(0)]}
    case Some{value}: J.JArray{[number(1),slot(value)]}

def menu_value(value:I.MenuSnapshot) -> J.Value:
  I.MenuSnapshot{I.Persisted{main,equipment,I.Status{invulnerable,mayfly,flying,walk,fly}},craft,carried,result,opened,revision} = value
  J.JArray{[main_value(main),slots(equipment),J.JArray{[J.JBool{invulnerable},J.JBool{mayfly},J.JBool{flying},number(walk),number(fly)]},slots(craft),slot(carried),output_value(result),J.JBool{opened},J.JNumber{Nat.show(revision)}]}

def cache(context:Maybe<&2,CS.Context>) -> J.Value:
  match context:
    case None{}: J.JNull{}
    case Some{CS.Context{R.Catalog{recipes,tags,items},None{},mode}}:
      J.JArray{[J.JBool{True{}},J.JNull{},J.JNumber{U32.show(U32.from_nat(List.length(&2,R.ItemDefinition,items)))}]}
    case Some{CS.Context{R.Catalog{recipes,tags,items},Some{R.Plan{id,result,R.Grid{width,height,inputs},steps}},mode}}:
      J.JArray{[J.JBool{True{}},J.JArray{[J.JString{id},slot(result),slots(inputs)]},J.JNumber{U32.show(U32.from_nat(List.length(&2,R.ItemDefinition,items)))}]}

def snapshot_value(snapshot:Maybe<&2,I.MenuSnapshot>) -> J.Value:
  match snapshot:
    case None{}: J.JNull{}
    case Some{value}: menu_value(value)

def selected_context(context:CS.Context,with_context:Bool) -> Maybe<&2,CS.Context>:
  match with_context:
    case False{}: None{}
    case True{}: Some{context}

def printed(label:String,protocol:Bool,accepted:Bool,message:String,snapshot:Maybe<&2,I.MenuSnapshot>,lease:B.Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,+context:Maybe<&2,CS.Context>,before:CoreImage.WorldImage,result:S.State & List<&2,Inv.Slot>) -> IO(B.State):
  B.Lease{epoch,+next,remaining,active} = lease
  (saved,+all) = result
  do IO<B.State>:
    CoreImage.require(Nat.is_eq(List.length(&2,Inv.Slot,all),64n),"backend lost inventory backing cells")
    IO.print(J.encode(J.JObject{[J.JMember{"label",J.JString{label}},J.JMember{"protocol",J.JBool{protocol}},J.JMember{"accepted",J.JBool{accepted}},J.JMember{"message",J.JString{message}},J.JMember{"next",J.JNumber{Nat.show(next)}},J.JMember{"cells",slots(all)},J.JMember{"context",cache(context)},J.JMember{"menu",snapshot_value(snapshot)}]}))
    return B.State{saved,B.Lease{epoch,next,remaining,active},counter,nonce,capability,owner,context}

def observed(label:String,protocol:Bool,accepted:Bool,message:String,snapshot:Maybe<&2,I.MenuSnapshot>,lease:B.Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,context:Maybe<&2,CS.Context>,+before:CoreImage.WorldImage,result:S.State & CoreImage.WorldImage) -> IO(B.State):
  (saved,after) = result
  do IO<B.State>:
    CoreImage.require(CoreImage.worlds_equal(before,after),"backend crafting changed complete raw Core")
    printed(label,protocol,accepted,message,snapshot,lease,counter,nonce,capability,owner,context,before,S.inventory_query(List<&2,Inv.Slot>,saved,inventory_image))

def reported(label:String,protocol:Bool,accepted:Bool,message:String,snapshot:Maybe<&2,I.MenuSnapshot>,before:CoreImage.WorldImage,state:B.State) -> IO(B.State):
  B.State{saved,lease,counter,nonce,capability,owner,context} = state
  observed(label,protocol,accepted,message,snapshot,lease,counter,nonce,capability,owner,context,before,session_world(saved))

def emitted(label:String,before:CoreImage.WorldImage,result:B.State & Result<&2,&2,String,B.MenuOutcome>) -> IO(B.State):
  (state,status) = result
  match status:
    case Fail{message}: reported(label,False{},False{},message,None{},before,state)
    case Done{B.MenuOutcome{accepted,message,snapshot}}: reported(label,True{},accepted,message,Some{snapshot},before,state)

def empty_slots(n:Nat) -> List<&2,Inv.Slot>:
  match n:
    case 0n: []
    case 1n+rest: Inv.InvEmpty{} <> empty_slots(rest)

def stick_catalog() -> R.Catalog:
  R.Catalog{[R.Shaped{"minecraft:stick",1,2,[R.AnyOf{[R.Item{"minecraft:oak_planks"}]},R.AnyOf{[R.Item{"minecraft:oak_planks"}]}],Inv.InvStack{Inv.ItemKey{"minecraft:stick",""},4}}],[],[R.ItemDefinition{"minecraft:oak_planks",64,Inv.InvEmpty{}},R.ItemDefinition{"minecraft:stick",64,Inv.InvEmpty{}}]}

# Deliberately incomplete service catalog reaches the post-commit refresh error:
# milk consumption returns an admitted bucket which has no recipe definition.
def refresh_failure_catalog() -> R.Catalog:
  R.Catalog{[R.Shaped{"fixture:refresh-failure",1,1,[R.AnyOf{[R.Item{"minecraft:milk_bucket"}]}],Inv.InvStack{Inv.ItemKey{"minecraft:stick",""},4}}],[],[R.ItemDefinition{"minecraft:milk_bucket",1,Inv.InvStack{Inv.ItemKey{"minecraft:bucket",""},1}},R.ItemDefinition{"minecraft:stick",64,Inv.InvEmpty{}}]}

def player(definitions:D.Catalog,inputs:List<&2,Inv.Slot>) -> I.State:
  I.State{I.write_returned(List.append(&2,Inv.Slot,Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},3} <> empty_slots(42n),List.append(&2,Inv.Slot,inputs,List.append(&2,Inv.Slot,empty_slots(16n),[Inv.InvStack{Inv.ItemKey{"minecraft:dirt",""},7}]))),0,Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),48}),7,I.Abilities{False{},True{}},I.Profile{definitions,I.default_status(),I.default_menu()}}

def session(file:File,inventory:I.State) -> S.State:
  +body:Motion.Body = Motion.Body.new(Motion.Vec3{F.from_f32(0.5),F.from_u32(1),F.from_f32(0.5)},0.6,1.8,Motion.Vec3.zero(),True{})
  world:W.State = W.State{G.Engine{CoreImage.fixture(SectionMap.EmptySections{},C.Position{"minecraft:overworld",16,32,48}),Registry.Registry{ALeaf{Registry.empty_block()},Map.new(&2,U32),1,32}},body,0.0,0.0,None{},W.Bounds{0,0,0,4,4,4},None{}}
  S.State{Runtime.fresh(world,L.Tables{ALeaf{0.25}}),S.Shell{"fixture:crafting-backend","/dev/null",13,Persistence.default_limits(),Lock.Lease{file},99,[],inventory,False{},Generation.legacy()}}

def seeded(file:File,definitions:D.Catalog,inputs:List<&2,Inv.Slot>,catalog:R.Catalog,owner:C.Capability,with_context:Bool) -> B.State:
  +context = CS.new(catalog)
  B.State{session(file,player(definitions,inputs)),B.Lease{"fixture:epoch",1n,100,True{}},5n,"fixture:nonce","fixture:token",owner,selected_context(context,with_context)}

def changed_player(state:I.State) -> I.State:
  I.State{inventory,selected,abilities,profile} = state
  I.State{I.write_returned([Inv.InvStack{Inv.ItemKey{"minecraft:oak_planks",""},3}],43,inventory),selected,abilities,profile}

def changed(result:S.State & Unit,lease:B.Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,context:Maybe<&2,CS.Context>) -> B.State:
  (saved,unit) = result
  B.State{saved,lease,counter,nonce,capability,owner,context}

def make_stale(state:B.State) -> B.State:
  B.State{saved,lease,counter,nonce,capability,owner,context} = state
  changed(S.inventory_query(Unit,saved,player => (changed_player(player),Unit{})),lease,counter,nonce,capability,owner,context)

def dispose(state:B.State) -> IO(Unit):
  B.State{S.State{player,S.Shell{identity,path,highwater,limits,Lock.Lease{file},maximum,catalog,inventory,fresh,generation}},lease,counter,nonce,capability,owner,context} = state
  File.close(file)

def sequence(+before:CoreImage.WorldImage,state:B.State) -> IO(Unit):
  do IO<Unit>:
    state:B.State <- emitted("opened",before,B.menu_open(state,"fixture:epoch",1n))
    state:B.State <- emitted("inspected",before,B.menu_inspect(state,"fixture:epoch",2n))
    state:B.State <- emitted("wrong-sequence",before,B.menu_click(state,"fixture:epoch",999n,0,I.Pickup{0}))
    state:B.State <- emitted("stale",before,B.menu_click(make_stale(state),"fixture:epoch",3n,0,I.Pickup{0}))
    state:B.State <- emitted("refreshed",before,B.menu_inspect(state,"fixture:epoch",4n))
    state:B.State <- emitted("first",before,B.menu_click(state,"fixture:epoch",5n,0,I.Pickup{1}))
    state:B.State <- emitted("second",before,B.menu_click(state,"fixture:epoch",6n,0,I.Pickup{0}))
    state:B.State <- emitted("absent",before,B.menu_click(state,"fixture:epoch",7n,0,I.Pickup{0}))
    state:B.State <- emitted("closed",before,B.menu_close(state,"fixture:epoch",8n))
    dispose(state)

def begun_mode(state:B.State,+before:CoreImage.WorldImage,mode:U32) -> IO(Unit):
  match mode:
    case 0: sequence(before,state)
    case 1:
      do IO<Unit>:
        state:B.State <- emitted("observer",before,B.menu_open(state,"fixture:epoch",1n))
        dispose(state)
    case 2:
      do IO<Unit>:
        state:B.State <- emitted("legacy-open",before,B.menu_open(state,"fixture:epoch",1n))
        state:B.State <- emitted("legacy-result",before,B.menu_click(state,"fixture:epoch",2n,0,I.Pickup{0}))
        dispose(state)
    case 4:
      do IO<Unit>:
        state:B.State <- emitted("invalid-player",before,B.menu_open(state,"fixture:epoch",1n))
        dispose(state)
    case _:
      do IO<Unit>:
        state:B.State <- emitted("failure-open",before,B.menu_open(state,"fixture:epoch",1n))
        state:B.State <- emitted("committed-refresh-failure",before,B.menu_click(state,"fixture:epoch",2n,0,I.Pickup{0}))
        dispose(state)

def begun(result:S.State & CoreImage.WorldImage,lease:B.Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,context:Maybe<&2,CS.Context>,mode:U32) -> IO(Unit):
  (saved,before) = result
  begun_mode(B.State{saved,lease,counter,nonce,capability,owner,context},before,mode)

def begin(state:B.State,mode:U32) -> IO(Unit):
  B.State{saved,lease,counter,nonce,capability,owner,context} = state
  begun(session_world(saved),lease,counter,nonce,capability,owner,context,mode)

def loaded(result:Result<&2,&2,String,D.Catalog>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{+definitions}:
      +inputs:List<&2,Inv.Slot> = [Inv.InvStack{Inv.ItemKey{"minecraft:oak_planks",""},2},Inv.InvEmpty{},Inv.InvStack{Inv.ItemKey{"minecraft:oak_planks",""},2},Inv.InvEmpty{}]
      do IO<Unit>:
        file:File <- IO.try(File,File.open("/dev/null","r"))
        begin(seeded(file,definitions,inputs,stick_catalog(),C.Player{17},True{}),0)
        file:File <- IO.try(File,File.open("/dev/null","r"))
        begin(seeded(file,definitions,inputs,stick_catalog(),C.Observer{},True{}),1)
        file:File <- IO.try(File,File.open("/dev/null","r"))
        begin(seeded(file,definitions,inputs,stick_catalog(),C.Player{0},True{}),4)
        file:File <- IO.try(File,File.open("/dev/null","r"))
        begin(seeded(file,definitions,inputs,stick_catalog(),C.Player{17},False{}),2)
        file:File <- IO.try(File,File.open("/dev/null","r"))
        begin(seeded(file,definitions,[Inv.InvStack{Inv.ItemKey{"minecraft:milk_bucket",""},1},Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{}],refresh_failure_catalog(),C.Player{17},True{}),3)

def main() -> IO(Unit):
  IO.bind(Result<&2,&2,String,D.Catalog>,Unit,Catalog.load("generated/reference_item_metadata.tsv"),loaded)
