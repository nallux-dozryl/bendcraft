import Base
import ./inventory.bend as I
import ./json.bend as J
import ./crafting_recipe_components.bend as C
import ./item_entity_pickup_patch.bend as Patch
import ./campfire_authority_items.bend as A
import ./item_entity_pickup_model.bend as M

def initialized(found:Maybe<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  match found:
    case None{}: Fail{"pickup key lacks actual initialized defaults"}
    case Some{value}: Done{value}
def members(value:J.Value) -> Result<&2,&2,String,List<&2,J.Member>>:
  match value:
    case J.JObject{values}: Done{values}
    case _: Fail{"pickup requires initialized component object"}
def numeric(+value:J.Value,key:String) -> U32: C.unsigned_default(J.member(value,key),0)
def damaged(+effective:J.Value) -> Bool:
  Maybe.is_some(&2,J.Value,J.member(effective,"minecraft:max_damage")) &&
  Maybe.is_none(&2,J.Value,J.member(effective,"minecraft:unbreakable")) &&
  Maybe.is_some(&2,J.Value,J.member(effective,"minecraft:damage")) &&
  U32.is_gt(numeric(effective,"minecraft:max_damage"),0) && U32.is_gt(numeric(effective,"minecraft:damage"),0)
def found(effective:J.Value,result:Maybe<&2,I.ItemMetadata>) -> Result<&2,&2,String,M.Properties>:
  match result:
    case None{}: Fail{"pickup key has no actual registered item metadata"}
    case Some{metadata}: Done{M.Properties{metadata,damaged(effective)}}
# Reconstruct and authenticate the full key against actual initialized defaults.
# A string envelope/header or caller ItemMetadata alone cannot authorize pickup.
def of_key(+context:A.Context,+key:I.ItemKey) -> Result<&2,&2,String,M.Properties>:
  A.Context{recipes,+defaults,features} = context
  I.ItemKey{id,components} = key
  do Result<&2,&2,String,M.Properties>:
    +base : J.Value <- initialized(C.default_for(defaults,id))
    +patch : J.Value <- Patch.patch(base,key)
    edits : List<&2,C.Change> <- C.decode(patch)
    original : List<&2,J.Member> <- members(base)
    admitted : Maybe<&2,I.ItemMetadata> <- A.admit(context,A.Input{I.InvStack{key,1},patch})
    found(J.JObject{C.apply(edits,original)},admitted)
def valid_property(+slot:I.Slot,properties:M.Properties) -> Result<&2,&2,String,Unit>:
  M.Properties{metadata,damaged} = properties
  A.guarded(I.slot_valid(slot,metadata),"pickup inventory slot violates exact admitted stack limit")
def valid_slot(+context:A.Context,+slot:I.Slot) -> Result<&2,&2,String,Unit>:
  match slot:
    case I.InvEmpty{}: Done{Unit{}}
    case I.InvStack{key,count}:
      do Result<&2,&2,String,Unit>:
        properties : M.Properties <- of_key(context,key)
        valid_property(slot,properties)
def valid(left:Nat,slots:List<&2,I.Slot>,+context:A.Context) -> Result<&2,&2,String,Unit>:
  match left slots:
    case 0n Nil{}: Done{Unit{}}
    case 1n+rest slot <> tail:
      do Result<&2,&2,String,Unit>:
        valid_slot(context,slot)
        valid(rest,tail,context)
    case _ _: Fail{"pickup requires actual complete48-slot inventory owner"}
