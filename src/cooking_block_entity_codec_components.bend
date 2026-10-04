import Base
import ./json.bend as J
import ./nbt.bend as N
import ./inventory.bend as I
import ./crafting_recipe.bend as R
import ./crafting_recipe_decoder.bend as D
import ./crafting_recipe_components.bend as C
import ./crafting_recipe_component_registry.bend as Registry
import ./cooking_block_entity_codec_nbt.bend as B

type Patch is Data:
  Patch{members:List<&2,J.Member>,discarded:U32}

def unchanged(+a:J.Value,+b:Maybe<&2,J.Value>) -> Bool:
  match b:
    case None{}: False{}
    case Some{value}: String.eq(J.encode(a),J.encode(value))
def additions(values:List<&2,J.Member>,+defaults:J.Value) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case +head <> +rest:
      J.JMember{id,+value} = head
      R.choose(List<&2,J.Member>,additions(rest,defaults),head <> additions(rest,defaults),unchanged(value,J.member(defaults,id)))
def removals(values:List<&2,J.Member>,+effective:J.Value) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case J.JMember{+id,value} <> +rest:
      R.choose(List<&2,J.Member>,removals(rest,effective),J.JMember{"!" ++ id,J.JObject{[]}} <> removals(rest,effective),Maybe.is_some(&2,J.Value,J.member(effective,id)))
def diff(+defaults:J.Value,+effective:J.Value) -> Result<&2,&2,String,J.Value>:
  match defaults effective:
    case J.JObject{original} J.JObject{actual}: Done{J.JObject{List.append(&2,J.Member,additions(actual,defaults),removals(original,effective))}}
    case _ _: Fail{"component patch reconstruction requires initialized and effective object maps"}
def effective_fields(marker:String,limit:String,body:String) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    B.guard(String.eq(marker,"BendCraftComponents1"),"unsupported component identity envelope")
    J.parse_bounded(body,1048576n,256)
def effective(parts:List<&2,String>) -> Result<&2,&2,String,J.Value>:
  match parts:
    case marker <> limit <> body <> Nil{}: effective_fields(marker,limit,body)
    case _: Fail{"modified identity requires one complete canonical component envelope"}
def authenticated(+defaults:J.Value,+key:I.ItemKey,+value:J.Value) -> Result<&2,&2,String,J.Value>:
  I.ItemKey{id,+identity} = key
  do Result<&2,&2,String,J.Value>:
    changes : List<&2,C.Change> <- C.decode(value)
    actual : String <- C.resolve(defaults,value)
    B.guard(String.eq(actual,identity),"reconstructed patch differs from exact component identity")
    B.guard(String.is_empty(identity) || Maybe.is_some(&2,U32,R.component_limit(identity)),"invalid resolved component combination")
    return value
def patch_kind(+defaults:J.Value,+key:I.ItemKey,plain:Bool) -> Result<&2,&2,String,J.Value>:
  I.ItemKey{id,identity} = key
  match plain:
    case True{}: authenticated(defaults,key,J.JObject{[]})
    case False{}:
      do Result<&2,&2,String,J.Value>:
        candidate : J.Value <- effective(String.split(identity,'\t'))
        delta : J.Value <- diff(defaults,candidate)
        authenticated(defaults,key,delta)
# Envelope parsing only produces a candidate. Shared codec/default equality is
# required before this helper can return any reconstructed patch.
def patch(+defaults:J.Value,+key:I.ItemKey) -> Result<&2,&2,String,J.Value>:
  I.ItemKey{id,identity} = key
  patch_kind(defaults,key,String.is_empty(identity))
def kind(+id:String) -> U32:
  R.choose(U32,1,R.choose(U32,2,R.choose(U32,3,R.choose(U32,4,R.choose(U32,5,R.choose(U32,6,R.choose(U32,7,0,String.eq(id,"minecraft:enchantment_glint_override")),String.eq(id,"minecraft:unbreakable")),String.eq(id,"minecraft:suspicious_stew_effects")),String.eq(id,"minecraft:repair_cost")),String.eq(id,"minecraft:damage")),String.eq(id,"minecraft:max_damage")),String.eq(id,"minecraft:max_stack_size"))
def json_number(value:Maybe<&2,U32>) -> Maybe<&2,J.Value>:
  match value:
    case None{}: None{}
    case Some{bits}: Some{J.JNumber{B.signed_text(bits)}}
def json_bool(value:Maybe<&2,Bool>) -> Maybe<&2,J.Value>:
  match value:
    case None{}: None{}
    case Some{flag}: Some{J.JBool{flag}}
def effect_id(value:Maybe<&2,N.Value>) -> Result<&2,&2,String,String>:
  match value:
    case None{}: Fail{"stew effect requires id"}
    case Some{raw}:
      do Result<&2,&2,String,String>:
        text : String <- B.string(raw)
        +id : String = D.qualified(text)
        B.guard(Registry.effect(id),"unknown stew effect id")
        return id
def effect(+value:N.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- effect_id(B.field(value,"id"))
    return C.effect_entry(id,B.signed_text(B.int_optional(B.field(value,"duration"),160,False{})))
# NbtOps list streams unwrap the singleton empty-name compound wrapper.
def effect_unwrap(value:N.Value) -> N.Value:
  match value:
    case N.Compound{N.Member{N.Text{Nil{}},inner} <> Nil{}}: inner
    case _: value
def effect_more(head:Result<&2,&2,String,J.Value>,tail:List<&2,J.Value>) -> List<&2,J.Value>:
  match head:
    case Fail{message}: tail
    case Done{value}: value <> tail
def effects(values:List<&2,N.Value>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: effect_more(effect(effect_unwrap(head)),effects(rest))
def stew(value:N.Value) -> Maybe<&2,J.Value>:
  match value:
    case N.ListTag{element,values}: Some{J.JArray{effects(values)}}
    case _: None{}
def component_shape(parsed_kind:U32,value:N.Value) -> Result<&2,&2,String,Maybe<&2,J.Value>>:
  match parsed_kind value:
    case 1 _: Done{json_number(B.int_tag(value,False{}))}
    case 2 _: Done{json_number(B.int_tag(value,False{}))}
    case 3 _: Done{json_number(B.int_tag(value,False{}))}
    case 4 _: Done{json_number(B.int_tag(value,False{}))}
    case 5 _: Done{stew(value)}
    case 6 N.Compound{members}: Done{Some{J.JObject{[]}}}
    case 6 _: Done{None{}}
    case 7 _: Done{json_bool(B.bool_tag(value))}
    case _ _: Fail{"persistent component setter outside verified physical codec domain"}
def field_candidate(name:String,value:J.Value,normalized:Result<&2,&2,String,C.Change>) -> Maybe<&2,J.Member>:
  match normalized:
    case Fail{message}: None{}
    case Done{C.SetComponent{id,actual}}: Some{J.JMember{id,actual}}
    case Done{C.RemoveComponent{id}}: Some{J.JMember{"!" ++ id,J.JObject{[]}}}
def converted(+name:String,value:Maybe<&2,J.Value>) -> Maybe<&2,J.Member>:
  match value:
    case None{}: None{}
    case Some{+actual}: field_candidate(name,actual,C.change(name,actual))
def removed(+id:String,known:Bool,value:N.Value) -> Result<&2,&2,String,Maybe<&2,J.Member>>:
  match known value:
    case False{} _: Done{None{}}
    case True{} N.Compound{members}: Done{Some{J.JMember{"!" ++ id,J.JObject{[]}}}}
    case True{} _: Done{None{}}
def set_known(+id:String,value:N.Value,known:Bool) -> Result<&2,&2,String,Maybe<&2,J.Member>>:
  match known:
    case False{}: Done{None{}}
    case True{}:
      do Result<&2,&2,String,Maybe<&2,J.Member>>:
        shape : Maybe<&2,J.Value> <- component_shape(kind(id),value)
        return converted(id,shape)
def change(+name:String,value:N.Value) -> Result<&2,&2,String,Maybe<&2,J.Member>>:
  match name:
    case SCon{Chr{33},rest}:
      +id = D.qualified(rest)
      removed(id,Registry.persistent(id),value)
    case _:
      +id = D.qualified(name)
      set_known(id,value,Registry.persistent(id))
def member_name(value:N.Text) -> Result<&2,&2,String,String>:
  N.Text{units} = value
  B.ascii(units,"")
def patch_member(name:Result<&2,&2,String,String>,value:N.Value) -> Result<&2,&2,String,Maybe<&2,J.Member>>:
  match name:
    case Fail{message}: Done{None{}}
    case Done{actual}: change(actual,value)
def added(head:Maybe<&2,J.Member>,+tail:Patch) -> Patch:
  match head tail:
    case None{} Patch{members,count}: Patch{members,U32.add(count,1)}
    case Some{value} Patch{members,count}: Patch{value <> members,count}
def member_dispatch(duplicate:Bool,name:N.Text,value:N.Value,tail:Result<&2,&2,String,Patch>) -> Result<&2,&2,String,Patch>:
  match duplicate:
    case True{}: tail
    case False{}:
      do Result<&2,&2,String,Patch>:
        head : Maybe<&2,J.Member> <- patch_member(member_name(name),value)
        rest : Patch <- tail
        return added(head,rest)
def members(values:List<&2,N.Member>) -> Result<&2,&2,String,Patch>:
  match values:
    case Nil{}: Done{Patch{[],0}}
    case N.Member{+name,value} <> +rest: member_dispatch(Maybe.is_some(&2,N.Value,B.find(rest,name)),name,value,members(rest))
def decode(value:Maybe<&2,N.Value>) -> Result<&2,&2,String,Patch>:
  match value:
    case Some{N.Compound{values}}: members(values)
    case _: Done{Patch{[],0}}
def signed(raw:String) -> Result<&2,&2,String,U32>:
  match raw:
    case SCon{Chr{45},rest}:
      do Result<&2,&2,String,U32>:
        value : U32 <- D.number(J.JNumber{rest})
        return U32.sub(0,value)
    case _: D.number(J.JNumber{raw})
def numeric(value:J.Value) -> Result<&2,&2,String,N.Value>:
  match value:
    case J.JNumber{raw}:
      do Result<&2,&2,String,N.Value>:
        bits : U32 <- signed(raw)
        return N.Int{bits}
    case _: Fail{"normalized integer component requires number"}
def effect_tag(+value:J.Value) -> Result<&2,&2,String,N.Value>:
  do Result<&2,&2,String,N.Value>:
    +id : String <- D.text_field(value,"id")
    +ticks : String <- C.duration(J.member(value,"duration"))
    bits : U32 <- signed(ticks)
    return N.Compound{R.choose(List<&2,N.Member>,[B.member("id",N.StringTag{B.text(id)})],[B.member("id",N.StringTag{B.text(id)}),B.member("duration",N.Int{bits})],String.eq(ticks,"160"))}
def effect_tags(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,N.Value>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,N.Value>>:
        actual : N.Value <- effect_tag(head)
        tail : List<&2,N.Value> <- effect_tags(rest)
        return actual <> tail
def encoded_component(parsed_kind:U32,value:J.Value) -> Result<&2,&2,String,N.Value>:
  match parsed_kind value:
    case 5 J.JArray{values}:
      do Result<&2,&2,String,N.Value>:
        +tags : List<&2,N.Value> <- effect_tags(values)
        return N.ListTag{R.choose(U32,0,10,List.is_empty(&2,N.Value,tags)),tags}
    case 6 _: Done{N.Compound{[]}}
    case 7 J.JBool{flag}: Done{N.Byte{Bool.to_u32(flag)}}
    case _ _: numeric(value)
def encode_changes(values:List<&2,C.Change>) -> Result<&2,&2,String,List<&2,N.Member>>:
  match values:
    case Nil{}: Done{[]}
    case C.RemoveComponent{id} <> rest:
      do Result<&2,&2,String,List<&2,N.Member>>:
        tail : List<&2,N.Member> <- encode_changes(rest)
        return B.member("!" ++ id,N.Compound{[]}) <> tail
    case C.SetComponent{+id,value} <> rest:
      do Result<&2,&2,String,List<&2,N.Member>>:
        tag : N.Value <- encoded_component(kind(id),value)
        tail : List<&2,N.Member> <- encode_changes(rest)
        return B.member(id,tag) <> tail
def encode(value:J.Value) -> Result<&2,&2,String,N.Value>:
  do Result<&2,&2,String,N.Value>:
    changes : List<&2,C.Change> <- C.decode(value)
    members : List<&2,N.Member> <- encode_changes(changes)
    return N.Compound{members}
