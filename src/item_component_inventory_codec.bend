import Base
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D
import ./item_component.bend as C
import ./item_component_effects.bend as E
import ./nbt.bend as N
import ./player_codec.bend as P

# Full version-3 slots use the same exact-key catalog authority as the live
# inventory. Legacy/version-2 helpers remain in their existing codec module.
def admitted(+slot:Inv.Slot,metadata:Maybe<&2,Inv.ItemMetadata>) -> Result<&2,&2,String,Inv.Slot>:
  match metadata:
    case None{}: Fail{"inventory slot requires admitted item components"}
    case Some{definition}:
      do Result<&2,&2,String,Inv.Slot>:
        C.guard(Inv.slot_valid(slot,definition),"inventory slot violates admitted stack limit")
        return slot

def validate(catalog:D.Catalog,+slot:Inv.Slot) -> Result<&2,&2,String,Inv.Slot>:
  match slot:
    case Inv.InvEmpty{}: Done{slot}
    case Inv.InvStack{key,count}: admitted(slot,D.metadata(catalog,key))

def stack_tag(catalog:D.Catalog,+key:Inv.ItemKey,+count:U32,plain:Bool) -> Result<&2,&2,String,N.Value>:
  Inv.ItemKey{+id,identity} = key
  match plain:
    case True{}: Done{N.Compound{[P.member("id",N.StringTag{P.text(id)}),P.member("count",N.Int{count})]}}
    case False{}: D.encode_modified_slot(catalog,key,count)

def validated_tag(catalog:D.Catalog,result:Result<&2,&2,String,Inv.Slot>) -> Result<&2,&2,String,N.Value>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Inv.InvEmpty{}}: Done{N.Compound{[]}}
    case Done{Inv.InvStack{+key,count}}:
      Inv.ItemKey{id,components} = key
      stack_tag(catalog,key,count,String.is_empty(components))

def slot_tag(+catalog:D.Catalog,slot:Inv.Slot) -> Result<&2,&2,String,N.Value>:
  validated_tag(catalog,validate(catalog,slot))

def slot_tags(+catalog:D.Catalog,values:List<&2,Inv.Slot>) -> Result<&2,&2,String,List<&2,N.Value>>:
  match values:
    case Nil{}: Done{[]}
    case slot <> rest:
      do Result<&2,&2,String,List<&2,N.Value>>:
        value : N.Value <- slot_tag(catalog,slot)
        tail : List<&2,N.Value> <- slot_tags(catalog,rest)
        return value <> tail

def fields_slot(catalog:D.Catalog,+value:N.Value,modified:Bool) -> Result<&2,&2,String,Inv.Slot>:
  match modified:
    case False{}:
      do Result<&2,&2,String,Inv.Slot>:
        +fields : List<&2,P.Field> <- E.schema(List<&2,P.Field>,P.fields(value,["id","count"]))
        id : String <- C.nbt_id(P.field(fields,"id"))
        count : U32 <- E.schema(U32,P.int_value(P.field(fields,"count"),"count"))
        validate(catalog,Inv.InvStack{Inv.ItemKey{id,""},count})
    case True{}:
      do Result<&2,&2,String,Inv.Slot>:
        fields : List<&2,P.Field> <- E.schema(List<&2,P.Field>,P.fields(value,["id","count","components"]))
        +id : String <- C.nbt_id(P.field(fields,"id"))
        D.decode_modified_slot(catalog,value)

def slot_value(catalog:D.Catalog,value:N.Value) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case N.Compound{Nil{}}: Done{Inv.InvEmpty{}}
    case N.Compound{+members}: fields_slot(catalog,N.Compound{members},Nat.is_eq(List.length(&2,N.Member,members),3n))
    case other: Fail{"inventory slot requires Compound tag"}

def sized_slots(left:Nat,+catalog:D.Catalog,values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match left values:
    case 0n Nil{}: Done{[]}
    case 1n+n value <> rest:
      do Result<&2,&2,String,List<&2,Inv.Slot>>:
        slot : Inv.Slot <- slot_value(catalog,value)
        tail : List<&2,Inv.Slot> <- sized_slots(n,catalog,rest)
        return slot <> tail
    case _ _: Fail{"full inventory slot list has wrong length"}

def sized_value(catalog:D.Catalog,value:N.Value,count:Nat) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match value:
    case N.ListTag{10,values}: sized_slots(count,catalog,values)
    case _: Fail{"full inventory requires Compound slot list"}
