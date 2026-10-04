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

law missing_catalog_definition_refuses_component_defaults:
  {D.component_defaults_known(None{}) == None{} : Maybe<&2,C.Defaults>}

law disabled_catalog_definition_refuses_component_defaults:
  for number:U32
  for id:String
  for description:String
  for limit:U32
  for component_set:U32
  for digest:String
  {D.component_defaults_known(Some{D.Definition{number,id,description,limit,component_set,digest,False{}}}) == None{} : Maybe<&2,C.Defaults>}

law default_metadata_branch_preserves_existing_catalog_lookup:
  for catalog:D.Catalog
  for key:Inv.ItemKey
  {D.metadata_components(catalog,key,True{}) == D.metadata_plain(catalog,key) : Maybe<&2,Inv.ItemMetadata>}

law refused_slot_cannot_become_a_saved_tag:
  for catalog:D.Catalog
  for +message:String
  {S.validated_tag(catalog,Fail{message}) == Fail{message} : Result<&2,&2,String,N.Value>}

law producer_completion_preserves_entire_save_owner_and_payload:
  for +record:R.Record
  for +fresh:Bool
  for +generation:WG.Settings
  for owner:I.State
  for +payload:Result<&2,&2,String,List<&2,U32>>
  {IC.encoded_payload(record,fresh,generation,owner,payload) == (IC.Saved{record,owner,fresh,generation},payload) : IC.Saved & Result<&2,&2,String,List<&2,U32>>}

law failed_menu_encode_retains_entire_save_owner:
  for +record:R.Record
  for +fresh:Bool
  for +generation:WG.Settings
  for +catalog:D.Catalog
  for owner:I.State
  for +snapshot:I.MenuSnapshot
  for +message:String
  for failure:{IC.menu_payload(I.temporary_empty(snapshot),record,snapshot,generation,catalog) == Fail{message} : Result<&2,&2,String,List<&2,U32>>}
  {IC.encoded_menu(record,fresh,generation,catalog,(owner,snapshot)) == (IC.Saved{record,owner,fresh,generation},Fail{message}) : IC.Saved & Result<&2,&2,String,List<&2,U32>>}
