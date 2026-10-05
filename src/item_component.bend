import Base
import ./json.bend as J
import ./nbt.bend as N
import ./player_codec.bend as P
import ./inventory.bend as Inv
import ./crafting_recipe_components.bend as RecipeComponents
import ./item_component_effects.bend as E
import ./player_item_components.bend as Registered

# A closed, typed effective profile for the seventeen patched 26.3 recipes.
# The variant represents all seventeen fixed initialized defaults; only its
# ordered effect list varies. No opaque JSON or raw component string is stored
# as the component value. The foundation key remains the shared canonical wire
# identity produced and revalidated by RecipeComponents.resolve/stew_profile.
type Components is Data:
  SuspiciousStew{effects:List<&2,E.Effect>}

type Defaults is Data:
  InitializedSuspiciousStew{}

type Validated is Data:
  Validated{key:Inv.ItemKey,components:Components}

def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}

# Primary observed default map, addressed by the same initialized component-map
# digest carried in the verified 1658-row item-definition catalog.
def default_digest() -> String:
  "7f324fff5c212f399a85e4e3962f34f634fdedeeddff5f6bb3e39dbf229b5c25"

def observed_defaults() -> J.Value:
  J.JObject{[J.JMember{"minecraft:attack_animation",J.JObject{[]}},J.JMember{"minecraft:attribute_modifiers",J.JArray{[]}},J.JMember{"minecraft:break_sound",J.JString{"minecraft:entity.item.break"}},J.JMember{"minecraft:consumable",J.JObject{[]}},J.JMember{"minecraft:enchantments",J.JObject{[]}},J.JMember{"minecraft:food",J.JObject{[J.JMember{"can_always_eat",J.JBool{True{}}},J.JMember{"nutrition",J.JNumber{"6"}},J.JMember{"saturation",J.JNumber{"7.2000003"}}]}},J.JMember{"minecraft:interact_animation",J.JObject{[]}},J.JMember{"minecraft:item_model",J.JString{"minecraft:suspicious_stew"}},J.JMember{"minecraft:item_name",J.JObject{[J.JMember{"translate",J.JString{"item.minecraft.suspicious_stew"}}]}},J.JMember{"minecraft:lore",J.JArray{[]}},J.JMember{"minecraft:max_stack_size",J.JNumber{"1"}},J.JMember{"minecraft:rarity",J.JString{"common"}},J.JMember{"minecraft:repair_cost",J.JNumber{"0"}},J.JMember{"minecraft:suspicious_stew_effects",J.JArray{[]}},J.JMember{"minecraft:tooltip_display",J.JObject{[]}},J.JMember{"minecraft:use_effects",J.JObject{[]}},J.JMember{"minecraft:use_remainder",J.JObject{[J.JMember{"id",J.JString{"minecraft:bowl"}}]}}]}

def normalized_fixed(value:J.Value) -> J.Value:
  match value:
    case J.JObject{members}: J.JObject{RecipeComponents.sorted(members)}
    case _: value

def normalized_members(values:List<&2,J.Member>) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case J.JMember{key,value} <> rest: J.JMember{key,normalized_fixed(value)} <> normalized_members(rest)

def normalized(value:J.Value) -> J.Value:
  match value:
    case J.JObject{members}: J.JObject{RecipeComponents.sorted(normalized_members(members))}
    case _: value

def initial_number_valid(+raw:String) -> Bool:
  String.eq(raw,"0") || (String.eq(raw,"1") || (String.eq(raw,"6") || String.eq(raw,"7.2000003")))

def initial_member_values(values:List<&2,J.Member>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case J.JMember{name,value} <> rest: value <> initial_member_values(rest)

# JNumber owns a raw lexeme. Encoding comparison alone cannot validate a
# manually constructed AST whose numeric text injects object syntax.
def initial_values_valid(fuel:Nat,values:List<&2,J.Value>) -> Bool:
  match fuel values:
    case _ Nil{}: True{}
    case 0n _: False{}
    case 1n+n J.JNumber{raw} <> rest: initial_number_valid(raw) && initial_values_valid(n,rest)
    case 1n+n J.JArray{children} <> rest: initial_values_valid(n,List.append(&2,J.Value,children,rest))
    case 1n+n J.JObject{members} <> rest: initial_values_valid(n,List.append(&2,J.Value,initial_member_values(members),rest))
    case 1n+n value <> rest: initial_values_valid(n,rest)

# Catalog initialization accepts exactly the pinned complete default profile,
# including all field shapes/values. Missing, duplicate, unknown or changed
# fields cannot produce the typed initialized-default token.
def initialize(+value:J.Value) -> Result<&2,&2,String,Defaults>:
  do Result<&2,&2,String,Defaults>:
    guard(initial_values_valid(128n,[value]),"invalid initialized default numeric lexeme or profile depth")
    guard(String.eq(J.encode(normalized(value)),J.encode(observed_defaults())),"missing or unsupported initialized suspicious stew defaults")
    return InitializedSuspiciousStew{}

def default_identity_checked(valid:Bool) -> Maybe<&2,Defaults>:
  match valid:
    case False{}: None{}
    case True{}: Some{InitializedSuspiciousStew{}}

def default_from_identity(+id:String,enabled:Bool,identity:String) -> Maybe<&2,Defaults>:
  default_identity_checked(enabled && String.eq(id,"minecraft:suspicious_stew") && String.eq(identity,default_digest()))

def profile(defaults:Defaults,+key:Inv.ItemKey) -> Result<&2,&2,String,Validated>:
  Inv.ItemKey{+id,components} = key
  do Result<&2,&2,String,Validated>:
    guard(String.eq(id,"minecraft:suspicious_stew"),"unsupported component-bearing item profile")
    effects_json : J.Value <- RecipeComponents.stew_profile(observed_defaults(),components)
    effects : List<&2,E.Effect> <- E.json_list(effects_json)
    return Validated{key,SuspiciousStew{effects}}

def validate(defaults:Maybe<&2,Defaults>,key:Inv.ItemKey) -> Result<&2,&2,String,Validated>:
  match defaults:
    case None{}: Fail{"item components require initialized defaults"}
    case Some{token}: profile(token,key)

def metadata_result(result:Result<&2,&2,String,Validated>) -> Maybe<&2,Inv.ItemMetadata>:
  match result:
    case Fail{message}: None{}
    case Done{Validated{key,components}}: Some{Inv.ItemMetadata{key,1}}

def metadata(defaults:Maybe<&2,Defaults>,key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  metadata_result(validate(defaults,key))

def profile_patch(components:Components) -> J.Value:
  SuspiciousStew{effects} = components
  J.JObject{[J.JMember{"minecraft:suspicious_stew_effects",J.JArray{E.json_tags(effects)}}]}

def key_initialized(defaults:Defaults,+id:String,components:Components) -> Result<&2,&2,String,Inv.ItemKey>:
  do Result<&2,&2,String,Inv.ItemKey>:
    guard(String.eq(id,"minecraft:suspicious_stew"),"unsupported component-bearing item profile")
    +identity : String <- RecipeComponents.resolve(observed_defaults(),profile_patch(components))
    guard(Nat.is_le(String.length(identity),Nat.add(65536n,String.length("BendCraftComponents1\t1\t"))),"item component profile exceeds bounded payload")
    return Inv.ItemKey{id,identity}

def key(defaults:Maybe<&2,Defaults>,id:String,components:Components) -> Result<&2,&2,String,Inv.ItemKey>:
  match defaults:
    case None{}: Fail{"item components require initialized defaults"}
    case Some{token}: key_initialized(token,id,components)

def patch_tag(components:Components) -> N.Value:
  SuspiciousStew{effects} = components
  N.Compound{[P.member("minecraft:suspicious_stew_effects",N.ListTag{10,E.nbt_tags(effects)})]}

def patch_read(result:Result<&2,&2,String,List<&2,E.Effect>>) -> Result<&2,&2,String,Components>:
  match result:
    case Fail{message}: Fail{message}
    case Done{effects}: Done{SuspiciousStew{effects}}

def patch_value(value:N.Value) -> Result<&2,&2,String,Components>:
  do Result<&2,&2,String,Components>:
    fields : List<&2,P.Field> <- E.schema(List<&2,P.Field>,P.fields(value,["minecraft:suspicious_stew_effects"]))
    patch_read(E.nbt_list(P.field(fields,"minecraft:suspicious_stew_effects")))

def key_from_patch(+defaults:Maybe<&2,Defaults>,id:String,value:N.Value) -> Result<&2,&2,String,Inv.ItemKey>:
  do Result<&2,&2,String,Inv.ItemKey>:
    typed : Components <- patch_value(value)
    key(defaults,id,typed)

def slot_metadata(defaults:Maybe<&2,Defaults>,slot:Inv.Slot) -> Result<&2,&2,String,Inv.ItemMetadata>:
  match slot:
    case Inv.InvEmpty{}: Done{Inv.ItemMetadata{Inv.ItemKey{"",""},1}}
    case Inv.InvStack{+key,+count}:
      do Result<&2,&2,String,Inv.ItemMetadata>:
        admitted : Validated <- validate(defaults,key)
        guard(U32.is_eq(count,1),"suspicious stew count requires one item")
        return Inv.ItemMetadata{key,1}

# Canonical transport shape only; initialized catalog authority remains the
# separate player_item_definitions.metadata/codec boundary.
def structural_slot_metadata(slot:Inv.Slot) -> Result<&2,&2,String,Inv.ItemMetadata>:
  Registered.structural_slot_metadata(slot)

def installed(result:Inv.Inventory & Bool) -> Inv.Inventory & Result<&2,&2,String,Unit>:
  (owner,accepted) = result
  match accepted:
    case False{}: (owner,Fail{"item component installation refused bounds or stack"})
    case True{}: (owner,Done{Unit{}})

# This is the actual foundation Inventory owner, including its complete affine
# backing array and logical size. Component refusal returns it untouched before
# the existing admitted load operation can inspect or mutate any slot.
def install(owner:Inv.Inventory,index:U32,slot:Inv.Slot,admission:Result<&2,&2,String,Inv.ItemMetadata>) -> Inv.Inventory & Result<&2,&2,String,Unit>:
  match admission:
    case Fail{message}: (owner,Fail{message})
    case Done{metadata}: installed(Inv.load_slot(owner,index,slot,metadata))

def load(defaults:Maybe<&2,Defaults>,owner:Inv.Inventory,index:U32,+slot:Inv.Slot) -> Inv.Inventory & Result<&2,&2,String,Unit>:
  install(owner,index,slot,slot_metadata(defaults,slot))

def modified_slot_tag(validated:Validated,count:U32) -> N.Value:
  Validated{Inv.ItemKey{id,identity},components} = validated
  N.Compound{[P.member("id",N.StringTag{P.text(id)}),P.member("count",N.Int{count}),P.member("components",patch_tag(components))]}

def encode_modified_slot(defaults:Maybe<&2,Defaults>,+key:Inv.ItemKey,+count:U32) -> Result<&2,&2,String,N.Value>:
  Inv.ItemKey{id,+identity} = key
  do Result<&2,&2,String,N.Value>:
    admitted : Validated <- validate(defaults,key)
    guard(Bool.not(String.is_empty(identity)) && U32.is_eq(count,1),"modified suspicious stew requires canonical components and one item")
    return modified_slot_tag(admitted,count)

def nbt_id(value:N.Value) -> Result<&2,&2,String,String>:
  match value:
    case N.StringTag{text}: E.schema(String,P.read_text(text))
    case _: Fail{"component stack id requires String tag"}

def decode_modified_slot(+defaults:Maybe<&2,Defaults>,value:N.Value) -> Result<&2,&2,String,Inv.Slot>:
  do Result<&2,&2,String,Inv.Slot>:
    +fields : List<&2,P.Field> <- E.schema(List<&2,P.Field>,P.fields(value,["id","count","components"]))
    id : String <- nbt_id(P.field(fields,"id"))
    +count : U32 <- E.schema(U32,P.int_value(P.field(fields,"count"),"count"))
    guard(U32.is_eq(count,1),"suspicious stew count requires one item")
    value : Inv.ItemKey <- key_from_patch(defaults,id,P.field(fields,"components"))
    return Inv.InvStack{value,count}

def load_decoded(defaults:Maybe<&2,Defaults>,owner:Inv.Inventory,index:U32,result:Result<&2,&2,String,Inv.Slot>) -> Inv.Inventory & Result<&2,&2,String,Unit>:
  match result:
    case Fail{message}: (owner,Fail{message})
    case Done{slot}: load(defaults,owner,index,slot)

def load_tag(+defaults:Maybe<&2,Defaults>,owner:Inv.Inventory,index:U32,value:N.Value) -> Inv.Inventory & Result<&2,&2,String,Unit>:
  load_decoded(defaults,owner,index,decode_modified_slot(defaults,value))

# Standalone physical stack NBT boundary used by the targeted reference replay.
# The saved inventory writer composes encode_modified_slot within its own root.
def nbt_limits() -> N.Limits:
  N.Limits{65536,8,16384}

def encoded_tag(result:Result<&2,&2,String,N.Value>) -> Result<&2,&2,String,List<&2,U32>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: N.encode_with(nbt_limits(),N.Root{P.text(""),value})

def encode_bytes(defaults:Maybe<&2,Defaults>,key:Inv.ItemKey,count:U32) -> Result<&2,&2,String,List<&2,U32>>:
  encoded_tag(encode_modified_slot(defaults,key,count))

def decoded_root(defaults:Maybe<&2,Defaults>,result:Result<&2,&2,String,N.Root>) -> Result<&2,&2,String,Inv.Slot>:
  match result:
    case Fail{message}: Fail{message}
    case Done{N.Root{name,value}}:
      do Result<&2,&2,String,Inv.Slot>:
        text : String <- E.schema(String,P.read_text(name))
        guard(String.is_empty(text),"component stack NBT requires unnamed root")
        decode_modified_slot(defaults,value)

def decode_bytes(defaults:Maybe<&2,Defaults>,bytes:List<&2,U32>) -> Result<&2,&2,String,Inv.Slot>:
  decoded_root(defaults,N.decode_with(nbt_limits(),bytes))

def load_bytes(+defaults:Maybe<&2,Defaults>,owner:Inv.Inventory,index:U32,bytes:List<&2,U32>) -> Inv.Inventory & Result<&2,&2,String,Unit>:
  load_decoded(defaults,owner,index,decode_bytes(defaults,bytes))
