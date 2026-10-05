import Base
import ./item_component_effects.bend as E

# Evidence excludes each registered identifier independently. It does not
# assume the implementation's Result or a successful/failed decoder outcome.
def absent(values:List<&2,E.EffectType>,+value:String) -> Type:
  match values:
    case Nil{}: Unit
    case head <> rest: {String.eq(value,E.kind_name(head)) == False{} : Bool} & absent(rest,value)

law every_registered_effect_identifier_has_its_original_type:
  for +kind:E.EffectType
  {E.kind(E.kind_name(kind)) == Done{kind} : Result<&2,&2,String,E.EffectType>}
def every_registered_effect_identifier_has_its_original_type(kind):
  match kind:
    case E.Absorption{}: {==}
    case E.BadOmen{}: {==}
    case E.Blindness{}: {==}
    case E.BreathOfTheNautilus{}: {==}
    case E.ConduitPower{}: {==}
    case E.Darkness{}: {==}
    case E.DolphinsGrace{}: {==}
    case E.FireResistance{}: {==}
    case E.Glowing{}: {==}
    case E.Haste{}: {==}
    case E.HealthBoost{}: {==}
    case E.HeroOfTheVillage{}: {==}
    case E.Hunger{}: {==}
    case E.Infested{}: {==}
    case E.InstantDamage{}: {==}
    case E.InstantHealth{}: {==}
    case E.Invisibility{}: {==}
    case E.JumpBoost{}: {==}
    case E.Levitation{}: {==}
    case E.Luck{}: {==}
    case E.MiningFatigue{}: {==}
    case E.Nausea{}: {==}
    case E.NightVision{}: {==}
    case E.Oozing{}: {==}
    case E.Poison{}: {==}
    case E.RaidOmen{}: {==}
    case E.Regeneration{}: {==}
    case E.Resistance{}: {==}
    case E.Saturation{}: {==}
    case E.SlowFalling{}: {==}
    case E.Slowness{}: {==}
    case E.Speed{}: {==}
    case E.Strength{}: {==}
    case E.TrialOmen{}: {==}
    case E.Unluck{}: {==}
    case E.WaterBreathing{}: {==}
    case E.Weakness{}: {==}
    case E.Weaving{}: {==}
    case E.WindCharged{}: {==}
    case E.Wither{}: {==}

law lookup_refuses_an_identifier_absent_from_every_supplied_type:
  for +values:List<&2,E.EffectType>
  for +value:String
  for missing:absent(values,value)
  {E.kind_lookup(values,value) == Fail{"unknown suspicious stew effect"} : Result<&2,&2,String,E.EffectType>}
def lookup_refuses_an_identifier_absent_from_every_supplied_type(values,value,missing):
  match values:
    case Nil{}: {==}
    case +head <> +rest:
      (miss,tail) = missing
      %Equal.sym(Bool,String.eq(value,E.kind_name(head)),False{},miss) :
        {E.kind_match(_,head,u => E.kind_lookup(rest,value)) == Fail{"unknown suspicious stew effect"} : Result<&2,&2,String,E.EffectType>}
      lookup_refuses_an_identifier_absent_from_every_supplied_type(rest,value,tail)

law an_identifier_outside_the_complete_effect_registry_is_refused:
  for +value:String
  for missing:absent(E.registered(),value)
  {E.kind(value) == Fail{"unknown suspicious stew effect"} : Result<&2,&2,String,E.EffectType>}
def an_identifier_outside_the_complete_effect_registry_is_refused(value,missing):
  lookup_refuses_an_identifier_absent_from_every_supplied_type(E.registered(),value,missing)
