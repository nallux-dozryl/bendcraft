import Base
import ./player_cooking_menu.bend as Menu
import ./player_cooking_menu_transfer.bend as Move
import ./player_inventory.bend as I
import ./player_inventory_return.bend as R
import ./inventory.bend as Inv
import ./campfire_authority.bend as CA
import ./campfire_authority_items.bend as AI
import ./cooking_world.bend as CW
import ./cooking_world_slots.bend as Slots
import ./cooking_recipe.bend as K
import ./core.bend as C
import ./player_core_edit.bend as Player
import ./nbt.bend as N

# A campfire has no GUI. This instant world action consumes only the actual
# selected main slot or actual offhand; saved instabuild is its only source
# creation authority. Slot dispatch rechecks the sole Core and campfire owner.
def held_index(+snapshot:I.MenuSnapshot,+offhand:Bool) -> U32:
  N.choose(U32,40,Menu.selection(snapshot),offhand)
def infinite(snapshot:I.MenuSnapshot) -> Bool:
  I.MenuSnapshot{I.Persisted{I.Snapshot{selected,main,I.Abilities{creative,maybuild}},equipment,status},craft,carried,result,opened,revision} = snapshot
  creative
def closed(snapshot:I.MenuSnapshot) -> Bool:
  I.MenuSnapshot{saved,craft,carried,result,opened,revision} = snapshot
  Bool.not(opened)
def authorized(+snapshot:I.MenuSnapshot,+access:Menu.Access,+position:C.Position) -> Bool:
  Menu.Access{capability,may_interact,dimension,eye,range,token} = access
  I.menu_snapshot_valid(snapshot) && closed(snapshot) && may_interact &&
    Maybe.is_some(&2,U32,Player.player_peer(capability)) && String.eq(dimension,C.dimension(position)) && Menu.in_range(position,eye,range,0)
def slot_equal(+left:Inv.Slot,+right:Inv.Slot) -> Bool:
  match left right:
    case Inv.InvEmpty{} Inv.InvEmpty{}: True{}
    case Inv.InvStack{a,n} Inv.InvStack{b,m}: Inv.key_equal(a,b) && U32.is_eq(n,m)
    case _ _: False{}
def placed(owner_result:CW.State & Result<&2,&2,CW.Error,Slots.Receipt>,inventory:I.State,+old:I.MenuSnapshot,+index:U32) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  (owner,status) = owner_result
  match status:
    case Fail{error}: (owner,inventory,Done{Menu.reply(False{},"cooking-menu:campfire-placement-refused",Menu.Closed{},None{},old,[])})
    case Done{Slots.Receipt{previous,AI.Input{+remaining,patch},slot,effects}}:
      +values = R.replace(I.menu_slots(old),U32.to_nat(index),remaining)
      +changed = Bool.not(slot_equal(R.at(I.menu_slots(old),U32.to_nat(index)),remaining))
      (owner,Menu.published(inventory,values,changed),Done{Menu.reply(True{},"",Menu.Closed{},None{},Menu.projected(old,values,changed),effects)})
def publish_dispatch(+context:CW.Context,owner:CW.State,inventory:I.State,+position:C.Position,+access:Menu.Access,+old:I.MenuSnapshot,+index:U32,+held:AI.Input) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  Menu.Access{capability,may_interact,dimension,eye,range,token} = access
  placed(Slots.dispatch(context,owner,position,Slots.CampfirePlace{held,infinite(old)},capability,may_interact),inventory,old,index)
def admitted(admission:Result<&2,&2,String,Unit>,+context:CW.Context,owner:CW.State,inventory:I.State,+position:C.Position,+access:Menu.Access,+old:I.MenuSnapshot,+index:U32,+held:AI.Input) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match admission:
    case Fail{message}: (owner,inventory,Done{Menu.reply(False{},message,Menu.Closed{},None{},old,[])})
    case Done{unit}: publish_dispatch(context,owner,inventory,position,access,old,index,held)
def retained_slot(input:AI.Input) -> Inv.Slot:
  AI.Input{slot,patch} = input
  slot
def hand_pass(message:String) -> Bool: String.eq(message,"cooking-menu:campfire-hand-pass")
def supported(context:CW.Context) -> Bool:
  CW.Context{bindings,AI.Context{K.Catalog{recipes,tags,items},defaults,features},fuel,depth} = context
  AI.supported(recipes)
def selected(+context:CW.Context,+held:AI.Input) -> Result<&2,&2,String,Maybe<&2,K.Plan>>:
  do Result<&2,&2,String,Maybe<&2,K.Plan>>:
    AI.guarded(supported(context),"cooking-menu:unsupported-campfire-recipe-domain")
    AI.select(CW.recipes(context),None{},held)
def input_admitted(result:Result<&2,&2,String,Maybe<&2,K.Plan>>,admit:Menu.Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,owner:CW.State,inventory:I.State,+position:C.Position,+access:Menu.Access,+old:I.MenuSnapshot,+index:U32,+held:AI.Input) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match result:
    case Fail{message}: (owner,inventory,Done{Menu.reply(False{},message,Menu.Closed{},None{},old,[])})
    case Done{None{}}: (owner,inventory,Done{Menu.reply(False{},"cooking-menu:campfire-hand-pass",Menu.Closed{},None{},old,[])})
    case Done{Some{plan}}:
      +remaining = retained_slot(CA.retained(held,infinite(old)))
      +values = R.replace(I.menu_slots(old),U32.to_nat(index),remaining)
      admitted(admit(Menu.reply(True{},"",Menu.Closed{},None{},Menu.projected(old,values,Bool.not(infinite(old))),[])),context,owner,inventory,position,access,old,index,held)
def input_ready(result:Result<&2,&2,String,AI.Input>,admit:Menu.Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,owner:CW.State,inventory:I.State,+position:C.Position,+access:Menu.Access,+old:I.MenuSnapshot,+index:U32) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match result:
    case Fail{message}: (owner,inventory,Done{Menu.reply(False{},message,Menu.Closed{},None{},old,[])})
    case Done{+held}: input_admitted(selected(context,held),admit,context,owner,inventory,position,access,old,index,held)
def allowed(allowed:Bool,admit:Menu.Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,owner:CW.State,inventory:I.State,+position:C.Position,+access:Menu.Access,+old:I.MenuSnapshot,+offhand:Bool) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match allowed:
    case False{}: (owner,inventory,Done{Menu.reply(False{},"cooking-menu:campfire-world-authority-refused",Menu.Closed{},None{},old,[])})
    case True{}: input_ready(Move.input(context,R.at(I.menu_slots(old),U32.to_nat(held_index(old,offhand)))),admit,context,owner,inventory,position,access,old,held_index(old,offhand))
def inspected(result:I.State & I.MenuSnapshot,admit:Menu.Reply -> Result<&2,&2,String,Unit>,context:CW.Context,owner:CW.State,+position:C.Position,+access:Menu.Access,offhand:Bool) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  (inventory,+old) = result
  allowed(authorized(old,access,position),admit,context,owner,inventory,position,access,old,offhand)
def use(admit:Menu.Reply -> Result<&2,&2,String,Unit>,context:CW.Context,owner:CW.State,inventory:I.State,position:C.Position,access:Menu.Access,offhand:Bool) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  inspected(I.menu_inspect(inventory),admit,context,owner,position,access,offhand)

# Resolve the real two hands before any publication. A valid non-campfire main
# hand passes to the actual offhand in the same owner/target/access transaction;
# security, component, unsupported-domain and placement refusals do not pass.
def twohand_selected(result:Result<&2,&2,String,Maybe<&2,K.Plan>>,admit:Menu.Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,owner:CW.State,inventory:I.State,+position:C.Position,+access:Menu.Access,+old:I.MenuSnapshot,+held:AI.Input) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match result:
    case Done{None{}}:
      input_ready(Move.input(context,R.at(I.menu_slots(old),40n)),admit,context,owner,inventory,position,access,old,40)
    case Fail{message}:
      input_admitted(Fail{message},admit,context,owner,inventory,position,access,old,held_index(old,False{}),held)
    case Done{Some{plan}}:
      input_admitted(Done{Some{plan}},admit,context,owner,inventory,position,access,old,held_index(old,False{}),held)
def twohand_ready(result:Result<&2,&2,String,AI.Input>,admit:Menu.Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,owner:CW.State,inventory:I.State,+position:C.Position,+access:Menu.Access,+old:I.MenuSnapshot) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match result:
    case Fail{message}: (owner,inventory,Done{Menu.reply(False{},message,Menu.Closed{},None{},old,[])})
    case Done{+held}: twohand_selected(selected(context,held),admit,context,owner,inventory,position,access,old,held)
def twohand_allowed(allowed:Bool,admit:Menu.Reply -> Result<&2,&2,String,Unit>,+context:CW.Context,owner:CW.State,inventory:I.State,+position:C.Position,+access:Menu.Access,+old:I.MenuSnapshot) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match allowed:
    case False{}: (owner,inventory,Done{Menu.reply(False{},"cooking-menu:campfire-world-authority-refused",Menu.Closed{},None{},old,[])})
    case True{}:
      twohand_ready(Move.input(context,R.at(I.menu_slots(old),U32.to_nat(held_index(old,False{})))),admit,context,owner,inventory,position,access,old)
def twohand_inspected(result:I.State & I.MenuSnapshot,admit:Menu.Reply -> Result<&2,&2,String,Unit>,context:CW.Context,owner:CW.State,+position:C.Position,+access:Menu.Access) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  (inventory,+old) = result
  twohand_allowed(authorized(old,access,position),admit,context,owner,inventory,position,access,old)
def use_hands(admit:Menu.Reply -> Result<&2,&2,String,Unit>,context:CW.Context,owner:CW.State,inventory:I.State,position:C.Position,access:Menu.Access) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  twohand_inspected(I.menu_inspect(inventory),admit,context,owner,position,access)
