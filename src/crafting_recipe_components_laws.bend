import Base
import ./crafting_recipe_components.bend as C
import ./crafting_recipe.bend as R
import ./json.bend as J
import ./inventory.bend as Inv

law empty_patch_preserves_complete_default_map:
  for members:List<&2,J.Member>
  {C.apply([],members) == members : List<&2,J.Member>}

law removal_retains_unrelated_member_and_complete_tail:
  for head:J.Member
  for tail:List<&2,J.Member>
  {C.remove_match(False{},head,tail) == head <> tail : List<&2,J.Member>}

law removal_discards_selected_member_only:
  for head:J.Member
  for tail:List<&2,J.Member>
  {C.remove_match(True{},head,tail) == tail : List<&2,J.Member>}

law omitted_duration_uses_actual_codec_default:
  {C.duration(None{}) == Done{"160"} : Result<&2,&2,String,String>}

law explicit_default_duration_has_one_canonical_identity:
  for id:String
  {C.effect_entry(id,"160") == J.JObject{[J.JMember{"id",J.JString{id}}]} : J.Value}

law unresolved_patch_cannot_supply_effective_limit:
  for patch:String
  {R.component_limit_fields(["BendCraftPatch1",patch]) == None{} : Maybe<&2,U32>}

law strictly_invalid_components_cannot_supply_effective_limit:
  for payload:String
  {R.component_limit_fields(["BendCraftInvalidComponents1",payload]) == None{} : Maybe<&2,U32>}

law absent_effective_limit_cannot_manufacture_metadata:
  for key:Inv.ItemKey
  {R.output_component_metadata(None{},key) == None{} : Maybe<&2,Inv.ItemMetadata>}

law effective_metadata_retains_exact_component_identity:
  for key:Inv.ItemKey
  for limit:U32
  {R.output_component_metadata(Some{limit},key) == Some{Inv.ItemMetadata{key,limit}} : Maybe<&2,Inv.ItemMetadata>}

law absent_output_metadata_refuses_all_counts:
  for count:U32
  {R.output_slot_valid(None{},count) == False{} : Bool}

law invalid_stew_profile_refuses_complete_inventory_key:
  for message:String
  for key:Inv.ItemKey
  {C.stew_metadata_checked(Fail{message},key) == None{} : Maybe<&2,Inv.ItemMetadata>}

law absent_input_authority_cannot_manufacture_metadata:
  for key:Inv.ItemKey
  {R.input_metadata([],key) == None{} : Maybe<&2,Inv.ItemMetadata>}

law absent_input_metadata_refuses_all_counts:
  for count:U32
  {R.input_metadata_admits(None{},count) == False{} : Bool}

law non_stew_identity_cannot_use_closed_stew_authority:
  for defaults:J.Value
  for key:Inv.ItemKey
  {C.stew_metadata_item(False{},defaults,key) == None{} : Maybe<&2,Inv.ItemMetadata>}
