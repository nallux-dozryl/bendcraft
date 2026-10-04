import Base
import ./json.bend as J
import ./nbt.bend as N
import ./inventory.bend as Inv
import ./item_component_effects.bend as E
import ./item_component.bend as C

law effect_identifier_roundtrip:
  for +effect:E.EffectType
  {E.kind(E.kind_name(effect)) == Done{effect} : Result<&2,&2,String,E.EffectType>}

law nbt_duration_retains_all_signed_words:
  for +word:U32
  {E.nbt_duration(N.Int{word}) == Done{word} : Result<&2,&2,String,U32>}

law typed_nbt_effect_roundtrip:
  for +effect:E.Effect
  {E.nbt_effect(E.nbt_tag(effect)) == Done{effect} : Result<&2,&2,String,E.Effect>}

law ordered_nbt_effects_roundtrip:
  for +effects:List<&2,E.Effect>
  {E.nbt_effects(E.nbt_tags(effects)) == Done{effects} : Result<&2,&2,String,List<&2,E.Effect>>}

law complete_typed_patch_roundtrip:
  for +components:C.Components
  {C.patch_value(C.patch_tag(components)) == Done{components} : Result<&2,&2,String,C.Components>}

law missing_defaults_refuse_complete_key:
  for key:Inv.ItemKey
  {C.validate(None{},key) == Fail{"item components require initialized defaults"} : Result<&2,&2,String,C.Validated>}

law missing_defaults_refuse_metadata:
  for key:Inv.ItemKey
  {C.metadata(None{},key) == None{} : Maybe<&2,Inv.ItemMetadata>}

law admitted_metadata_retains_complete_key:
  for +key:Inv.ItemKey
  for components:C.Components
  {C.metadata_result(Done{C.Validated{key,components}}) == Some{Inv.ItemMetadata{key,1}} : Maybe<&2,Inv.ItemMetadata>}

law disabled_catalog_definition_refuses_components:
  for id:String
  for digest:String
  {C.default_from_identity(id,False{},digest) == None{} : Maybe<&2,C.Defaults>}

law admission_refusal_retains_complete_inventory_owner:
  for owner:Inv.Inventory
  for index:U32
  for slot:Inv.Slot
  for +message:String
  {C.install(owner,index,slot,Fail{message}) == (owner,Fail{message}) : Inv.Inventory & Result<&2,&2,String,Unit>}

law load_refusal_retains_complete_inventory_owner:
  for defaults:Maybe<&2,C.Defaults>
  for owner:Inv.Inventory
  for index:U32
  for +slot:Inv.Slot
  for +message:String
  for refusal:{C.slot_metadata(defaults,slot) == Fail{message} : Result<&2,&2,String,Inv.ItemMetadata>}
  {C.load(defaults,owner,index,slot) == (owner,Fail{message}) : Inv.Inventory & Result<&2,&2,String,Unit>}

law missing_defaults_load_retains_complete_inventory_owner:
  for owner:Inv.Inventory
  for index:U32
  for key:Inv.ItemKey
  for count:U32
  {C.load(None{},owner,index,Inv.InvStack{key,count}) == (owner,Fail{"item components require initialized defaults"}) : Inv.Inventory & Result<&2,&2,String,Unit>}

law nbt_refusal_retains_complete_inventory_owner:
  for defaults:Maybe<&2,C.Defaults>
  for owner:Inv.Inventory
  for index:U32
  for +value:N.Value
  for +message:String
  for refusal:{C.decode_modified_slot(defaults,value) == Fail{message} : Result<&2,&2,String,Inv.Slot>}
  {C.load_tag(defaults,owner,index,value) == (owner,Fail{message}) : Inv.Inventory & Result<&2,&2,String,Unit>}
