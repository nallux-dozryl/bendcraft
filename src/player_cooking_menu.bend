import Base
import ./core.bend as C
import ./block_light_world.bend as W
import ./block_light.bend as L
import ./campfire_authority_items.bend as AI
import ./cooking_world.bend as CW
import ./cooking_world_store.bend as Store
import ./cooking_world_bindings.bend as Binding
import ./cooking_world_slots.bend as Slots
import ./cooking_recipe.bend as K
import ./furnace_authority.bend as FA
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D
import ./player_inventory_return.bend as Return
import ./player_cooking_menu_transfer.bend as Transfer
import ./player_core_edit.bend as Player
import ./movement.bend as M
import ./f64.bend as F
import ./nbt.bend as N

# Server metadata only. The actual Core, cooking store and player Array remain
# in their existing sole owners. Incarnation changes on accepted OwnerReset;
# neither a matching block kind nor a global Core revision is owner identity.
type Handle is Data:
  Closed{}
  Furnace{menu:U32,peer:U32,position:C.Position,block:String,kind:K.CookingKind,incarnation:Nat}
type Access is Data:
  Access{capability:C.Capability,may_interact:Bool,dimension:String,eye:M.Vec3,
    block_range:F.F64,incarnation:Nat}
type Action is Data:
  MenuInspect{menu:U32}
  MenuPickup{menu:U32,index:U32,button:U32}
  MenuQuickMove{menu:U32,index:U32}
  MenuClose{menu:U32}
type FurnaceView is Data:
  FurnaceView{kind:K.CookingKind,slots:K.FurnaceSlots,lit_remaining:U32,
    lit_total:U32,cooking_spent:U32,cooking_total:U32}
type Snapshot is Data:
  Snapshot{handle:Handle,furnace:Maybe<&2,FurnaceView>,inventory:I.MenuSnapshot}
type Reply is Data:
  Reply{accepted:Bool,message:String,snapshot:Snapshot,effects:List<&2,Store.Effect>}
type Live is Data:
  Live{binding:Binding.Binding,snapshot:FA.Snapshot}

def view(+snapshot:FA.Snapshot) -> FurnaceView:
  FA.Snapshot{FA.Frame{kind,r,t,s,c,speed,cached,uses},slots} = snapshot
  FurnaceView{kind,slots,r,t,s,c}

def outside(+value:F.F64,+lower:F.F64,+upper:F.F64) -> F.F64:
  N.choose(F.F64,F.sub(lower,value),N.choose(F.F64,F.sub(value,upper),F.F64{0,0},F.is_gt(value,upper)),F.is_lt(value,lower))

def squared(+value:F.F64) -> F.F64: F.mul(value,value)

def capability_matches(+expected:U32,+peer:Maybe<&2,U32>) -> Bool:
  match peer:
    case None{}: False{}
    case Some{value}: U32.is_eq(expected,value)

def inspected_entry(+state:U32,result:Store.Entry & Result<&2,&2,String,Store.View>,rest:List<&1,Store.Entry>) ->
    List<&1,Store.Entry> & Result<&2,&2,String,Live>:
  (entry,status) = result
  match status:
    case Fail{message}: (entry <> rest,Fail{message})
    case Done{Store.View{position,Binding.Binding{+id,+block,+family,+lit,+dark,+bright},body,removal}}:
      match family body:
        case Binding.Furnace{kind} Store.FurnaceView{snapshot}:
          (entry <> rest,N.choose(Result<&2,&2,String,Live>,Done{Live{Binding.Binding{id,block,family,lit,dark,bright},snapshot}},
            Fail{"cooking-menu:entity-state-mismatch"},U32.is_eq(state,id)))
        case _ _: (entry <> rest,Fail{"cooking-menu:target-has-no-furnace-menu"})

def skipped(entry:Store.Entry,result:List<&1,Store.Entry> & Result<&2,&2,String,Live>) ->
    List<&1,Store.Entry> & Result<&2,&2,String,Live>:
  (rest,status) = result
  (entry <> rest,status)

def found(world:W.State,result:List<&1,Store.Entry> & Result<&2,&2,String,Live>) -> CW.State & Result<&2,&2,String,Live>:
  (entries,status) = result
  (CW.State{world,entries,CW.Idle{},[]},status)

def reply(+accepted:Bool,+message:String,+handle:Handle,+furnace:Maybe<&2,FurnaceView>,+inventory:I.MenuSnapshot,+effects:List<&2,Store.Effect>) -> Reply:
  Reply{accepted,message,Snapshot{handle,furnace,inventory},effects}

def projected(+snapshot:I.MenuSnapshot,+slots:List<&2,Inv.Slot>,+changed:Bool) -> I.MenuSnapshot:
  I.MenuSnapshot{I.Persisted{I.Snapshot{selected,main,abilities},equipment,status},craft,carried,result,opened,+revision} = snapshot
  I.MenuSnapshot{I.Persisted{I.Snapshot{selected,List.take(&2,Inv.Slot,slots,36n),abilities},
    List.take(&2,Inv.Slot,Return.skip(36n,slots),7n),status},
    List.take(&2,Inv.Slot,Return.skip(43n,slots),4n),Return.at(slots,47n),
    N.choose(Maybe<&2,Inv.Slot>,None{},result,changed),opened,N.choose(Nat,1n+revision,revision,changed)}

def publish_revision(inventory:I.State,+changed:Bool) -> I.State:
  match changed:
    case False{}: inventory
    case True{}: I.revised(inventory)

def catalog(+context:CW.Context) -> K.Catalog:
  CW.Context{bindings,AI.Context{recipes,defaults,features},fuel,depth} = context
  recipes

def chosen_plan(+context:CW.Context,+old:FA.Snapshot,+snapshot:I.MenuSnapshot,+catalog:D.Catalog,+action:Action) -> Transfer.Plan:
  match action:
    case MenuPickup{menu,index,button}: Transfer.clicked(context,old,I.menu_slots(snapshot),catalog,index,button)
    case MenuQuickMove{menu,index}: Transfer.quick_move(context,old,I.menu_slots(snapshot),catalog,index)
    case _: Transfer.unchanged(old,I.menu_slots(snapshot),catalog)

def matching(+handle:Handle,+binding:Binding.Binding,+snapshot:FA.Snapshot) -> Bool:
  match handle binding snapshot:
    case Furnace{menu,peer,position,name,expected,token} Binding.Binding{state,block,family,lit,dark,bright} FA.Snapshot{FA.Frame{kind,r,t,s,c,speed,cached,uses},slots}:
      String.eq(name,block) && K.kind_equal(kind,expected)
    case _ _ _: False{}

def action_menu(+action:Action) -> U32:
  match action:
    case MenuInspect{menu}: menu
    case MenuPickup{menu,index,button}: menu
    case MenuQuickMove{menu,index}: menu
    case MenuClose{menu}: menu

def result(+snapshot:I.MenuSnapshot) -> Maybe<&2,Inv.Slot>:
  I.MenuSnapshot{saved,craft,carried,value,opened,revision} = snapshot
  value

def dirty(+handle:Handle) -> List<&2,Store.Effect>:
  match handle:
    case Closed{}: []
    case Furnace{menu,peer,position,block,kind,token}: [Store.Dirty{position}]

def opened_projected(+opened:Bool,+snapshot:I.MenuSnapshot) -> I.MenuSnapshot:
  I.MenuSnapshot{saved,craft,carried,result,previous,revision} = snapshot
  I.MenuSnapshot{saved,craft,carried,None{},opened,revision}

def selection(+snapshot:I.MenuSnapshot) -> U32:
  I.MenuSnapshot{I.Persisted{I.Snapshot{selected,main,abilities},equipment,status},craft,carried,result,opened,revision} = snapshot
  selected

def kind(+snapshot:FA.Snapshot) -> K.CookingKind:
  FA.Snapshot{FA.Frame{value,r,t,s,c,speed,cached,uses},slots} = snapshot
  value
def in_range(+position:C.Position,+eye:M.Vec3,+range:F.F64,+buffer:U32) -> Bool:
  C.Position{dimension,x,y,z} = position
  M.Vec3{+ex,+ey,+ez} = eye
  +a = F.from_i32(x)
  +b = F.from_i32(y)
  +c = F.from_i32(z)
  +reach = F.add(range,F.from_u32(buffer))
  F.is_finite(ex) && F.is_finite(ey) && F.is_finite(ez) && F.is_finite(range) &&
    F.is_gt(reach,F.F64{0,0}) && F.is_lt(F.add(F.add(squared(outside(ex,a,F.add(a,F.from_u32(1)))),
      squared(outside(ey,b,F.add(b,F.from_u32(1))))),squared(outside(ez,c,F.add(c,F.from_u32(1))))),squared(reach))

def denied(owner:CW.State,result:I.State & I.MenuSnapshot,+handle:Handle,+message:String) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  (inventory,snapshot) = result
  (owner,inventory,Done{reply(False{},message,handle,None{},snapshot,[])})

def published(inventory:I.State,+slots:List<&2,Inv.Slot>,+changed:Bool) -> I.State:
  I.State{owned,selected,abilities,profile} = inventory
  publish_revision(I.State{I.write_returned(slots,0,owned),selected,abilities,profile},changed)

def opened_snapshot(+old:I.MenuSnapshot,+slots:List<&2,Inv.Slot>,+opened:Bool) -> I.MenuSnapshot:
  +changed = Bool.not(I.temporary_empty(old)) || Maybe.is_some(&2,Inv.Slot,result(old))
  opened_projected(opened,projected(old,slots,changed))

def closed_observed(owner:CW.State,+handle:Handle,+furnace:Maybe<&2,FurnaceView>,+opened:Bool,result:I.State & I.MenuSnapshot) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  (inventory,snapshot) = result
  (owner,inventory,Done{reply(True{},"",handle,furnace,snapshot,[])})

def close_authority(+previous:Handle,+access:Access,+menu:U32) -> Bool:
  match previous:
    case Closed{}: False{}
    case Furnace{id,peer,position,block,kind,incarnation}:
      Access{capability,may_interact,dimension,eye,range,token} = access
      U32.is_eq(id,menu) && capability_matches(peer,Player.player_peer(capability))

def find_chosen(+hit:Bool,+context:CW.Context,+state:U32,head:Store.Entry,rest:List<&1,Store.Entry>,next:List<&1,Store.Entry> -> List<&1,Store.Entry> & Result<&2,&2,String,Live>) -> List<&1,Store.Entry> & Result<&2,&2,String,Live>:
  match hit:
    case True{}: inspected_entry(state,Store.inspect_entry(catalog(context),head),rest)
    case False{}: skipped(head,next(rest))

def admitted(+handle:Handle,+access:Access,+menu:U32) -> Bool:
  match handle:
    case Closed{}: False{}
    case Furnace{id,peer,+position,block,kind,token}:
      Access{capability,may_interact,dimension,eye,range,incarnation} = access
      may_interact && U32.is_eq(menu,id) && Nat.is_eq(token,incarnation) &&
        capability_matches(peer,Player.player_peer(capability)) &&
        String.eq(dimension,C.dimension(position)) && in_range(position,eye,range,4)

def find(+left:Nat,+context:CW.Context,+position:C.Position,+state:U32,entries:List<&1,Store.Entry>) ->
    List<&1,Store.Entry> & Result<&2,&2,String,Live>:
  match left entries:
    case 0n entries: (entries,Fail{"cooking-menu:missing-owner"})
    case _ Nil{}: ([],Fail{"cooking-menu:missing-owner"})
    case 1n+n Store.Entry{+candidate,binding,entity} <> rest:
      find_chosen(Binding.equal_position(candidate,position),context,state,Store.Entry{candidate,binding,entity},rest,rest => find(n,context,position,state,rest))

def committed(inventory:I.State,+handle:Handle,+old:FA.Snapshot,+snapshot:I.MenuSnapshot,+plan:Transfer.Plan,
    result:CW.State & Result<&2,&2,CW.Error,Slots.Receipt>) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  Transfer.Plan{+next,+slots,command,before,after,valid,+changed,message} = plan
  (owner,status) = result
  match status:
    case Fail{error}: (owner,inventory,Done{reply(False{},"cooking-menu:slot-publication-refused",handle,Some{view(old)},snapshot,[])})
    case Done{Slots.Receipt{previous,remaining,index,+effects}}:
      (owner,published(inventory,slots,changed),Done{reply(True{},"",handle,Some{view(next)},projected(snapshot,slots,changed),
        List.append(&2,Store.Effect,effects,dirty(handle)))})

def closed_actual(owner:CW.State,+previous:Handle,+next:Handle,+furnace:Maybe<&2,FurnaceView>,+old:I.MenuSnapshot,+opened:Bool,result:I.State & Result<&2,&2,String,Unit>) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  (inventory,status) = result
  match status:
    case Fail{message}: (owner,inventory,Done{reply(False{},message,previous,None{},old,[])})
    case Done{unit}: closed_observed(owner,next,furnace,opened,I.menu_inspect(I.menu_set(inventory,opened)))

def sized(+context:CW.Context,+position:C.Position,+state:U32,world:W.State,result:List<&1,Store.Entry> & Nat) -> CW.State & Result<&2,&2,String,Live>:
  (entries,count) = result
  found(world,find(1n+count,context,position,state,entries))

def command_commit(+context:CW.Context,owner:CW.State,inventory:I.State,+handle:Handle,+old:FA.Snapshot,+snapshot:I.MenuSnapshot,+plan:Transfer.Plan,+next:FA.Snapshot,+slots:List<&2,Inv.Slot>,+changed:Bool,+capability:C.Capability,+may_interact:Bool,+command:Maybe<&2,Slots.Command>) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  match handle command:
    case _ None{}:
      (owner,published(inventory,slots,changed),Done{reply(True{},"",handle,Some{view(next)},projected(snapshot,slots,changed),[])})
    case Furnace{menu,peer,position,block,kind,incarnation} Some{command}:
      committed(inventory,handle,old,snapshot,plan,Slots.dispatch(context,owner,position,command,capability,may_interact))
    case Closed{} _:
      (owner,inventory,Done{reply(False{},"cooking-menu:closed",handle,Some{view(old)},snapshot,[])})

def returned_admitted(owner:CW.State,inventory:I.State,+previous:Handle,+next:Handle,+furnace:Maybe<&2,FurnaceView>,+old:I.MenuSnapshot,+opened:Bool,
    +admission:Result<&2,&2,String,Unit>) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  match admission:
    case Fail{message}: (owner,inventory,Done{reply(False{},message,previous,None{},old,[])})
    case Done{unit}: closed_actual(owner,previous,next,furnace,old,opened,I.menu_close(inventory))

def block_read(+context:CW.Context,+position:C.Position,light:L.State,+loading:Maybe<&2,W.Cursor>,entries:List<&1,Store.Entry>,result:C.World & Result<&2,&2,C.Error,U32>) -> CW.State & Result<&2,&2,String,Live>:
  (world,status) = result
  match status:
    case Fail{error}: (CW.State{W.State{world,light,loading},entries,CW.Idle{},[]},Fail{"cooking-menu:target-unavailable"})
    case Done{state}: sized(context,position,state,W.State{world,light,loading},Store.size(entries))

def commit_planned(+context:CW.Context,+access:Access,owner:CW.State,inventory:I.State,+handle:Handle,+old:FA.Snapshot,+snapshot:I.MenuSnapshot,+plan:Transfer.Plan) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  Access{capability,may_interact,dimension,eye,range,token} = access
  Transfer.Plan{+next,+slots,command,before,after,valid,+changed,message} = plan
  command_commit(context,owner,inventory,handle,old,snapshot,plan,next,slots,changed,capability,may_interact,command)

def return_allowed(+allowed:Bool,admit:Reply -> Result<&2,&2,String,Unit>,owner:CW.State,inventory:I.State,+previous:Handle,+next:Handle,+furnace:Maybe<&2,FurnaceView>,+old:I.MenuSnapshot,+opened:Bool,+plan:Return.Plan) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  match allowed:
    case False{}: (owner,inventory,Done{reply(False{},"cooking-menu:close-needs-real-drop-owner",previous,None{},old,[])})
    case True{}:
      returned_admitted(owner,inventory,previous,next,furnace,old,opened,
        admit(reply(True{},"",next,furnace,opened_snapshot(old,Return.slots(plan),opened),[])))

def live(+context:CW.Context,owner:CW.State,+position:C.Position) -> CW.State & Result<&2,&2,String,Live>:
  match owner:
    case CW.State{world,entries,CW.Cooking{tick,effects},keys}:
      (CW.State{world,entries,CW.Cooking{tick,effects},keys},Fail{"cooking-menu:tick-in-progress"})
    case CW.State{world,entries,CW.Idle{},key <> rest}:
      (CW.State{world,entries,CW.Idle{},key <> rest},Fail{"cooking-menu:bootstrap-in-progress"})
    case CW.State{W.State{world,light,Some{cursor}},entries,CW.Idle{},Nil{}}:
      (CW.State{W.State{world,light,Some{cursor}},entries,CW.Idle{},[]},Fail{"cooking-menu:light-loading"})
    case CW.State{W.State{world,light,loading},entries,CW.Idle{},Nil{}}:
      block_read(context,position,light,loading,entries,C.read_block(world,position))

def preflighted(+context:CW.Context,+access:Access,owner:CW.State,inventory:I.State,+handle:Handle,+old:FA.Snapshot,+snapshot:I.MenuSnapshot,
    +plan:Transfer.Plan,+admission:Result<&2,&2,String,Unit>) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  match admission:
    case Fail{message}: (owner,inventory,Done{reply(False{},message,handle,Some{view(old)},snapshot,[])})
    case Done{unit}: commit_planned(context,access,owner,inventory,handle,old,snapshot,plan)

def return_planned(admit:Reply -> Result<&2,&2,String,Unit>,owner:CW.State,inventory:I.State,+previous:Handle,+next:Handle,+furnace:Maybe<&2,FurnaceView>,+old:I.MenuSnapshot,+opened:Bool,+plan:Return.Plan) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  return_allowed(Return.admitted(plan),admit,owner,inventory,previous,next,furnace,old,opened,plan)

def planned(admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,+access:Access,owner:CW.State,inventory:I.State,+handle:Handle,+old:FA.Snapshot,+snapshot:I.MenuSnapshot,+plan:Transfer.Plan) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  Transfer.Plan{+next,+slots,command,before,after,+valid,+changed,message} = plan
  match valid:
    case False{}: (owner,inventory,Done{reply(False{},message,handle,Some{view(old)},snapshot,[])})
    case True{}:
      preflighted(context,access,owner,inventory,handle,old,snapshot,plan,
        admit(reply(True{},"",handle,Some{view(next)},projected(snapshot,slots,changed),[])))

def return_catalog(admit:Reply -> Result<&2,&2,String,Unit>,owner:CW.State,+previous:Handle,+next:Handle,+furnace:Maybe<&2,FurnaceView>,+old:I.MenuSnapshot,+opened:Bool,
    result:I.State & D.Catalog) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  (inventory,catalog) = result
  return_planned(admit,owner,inventory,previous,next,furnace,old,opened,Return.plan(I.menu_slots(old),selection(old),catalog))

def with_catalog(admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,+access:Access,owner:CW.State,+handle:Handle,+old:FA.Snapshot,+snapshot:I.MenuSnapshot,+action:Action,
    result:I.State & D.Catalog) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  (inventory,catalog) = result
  planned(admit,context,access,owner,inventory,handle,old,snapshot,chosen_plan(context,old,snapshot,catalog,action))

def open_peer(admit:Reply -> Result<&2,&2,String,Unit>,inventory:I.State,+previous:Handle,+access:Access,+position:C.Position,+menu:U32,+snapshot:I.MenuSnapshot,
    result:CW.State & Result<&2,&2,String,Live>,+peer:Maybe<&2,U32>) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  Access{capability,may_interact,dimension,eye,range,+token} = access
  (owner,status) = result
  match status peer:
    case Fail{message} _: (owner,inventory,Done{reply(False{},message,previous,None{},snapshot,[])})
    case Done{Live{Binding.Binding{state,block,family,lit,dark,bright},+furnace}} Some{peer}:
      return_catalog(admit,owner,previous,Furnace{menu,peer,position,block,kind(furnace),token},Some{view(furnace)},snapshot,True{},I.definitions(inventory))
    case _ None{}: (owner,inventory,Done{reply(False{},"cooking-menu:player-capability-required",previous,None{},snapshot,[])})

def close_allowed(+allowed:Bool,admit:Reply -> Result<&2,&2,String,Unit>,owner:CW.State,inventory:I.State,+handle:Handle,+snapshot:I.MenuSnapshot) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  match allowed:
    case False{}: (owner,inventory,Done{reply(False{},"cooking-menu:wrong-close-owner",handle,None{},snapshot,[])})
    case True{}: return_catalog(admit,owner,handle,Closed{},None{},snapshot,False{},I.definitions(inventory))

def owner_matched(+matched:Bool,admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,+access:Access,owner:CW.State,inventory:I.State,+handle:Handle,+old:FA.Snapshot,+snapshot:I.MenuSnapshot,+action:Action) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  match matched:
    case False{}: (owner,inventory,Done{reply(False{},"cooking-menu:owner-replaced",handle,None{},snapshot,[])})
    case True{}: with_catalog(admit,context,access,owner,handle,old,snapshot,action,I.definitions(inventory))

def open_live(admit:Reply -> Result<&2,&2,String,Unit>,inventory:I.State,+previous:Handle,+access:Access,+position:C.Position,+menu:U32,+snapshot:I.MenuSnapshot,result:CW.State & Result<&2,&2,String,Live>) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  Access{capability,may_interact,dimension,eye,range,token} = access
  open_peer(admit,inventory,previous,access,position,menu,snapshot,result,Player.player_peer(capability))

def live_result(admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,+access:Access,inventory:I.State,+handle:Handle,+snapshot:I.MenuSnapshot,+action:Action,
    result:CW.State & Result<&2,&2,String,Live>) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  (owner,status) = result
  match status:
    case Fail{message}: (owner,inventory,Done{reply(False{},message,handle,None{},snapshot,[])})
    case Done{Live{binding,+old}}:
      owner_matched(matching(handle,binding,old),admit,context,access,owner,inventory,handle,old,snapshot,action)

def open_allowed(+allowed:Bool,admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,+access:Access,owner:CW.State,inventory:I.State,+previous:Handle,+position:C.Position,+menu:U32,+snapshot:I.MenuSnapshot) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  match allowed:
    case False{}: (owner,inventory,Done{reply(False{},"cooking-menu:open-authority-or-range-refused",previous,None{},snapshot,[])})
    case True{}: open_live(admit,inventory,previous,access,position,menu,snapshot,live(context,owner,position))

def slot_admitted(+allowed:Bool,admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,+access:Access,owner:CW.State,inventory:I.State,+handle:Handle,+snapshot:I.MenuSnapshot,+action:Action) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  match allowed handle:
    case False{} _: (owner,inventory,Done{reply(False{},"cooking-menu:authority-menu-range-or-incarnation-refused",handle,None{},snapshot,[])})
    case True{} Furnace{menu,peer,position,block,kind,token}:
      live_result(admit,context,access,inventory,handle,snapshot,action,live(context,owner,position))
    case True{} Closed{}: (owner,inventory,Done{reply(False{},"cooking-menu:closed",handle,None{},snapshot,[])})

def open_inspected(admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,+access:Access,owner:CW.State,+previous:Handle,+position:C.Position,+menu:U32,result:I.State & I.MenuSnapshot) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  Access{+capability,may_interact,dimension,eye,range,token} = access
  (inventory,snapshot) = result
  open_allowed(may_interact && U32.is_gt(menu,0) && Maybe.is_some(&2,U32,Player.player_peer(capability)) &&
    String.eq(dimension,C.dimension(position)) && in_range(position,eye,range,4),admit,context,access,owner,inventory,previous,position,menu,snapshot)

def dispatch_kind(+action:Action,admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,+access:Access,owner:CW.State,inventory:I.State,+handle:Handle,+snapshot:I.MenuSnapshot) -> CW.State & I.State & Result<&2,&2,String,Reply>:
  match action:
    case MenuClose{menu}:
      close_allowed(close_authority(handle,access,menu),admit,owner,inventory,handle,snapshot)
    case _:
      slot_admitted(admitted(handle,access,action_menu(action)),admit,context,access,owner,inventory,handle,snapshot,action)

def open(admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,owner:CW.State,inventory:I.State,+previous:Handle,+access:Access,+position:C.Position,+server_menu:U32) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  open_inspected(admit,context,access,owner,previous,position,server_menu,I.menu_inspect(inventory))

def dispatched(admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,+access:Access,owner:CW.State,+handle:Handle,+action:Action,result:I.State & I.MenuSnapshot) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  (inventory,snapshot) = result
  dispatch_kind(action,admit,context,access,owner,inventory,handle,snapshot)

def dispatch(admit:Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,owner:CW.State,inventory:I.State,+handle:Handle,+access:Access,+action:Action) ->
    CW.State & I.State & Result<&2,&2,String,Reply>:
  dispatched(admit,context,access,owner,handle,action,I.menu_inspect(inventory))

