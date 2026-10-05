import Base
import ./player_item_definitions.bend as D
import ./crafting_recipe_components.bend as C
import ./inventory.bend as I
import ./json.bend as J
import ./player_inventory.bend as Player

law missing_initialized_defaults_cannot_authorize_a_modified_key:
  for key:I.ItemKey
  for allowed:Bool
  {D.metadata_registered_defaults(None{},key,allowed) == None{} : Maybe<&2,I.ItemMetadata>}
def missing_initialized_defaults_cannot_authorize_a_modified_key(key,allowed): {==}

law disabled_registered_definition_cannot_authorize_a_modified_key:
  for number:U32
  for id:String
  for description:String
  for limit:U32
  for component_set:U32
  for digest:String
  for defaults:Maybe<&2,J.Value>
  for key:I.ItemKey
  {D.metadata_registered(Some{D.Definition{number,id,description,limit,component_set,digest,False{}}},defaults,key) ==
    None{} : Maybe<&2,I.ItemMetadata>}
def disabled_registered_definition_cannot_authorize_a_modified_key(number,id,description,limit,component_set,digest,defaults,key):
  match defaults:
    case None{}: {==}
    case Some{value}: {==}

law initialized_default_join_retains_every_definition_and_count:
  for +catalog:D.Catalog
  for +defaults:List<&2,C.Default>
  { (D.all(D.with_initialized_defaults(catalog,defaults)),D.count(D.with_initialized_defaults(catalog,defaults))) ==
    (D.all(catalog),D.count(catalog)) : List<&2,D.Definition> & U32 }
def initialized_default_join_retains_every_definition_and_count(catalog,defaults):
  match catalog:
    case D.Catalog{definitions,count}: {==}
    case D.InitializedCatalog{definitions,count,old_defaults}: {==}

law missing_item_metadata_preserves_complete_inventory_owner:
  for state:Player.State
  for index:U32
  for key:I.ItemKey
  for count:U32
  {Player.acquire_known(None{},state,index,key,count) ==
    (state,Fail{"unsupported item or modified components"}) : Player.State & Result<&2,&2,String,Unit>}
def missing_item_metadata_preserves_complete_inventory_owner(state,index,key,count): {==}
