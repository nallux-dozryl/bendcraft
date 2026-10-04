import Base
import ./inventory.bend as Inv
import ./item_component.bend as C
import ./item_component_inventory_codec.bend as S
import ./player_item_definitions.bend as D
import ./player_inventory.bend as I
import ./player_inventory_codec.bend as IC
import ./local_player_record.bend as R
import ./world_generation_settings.bend as WG
import ./nbt.bend as N
import ./item_component_inventory_laws.bend as Laws

def Laws.missing_catalog_definition_refuses_component_defaults():
  {==}

def Laws.disabled_catalog_definition_refuses_component_defaults(number,id,description,limit,component_set,digest):
  {==}

def Laws.default_metadata_branch_preserves_existing_catalog_lookup(catalog,key):
  {==}

def Laws.refused_slot_cannot_become_a_saved_tag(catalog,message):
  {==}

def Laws.producer_completion_preserves_entire_save_owner_and_payload(record,fresh,generation,owner,payload):
  {==}

def Laws.failed_menu_encode_retains_entire_save_owner(record,fresh,generation,catalog,owner,snapshot,message,failure):
  %Equal.sym(Result<&2,&2,String,List<&2,U32>>,IC.menu_payload(I.temporary_empty(snapshot),record,snapshot,generation,catalog),Fail{message},failure) :
    {IC.encoded_payload(record,fresh,generation,owner,_) == (IC.Saved{record,owner,fresh,generation},Fail{message}) : IC.Saved & Result<&2,&2,String,List<&2,U32>>}
  {==}
