import Base
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./campfire_authority_items.bend as A
import ./inventory.bend as I
import ./crafting_recipe_components.bend as C
import ./cooking_block_entity_codec_components.bend as Patch
import ./json.bend as J

def found(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  match value:
    case Some{value}: Done{value}
    case None{}: Fail{"item tick key lacks actual initialized defaults"}
def metadata(value:Maybe<&2,I.ItemMetadata>) -> Result<&2,&2,String,I.ItemMetadata>:
  match value:
    case Some{value}: Done{value}
    case None{}: Fail{"item tick key lacks actual registered metadata"}
def of_key(+context:A.Context,+key:I.ItemKey) -> Result<&2,&2,T.Error,I.ItemMetadata>:
  A.Context{recipes,+defaults,features}=context
  I.ItemKey{id,components}=key
  do Result<&2,&2,T.Error,I.ItemMetadata>:
    +base : J.Value <- U.string_result(J.Value,found(C.default_for(defaults,id)))
    patch : J.Value <- U.string_result(J.Value,Patch.patch(base,key))
    value : Maybe<&2,I.ItemMetadata> <- U.string_result(Maybe<&2,I.ItemMetadata>,A.admit(context,A.Input{I.InvStack{key,1},patch}))
    U.string_result(I.ItemMetadata,metadata(value))
def maximum(meta:I.ItemMetadata) -> U32:
  I.ItemMetadata{key,max}=meta
  max
