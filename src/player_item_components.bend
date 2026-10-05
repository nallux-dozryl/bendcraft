import Base
import ./inventory.bend as I
import ./json.bend as J
import ./crafting_recipe_components.bend as C
import ./crafting_recipe_component_registry.bend as Registry
import ./cooking_block_entity_codec_components.bend as Patch
import ./nbt.bend as N
import ./player_codec.bend as P
import ./player_item_component_patch.bend as RawPatch

# Structural checks make a canonical key safe to carry on the wire. They do
# not authenticate an item's defaults or registry membership. The initialized
# catalog must separately call authenticated with its actual default map.
def names(values:List<&2,J.Member>,+seen:List<&2,String>) -> Bool:
  match values:
    case Nil{}: True{}
    case J.JMember{+name,value} <> rest:
      Registry.persistent(name) && Bool.not(Registry.contains(seen,name)) && names(rest,name <> seen)

def normalized(original:J.Value,result:Result<&2,&2,String,J.Value>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{actual}: String.eq(J.encode(original),J.encode(actual))

def checked_value(name:String,+value:J.Value) -> Bool:
  match name:
    case "minecraft:max_stack_size": normalized(value,C.value_codec(name,value))
    case "minecraft:max_damage": normalized(value,C.value_codec(name,value))
    case "minecraft:damage": normalized(value,C.value_codec(name,value))
    case "minecraft:repair_cost": normalized(value,C.value_codec(name,value))
    case "minecraft:unbreakable": normalized(value,C.value_codec(name,value))
    case "minecraft:enchantment_glint_override": normalized(value,C.value_codec(name,value))
    case "minecraft:suspicious_stew_effects": normalized(value,C.value_codec(name,value))
    case _: True{}

def values(entries:List<&2,J.Member>) -> Bool:
  match entries:
    case Nil{}: True{}
    case J.JMember{name,value} <> rest: checked_value(name,value) && values(rest)

def object_members(value:J.Value) -> Result<&2,&2,String,List<&2,J.Member>>:
  match value:
    case J.JObject{members}: Done{members}
    case _: Fail{"effective component map requires object"}

def effective(+identity:String,body:String) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    +value : J.Value <- J.parse_bounded(body,65536n,32)
    +members : List<&2,J.Member> <- object_members(value)
    C.guard(names(members,[]) && values(members),"invalid canonical effective component map")
    +maximum : U32 = C.unsigned_default(J.member(value,"minecraft:max_stack_size"),1)
    valid : Bool = Maybe.is_none(&2,J.Value,J.member(value,"minecraft:max_damage")) || U32.is_le(maximum,1)
    C.guard(String.eq(C.envelope_checked(valid,maximum,J.encode(J.JObject{C.sorted(members)})),identity),"noncanonical or invalid effective component identity")
    return maximum

def envelope(+identity:String,fields:List<&2,String>) -> Result<&2,&2,String,U32>:
  match fields:
    case "BendCraftComponents1" <> limit <> body <> Nil{}: effective(identity,body)
    case _: Fail{"invalid effective component identity envelope"}

def structural_metadata(+key:I.ItemKey) -> Result<&2,&2,String,I.ItemMetadata>:
  I.ItemKey{id,+identity} = key
  do Result<&2,&2,String,I.ItemMetadata>:
    maximum : U32 <- envelope(identity,String.split(identity,'\t'))
    return I.ItemMetadata{key,maximum}

def structural_slot_metadata(+slot:I.Slot) -> Result<&2,&2,String,I.ItemMetadata>:
  match slot:
    case I.InvEmpty{}: Done{I.ItemMetadata{I.ItemKey{"",""},1}}
    case I.InvStack{key,count}:
      do Result<&2,&2,String,I.ItemMetadata>:
        +metadata : I.ItemMetadata <- structural_metadata(key)
        C.guard(I.slot_valid(slot,metadata),"modified item count violates effective stack limit")
        return metadata

def authenticated(+defaults:J.Value,+key:I.ItemKey) -> Result<&2,&2,String,I.ItemMetadata>:
  do Result<&2,&2,String,I.ItemMetadata>:
    patch : J.Value <- Patch.patch(defaults,key)
    structural_metadata(key)

def encoded_slot(+defaults:J.Value,+key:I.ItemKey,+count:U32) -> Result<&2,&2,String,N.Value>:
  I.ItemKey{id,identity} = key
  do Result<&2,&2,String,N.Value>:
    +metadata : I.ItemMetadata <- authenticated(defaults,key)
    C.guard(I.slot_valid(I.InvStack{key,count},metadata),"modified item count violates effective stack limit")
    patch : J.Value <- Patch.patch(defaults,key)
    tag : N.Value <- Patch.encode(patch)
    return N.Compound{[P.member("id",N.StringTag{P.text(id)}),P.member("count",N.Int{count}),P.member("components",tag)]}

def decoded_patch(+defaults:J.Value,+id:String,patch:Patch.Patch) -> Result<&2,&2,String,I.ItemKey>:
  match patch:
    case Patch.Patch{members,discarded}:
      do Result<&2,&2,String,I.ItemKey>:
        C.guard(U32.is_zero(discarded),"modified inventory component patch contains discarded fields")
        identity : String <- C.resolve(defaults,J.JObject{members})
        +key : I.ItemKey = I.ItemKey{id,identity}
        canonical : J.Value <- Patch.patch(defaults,key)
        return key

def decoded_compound(+defaults:J.Value,+id:String,+value:N.Value) -> Result<&2,&2,String,I.ItemKey>:
  do Result<&2,&2,String,I.ItemKey>:
    RawPatch.validate(value)
    patch : Patch.Patch <- Patch.decode(Some{value})
    decoded_patch(defaults,id,patch)

def decoded_key(defaults:J.Value,id:String,value:N.Value) -> Result<&2,&2,String,I.ItemKey>:
  match value:
    case N.Compound{members}: decoded_compound(defaults,id,N.Compound{members})
    case _: Fail{"modified inventory components require Compound tag"}
