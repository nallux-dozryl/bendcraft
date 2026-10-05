import Base
import ./json.bend as J
import ./crafting_recipe.bend as R
import ./cooking_block_entity_codec_components.bend as Patch

# Exact prior recursive definitions, retained only as the refactoring
# specification. They evaluate both recursive branches of choose eagerly.
def previous_additions(values:List<&2,J.Member>,+defaults:J.Value) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case +head <> +rest:
      J.JMember{id,+value} = head
      R.choose(List<&2,J.Member>,previous_additions(rest,defaults),head <> previous_additions(rest,defaults),Patch.unchanged(value,J.member(defaults,id)))
def previous_removals(values:List<&2,J.Member>,+effective:J.Value) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case J.JMember{+id,value} <> +rest:
      R.choose(List<&2,J.Member>,previous_removals(rest,effective),J.JMember{"!" ++ id,J.JObject{[]}} <> previous_removals(rest,effective),Maybe.is_some(&2,J.Value,J.member(effective,id)))

law addition_selector_matches_previous_branch:
  for +equal:Bool
  for +head:J.Member
  for +tail:List<&2,J.Member>
  {Patch.additions_tail(equal,head,tail) == R.choose(List<&2,J.Member>,tail,head <> tail,equal) : List<&2,J.Member>}
def addition_selector_matches_previous_branch(equal,head,tail):
  match equal:
    case False{}: {==}
    case True{}: {==}

law removal_selector_matches_previous_branch:
  for +present:Bool
  for +id:String
  for +tail:List<&2,J.Member>
  {Patch.removals_tail(present,id,tail) == R.choose(List<&2,J.Member>,tail,J.JMember{"!" ++ id,J.JObject{[]}} <> tail,present) : List<&2,J.Member>}
def removal_selector_matches_previous_branch(present,id,tail):
  match present:
    case False{}: {==}
    case True{}: {==}

law linear_additions_preserves_complete_previous_delta:
  for +values:List<&2,J.Member>
  for +defaults:J.Value
  {Patch.additions(values,defaults) == previous_additions(values,defaults) : List<&2,J.Member>}
def linear_additions_preserves_complete_previous_delta(values,defaults):
  match values:
    case Nil{}: {==}
    case +head <> +rest:
      J.JMember{+id,+value} = head
      %Equal.sym(List<&2,J.Member>,Patch.additions(rest,defaults),previous_additions(rest,defaults),linear_additions_preserves_complete_previous_delta(rest,defaults)) :
        {Patch.additions_tail(Patch.unchanged(value,J.member(defaults,id)),head,_) ==
          R.choose(List<&2,J.Member>,previous_additions(rest,defaults),head <> previous_additions(rest,defaults),Patch.unchanged(value,J.member(defaults,id))) : List<&2,J.Member>}
      addition_selector_matches_previous_branch(Patch.unchanged(value,J.member(defaults,id)),head,previous_additions(rest,defaults))

law linear_removals_preserves_complete_previous_delta:
  for +values:List<&2,J.Member>
  for +effective:J.Value
  {Patch.removals(values,effective) == previous_removals(values,effective) : List<&2,J.Member>}
def linear_removals_preserves_complete_previous_delta(values,effective):
  match values:
    case Nil{}: {==}
    case J.JMember{+id,value} <> +rest:
      %Equal.sym(List<&2,J.Member>,Patch.removals(rest,effective),previous_removals(rest,effective),linear_removals_preserves_complete_previous_delta(rest,effective)) :
        {Patch.removals_tail(Maybe.is_some(&2,J.Value,J.member(effective,id)),id,_) ==
          R.choose(List<&2,J.Member>,previous_removals(rest,effective),J.JMember{"!" ++ id,J.JObject{[]}} <> previous_removals(rest,effective),Maybe.is_some(&2,J.Value,J.member(effective,id))) : List<&2,J.Member>}
      removal_selector_matches_previous_branch(Maybe.is_some(&2,J.Value,J.member(effective,id)),id,previous_removals(rest,effective))
