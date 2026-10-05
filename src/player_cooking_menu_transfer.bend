import Base
import ./inventory.bend as Inv
import ./player_inventory_return.bend as R
import ./player_item_definitions.bend as D
import ./cooking_recipe.bend as K
import ./cooking_world.bend as CW
import ./cooking_world_slots.bend as Slots
import ./cooking_world_items.bend as CI
import ./furnace_authority.bend as FA
import ./furnace_authority_slots.bend as FS
import ./furnace_authority_fuel.bend as Fuel
import ./campfire_authority_items.bend as AI
import ./nbt.bend as N
import ./json.bend as J
import ./crafting_recipe_components.bend as Components
import ./cooking_block_entity_codec_components.bend as Patch

# These51 immutable planning cells observe three actual furnace slots and
# all48 actual player slots. They never allocate or own a second inventory.
type Plan is Data:
  Plan{furnace:FA.Snapshot,player:List<&2,Inv.Slot>,command:Maybe<&2,Slots.Command>,
    before:List<&2,Nat>,after:List<&2,Nat>,valid:Bool,changed:Bool,message:String}
type MovePair is Data:
  MovePair{source:Inv.Slot,destination:Inv.Slot,moved:U32}

def combined(+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>) -> List<&2,Inv.Slot>:
  FA.Snapshot{frame,K.FurnaceSlots{input,fuel,output}} = furnace
  input <> fuel <> output <> player

def equal(+a:List<&2,Inv.Slot>,+b:List<&2,Inv.Slot>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case head <> rest other <> tail: K.slot_equal(head,other) && equal(rest,tail)
    case _ _: False{}

def limit(+value:Maybe<&2,Inv.ItemMetadata>) -> U32:
  match value:
    case None{}: 0
    case Some{Inv.ItemMetadata{key,count}}: count

def counted(+key:Inv.ItemKey,+counts:Inv.CountMove) -> MovePair:
  Inv.CountMove{source,destination,+moved} = counts
  MovePair{R.slot_from_count(key,source),R.slot_from_count(key,destination),U32.from_nat(moved)}

def compatible(+source:Inv.Slot,+destination:Inv.Slot) -> Bool:
  match source destination:
    case _ Inv.InvEmpty{}: True{}
    case Inv.InvStack{a,count} Inv.InvStack{b,total}: Inv.key_equal(a,b)
    case _ _: False{}

def pickup_requested(+count:U32,+button:U32,+taking:Bool) -> U32:
  N.choose(U32,N.choose(U32,U32.div(U32.add(count,1),2),1,taking),count,U32.is_eq(button,1))

def input(+context:CW.Context,+slot:Inv.Slot) -> Result<&2,&2,String,AI.Input>:
  CW.Context{bindings,AI.Context{recipes,defaults,features},fuel,depth} = context
  match slot:
    case Inv.InvEmpty{}: Done{AI.plain()}
    case Inv.InvStack{+key,count}:
      Inv.ItemKey{id,components} = key
      do Result<&2,&2,String,AI.Input>:
        base : J.Value <- CI.initialized(Components.default_for(defaults,id))
        patch : J.Value <- Patch.patch(base,key)
        return AI.Input{slot,patch}

def place_limit(+index:U32,+value:Inv.Slot,+limit:U32) -> U32:
  N.choose(U32,1,U32.min(64,limit),U32.is_eq(index,1) && FS.is_bucket(value))

def backing(+index:U32) -> U32:
  N.choose(U32,U32.add(index,9),N.choose(U32,U32.sub(index,27),index,U32.is_ge(index,30)),U32.is_ge(index,3) && U32.is_lt(index,30))

def move_valid(+allowed:Bool,+values:List<&2,Inv.Slot>,+source:U32,+target:U32,+limit:U32,+value:Inv.Slot,+old:Inv.Slot) -> List<&2,Inv.Slot>:
  match allowed value:
    case False{} _: values
    case True{} Inv.InvEmpty{}: values
    case True{} Inv.InvStack{key,+count}:
      R.moved(values,source,target,key,Inv.move_counts(U32.to_nat(count),U32.to_nat(count),
        U32.to_nat(Inv.slot_count(old)),U32.to_nat(U32.sub(limit,Inv.slot_count(old)))))

def empty_index(+values:List<&2,Inv.Slot>,indices:List<&2,U32>) -> Maybe<&2,U32>:
  match indices:
    case Nil{}: None{}
    case +target <> rest:
      N.choose(Maybe<&2,U32>,Some{target},empty_index(values,rest),K.slot_equal(R.at(values,U32.to_nat(target)),Inv.InvEmpty{}))

def route_equal(same:Bool,next:List<&2,Inv.Slot>,continue:List<&2,Inv.Slot> -> List<&2,Inv.Slot>) -> List<&2,Inv.Slot>:
  match same:
    case True{}: next
    case False{}: continue(next)

def checked(+before:List<&2,Inv.Slot>,+after:List<&2,Inv.Slot>,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,
    +command:Maybe<&2,Slots.Command>,+catalog:D.Catalog,+allowed:Bool,+message:String) -> Plan:
  +keys = List.append(&2,Inv.ItemKey,R.keys(before),R.keys(after))
  +old = R.ledger(keys,before)
  +next = R.ledger(keys,after)
  Plan{furnace,player,command,old,next,allowed && R.counts_equal(old,next) &&
    R.valid_slots(48n,player,catalog),Bool.not(equal(before,after)),message}

def stack_limit(+catalog:D.Catalog,+slot:Inv.Slot) -> U32:
  match slot:
    case Inv.InvEmpty{}: 0
    case Inv.InvStack{key,count}: limit(D.metadata(catalog,key))

def moved(+source:Inv.Slot,+destination:Inv.Slot,+requested:U32,+room:U32) -> MovePair:
  match source:
    case Inv.InvEmpty{}: MovePair{source,destination,0}
    case Inv.InvStack{key,+count}:
      counted(key,Inv.move_counts(U32.to_nat(requested),U32.to_nat(count),
        U32.to_nat(Inv.slot_count(destination)),U32.to_nat(room)))

def ascending(+left:Nat,+index:U32) -> List<&2,U32>:
  match left:
    case 0n: []
    case 1n+n: backing(index) <> ascending(n,U32.add(index,1))

def descending(+left:Nat,+index:U32) -> List<&2,U32>:
  match left:
    case 0n: []
    case 1n+n: backing(index) <> descending(n,U32.sub(index,1))

def merge_slots(+values:List<&2,Inv.Slot>,+source:U32,+target:U32,+limit:U32,+value:Inv.Slot,+old:Inv.Slot) -> List<&2,Inv.Slot>:
  move_valid(compatible(value,old) && U32.is_lt(Inv.slot_count(old),limit),values,source,target,limit,value,old)

def route_next(+old:List<&2,Inv.Slot>,+next:List<&2,Inv.Slot>,continue:List<&2,Inv.Slot> -> List<&2,Inv.Slot>) -> List<&2,Inv.Slot>:
  route_equal(equal(old,next),next,continue)

def refused(+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+message:String) -> Plan:
  checked(combined(furnace,player),combined(furnace,player),furnace,player,None{},catalog,False{},message)

def unchanged(+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog) -> Plan:
  checked(combined(furnace,player),combined(furnace,player),furnace,player,None{},catalog,True{},"")

def merge_at(+values:List<&2,Inv.Slot>,+source:U32,+target:U32,+limit:U32) -> List<&2,Inv.Slot>:
  merge_slots(values,source,target,limit,R.at(values,U32.to_nat(source)),R.at(values,U32.to_nat(target)))

def routing_unchanged(+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+next:List<&2,Inv.Slot>) -> Plan:
  checked(combined(furnace,player),combined(furnace,next),furnace,next,None{},catalog,
    R.valid_slots(48n,player,catalog),"")

def player_checked(+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+next:List<&2,Inv.Slot>,+catalog:D.Catalog) -> Plan:
  checked(combined(furnace,player),combined(furnace,next),furnace,next,None{},catalog,
    R.valid_slots(48n,player,catalog),"")

def proposed(+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+next:List<&2,Inv.Slot>,+catalog:D.Catalog,
    +command:Slots.Command,+result:Result<&2,&2,String,Slots.Proposal>) -> Plan:
  match result:
    case Fail{message}: refused(furnace,player,catalog,message)
    case Done{Slots.Proposal{FA.Transition{+after,effects},previous,remaining,index}}:
      checked(combined(furnace,player),combined(after,next),after,next,Some{command},catalog,
        R.valid_slots(48n,player,catalog),"")

def matching_value(+values:List<&2,Inv.Slot>,+source:U32,+target:U32,+limit:U32,slot:Inv.Slot) -> List<&2,Inv.Slot>:
  match slot:
    case Inv.InvEmpty{}: values
    case _: merge_at(values,source,target,limit)

def first_target(+values:List<&2,Inv.Slot>,source:U32,limit:U32,target:Maybe<&2,U32>) -> List<&2,Inv.Slot>:
  match target:
    case None{}: values
    case Some{index}: merge_at(values,source,index,limit)

def player_moved(+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+source:U32,+target:U32,+pair:MovePair) -> Plan:
  MovePair{value,destination,count} = pair
  player_checked(furnace,player,R.replace(R.replace(player,U32.to_nat(source),value),U32.to_nat(target),destination),catalog)

def propose(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+next:List<&2,Inv.Slot>,+catalog:D.Catalog,+command:Slots.Command) -> Plan:
  proposed(furnace,player,next,catalog,command,Slots.propose(context,furnace,command))

def matching(indices:List<&2,U32>,+values:List<&2,Inv.Slot>,+source:U32,+limit:U32) -> List<&2,Inv.Slot>:
  match indices:
    case Nil{}: values
    case +target <> rest:
      matching(rest,matching_value(values,source,target,limit,R.at(values,U32.to_nat(target))),source,limit)

def first_empty(+values:List<&2,Inv.Slot>,source:U32,indices:List<&2,U32>,limit:U32) -> List<&2,Inv.Slot>:
  first_target(values,source,limit,empty_index(values,indices))

def player_pickup_compatible(+same:Bool,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32,+value:Inv.Slot,+carried:Inv.Slot) -> Plan:
  match same:
    case True{}:
      +maximum = stack_limit(catalog,carried)
      player_moved(furnace,player,catalog,47,index,moved(carried,value,
        pickup_requested(Inv.slot_count(carried),button,False{}),U32.sub(maximum,U32.min(maximum,Inv.slot_count(value)))))
    case False{}: player_checked(furnace,player,R.replace(R.replace(player,U32.to_nat(index),carried),47n,value),catalog)
def extracted_pair(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+pair:MovePair) -> Plan:
  MovePair{source,destination,count} = pair
  propose(context,furnace,player,R.replace(player,47n,destination),catalog,Slots.FurnaceTakeCount{index,count})

def put_admitted(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,
    +carried:Inv.Slot,+result:Result<&2,&2,String,AI.Input>) -> Plan:
  match result:
    case Fail{message}: refused(furnace,player,catalog,message)
    case Done{value}:
      propose(context,furnace,player,R.replace(player,47n,carried),catalog,Slots.FurnaceSet{index,value})

def route_once(+values:List<&2,Inv.Slot>,+source:U32,+indices:List<&2,U32>,+limit:U32) -> List<&2,Inv.Slot>:
  first_empty(matching(indices,values,source,limit),source,indices,limit)

def routing_source(+taking:Bool,+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+source:U32,+after:List<&2,Inv.Slot>) -> Plan:
  match taking:
    case True{}:
      FA.Snapshot{frame,slots} = furnace
      propose(context,furnace,player,R.skip(3n,after),catalog,Slots.FurnaceTakeCount{source,
        U32.sub(Inv.slot_count(FS.slot_at(slots,source)),Inv.slot_count(R.at(after,U32.to_nat(source))))})
    case False{}:
      routing_unchanged(furnace,player,catalog,R.skip(3n,after))

def routed_set(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+next:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+result:Result<&2,&2,String,AI.Input>) -> Plan:
  match result:
    case Fail{message}: refused(furnace,player,catalog,message)
    case Done{value}: propose(context,furnace,player,next,catalog,Slots.FurnaceSet{index,value})

def player_pickup_slots(+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32,+value:Inv.Slot,+carried:Inv.Slot) -> Plan:
  match carried:
    case Inv.InvEmpty{}:
      player_moved(furnace,player,catalog,index,47,moved(value,carried,
        pickup_requested(Inv.slot_count(value),button,True{}),stack_limit(catalog,value)))
    case _:
      player_pickup_compatible(compatible(carried,value),furnace,player,catalog,index,button,value,carried)

def take_checked(+allowed:Bool,+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+pair:MovePair) -> Plan:
  match allowed:
    case False{}: unchanged(furnace,player,catalog)
    case True{}: extracted_pair(context,furnace,player,catalog,index,pair)

def put(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+value:Inv.Slot,+carried:Inv.Slot) -> Plan:
  put_admitted(context,furnace,player,catalog,index,carried,input(context,value))

def route(left:Nat,+values:List<&2,Inv.Slot>,+source:U32,+indices:List<&2,U32>,+limit:U32) -> List<&2,Inv.Slot>:
  match left:
    case 0n: values
    case 1n+n:
      route_next(values,route_once(values,source,indices,limit),next => route(n,next,source,indices,limit))

def routing_finished(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+source:U32,+target:U32,+after:List<&2,Inv.Slot>) -> Plan:
  routing_source(U32.is_lt(source,3),context,furnace,player,catalog,source,after)

# The complete next48 observation is used for player-to-furnace publication.

def player_pickup(+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32) -> Plan:
  +own = U32.sub(backing(index),3)
  player_pickup_slots(furnace,player,catalog,own,button,R.at(player,U32.to_nat(own)),R.at(player,47n))

def take(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32,+value:Inv.Slot,+carried:Inv.Slot) -> Plan:
  +capacity = stack_limit(catalog,value)
  take_checked(compatible(value,carried),context,furnace,player,catalog,index,
    moved(value,carried,pickup_requested(Inv.slot_count(value),button,True{}),
      U32.sub(capacity,U32.min(capacity,Inv.slot_count(carried)))))

def deposited(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+pair:MovePair) -> Plan:
  MovePair{source,destination,count} = pair
  put(context,furnace,player,catalog,index,destination,source)

def routed_kind(+setting:Bool,+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+source:U32,+target:U32,+after:List<&2,Inv.Slot>) -> Plan:
  match setting:
    case True{}: routed_set(context,furnace,player,R.skip(3n,after),catalog,target,input(context,R.at(after,U32.to_nat(target))))
    case False{}: routing_finished(context,furnace,player,catalog,source,target,after)

def place_compatible(+compatible:Bool,+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32,+value:Inv.Slot,+carried:Inv.Slot,+maximum:U32) -> Plan:
  match compatible:
    case True{}:
      deposited(context,furnace,player,catalog,index,moved(carried,value,
        pickup_requested(Inv.slot_count(carried),button,False{}),
        U32.sub(maximum,U32.min(maximum,Inv.slot_count(value)))))
    case False{}:
      N.choose(Plan,put(context,furnace,player,catalog,index,carried,value),
        unchanged(furnace,player,catalog),U32.is_le(Inv.slot_count(carried),maximum))

def routed(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+source:U32,+target:U32,+after:List<&2,Inv.Slot>) -> Plan:
  routed_kind(U32.is_ge(source,3) && U32.is_lt(target,3),context,furnace,player,catalog,source,target,after)

def place_allowed(+allowed:Bool,+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32,+value:Inv.Slot,+carried:Inv.Slot) -> Plan:
  match allowed:
    case False{}: unchanged(furnace,player,catalog)
    case True{}:
      place_compatible(compatible(carried,value),context,furnace,player,catalog,index,button,value,carried,
        place_limit(index,carried,stack_limit(catalog,carried)))

def quick_targets(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+source:U32,+indices:List<&2,U32>,+target:U32,+limit:U32) -> Plan:
  routed(context,furnace,player,catalog,source,target,route(38n,combined(furnace,player),source,indices,limit))

def player_routing(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+value:Inv.Slot,+source:U32,+maximum:U32,+smelt:Bool,+result:Result<&2,&2,String,Maybe<&2,Fuel.FuelProfile>>) -> Plan:
  match smelt result:
    case True{} _:
      quick_targets(context,furnace,player,catalog,source,[0],0,U32.min(maximum,64))
    case False{} Done{Some{Fuel.FuelProfile{key,fuel,item}}}:
      N.choose(Plan,quick_targets(context,furnace,player,catalog,source,[1],1,U32.min(maximum,64)),
        quick_targets(context,furnace,player,catalog,source,N.choose(List<&2,U32>,ascending(9n,30),ascending(27n,3),U32.is_lt(index,30)),39,maximum),
        Maybe.is_some(&2,Fuel.CookingFuel,fuel))
    case False{} Done{None{}}:
      quick_targets(context,furnace,player,catalog,source,N.choose(List<&2,U32>,ascending(9n,30),ascending(27n,3),U32.is_lt(index,30)),39,maximum)
    case False{} Fail{message}: refused(furnace,player,catalog,message)

def place_permission(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32,+value:Inv.Slot,+carried:Inv.Slot,+permission:Result<&2,&2,String,Bool>) -> Plan:
  match permission:
    case Fail{message}: refused(furnace,player,catalog,message)
    case Done{allowed}: place_allowed(allowed,context,furnace,player,catalog,index,button,value,carried)

def place_admitted(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32,+value:Inv.Slot,+carried:Inv.Slot,
    +result:Result<&2,&2,String,CI.Admission>) -> Plan:
  CW.Context{bindings,recipes,fuel,depth} = context
  FA.Snapshot{frame,slots} = furnace
  match result:
    case Fail{message}: refused(furnace,player,catalog,message)
    case Done{CI.Admission{metadata,profiles}}:
      place_permission(context,furnace,player,catalog,index,button,value,carried,
        FS.can_place(fuel,profiles,slots,index,carried))

def player_route(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+value:Inv.Slot,+smelt:Bool,+result:Result<&2,&2,String,Maybe<&2,Fuel.FuelProfile>>) -> Plan:
  player_routing(context,furnace,player,catalog,index,value,backing(index),stack_limit(catalog,value),smelt,result)

def pickup_slots(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32,+value:Inv.Slot,+carried:Inv.Slot) -> Plan:
  match carried:
    case Inv.InvEmpty{}: take(context,furnace,player,catalog,index,button,value,carried)
    case _:
      place_admitted(context,furnace,player,catalog,index,button,value,carried,
        CI.slots([value,carried],CW.recipes(context)))

def quick_player(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+value:Inv.Slot) -> Plan:
  CW.Context{bindings,AI.Context{K.Catalog{recipes,tags,items},defaults,features},fuel,depth} = context
  FA.Snapshot{FA.Frame{kind,r,t,s,c,speed,cached,uses},slots} = furnace
  player_route(context,furnace,player,catalog,index,value,
    Maybe.is_some(&2,K.Plan,K.find_recipes(recipes,kind,tags,items,value,None{})),CI.profile(CW.recipes(context),value))

def pickup_valid(+valid:Bool,+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32) -> Plan:
  match valid:
    case False{}: refused(furnace,player,catalog,"cooking-menu:invalid-pickup")
    case True{}:
      FA.Snapshot{frame,slots} = furnace
      pickup_slots(context,furnace,player,catalog,index,button,FS.slot_at(slots,index),R.at(player,47n))

def quick_value(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+source:U32,+value:Inv.Slot) -> Plan:
  match value:
    case Inv.InvEmpty{}: unchanged(furnace,player,catalog)
    case _:
      N.choose(Plan,quick_targets(context,furnace,player,catalog,source,
        N.choose(List<&2,U32>,descending(36n,38),ascending(36n,3),U32.is_eq(index,2)),39,stack_limit(catalog,value)),
        quick_player(context,furnace,player,catalog,index,value),U32.is_lt(index,3))

def pickup(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32) -> Plan:
  pickup_valid(U32.is_lt(index,3) && U32.is_lt(button,2),context,furnace,player,catalog,index,button)

# Actual furnace menu topology:0..2 owner slots,3..29 player9..35,
#30..38 player0..8. Equipment, craft and carried never enter quick-move targets.

def quick_valid(+valid:Bool,+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32) -> Plan:
  match valid:
    case False{}: refused(furnace,player,catalog,"cooking-menu:invalid-quick-move")
    case True{}: quick_value(context,furnace,player,catalog,index,backing(index),R.at(combined(furnace,player),U32.to_nat(backing(index))))

def quick_move(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32) -> Plan:
  quick_valid(U32.is_lt(index,39),context,furnace,player,catalog,index)

def clicked_valid(+valid:Bool,+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32) -> Plan:
  match valid:
    case False{}: refused(furnace,player,catalog,"cooking-menu:invalid-pickup")
    case True{}:
      N.choose(Plan,pickup(context,furnace,player,catalog,index,button),
        player_pickup(furnace,player,catalog,index,button),U32.is_lt(index,3))

def clicked(+context:CW.Context,+furnace:FA.Snapshot,+player:List<&2,Inv.Slot>,+catalog:D.Catalog,+index:U32,+button:U32) -> Plan:
  clicked_valid(U32.is_lt(index,39) && U32.is_lt(button,2),context,furnace,player,catalog,index,button)

