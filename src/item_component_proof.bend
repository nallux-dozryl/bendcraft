import Base
import ./json.bend as J
import ./nbt.bend as N
import ./inventory.bend as Inv
import ./item_component_effects.bend as E
import ./item_component.bend as C
import ./item_component_laws.bend as Laws

def Laws.effect_identifier_roundtrip(effect):
  match effect:
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

def Laws.nbt_duration_retains_all_signed_words(word):
  {==}

def Laws.typed_nbt_effect_roundtrip(effect):
  E.Effect{kind,ticks} = effect
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

def Laws.ordered_nbt_effects_roundtrip(effects):
  match effects:
    case Nil{}: {==}
    case +head <> +rest:
      %Equal.sym(Result<&2,&2,String,E.Effect>,E.nbt_effect(E.nbt_tag(head)),Done{head},Laws.typed_nbt_effect_roundtrip(head)) :
        {E.nbt_effects_next(_,u => E.nbt_effects(E.nbt_tags(rest))) == Done{head <> rest} : Result<&2,&2,String,List<&2,E.Effect>>}
      %Equal.sym(Result<&2,&2,String,List<&2,E.Effect>>,E.nbt_effects(E.nbt_tags(rest)),Done{rest},Laws.ordered_nbt_effects_roundtrip(rest)) :
        {E.nbt_effects_finish(head,_) == Done{head <> rest} : Result<&2,&2,String,List<&2,E.Effect>>}
      {==}

def Laws.complete_typed_patch_roundtrip(components):
  match components:
    case C.SuspiciousStew{+effects}:
      %Equal.sym(Result<&2,&2,String,List<&2,E.Effect>>,E.nbt_effects(E.nbt_tags(effects)),Done{effects},Laws.ordered_nbt_effects_roundtrip(effects)) :
        {C.patch_read(_) == Done{C.SuspiciousStew{effects}} : Result<&2,&2,String,C.Components>}
      {==}

def Laws.missing_defaults_refuse_complete_key(key):
  {==}

def Laws.missing_defaults_refuse_metadata(key):
  {==}

def Laws.admitted_metadata_retains_complete_key(key,components):
  {==}

def Laws.disabled_catalog_definition_refuses_components(id,digest):
  {==}

def Laws.admission_refusal_retains_complete_inventory_owner(owner,index,slot,message):
  {==}

def Laws.load_refusal_retains_complete_inventory_owner(defaults,owner,index,slot,message,refusal):
  %Equal.sym(Result<&2,&2,String,Inv.ItemMetadata>,C.slot_metadata(defaults,slot),Fail{message},refusal) :
    {C.install(owner,index,slot,_) == (owner,Fail{message}) : Inv.Inventory & Result<&2,&2,String,Unit>}
  {==}

def Laws.missing_defaults_load_retains_complete_inventory_owner(owner,index,key,count):
  {==}

def Laws.nbt_refusal_retains_complete_inventory_owner(defaults,owner,index,value,message,refusal):
  %Equal.sym(Result<&2,&2,String,Inv.Slot>,C.decode_modified_slot(defaults,value),Fail{message},refusal) :
    {C.load_decoded(defaults,owner,index,_) == (owner,Fail{message}) : Inv.Inventory & Result<&2,&2,String,Unit>}
  {==}
