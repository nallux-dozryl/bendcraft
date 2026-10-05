import Base
import ./json.bend as J
import ./nbt.bend as N
import ./player_codec.bend as P
import ./u32_decimal.bend as Decimal

# The pinned effect registry is a closed enum, not an arbitrary JSON/string key.
# Duration is the complete signed Java int bit pattern; order and duplicates
# are semantic and survive every typed/JSON/NBT conversion.
type EffectType is Data:
  Absorption{}
  BadOmen{}
  Blindness{}
  BreathOfTheNautilus{}
  ConduitPower{}
  Darkness{}
  DolphinsGrace{}
  FireResistance{}
  Glowing{}
  Haste{}
  HealthBoost{}
  HeroOfTheVillage{}
  Hunger{}
  Infested{}
  InstantDamage{}
  InstantHealth{}
  Invisibility{}
  JumpBoost{}
  Levitation{}
  Luck{}
  MiningFatigue{}
  Nausea{}
  NightVision{}
  Oozing{}
  Poison{}
  RaidOmen{}
  Regeneration{}
  Resistance{}
  Saturation{}
  SlowFalling{}
  Slowness{}
  Speed{}
  Strength{}
  TrialOmen{}
  Unluck{}
  WaterBreathing{}
  Weakness{}
  Weaving{}
  WindCharged{}
  Wither{}

type Effect is Data:
  Effect{kind:EffectType,ticks:U32}

def kind_name(kind:EffectType) -> String:
  match kind:
    case Absorption{}: "minecraft:absorption"
    case BadOmen{}: "minecraft:bad_omen"
    case Blindness{}: "minecraft:blindness"
    case BreathOfTheNautilus{}: "minecraft:breath_of_the_nautilus"
    case ConduitPower{}: "minecraft:conduit_power"
    case Darkness{}: "minecraft:darkness"
    case DolphinsGrace{}: "minecraft:dolphins_grace"
    case FireResistance{}: "minecraft:fire_resistance"
    case Glowing{}: "minecraft:glowing"
    case Haste{}: "minecraft:haste"
    case HealthBoost{}: "minecraft:health_boost"
    case HeroOfTheVillage{}: "minecraft:hero_of_the_village"
    case Hunger{}: "minecraft:hunger"
    case Infested{}: "minecraft:infested"
    case InstantDamage{}: "minecraft:instant_damage"
    case InstantHealth{}: "minecraft:instant_health"
    case Invisibility{}: "minecraft:invisibility"
    case JumpBoost{}: "minecraft:jump_boost"
    case Levitation{}: "minecraft:levitation"
    case Luck{}: "minecraft:luck"
    case MiningFatigue{}: "minecraft:mining_fatigue"
    case Nausea{}: "minecraft:nausea"
    case NightVision{}: "minecraft:night_vision"
    case Oozing{}: "minecraft:oozing"
    case Poison{}: "minecraft:poison"
    case RaidOmen{}: "minecraft:raid_omen"
    case Regeneration{}: "minecraft:regeneration"
    case Resistance{}: "minecraft:resistance"
    case Saturation{}: "minecraft:saturation"
    case SlowFalling{}: "minecraft:slow_falling"
    case Slowness{}: "minecraft:slowness"
    case Speed{}: "minecraft:speed"
    case Strength{}: "minecraft:strength"
    case TrialOmen{}: "minecraft:trial_omen"
    case Unluck{}: "minecraft:unluck"
    case WaterBreathing{}: "minecraft:water_breathing"
    case Weakness{}: "minecraft:weakness"
    case Weaving{}: "minecraft:weaving"
    case WindCharged{}: "minecraft:wind_charged"
    case Wither{}: "minecraft:wither"

# Compare identifiers as values, then branch on Bool. Matching forty long
# String literals here expands the original checker pattern tree excessively.
def registered() -> List<&2,EffectType>:
  [
    Absorption{},
    BadOmen{},
    Blindness{},
    BreathOfTheNautilus{},
    ConduitPower{},
    Darkness{},
    DolphinsGrace{},
    FireResistance{},
    Glowing{},
    Haste{},
    HealthBoost{},
    HeroOfTheVillage{},
    Hunger{},
    Infested{},
    InstantDamage{},
    InstantHealth{},
    Invisibility{},
    JumpBoost{},
    Levitation{},
    Luck{},
    MiningFatigue{},
    Nausea{},
    NightVision{},
    Oozing{},
    Poison{},
    RaidOmen{},
    Regeneration{},
    Resistance{},
    Saturation{},
    SlowFalling{},
    Slowness{},
    Speed{},
    Strength{},
    TrialOmen{},
    Unluck{},
    WaterBreathing{},
    Weakness{},
    Weaving{},
    WindCharged{},
    Wither{}
  ]

def kind_match(equal:Bool,selected:EffectType,rest:Unit -> Result<&2,&2,String,EffectType>) -> Result<&2,&2,String,EffectType>:
  match equal:
    case True{}: Done{selected}
    case False{}: rest(Unit{})

def kind_lookup(values:List<&2,EffectType>,+value:String) -> Result<&2,&2,String,EffectType>:
  match values:
    case Nil{}: Fail{"unknown suspicious stew effect"}
    case +head <> rest: kind_match(String.eq(value,kind_name(head)),head,u => kind_lookup(rest,value))

def kind(value:String) -> Result<&2,&2,String,EffectType>:
  kind_lookup(registered(),value)

def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}

def positive(parsed:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match parsed:
    case None{}: Fail{"effect duration requires signed integer"}
    case Some{+value}:
      do Result<&2,&2,String,U32>:
        guard(U32.is_le(value,2147483647),"effect duration outside signed integer")
        return value

def negative(parsed:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match parsed:
    case None{}: Fail{"effect duration requires signed integer"}
    case Some{+value}:
      do Result<&2,&2,String,U32>:
        guard(U32.is_le(value,2147483648),"effect duration outside signed integer")
        return U32.sub(0,value)

def signed(value:String) -> Result<&2,&2,String,U32>:
  match value:
    case SCon{Chr{45},rest}: negative(J.u32_lexeme(rest))
    case _: positive(J.u32_lexeme(value))

def signed_text_checked(+word:U32,positive:Bool) -> String:
  match positive:
    case True{}: Decimal.show(word)
    case False{}: "-" ++ Decimal.show(U32.sub(0,word))

def signed_text(+word:U32) -> String:
  signed_text_checked(word,U32.is_le(word,2147483647))

def duration(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,U32>:
  match value:
    case None{}: Done{160}
    case Some{J.JNumber{raw}}: signed(raw)
    case _: Fail{"effect duration requires signed integer"}

def json_kind(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,EffectType>:
  match value:
    case Some{J.JString{id}}: kind(id)
    case _: Fail{"effect requires id"}

def json_fields(fields:List<&2,J.Member>,+seen_id:Bool,+seen_duration:Bool) -> Bool:
  match fields:
    case Nil{}: seen_id
    case J.JMember{"id",value} <> rest: Bool.not(seen_id) && json_fields(rest,True{},seen_duration)
    case J.JMember{"duration",value} <> rest: Bool.not(seen_duration) && json_fields(rest,seen_id,True{})
    case _: False{}

def json_effect(value:J.Value) -> Result<&2,&2,String,Effect>:
  match value:
    case J.JObject{+members}:
      do Result<&2,&2,String,Effect>:
        guard(json_fields(members,False{},False{}),"unknown, duplicate or missing effect field")
        selected : EffectType <- json_kind(J.member(J.JObject{members},"id"))
        ticks : U32 <- duration(J.member(J.JObject{members},"duration"))
        return Effect{selected,ticks}
    case _: Fail{"effect requires object"}

def json_effects(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,Effect>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,Effect>>:
        selected : Effect <- json_effect(value)
        tail : List<&2,Effect> <- json_effects(rest)
        return selected <> tail

def json_list(value:J.Value) -> Result<&2,&2,String,List<&2,Effect>>:
  match value:
    case J.JArray{values}: json_effects(values)
    case _: Fail{"effects requires array"}

def json_tag_checked(kind:EffectType,ticks:U32,default:Bool) -> J.Value:
  match default:
    case True{}: J.JObject{[J.JMember{"id",J.JString{kind_name(kind)}}]}
    case False{}: J.JObject{[J.JMember{"duration",J.JNumber{signed_text(ticks)}},J.JMember{"id",J.JString{kind_name(kind)}}]}

def json_effect_tag(effect:Effect) -> J.Value:
  Effect{kind,+ticks} = effect
  json_tag_checked(kind,ticks,U32.is_eq(ticks,160))

def json_tags(values:List<&2,Effect>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case effect <> rest: json_effect_tag(effect) <> json_tags(rest)

def schema(-A:Data,value:Result<&2,&2,P.Error,A>) -> Result<&2,&2,String,A>:
  match value:
    case Fail{cause}: Fail{"invalid suspicious stew component NBT"}
    case Done{result}: Done{result}

def nbt_duration(value:N.Value) -> Result<&2,&2,String,U32>:
  match value:
    case N.Int{bits}: Done{bits}
    case _: Fail{"effect duration requires Int tag"}

def nbt_duration_present(value:N.Value,present:Bool) -> Result<&2,&2,String,U32>:
  match present:
    case False{}: Done{160}
    case True{}: nbt_duration(value)

def nbt_kind(value:N.Value) -> Result<&2,&2,String,EffectType>:
  match value:
    case N.StringTag{text}:
      do Result<&2,&2,String,EffectType>:
        id : String <- schema(String,P.read_text(text))
        kind(id)
    case _: Fail{"effect id requires String tag"}

def nbt_effect(value:N.Value) -> Result<&2,&2,String,Effect>:
  match value:
    case N.Compound{+members}:
      do Result<&2,&2,String,Effect>:
        # Int duration is optional only when it is physically absent.
        +fields : List<&2,P.Field> <- schema(List<&2,P.Field>,P.fields(N.Compound{members},
          N.choose(List<&2,String>,["id"],["id","duration"],Nat.is_eq(List.length(&2,N.Member,members),1n))))
        selected : EffectType <- nbt_kind(P.field(fields,"id"))
        ticks : U32 <- nbt_duration_present(P.field(fields,"duration"),Nat.is_eq(List.length(&2,N.Member,members),2n))
        return Effect{selected,ticks}
    case _: Fail{"effect requires Compound tag"}

def nbt_effects_finish(head:Effect,result:Result<&2,&2,String,List<&2,Effect>>) -> Result<&2,&2,String,List<&2,Effect>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{tail}: Done{head <> tail}

def nbt_effects_next(head:Result<&2,&2,String,Effect>,rest:Unit -> Result<&2,&2,String,List<&2,Effect>>) -> Result<&2,&2,String,List<&2,Effect>>:
  match head:
    case Fail{message}: Fail{message}
    case Done{value}: nbt_effects_finish(value,rest(Unit{}))

def nbt_effects(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,Effect>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest: nbt_effects_next(nbt_effect(value),u => nbt_effects(rest))

def nbt_list(value:N.Value) -> Result<&2,&2,String,List<&2,Effect>>:
  match value:
    case N.ListTag{0,Nil{}}: Done{[]}
    case N.ListTag{10,values}: nbt_effects(values)
    case _: Fail{"effects requires Compound list"}

# Explicit duration retains every signed int word, including default160. The
# seventeen jar recipes all have nondefault duration, matching their Java tags.
def nbt_tag(effect:Effect) -> N.Value:
  Effect{kind,ticks} = effect
  N.Compound{[P.member("id",N.StringTag{P.text(kind_name(kind))}),P.member("duration",N.Int{ticks})]}

def nbt_tags(values:List<&2,Effect>) -> List<&2,N.Value>:
  match values:
    case Nil{}: []
    case effect <> rest: nbt_tag(effect) <> nbt_tags(rest)
