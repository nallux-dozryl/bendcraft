import Base
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D
import ./nbt.bend as N

# One owner retains main inventory, equipment and temporary menu storage.
# The legacy36 projection keeps slots0..8 as the hotbar.
# Empty component strings denote unmodified pinned item defaults, not an NBT
# component payload. Modified items are deliberately outside this consumer.
type Abilities is Data:
  Abilities{instabuild:Bool,maybuild:Bool}

type Snapshot is Data:
  Snapshot{selected:U32,slots:List<&2,Inv.Slot>,abilities:Abilities}

type Status is Data:
  Status{invulnerable:Bool,mayfly:Bool,flying:Bool,walking_speed:U32,flying_speed:U32}

type Menu is Data:
  Menu{opened:Bool,revision:Nat,result:Maybe<&2,Inv.Slot>}

type Profile is Data:
  Profile{definitions:D.Catalog,status:Status,menu:Menu}

# One owner: durable main0..35, feet36/legs37/chest38/head39,
# offhand40/body41/saddle42; temporary crafting43..46 and carried47.
# Crafting output is derived by a recipe consumer, never a writable stack.
type State is Type:
  State{inventory:Inv.Inventory,selected:U32,abilities:Abilities,profile:Profile}

type Persisted is Data:
  Persisted{main:Snapshot,equipment:List<&2,Inv.Slot>,status:Status}

type MenuSnapshot is Data:
  MenuSnapshot{saved:Persisted,craft:List<&2,Inv.Slot>,carried:Inv.Slot,
    result:Maybe<&2,Inv.Slot>,opened:Bool,revision:Nat}

type Click is Data:
  Pickup{button:U32}
  QuickMove{}
  Swap{hotbar:U32}
  Clone{}
  Throw{all:Bool}
  QuickCraft{phase:U32,button:U32}
  PickupAll{}

def default_status() -> Status:
  Status{False{},False{},False{},1036831949,1028443341}

def default_menu() -> Menu:
  Menu{False{},0n,None{}}

def legacy_profile() -> Profile:
  Profile{D.legacy(),default_status(),default_menu()}

def profile_metadata(profile:Profile,key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  Profile{definitions,status,menu} = profile
  D.metadata(definitions,key)

def default_abilities() -> Abilities:
  Abilities{False{},True{}}

def new() -> State:
  State{Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),48},0,default_abilities(),legacy_profile()}

def supported(item:String) -> Bool:
  match item:
    case "minecraft:stone": True{}
    case "minecraft:dirt": True{}
    case "minecraft:oak_planks": True{}
    case _: False{}

def metadata_checked(key:Inv.ItemKey,valid:Bool) -> Maybe<&2,Inv.ItemMetadata>:
  match valid:
    case False{}: None{}
    case True{}: Some{Inv.ItemMetadata{key,64}}

def metadata(+key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  Inv.ItemKey{id,components} = key
  metadata_checked(key,supported(id) && String.is_empty(components))

def slot_valid(slot:Inv.Slot) -> Bool:
  match slot:
    case Inv.InvEmpty{}: True{}
    case Inv.InvStack{+key,+count}:
      Maybe.is_some(&2,Inv.ItemMetadata,metadata(key)) && U32.is_gt(count,0) && U32.is_le(count,64)

def slots_valid(left:Nat,slots:List<&2,Inv.Slot>) -> Bool:
  match left slots:
    case 0n Nil{}: True{}
    case 1n+n slot <> rest: slot_valid(slot) && slots_valid(n,rest)
    case _ _: False{}

def snapshot_valid(snapshot:Snapshot) -> Bool:
  Snapshot{selected,slots,abilities} = snapshot
  U32.is_lt(selected,9) && slots_valid(36n,slots)

def empty_slots(slots:List<&2,Inv.Slot>) -> Bool:
  match slots:
    case Nil{}: True{}
    case Inv.InvEmpty{} <> rest: empty_slots(rest)
    case _: False{}

def is_default(snapshot:Snapshot) -> Bool:
  Snapshot{selected,slots,Abilities{instabuild,maybuild}} = snapshot
  U32.is_zero(selected) && Bool.not(instabuild) && maybuild && empty_slots(slots)

def read_slots(left:Nat,index:U32,result:Inv.Inventory & Maybe<&2,Inv.Slot>,values:List<&2,Inv.Slot>) -> Inv.Inventory & List<&2,Inv.Slot>:
  match left result:
    case 0n Tuple{inventory,slot}: (inventory,List.reverse(&2,Inv.Slot,values))
    case 1n+n Tuple{inventory,None{}}: (inventory,List.reverse(&2,Inv.Slot,values))
    case 1n+n Tuple{inventory,Some{slot}}:
      +next = U32.add(index,1)
      read_slots(n,next,Inv.read(inventory,next),slot <> values)

def inspected(+selected:U32,+abilities:Abilities,extra:Profile,result:Inv.Inventory & List<&2,Inv.Slot>) -> State & Snapshot:
  (inventory,slots) = result
  (State{inventory,selected,abilities,extra},Snapshot{selected,slots,abilities})

def inspect(state:State) -> State & Snapshot:
  State{inventory,selected,abilities,extra} = state
  inspected(selected,abilities,extra,read_slots(36n,0,Inv.read(inventory,0),[]))

def selected_read(selected:U32,abilities:Abilities,extra:Profile,result:Inv.Inventory & Maybe<&2,Inv.Slot>) -> State & Inv.Slot:
  (inventory,slot) = result
  match slot:
    case None{}: (State{inventory,selected,abilities,extra},Inv.InvEmpty{})
    case Some{value}: (State{inventory,selected,abilities,extra},value)

def selected(state:State) -> State & Inv.Slot:
  State{inventory,+index,abilities,extra} = state
  selected_read(index,abilities,extra,Inv.read(inventory,index))

def select_checked(valid:Bool,state:State,index:U32) -> State & Result<&2,&2,String,Unit>:
  match valid:
    case False{}: (state,Fail{"hotbar slot must be 0 through 8"})
    case True{}:
      State{inventory,previous,abilities,extra} = state
      (State{inventory,index,abilities,extra},Done{Unit{}})

def select(state:State,+index:U32) -> State & Result<&2,&2,String,Unit>:
  select_checked(U32.is_lt(index,9),state,index)

def transferred(selected:U32,abilities:Abilities,extra:Profile,result:Inv.Inventory & Inv.TransferStatus) -> State & Inv.TransferStatus:
  (inventory,status) = result
  (State{inventory,selected,abilities,extra},status)

def transfer_known(selected:U32,abilities:Abilities,extra:Profile,source:U32,destination:U32,count:U32,mode:Inv.TransferMode,inventory:Inv.Inventory,known:Maybe<&2,Inv.ItemMetadata>) -> State & Inv.TransferStatus:
  match known:
    case None{}: (State{inventory,selected,abilities,extra},Inv.InvRejected{Inv.InvBadMetadata{}})
    case Some{metadata}: transferred(selected,abilities,extra,Inv.transfer_mode(inventory,source,destination,count,metadata,mode))

def transfer_read(selected:U32,abilities:Abilities,+extra:Profile,source:U32,destination:U32,count:U32,mode:Inv.TransferMode,result:Inv.Inventory & Maybe<&2,Inv.Slot>) -> State & Inv.TransferStatus:
  (inventory,slot) = result
  match slot:
    case None{}: (State{inventory,selected,abilities,extra},Inv.InvRejected{Inv.InvBounds{}})
    case Some{Inv.InvEmpty{}}: transferred(selected,abilities,extra,Inv.transfer_mode(inventory,source,destination,count,Inv.ItemMetadata{Inv.ItemKey{"minecraft:stone",""},64},mode))
    case Some{Inv.InvStack{key,stored}}: transfer_known(selected,abilities,extra,source,destination,count,mode,inventory,profile_metadata(extra,key))

def transfer_guard(valid:Bool,state:State,+source:U32,destination:U32,count:U32,mode:Inv.TransferMode) -> State & Inv.TransferStatus:
  match valid:
    case False{}: (state,Inv.InvRejected{Inv.InvBounds{}})
    case True{}:
      State{inventory,selected,abilities,extra} = state
      transfer_read(selected,abilities,extra,source,destination,count,mode,Inv.read(inventory,source))

def transfer(state:State,+source:U32,+destination:U32,count:U32,mode:Inv.TransferMode) -> State & Inv.TransferStatus:
  transfer_guard(U32.is_lt(source,36) && U32.is_lt(destination,36),state,source,destination,count,mode)

def loaded(selected:U32,abilities:Abilities,extra:Profile,result:Inv.Inventory & Bool) -> State & Result<&2,&2,String,Unit>:
  (inventory,valid) = result
  match valid:
    case False{}: (State{inventory,selected,abilities,extra},Fail{"invalid inventory slot or count"})
    case True{}: (State{inventory,selected,abilities,extra},Done{Unit{}})

def acquire_known(known:Maybe<&2,Inv.ItemMetadata>,state:State,index:U32,+key:Inv.ItemKey,+count:U32) -> State & Result<&2,&2,String,Unit>:
  match known:
    case None{}: (state,Fail{"unsupported item or modified components"})
    case Some{metadata}:
      State{inventory,selected,abilities,extra} = state
      loaded(selected,abilities,extra,Inv.load_slot(inventory,index,Inv.canonical_stack(key,count,U32.is_zero(count)),metadata))

def acquire_admitted(state:State,index:U32,+key:Inv.ItemKey,count:U32) -> State & Result<&2,&2,String,Unit>:
  State{inventory,selected,abilities,+extra} = state
  acquire_known(profile_metadata(extra,key),State{inventory,selected,abilities,extra},index,key,count)

def acquire_checked(state:State,index:U32,key:Inv.ItemKey,count:U32,allowed:Bool) -> State & Result<&2,&2,String,Unit>:
  match allowed:
    case False{}: (state,Fail{"creative acquisition requires player instabuild ability"})
    case True{}: acquire_admitted(state,index,key,count)

def acquire_main(valid:Bool,state:State,index:U32,key:Inv.ItemKey,count:U32) -> State & Result<&2,&2,String,Unit>:
  match valid:
    case False{}: (state,Fail{"invalid inventory slot or count"})
    case True{}: acquire_checked(state,index,key,count,True{})

def acquire_allowed(allowed:Bool,state:State,+index:U32,key:Inv.ItemKey,count:U32) -> State & Result<&2,&2,String,Unit>:
  match allowed:
    case False{}: acquire_checked(state,index,key,count,False{})
    case True{}: acquire_main(U32.is_lt(index,36),state,index,key,count)

def acquire(state:State,+index:U32,key:Inv.ItemKey,count:U32) -> State & Result<&2,&2,String,Unit>:
  State{inventory,selected,Abilities{+instabuild,maybuild},extra} = state
  acquire_allowed(instabuild,State{inventory,selected,Abilities{instabuild,maybuild},extra},index,key,count)

def set_abilities(state:State,abilities:Abilities) -> State:
  State{inventory,selected,old,extra} = state
  State{inventory,selected,abilities,extra}

def abilities(state:State) -> State & Abilities:
  State{inventory,selected,+profile,extra} = state
  (State{inventory,selected,profile,extra},profile)

def restore_slots(slots:List<&2,Inv.Slot>,+index:U32,selected:U32,abilities:Abilities,extra:Profile,result:Inv.Inventory & Bool) -> Result<&2,&1,String,State>:
  match slots result:
    case _ Tuple{inventory,False{}}: Fail{"invalid inventory slot"}
    case Nil{} Tuple{inventory,True{}}: Done{State{inventory,selected,abilities,extra}}
    case Inv.InvEmpty{} <> rest Tuple{inventory,True{}}: restore_slots(rest,U32.add(index,1),selected,abilities,extra,(inventory,True{}))
    case Inv.InvStack{+key,count} <> rest Tuple{inventory,True{}}:
      restore_slots(rest,U32.add(index,1),selected,abilities,extra,Inv.load_slot(inventory,index,Inv.InvStack{key,count},Inv.ItemMetadata{key,64}))

def restore_checked(valid:Bool,snapshot:Snapshot) -> Result<&2,&1,String,State>:
  match valid:
    case False{}: Fail{"invalid selected hotbar, slot count, item or stack"}
    case True{}:
      Snapshot{selected,slots,abilities} = snapshot
      restore_slots(slots,0,selected,abilities,legacy_profile(),(Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),48},True{}))

def restore(+snapshot:Snapshot) -> Result<&2,&1,String,State>:
  restore_checked(snapshot_valid(snapshot),snapshot)

law invalid_selection_preserves_inventory:
  for +index:U32
  for state:State
  {select_checked(False{},state,index) == (state,Fail{"hotbar slot must be 0 through 8"}) : State & Result<&2,&2,String,Unit>}

def invalid_selection_preserves_inventory(index,state):
  {==}

law refused_acquisition_preserves_inventory:
  for state:State
  for index:U32
  for key:Inv.ItemKey
  for count:U32
  {acquire_checked(state,index,key,count,False{}) == (state,Fail{"creative acquisition requires player instabuild ability"}) : State & Result<&2,&2,String,Unit>}

def refused_acquisition_preserves_inventory(state,index,key,count):
  {==}

law restore_refuses_invalid_snapshot:
  for snapshot:Snapshot
  {restore_checked(False{},snapshot) == Fail{"invalid selected hotbar, slot count, item or stack"} : Result<&2,&1,String,State>}

def restore_refuses_invalid_snapshot(snapshot):
  {==}

def new_with(definitions:D.Catalog) -> State:
  State{Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),48},0,default_abilities(),Profile{definitions,default_status(),default_menu()}}

def selection(state:State) -> State & U32:
  State{inventory,+index,abilities,extra} = state
  (State{inventory,index,abilities,extra},index)

def definitions(state:State) -> State & D.Catalog:
  State{inventory,selected,abilities,Profile{+definitions,status,menu}} = state
  (State{inventory,selected,abilities,Profile{definitions,status,menu}},definitions)

def set_status(state:State,status:Status) -> State:
  State{inventory,selected,abilities,Profile{definitions,old,menu}} = state
  State{inventory,selected,abilities,Profile{definitions,status,menu}}

def status(state:State) -> State & Status:
  State{inventory,selected,abilities,Profile{definitions,+status,menu}} = state
  (State{inventory,selected,abilities,Profile{definitions,status,menu}},status)

def first(left:Nat,values:List<&2,Inv.Slot>) -> List<&2,Inv.Slot>:
  match left values:
    case 1n+n value <> rest: value <> first(n,rest)
    case _ _: []

def skip(left:Nat,values:List<&2,Inv.Slot>) -> List<&2,Inv.Slot>:
  match left values:
    case 0n _: values
    case 1n+n value <> rest: skip(n,rest)
    case _ _: []

def list_slot(values:List<&2,Inv.Slot>) -> Inv.Slot:
  match values:
    case value <> rest: value
    case _: Inv.InvEmpty{}

def menu_inspected(+selected:U32,+abilities:Abilities,+profile:Profile,result:Inv.Inventory & List<&2,Inv.Slot>) -> State & MenuSnapshot:
  Profile{definitions,status,Menu{opened,revision,output}} = profile
  (inventory,+slots) = result
  (State{inventory,selected,abilities,profile},MenuSnapshot{Persisted{Snapshot{selected,first(36n,slots),abilities},
    first(7n,skip(36n,slots)),status},first(4n,skip(43n,slots)),list_slot(skip(47n,slots)),output,opened,revision})

def menu_inspect(state:State) -> State & MenuSnapshot:
  State{inventory,selected,abilities,profile} = state
  menu_inspected(selected,abilities,profile,read_slots(48n,0,Inv.read(inventory,0),[]))

def structural_slot(slot:Inv.Slot) -> Bool:
  match slot:
    case Inv.InvEmpty{}: True{}
    case Inv.InvStack{Inv.ItemKey{+id,components},+count}:
      Nat.is_gt(String.length(id),0n) && Nat.is_le(String.length(id),256n) && D.identifier(id) &&
        String.is_empty(components) && U32.is_gt(count,0) && U32.is_le(count,99)

def structural_slots(left:Nat,slots:List<&2,Inv.Slot>) -> Bool:
  match left slots:
    case 0n Nil{}: True{}
    case 1n+n slot <> rest: structural_slot(slot) && structural_slots(n,rest)
    case _ _: False{}

def slot_known(slot:Inv.Slot,known:Maybe<&2,Inv.ItemMetadata>) -> Bool:
  match known:
    case None{}: False{}
    case Some{metadata}: Inv.slot_valid(slot,metadata)

def slot_valid_with(catalog:D.Catalog,+slot:Inv.Slot) -> Bool:
  match slot:
    case Inv.InvEmpty{}: True{}
    case Inv.InvStack{key,count}: slot_known(slot,D.metadata(catalog,key))

def slots_valid_with(left:Nat,+catalog:D.Catalog,slots:List<&2,Inv.Slot>) -> Bool:
  match left slots:
    case 0n Nil{}: True{}
    case 1n+n slot <> rest: slot_valid_with(catalog,slot) && slots_valid_with(n,catalog,rest)
    case _ _: False{}

def snapshot_valid_with(catalog:D.Catalog,snapshot:Snapshot) -> Bool:
  Snapshot{selected,slots,abilities} = snapshot
  U32.is_lt(selected,9) && slots_valid_with(36n,catalog,slots)

def status_valid(status:Status) -> Bool:
  # NBT Float owns rawbinary32 words. No unobserved normalization or finite/
  # nonnegative restriction may change the saved abilities on load.
  True{}

def persisted_valid_with(+catalog:D.Catalog,snapshot:Persisted) -> Bool:
  Persisted{main,equipment,status} = snapshot
  snapshot_valid_with(catalog,main) && slots_valid_with(7n,catalog,equipment) && status_valid(status)

def output_valid(result:Maybe<&2,Inv.Slot>) -> Bool:
  match result:
    case None{}: True{}
    case Some{slot}: structural_slot(slot)

def menu_snapshot_valid(snapshot:MenuSnapshot) -> Bool:
  MenuSnapshot{Persisted{Snapshot{selected,slots,abilities},equipment,status},craft,carried,result,opened,revision} = snapshot
  U32.is_lt(selected,9) && structural_slots(36n,slots) && structural_slots(7n,equipment) &&
    structural_slots(4n,craft) && structural_slot(carried) && output_valid(result) && status_valid(status)

def restore_full_slots(slots:List<&2,Inv.Slot>,+index:U32,selected:U32,abilities:Abilities,extra:Profile,result:Inv.Inventory & Bool) -> Result<&2,&1,String,State>:
  match slots result:
    case _ Tuple{inventory,False{}}: Fail{"invalid full inventory slot"}
    case Nil{} Tuple{inventory,True{}}: Done{State{inventory,selected,abilities,extra}}
    case slot <> rest Tuple{inventory,True{}}:
      restore_full_slots(rest,U32.add(index,1),selected,abilities,extra,Inv.load_valid(inventory,index,slot,True{}))

def restore_persisted_valid(valid:Bool,catalog:D.Catalog,snapshot:Persisted) -> Result<&2,&1,String,State>:
  match valid:
    case False{}: Fail{"invalid full inventory state"}
    case True{}:
      Persisted{Snapshot{selected,slots,abilities},equipment,status} = snapshot
      restore_full_slots(List.append(&2,Inv.Slot,slots,equipment),0,selected,abilities,Profile{catalog,status,default_menu()},
        (Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),48},True{}))

def restore_persisted(+catalog:D.Catalog,+snapshot:Persisted) -> Result<&2,&1,String,State>:
  restore_persisted_valid(persisted_valid_with(catalog,snapshot),catalog,snapshot)

def menu_set(state:State,opened:Bool) -> State:
  State{inventory,selected,abilities,Profile{definitions,status,Menu{previous,revision,result}}} = state
  State{inventory,selected,abilities,Profile{definitions,status,Menu{opened,revision,result}}}

def menu_open(state:State) -> State & Result<&2,&2,String,Unit>:
  (menu_set(state,True{}),Done{Unit{}})

def temporary_empty(snapshot:MenuSnapshot) -> Bool:
  MenuSnapshot{saved,craft,carried,result,opened,revision} = snapshot
  empty_slots(carried <> craft)

def close_checked(allowed:Bool,state:State) -> State & Result<&2,&2,String,Unit>:
  match allowed:
    case False{}: (state,Fail{"menu retains carried or crafting items; return/drop authority is required before closing"})
    case True{}: (menu_set(state,False{}),Done{Unit{}})

def close_inspected(result:State & MenuSnapshot) -> State & Result<&2,&2,String,Unit>:
  (state,snapshot) = result
  close_checked(temporary_empty(snapshot),state)

def menu_close(state:State) -> State & Result<&2,&2,String,Unit>: close_inspected(menu_inspect(state))

def menu_index(+slot:U32) -> Maybe<&2,U32>:
  N.choose(Maybe<&2,U32>,Some{U32.add(slot,42)},
    N.choose(Maybe<&2,U32>,Some{U32.sub(44,slot)},
      N.choose(Maybe<&2,U32>,Some{slot},
        N.choose(Maybe<&2,U32>,Some{U32.sub(slot,36)},
          N.choose(Maybe<&2,U32>,Some{40},None{},U32.is_eq(slot,45)),U32.is_ge(slot,36) && U32.is_lt(slot,45)),
        U32.is_ge(slot,9) && U32.is_lt(slot,36)),U32.is_ge(slot,5) && U32.is_lt(slot,9)),
    U32.is_ge(slot,1) && U32.is_lt(slot,5))

def menu_snapshot_slot_valid(snapshot:MenuSnapshot,+index:U32) -> Inv.Slot:
  MenuSnapshot{Persisted{Snapshot{selected,+main,abilities},+equipment,status},+craft,carried,result,opened,revision} = snapshot
  N.choose(Inv.Slot,list_slot(skip(U32.to_nat(index),main)),
    N.choose(Inv.Slot,list_slot(skip(U32.to_nat(U32.sub(U32.max(index,36),36)),equipment)),
      N.choose(Inv.Slot,list_slot(skip(U32.to_nat(U32.sub(U32.max(index,43),43)),craft)),carried,U32.is_lt(index,47)),U32.is_lt(index,43)),U32.is_lt(index,36))

def menu_snapshot_slot_checked(valid:Bool,snapshot:MenuSnapshot,index:U32) -> Inv.Slot:
  match valid:
    case False{}: Inv.InvEmpty{}
    case True{}: menu_snapshot_slot_valid(snapshot,index)

def menu_snapshot_slot(snapshot:MenuSnapshot,+index:U32) -> Inv.Slot:
  menu_snapshot_slot_checked(U32.is_lt(index,48),snapshot,index)

def ref_equipment(found:Maybe<&2,U32>,index:U32) -> Bool:
  match found:
    case None{}: False{}
    case Some{slot}: U32.is_eq(slot,index)

def menu_allowed_item(+index:U32,key:Inv.ItemKey) -> Bool:
  Inv.ItemKey{id,components} = key
  N.choose(Bool,ref_equipment(D.equipment(id),index),True{},U32.is_ge(index,36) && U32.is_lt(index,40))

def menu_slot_room(+index:U32,slot:Inv.Slot) -> Bool:
  match slot:
    case Inv.InvEmpty{}: True{}
    case Inv.InvStack{key,count}: Bool.not(U32.is_ge(index,36) && U32.is_lt(index,40))

def revised(state:State) -> State:
  State{inventory,selected,abilities,Profile{definitions,status,Menu{opened,revision,result}}} = state
  State{inventory,selected,abilities,Profile{definitions,status,Menu{opened,1n+revision,None{}}}}

def menu_moved(result:State & Inv.TransferStatus) -> State & Result<&2,&2,String,Unit>:
  (state,status) = result
  match status:
    case Inv.InvMoved{count}: (revised(state),Done{Unit{}})
    case Inv.InvRejected{reason}: (state,Fail{"menu transfer refused"})

def menu_transfer_guard(allowed:Bool,state:State,+source:U32,destination:U32,count:U32) -> State & Result<&2,&2,String,Unit>:
  match allowed:
    case False{}: (state,Fail{"item is not admitted by this menu slot"})
    case True{}:
      State{inventory,selected,abilities,profile} = state
      menu_moved(transfer_read(selected,abilities,profile,source,destination,count,Inv.TransferAny{},Inv.read(inventory,source)))

def pickup_slots(state:State,+index:U32,+button:U32,slot:Inv.Slot,carried:Inv.Slot) -> State & Result<&2,&2,String,Unit>:
  match slot carried:
    case Inv.InvEmpty{} Inv.InvEmpty{}: (state,Done{Unit{}})
    case Inv.InvStack{key,+count} Inv.InvEmpty{}:
      menu_transfer_guard(True{},state,index,47,N.choose(U32,U32.div(U32.add(count,1),2),count,U32.is_eq(button,1)))
    case destination Inv.InvStack{+key,+count}:
      menu_transfer_guard(menu_allowed_item(index,key) && menu_slot_room(index,destination),state,47,index,N.choose(U32,1,
        N.choose(U32,1,count,U32.is_ge(index,36) && U32.is_lt(index,40)),U32.is_eq(button,1)))

def pickup_inspected(+index:U32,button:U32,result:State & MenuSnapshot) -> State & Result<&2,&2,String,Unit>:
  (state,+snapshot) = result
  pickup_slots(state,index,button,menu_snapshot_slot(snapshot,index),menu_snapshot_slot(snapshot,47))

def pickup_button(valid:Bool,state:State,index:U32,button:U32) -> State & Result<&2,&2,String,Unit>:
  match valid:
    case False{}: (state,Fail{"pickup button must be left or right"})
    case True{}: pickup_inspected(index,button,menu_inspect(state))

def click_index(index:Maybe<&2,U32>,state:State,click:Click) -> State & Result<&2,&2,String,Unit>:
  match index click:
    case None{} _: (state,Fail{"crafting output or outside slot requires recipe/drop authority"})
    case Some{slot} Pickup{+button}: pickup_button(U32.is_lt(button,2),state,slot,button)
    case Some{slot} _: (state,Fail{"menu click kind requires its authoritative vanilla consumer"})

def click_open(allowed:Bool,state:State,index:U32,click:Click) -> State & Result<&2,&2,String,Unit>:
  match allowed:
    case False{}: (state,Fail{"player inventory menu is closed"})
    case True{}: click_index(menu_index(index),state,click)

def menu_click(state:State,index:U32,click:Click) -> State & Result<&2,&2,String,Unit>:
  State{inventory,selected,abilities,Profile{definitions,status,Menu{+opened,revision,result}}} = state
  click_open(opened,State{inventory,selected,abilities,Profile{definitions,status,Menu{opened,revision,result}}},index,click)
