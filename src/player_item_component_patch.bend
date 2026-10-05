import Base
import ./json.bend as J
import ./nbt.bend as N
import ./player_codec.bend as P
import ./crafting_recipe_components.bend as C
import ./crafting_recipe_component_registry.bend as Registry
import ./item_component_effects.bend as E
import ./cooking_block_entity_codec_components.bend as Patch
import ./cooking_block_entity_codec_nbt.bend as Read

# World cooking codecs intentionally salvage valid entries. Inventory storage
# must instead reject a patch that would discard an entry or shadow a field.
# Delegate value decoding to the same actual codecs after this loss check.
def duration_valid(value:Maybe<&2,N.Value>) -> Bool:
  match value:
    case None{}: True{}
    case Some{tag}: Maybe.is_some(&2,U32,Read.int_tag(tag,False{}))

def effect_members(+value:N.Value,members:List<&2,N.Member>) -> Result<&2,&2,String,Unit>:
  do Result<&2,&2,String,Unit>:
    fields : List<&2,P.Field> <- E.schema(List<&2,P.Field>,P.fields(value,
      N.choose(List<&2,String>,["id"],["id","duration"],Nat.is_eq(List.length(&2,N.Member,members),1n))))
    C.guard(duration_valid(Read.field(value,"duration")),"inventory effect duration requires a numeric tag")
    decoded : J.Value <- Patch.effect(value)
    return Unit{}

def effect(value:N.Value) -> Result<&2,&2,String,Unit>:
  match value:
    case N.Compound{+members}: effect_members(N.Compound{members},members)
    case _: Fail{"inventory effect requires Compound tag"}

def effects(values:List<&2,N.Value>) -> Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case head <> rest:
      do Result<&2,&2,String,Unit>:
        effect(Patch.effect_unwrap(head))
        effects(rest)

def effect_list(value:N.Value) -> Result<&2,&2,String,Unit>:
  match value:
    case N.ListTag{0,Nil{}}: Done{Unit{}}
    case N.ListTag{10,values}: effects(values)
    case _: Fail{"inventory effects requires Compound list"}

def member_identity(name:String) -> String:
  match name:
    case SCon{Chr{33},rest}: "!" ++ C.qualified(rest)
    case _: C.qualified(name)

def member_value(name:String,value:N.Value) -> Result<&2,&2,String,Unit>:
  match name:
    case "minecraft:suspicious_stew_effects": effect_list(value)
    case _: Done{Unit{}}

def members(values:List<&2,N.Member>,+seen:List<&2,String>) -> Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case N.Member{name,value} <> rest:
      do Result<&2,&2,String,Unit>:
        text : String <- E.schema(String,P.read_text(name))
        +id : String = member_identity(text)
        C.guard(Bool.not(Registry.contains(seen,id)),"duplicate inventory component patch field")
        member_value(id,value)
        members(rest,id <> seen)

def validate(value:N.Value) -> Result<&2,&2,String,Unit>:
  match value:
    case N.Compound{values}: members(values,[])
    case _: Fail{"modified inventory components require Compound tag"}
