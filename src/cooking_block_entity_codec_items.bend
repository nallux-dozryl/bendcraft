import Base
import ./nbt.bend as N
import ./json.bend as J
import ./inventory.bend as I
import ./crafting_recipe.bend as R
import ./crafting_recipe_decoder.bend as D
import ./crafting_recipe_components.bend as C
import ./cooking_recipe.bend as K
import ./campfire_authority_items.bend as CI
import ./furnace_authority_fuel.bend as F
import ./furnace_authority_decoder.bend as FD
import ./cooking_block_entity_codec_nbt.bend as B
import ./cooking_block_entity_codec_components.bend as P

type Context is Data:
  Context{recipes:K.Catalog,defaults:List<&2,C.Default>}
type Row is Data:
  Row{index:U32,input:Maybe<&2,CI.Input>,discarded:U32}
type Decoded is Data:
  Decoded{inputs:List<&2,CI.Input>,discarded:U32}
type Admission is Data:
  Admission{metadata:List<&2,I.ItemMetadata>,profiles:List<&2,F.FuelProfile>}

def empty(count:Nat) -> List<&2,CI.Input>:
  match count:
    case 0n: []
    case 1n+rest: CI.plain() <> empty(rest)
def replace(values:List<&2,CI.Input>,index:U32,+value:CI.Input) -> List<&2,CI.Input>:
  match values index:
    case Nil{} _: []
    case head <> rest 0: value <> rest
    case head <> rest _: head <> replace(rest,U32.sub(index,1),value)
def valid_id(value:Result<&2,&2,String,String>) -> Maybe<&2,String>:
  match value:
    case Fail{message}: None{}
    case Done{raw}:
      +id = D.qualified(raw)
      R.choose(Maybe<&2,String>,Some{id},None{},D.identifier(id) && Bool.not(String.eq(id,"minecraft:air")))
def parsed_id(value:Maybe<&2,N.Value>) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{raw}: valid_id(B.string(raw))
def count(+value:Maybe<&2,N.Value>) -> U32:
  +bits = B.int_optional(value,1,False{})
  R.choose(U32,bits,1,U32.is_ge(bits,1) && U32.is_le(bits,99))
def default_map(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  match value:
    case None{}: Fail{"physical stack lacks actual initialized component defaults"}
    case Some{map}: Done{map}
def materialized(+defaults:J.Value,+id:String,amount:U32,+patch:P.Patch) -> Result<&2,&2,String,Row>:
  P.Patch{+members,discarded} = patch
  do Result<&2,&2,String,Row>:
    +identity : String <- C.resolve(defaults,J.JObject{members})
    +key : I.ItemKey = I.ItemKey{id,identity}
    canonical : J.Value <- P.patch(defaults,key)
    return Row{0,Some{CI.Input{I.InvStack{key,amount},canonical}},discarded}
def known_row(+context:Context,+id:String,+value:N.Value,known:Bool) -> Result<&2,&2,String,Row>:
  Context{recipes,defaults} = context
  match known:
    case False{}: Done{Row{0,None{},1}}
    case True{}:
      do Result<&2,&2,String,Row>:
        map : J.Value <- default_map(C.default_for(defaults,id))
        patch : P.Patch <- P.decode(B.field(value,"components"))
        materialized(map,id,count(B.field(value,"count")),patch)
def named_row(+context:Context,+value:N.Value,name:Maybe<&2,String>) -> Result<&2,&2,String,Row>:
  Context{K.Catalog{recipes,tags,items},defaults} = context
  match name:
    case None{}: Done{Row{0,None{},1}}
    case Some{+id}: known_row(context,id,value,Maybe.is_some(&2,R.ItemDefinition,R.item_definition(items,id)))
def indexed(value:Row,index:U32) -> Row:
  Row{old,input,discarded} = value
  Row{index,input,discarded}
def unwrap(value:N.Value) -> N.Value:
  match value:
    case N.Compound{N.Member{N.Text{Nil{}},inner} <> Nil{}}: inner
    case _: value
def row(+context:Context,+value:N.Value) -> Result<&2,&2,String,Row>:
  match value:
    case N.Compound{members}:
      do Result<&2,&2,String,Row>:
        actual : Row <- named_row(context,value,parsed_id(B.field(value,"id")))
        return indexed(actual,U32.and(B.int_optional(B.field(value,"Slot"),0,False{}),255))
    case _: Done{Row{0,None{},1}}
def applied(+values:List<&2,CI.Input>,+discarded:U32,actual:Row) -> Decoded:
  Row{index,input,more} = actual
  match input:
    case None{}: Decoded{values,U32.add(discarded,more)}
    case Some{value}: Decoded{replace(values,index,value),U32.add(discarded,more)}
def rows(values:List<&2,N.Value>,+context:Context,current:Decoded) -> Result<&2,&2,String,Decoded>:
  match values current:
    case Nil{} _: Done{current}
    case value <> rest Decoded{slots,discarded}:
      do Result<&2,&2,String,Decoded>:
        actual : Row <- row(context,unwrap(value))
        rows(rest,context,applied(slots,discarded,actual))
def decode(+context:Context,count:Nat,value:Maybe<&2,N.Value>) -> Result<&2,&2,String,Decoded>:
  match value:
    case Some{N.ListTag{element,values}}: rows(values,context,Decoded{empty(count),0})
    case _: Done{Decoded{empty(count),0}}
def defaults(context:Context,id:String) -> Result<&2,&2,String,J.Value>:
  Context{recipes,maps} = context
  default_map(C.default_for(maps,id))
def profile_kind(context:Context,+key:I.ItemKey,patch:J.Value,plain:Bool) -> Result<&2,&2,String,Maybe<&2,F.FuelProfile>>:
  I.ItemKey{id,identity} = key
  match plain:
    case True{}: Done{None{}}
    case False{}:
      do Result<&2,&2,String,Maybe<&2,F.FuelProfile>>:
        map : J.Value <- defaults(context,id)
        admitted : F.FuelProfile <- FD.admit(map,key,patch)
        return Some{admitted}
def profile(+context:Context,+input:CI.Input) -> Result<&2,&2,String,Maybe<&2,F.FuelProfile>>:
  CI.Input{slot,+patch} = input
  match slot:
    case I.InvEmpty{}: Done{None{}}
    case I.InvStack{+key,count}:
      I.ItemKey{+id,identity} = key
      profile_kind(context,key,patch,String.is_empty(identity))
def admitted_more(value:Maybe<&2,F.FuelProfile>,tail:Admission) -> Admission:
  match value tail:
    case None{} _: tail
    case Some{F.FuelProfile{key,fuel,+token}} Admission{metadata,profiles}:
      Admission{token <> metadata,F.FuelProfile{key,fuel,token} <> profiles}
def admit(values:List<&2,CI.Input>,+context:Context) -> Result<&2,&2,String,Admission>:
  match values:
    case Nil{}: Done{Admission{[],[]}}
    case value <> rest:
      do Result<&2,&2,String,Admission>:
        entry : Maybe<&2,F.FuelProfile> <- profile(context,value)
        tail : Admission <- admit(rest,context)
        return admitted_more(entry,tail)
def patch_members(value:N.Value) -> Result<&2,&2,String,List<&2,N.Member>>:
  match value:
    case N.Compound{members}: Done{members}
    case _: Fail{"physical component patch requires compound"}
def component_member(values:List<&2,N.Member>) -> List<&2,N.Member>:
  match values:
    case Nil{}: []
    case head <> rest: [B.member("components",N.Compound{head <> rest})]
def stack_members(id:String,count:U32,index:U32,patch:List<&2,N.Member>) -> N.Value:
  N.Compound{List.append(&2,N.Member,[B.member("Slot",N.Byte{index}),B.member("id",N.StringTag{B.text(id)}),B.member("count",N.Int{count})],component_member(patch))}
def encode_slot(+context:Context,index:U32,+slot:I.Slot) -> Result<&2,&2,String,Maybe<&2,N.Value>>:
  match slot:
    case I.InvEmpty{}: Done{None{}}
    case I.InvStack{I.ItemKey{+id,identity},+amount}:
      do Result<&2,&2,String,Maybe<&2,N.Value>>:
        B.guard(U32.is_ge(amount,1) && U32.is_le(amount,99),"physical item count outside actual codec1..99")
        +map : J.Value <- defaults(context,id)
        delta : J.Value <- P.patch(map,I.ItemKey{id,identity})
        raw : N.Value <- P.encode(delta)
        fields : List<&2,N.Member> <- patch_members(raw)
        return Some{stack_members(id,amount,index,fields)}
def prepend(head:Maybe<&2,N.Value>,tail:List<&2,N.Value>) -> List<&2,N.Value>:
  match head:
    case None{}: tail
    case Some{value}: value <> tail
def encode_slots(values:List<&2,I.Slot>,+context:Context,+index:U32) -> Result<&2,&2,String,List<&2,N.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,N.Value>>:
        head : Maybe<&2,N.Value> <- encode_slot(context,index,value)
        tail : List<&2,N.Value> <- encode_slots(rest,context,U32.add(index,1))
        return prepend(head,tail)
