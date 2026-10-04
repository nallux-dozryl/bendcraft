import Base
import ./json.bend as J
import ./crafting_recipe_component_registry.bend as Registry
import ./inventory.bend as Inv

# The inventory foundation owns opaque canonical identities. Here only
# explicitly implemented codec types may produce a resolved identity.
type Change is Data:
  SetComponent{id:String,value:J.Value}
  RemoveComponent{id:String}

type Default is Data:
  Default{id:String,components:J.Value}

def choose(-A:Data,yes:A,no:A,test:Bool) -> A:
  match test:
    case True{}: yes
    case False{}: no

def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}

def qualified(+id:String) -> String:
  choose(String,id,"minecraft:" ++ id,String.contains(id,":"))

def signed_positive(raw:String,parsed:Maybe<&2,U32>) -> Result<&2,&2,String,String>:
  match parsed:
    case None{}: Fail{"component codec outside supported domain"}
    case Some{+value}:
      do Result<&2,&2,String,String>:
        guard(U32.is_le(value,2147483647),"component codec outside supported domain")
        return U32.show(value)

def signed_negative(parsed:Maybe<&2,U32>) -> Result<&2,&2,String,String>:
  match parsed:
    case None{}: Fail{"component codec outside supported domain"}
    case Some{+value}:
      do Result<&2,&2,String,String>:
        guard(U32.is_le(value,2147483648),"component codec outside supported domain")
        return choose(String,"0","-" ++ U32.show(value),U32.is_zero(value))

def signed(+raw:String) -> Result<&2,&2,String,String>:
  match raw:
    case SCon{Chr{45},rest}: signed_negative(J.u32_lexeme(rest))
    case _: signed_positive(raw,J.u32_lexeme(raw))

def duration(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,String>:
  match value:
    case None{}: Done{"160"}
    case Some{J.JNumber{raw}}: signed(raw)
    # The pinned field codec is lenientOptionalFieldOf, including malformed
    # nonnumeric values. Numeric coercions outside signed integer lexemes are
    # an explicit codec boundary rather than an invented approximation.
    case Some{other}: Done{"160"}

def effect_id(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,String>:
  match value:
    case Some{J.JString{raw}}:
      do Result<&2,&2,String,String>:
        +id : String = qualified(raw)
        guard(Registry.effect(id),"unknown suspicious stew effect")
        return id
    case _: Fail{"suspicious stew effect requires id"}

def effect_entry(+id:String,+ticks:String) -> J.Value:
  J.JObject{choose(List<&2,J.Member>,[J.JMember{"id",J.JString{id}}],
    [J.JMember{"duration",J.JNumber{ticks}},J.JMember{"id",J.JString{id}}],String.eq(ticks,"160"))}

def effect(value:J.Value) -> Result<&2,&2,String,J.Value>:
  match value:
    case J.JObject{+members}:
      do Result<&2,&2,String,J.Value>:
        id : String <- effect_id(J.member(J.JObject{members},"id"))
        ticks : String <- duration(J.member(J.JObject{members},"duration"))
        return effect_entry(id,ticks)
    case _: Fail{"suspicious stew effect must be an object"}

def effects(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- effect(value)
        tail : List<&2,J.Value> <- effects(rest)
        return head <> tail

def bounded_read(value:Maybe<&2,U32>,minimum:U32,maximum:U32) -> Result<&2,&2,String,J.Value>:
  match value:
    case None{}: Fail{"integer component outside its range"}
    case Some{+amount}:
      do Result<&2,&2,String,J.Value>:
        guard(U32.is_ge(amount,minimum) && U32.is_le(amount,maximum),"integer component outside its range")
        return J.JNumber{U32.show(amount)}

def bounded_number(value:J.Value,minimum:U32,maximum:U32) -> Result<&2,&2,String,J.Value>:
  match value:
    case J.JNumber{raw}:
      do Result<&2,&2,String,J.Value>:
        normalized : String <- signed(raw)
        # These components' codecs are nonnegative or positive integer ranges.
        amount : Maybe<&2,U32> = U32.read(normalized)
        bounded_read(amount,minimum,maximum)
    case _: Fail{"integer component requires a number"}

def value_codec(id:String,value:J.Value) -> Result<&2,&2,String,J.Value>:
  match id value:
    case "minecraft:suspicious_stew_effects" J.JArray{values}:
      do Result<&2,&2,String,J.Value>:
        entries : List<&2,J.Value> <- effects(values)
        return J.JArray{entries}
    case "minecraft:max_stack_size" _: bounded_number(value,1,99)
    case "minecraft:max_damage" _: bounded_number(value,1,2147483647)
    case "minecraft:damage" _: bounded_number(value,0,2147483647)
    case "minecraft:repair_cost" _: bounded_number(value,0,2147483647)
    case "minecraft:unbreakable" J.JObject{members}: Done{J.JObject{[]}}
    case "minecraft:enchantment_glint_override" J.JBool{value}: Done{J.JBool{value}}
    case "minecraft:suspicious_stew_effects" _: Fail{"suspicious stew effects requires an array"}
    case "minecraft:unbreakable" _: Fail{"unbreakable component requires an object"}
    case "minecraft:enchantment_glint_override" _: Fail{"glint component requires a boolean"}
    case _ _: Fail{"component codec outside supported domain"}

def removal_value(value:J.Value) -> Bool:
  match value:
    case J.JObject{Nil{}}: True{}
    case _: False{}

def change(name:String,+value:J.Value) -> Result<&2,&2,String,Change>:
  match name:
    case SCon{Chr{33},rest}:
      do Result<&2,&2,String,Change>:
        +id : String = qualified(rest)
        guard(Registry.persistent(id),"unknown or transient removed component")
        guard(removal_value(value),"component codec outside supported domain")
        return RemoveComponent{id}
    case _:
      do Result<&2,&2,String,Change>:
        +id : String = qualified(name)
        guard(Registry.persistent(id),"unknown or transient component")
        normalized : J.Value <- value_codec(id,value)
        return SetComponent{id,normalized}

def change_name(value:Change) -> String:
  match value:
    case SetComponent{id,value}: id
    case RemoveComponent{id}: id

def seen(values:List<&2,Change>,+name:String) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: String.eq(change_name(value),name) || seen(rest,name)

def changes(members:List<&2,J.Member>,+previous:List<&2,Change>) -> Result<&2,&2,String,List<&2,Change>>:
  match members:
    case Nil{}: Done{List.reverse(&2,Change,previous)}
    case J.JMember{name,value} <> rest:
      do Result<&2,&2,String,List<&2,Change>>:
        +parsed : Change <- change(name,value)
        guard(Bool.not(seen(previous,change_name(parsed))),"duplicate effective component key")
        changes(rest,parsed <> previous)

def decode(value:J.Value) -> Result<&2,&2,String,List<&2,Change>>:
  match value:
    case J.JObject{members}: changes(members,[])
    case _: Fail{"recipe components must be an object"}

def remove_match(equal:Bool,head:J.Member,tail:List<&2,J.Member>) -> List<&2,J.Member>:
  match equal:
    case True{}: tail
    case False{}: head <> tail

def remove(members:List<&2,J.Member>,+name:String) -> List<&2,J.Member>:
  match members:
    case Nil{}: []
    case +head <> rest:
      J.JMember{key,value} = head
      remove_match(String.eq(key,name),head,remove(rest,name))

def apply(values:List<&2,Change>,members:List<&2,J.Member>) -> List<&2,J.Member>:
  match values:
    case Nil{}: members
    case SetComponent{+id,value} <> rest: apply(rest,J.JMember{id,value} <> remove(members,id))
    case RemoveComponent{id} <> rest: apply(rest,remove(members,id))

def compared(result:(String & String) & Cmp) -> Bool:
  (strings,order) = result
  Cmp.is_lt(order)

def insert(members:List<&2,J.Member>,+entry:J.Member) -> List<&2,J.Member>:
  match members:
    case Nil{}: [entry]
    case +head <> +rest:
      J.JMember{b,other} = head
      J.JMember{a,value} = entry
      choose(List<&2,J.Member>,entry <> head <> rest,head <> insert(rest,entry),compared(String.cmp(a,b)))

def sorted(members:List<&2,J.Member>) -> List<&2,J.Member>:
  match members:
    case Nil{}: []
    case head <> rest: insert(sorted(rest),head)

def choose_unsigned(value:Maybe<&2,U32>,fallback:U32) -> U32:
  match value:
    case None{}: fallback
    case Some{number}: number

def unsigned_default(value:Maybe<&2,J.Value>,fallback:U32) -> U32:
  match value:
    case Some{J.JNumber{raw}}:
      result = J.u32_lexeme(raw)
      choose_unsigned(result,fallback)
    case _: fallback

def envelope_checked(valid:Bool,limit:U32,effective:String) -> String:
  match valid:
    case False{}: "BendCraftInvalidComponents1\t" ++ effective
    case True{}: "BendCraftComponents1\t" ++ U32.show(limit) ++ "\t" ++ effective

def identity(+defaults:List<&2,J.Member>,+effective:List<&2,J.Member>) -> String:
  +original = J.encode(J.JObject{sorted(defaults)})
  +actual = J.encode(J.JObject{sorted(effective)})
  +limit = unsigned_default(J.member(J.JObject{effective},"minecraft:max_stack_size"),1)
  valid = Bool.not(Maybe.is_some(&2,J.Value,J.member(J.JObject{effective},"minecraft:max_damage"))) || U32.is_le(limit,1)
  choose(String,"",envelope_checked(valid,limit,actual),String.eq(original,actual))

def resolve(defaults:J.Value,patch:J.Value) -> Result<&2,&2,String,String>:
  match defaults:
    case J.JObject{+members}:
      do Result<&2,&2,String,String>:
        edits : List<&2,Change> <- decode(patch)
        return identity(members,apply(edits,members))
    case _: Fail{"recipe output requires initialized component defaults"}

def default_for(values:List<&2,Default>,+wanted:String) -> Maybe<&2,J.Value>:
  match values:
    case Nil{}: None{}
    case Default{id,components} <> rest:
      choose(Maybe<&2,J.Value>,Some{components},default_for(rest,wanted),String.eq(id,wanted))

def patch_members(values:List<&2,Change>) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case SetComponent{id,value} <> rest: J.JMember{id,value} <> patch_members(rest)
    case RemoveComponent{id} <> rest: J.JMember{"!" ++ id,J.JObject{[]}} <> patch_members(rest)

def patch_text_edits(values:List<&2,Change>) -> Result<&2,&2,String,String>:
  match values:
    case Nil{}: Done{""}
    case _: Done{"BendCraftPatch1\t" ++ J.encode(J.JObject{sorted(patch_members(values))})}

def patch_text(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,String>:
  match value:
    case None{}: Done{""}
    case Some{raw}:
      do Result<&2,&2,String,String>:
        edits : List<&2,Change> <- decode(raw)
        patch_text_edits(edits)

# Admission for the inventory owner's closed suspicious-stew profile. Rebuild
# the complete effective identity from its initialized defaults; parsing an
# envelope header alone never authorizes a component-bearing inventory key.
def stew_effects(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  match value:
    case Some{J.JArray{entries}}:
      do Result<&2,&2,String,J.Value>:
        normalized : List<&2,J.Value> <- effects(entries)
        return J.JArray{normalized}
    case _: Fail{"suspicious stew profile requires effects"}

def stew_effective(defaults:J.Value,+components:String,effective:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    +normalized : J.Value <- stew_effects(J.member(effective,"minecraft:suspicious_stew_effects"))
    expected : String <- resolve(defaults,J.JObject{[J.JMember{"minecraft:suspicious_stew_effects",normalized}]})
    guard(String.eq(expected,components),"suspicious stew profile changes defaults or is not canonical")
    return normalized

def stew_fields(+defaults:J.Value,+components:String,fields:List<&2,String>) -> Result<&2,&2,String,J.Value>:
  match fields:
    case marker <> Nil{}:
      do Result<&2,&2,String,J.Value>:
        guard(String.is_empty(marker),"unknown suspicious stew profile envelope")
        stew_effective(defaults,components,defaults)
    case marker <> limit <> payload <> Nil{}:
      do Result<&2,&2,String,J.Value>:
        guard(String.eq(marker,"BendCraftComponents1") && String.eq(limit,"1"),"invalid suspicious stew profile envelope")
        effective : J.Value <- J.parse_bounded(payload,65536n,32)
        stew_effective(defaults,components,effective)
    case _: Fail{"invalid suspicious stew profile envelope"}

def stew_profile(defaults:J.Value,+components:String) -> Result<&2,&2,String,J.Value>:
  stew_fields(defaults,components,String.split(components,'\t'))

def stew_metadata_checked(profile:Result<&2,&2,String,J.Value>,key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  match profile:
    case Fail{message}: None{}
    case Done{effects}: Some{Inv.ItemMetadata{key,1}}

def stew_metadata_item(stew:Bool,defaults:J.Value,+key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  match stew:
    case False{}: None{}
    case True{}:
      Inv.ItemKey{id,components} = key
      stew_metadata_checked(stew_profile(defaults,components),key)

def stew_metadata(defaults:J.Value,+key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  Inv.ItemKey{id,components} = key
  stew_metadata_item(String.eq(id,"minecraft:suspicious_stew"),defaults,key)
