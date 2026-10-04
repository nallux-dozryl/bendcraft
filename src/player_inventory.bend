import Base
import ./inventory.bend as Inv

# The 36 main-inventory slots are owned once. Slots 0..8 are the hotbar.
# Empty component strings denote unmodified pinned item defaults, not an NBT
# component payload. Modified items are deliberately outside this consumer.
type Abilities is Data:
  Abilities{instabuild:Bool,maybuild:Bool}

type Snapshot is Data:
  Snapshot{selected:U32,slots:List<&2,Inv.Slot>,abilities:Abilities}

type State is Type:
  State{inventory:Inv.Inventory,selected:U32,abilities:Abilities}

def default_abilities() -> Abilities:
  Abilities{False{},True{}}

def new() -> State:
  State{Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),36},0,default_abilities()}

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

def inspected(+selected:U32,+abilities:Abilities,result:Inv.Inventory & List<&2,Inv.Slot>) -> State & Snapshot:
  (inventory,slots) = result
  (State{inventory,selected,abilities},Snapshot{selected,slots,abilities})

def inspect(state:State) -> State & Snapshot:
  State{inventory,selected,abilities} = state
  inspected(selected,abilities,read_slots(36n,0,Inv.read(inventory,0),[]))

def selected_read(selected:U32,abilities:Abilities,result:Inv.Inventory & Maybe<&2,Inv.Slot>) -> State & Inv.Slot:
  (inventory,slot) = result
  match slot:
    case None{}: (State{inventory,selected,abilities},Inv.InvEmpty{})
    case Some{value}: (State{inventory,selected,abilities},value)

def selected(state:State) -> State & Inv.Slot:
  State{inventory,+index,abilities} = state
  selected_read(index,abilities,Inv.read(inventory,index))

def select_checked(valid:Bool,state:State,index:U32) -> State & Result<&2,&2,String,Unit>:
  match valid:
    case False{}: (state,Fail{"hotbar slot must be 0 through 8"})
    case True{}:
      State{inventory,previous,abilities} = state
      (State{inventory,index,abilities},Done{Unit{}})

def select(state:State,+index:U32) -> State & Result<&2,&2,String,Unit>:
  select_checked(U32.is_lt(index,9),state,index)

def transferred(selected:U32,abilities:Abilities,result:Inv.Inventory & Inv.TransferStatus) -> State & Inv.TransferStatus:
  (inventory,status) = result
  (State{inventory,selected,abilities},status)

def transfer_known(selected:U32,abilities:Abilities,source:U32,destination:U32,count:U32,mode:Inv.TransferMode,inventory:Inv.Inventory,known:Maybe<&2,Inv.ItemMetadata>) -> State & Inv.TransferStatus:
  match known:
    case None{}: (State{inventory,selected,abilities},Inv.InvRejected{Inv.InvBadMetadata{}})
    case Some{metadata}: transferred(selected,abilities,Inv.transfer_mode(inventory,source,destination,count,metadata,mode))

def transfer_read(selected:U32,abilities:Abilities,source:U32,destination:U32,count:U32,mode:Inv.TransferMode,result:Inv.Inventory & Maybe<&2,Inv.Slot>) -> State & Inv.TransferStatus:
  (inventory,slot) = result
  match slot:
    case None{}: (State{inventory,selected,abilities},Inv.InvRejected{Inv.InvBounds{}})
    case Some{Inv.InvEmpty{}}: transferred(selected,abilities,Inv.transfer_mode(inventory,source,destination,count,Inv.ItemMetadata{Inv.ItemKey{"minecraft:stone",""},64},mode))
    case Some{Inv.InvStack{key,stored}}: transfer_known(selected,abilities,source,destination,count,mode,inventory,metadata(key))

def transfer(state:State,+source:U32,destination:U32,count:U32,mode:Inv.TransferMode) -> State & Inv.TransferStatus:
  State{inventory,selected,abilities} = state
  transfer_read(selected,abilities,source,destination,count,mode,Inv.read(inventory,source))

def loaded(selected:U32,abilities:Abilities,result:Inv.Inventory & Bool) -> State & Result<&2,&2,String,Unit>:
  (inventory,valid) = result
  match valid:
    case False{}: (State{inventory,selected,abilities},Fail{"invalid inventory slot or count"})
    case True{}: (State{inventory,selected,abilities},Done{Unit{}})

def acquire_known(known:Maybe<&2,Inv.ItemMetadata>,state:State,index:U32,+key:Inv.ItemKey,+count:U32) -> State & Result<&2,&2,String,Unit>:
  match known:
    case None{}: (state,Fail{"unsupported item or modified components"})
    case Some{metadata}:
      State{inventory,selected,abilities} = state
      loaded(selected,abilities,Inv.load_slot(inventory,index,Inv.canonical_stack(key,count,U32.is_zero(count)),metadata))

def acquire_checked(state:State,index:U32,+key:Inv.ItemKey,count:U32,allowed:Bool) -> State & Result<&2,&2,String,Unit>:
  match allowed:
    case False{}: (state,Fail{"creative acquisition requires player instabuild ability"})
    case True{}: acquire_known(metadata(key),state,index,key,count)

def acquire(state:State,index:U32,key:Inv.ItemKey,count:U32) -> State & Result<&2,&2,String,Unit>:
  State{inventory,selected,Abilities{+instabuild,maybuild}} = state
  acquire_checked(State{inventory,selected,Abilities{instabuild,maybuild}},index,key,count,instabuild)

def set_abilities(state:State,abilities:Abilities) -> State:
  State{inventory,selected,old} = state
  State{inventory,selected,abilities}

def abilities(state:State) -> State & Abilities:
  State{inventory,selected,+profile} = state
  (State{inventory,selected,profile},profile)

def restore_slots(slots:List<&2,Inv.Slot>,+index:U32,selected:U32,abilities:Abilities,result:Inv.Inventory & Bool) -> Result<&2,&1,String,State>:
  match slots result:
    case _ Tuple{inventory,False{}}: Fail{"invalid inventory slot"}
    case Nil{} Tuple{inventory,True{}}: Done{State{inventory,selected,abilities}}
    case Inv.InvEmpty{} <> rest Tuple{inventory,True{}}: restore_slots(rest,U32.add(index,1),selected,abilities,(inventory,True{}))
    case Inv.InvStack{+key,count} <> rest Tuple{inventory,True{}}:
      restore_slots(rest,U32.add(index,1),selected,abilities,Inv.load_slot(inventory,index,Inv.InvStack{key,count},Inv.ItemMetadata{key,64}))

def restore_checked(valid:Bool,snapshot:Snapshot) -> Result<&2,&1,String,State>:
  match valid:
    case False{}: Fail{"invalid selected hotbar, slot count, item or stack"}
    case True{}:
      Snapshot{selected,slots,abilities} = snapshot
      restore_slots(slots,0,selected,abilities,(Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),36},True{}))

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
