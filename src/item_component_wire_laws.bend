import Base
import ./inventory.bend as Inv
import ./player_inventory.bend as I
import ./player_item_definitions.bend as D
import ./resource_client_wire.bend as W

law refused_component_validation_is_structurally_refused:
  for message:String
  {I.structural_components(Fail{message}) == False{} : Bool}

law structurally_refused_key_cannot_enter_wire:
  for +key:Inv.ItemKey
  for refused:{I.structural_slot(Inv.InvStack{key,1}) == False{} : Bool}
  {W.admitted_item_key(key) == Fail{"wire:item-key-components"} : Result<&2,&2,String,Inv.ItemKey>}

law structurally_refused_slot_cannot_enter_wire:
  for +slot:Inv.Slot
  for refused:{I.structural_slot(slot) == False{} : Bool}
  {W.admitted_inventory_slot(slot) == Fail{"wire:inventory-slot-components-count"} : Result<&2,&2,String,Inv.Slot>}

law missing_catalog_admission_retains_complete_player_owner:
  for owner:I.State
  for index:U32
  for key:Inv.ItemKey
  for count:U32
  {I.acquire_known(None{},owner,index,key,count) == (owner,Fail{"unsupported item or modified components"}) : I.State & Result<&2,&2,String,Unit>}

law creative_refusal_retains_complete_player_owner:
  for owner:I.State
  for index:U32
  for key:Inv.ItemKey
  for count:U32
  {I.acquire_checked(owner,index,key,count,False{}) == (owner,Fail{"creative acquisition requires player instabuild ability"}) : I.State & Result<&2,&2,String,Unit>}

law actual_catalog_refusal_retains_complete_player_owner:
  for array:Array<Inv.Slot>
  for +length:U32
  for +selected:U32
  for +abilities:I.Abilities
  for +catalog:D.Catalog
  for +status:I.Status
  for +menu:I.Menu
  for index:U32
  for +key:Inv.ItemKey
  for +count:U32
  for refused:{D.metadata(catalog,key) == None{} : Maybe<&2,Inv.ItemMetadata>}
  {I.acquire_admitted(I.State{Inv.Inventory{array,length},selected,abilities,I.Profile{catalog,status,menu}},index,key,count) ==
    (I.State{Inv.Inventory{array,length},selected,abilities,I.Profile{catalog,status,menu}},Fail{"unsupported item or modified components"}) : I.State & Result<&2,&2,String,Unit>}

law modified_key_cannot_request_count_two:
  for id:String
  for +components:String
  for modified:{String.is_empty(components) == False{} : Bool}
  {W.acquire_component_count(Inv.ItemKey{id,components},2) == False{} : Bool}

law failed_slot_install_retains_complete_player_owner:
  for array:Array<Inv.Slot>
  for +length:U32
  for +selected:U32
  for +abilities:I.Abilities
  for +profile:I.Profile
  {I.loaded(selected,abilities,profile,(Inv.Inventory{array,length},False{})) ==
    (I.State{Inv.Inventory{array,length},selected,abilities,profile},Fail{"invalid inventory slot or count"}) : I.State & Result<&2,&2,String,Unit>}
