import Base
import ./inventory.bend as Inv
import ./player_inventory.bend as I
import ./player_item_definitions.bend as D
import ./resource_client_wire.bend as W
import ./item_component_wire_laws.bend as Laws

def Laws.refused_component_validation_is_structurally_refused(message): {==}

def Laws.structurally_refused_key_cannot_enter_wire(key,refused):
  %Equal.sym(Bool,I.structural_slot(Inv.InvStack{key,1}),False{},refused) :
    {Result.bind(&2,&2,String,Unit,Inv.ItemKey,W.guard(_,"wire:item-key-components"),unit => Done{key}) == Fail{"wire:item-key-components"} : Result<&2,&2,String,Inv.ItemKey>}
  {==}

def Laws.structurally_refused_slot_cannot_enter_wire(slot,refused):
  %Equal.sym(Bool,I.structural_slot(slot),False{},refused) :
    {Result.bind(&2,&2,String,Unit,Inv.Slot,W.guard(_,"wire:inventory-slot-components-count"),unit => Done{slot}) == Fail{"wire:inventory-slot-components-count"} : Result<&2,&2,String,Inv.Slot>}
  {==}

def Laws.missing_catalog_admission_retains_complete_player_owner(owner,index,key,count): {==}

def Laws.creative_refusal_retains_complete_player_owner(owner,index,key,count): {==}

def Laws.actual_catalog_refusal_retains_complete_player_owner(array,length,selected,abilities,catalog,status,menu,index,key,count,refused):
  %Equal.sym(Maybe<&2,Inv.ItemMetadata>,D.metadata(catalog,key),None{},refused) :
    {I.acquire_known(_,I.State{Inv.Inventory{array,length},selected,abilities,I.Profile{catalog,status,menu}},index,key,count) ==
      (I.State{Inv.Inventory{array,length},selected,abilities,I.Profile{catalog,status,menu}},Fail{"unsupported item or modified components"}) : I.State & Result<&2,&2,String,Unit>}
  {==}

def Laws.modified_key_cannot_request_count_two(id,components,modified):
  %Equal.sym(Bool,String.is_empty(components),False{},modified) :
    {_ || U32.is_le(2,1) == False{} : Bool}
  {==}

def Laws.failed_slot_install_retains_complete_player_owner(array,length,selected,abilities,profile): {==}
