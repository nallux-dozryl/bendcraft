import Base
import ./cooking_effect_delivery.bend as D
import ./cooking_world_store.bend as S
import ./core.bend as C
import ./inventory.bend as I
import ./furnace_authority.bend as F

law missing_item_owner_retains_complete_ordered_suffix:
  for position:C.Position
  for slot:U32
  for item:I.Slot
  for rest:List<&2,S.Effect>
  {D.deliver(S.Drop{position,slot,item} <> rest) ==
    D.Outcome{S.Drop{position,slot,item} <> rest,Fail{"cooking-effects:item-entity-and-level-rng-owner-required"}} : D.Outcome}
def missing_item_owner_retains_complete_ordered_suffix(position,slot,item,rest): {==}

law missing_xp_owner_retains_complete_ordered_suffix:
  for position:C.Position
  for request:F.XpRequest
  for rest:List<&2,S.Effect>
  {D.deliver(S.Experience{position,request} <> rest) ==
    D.Outcome{S.Experience{position,request} <> rest,Fail{"cooking-effects:xp-orb-and-level-rng-owner-required"}} : D.Outcome}
def missing_xp_owner_retains_complete_ordered_suffix(position,request,rest): {==}

law missing_comparator_owner_retains_complete_ordered_suffix:
  for position:C.Position
  for rest:List<&2,S.Effect>
  {D.deliver(S.Dirty{position} <> rest) ==
    D.Outcome{S.Dirty{position} <> rest,Fail{"cooking-effects:block-entity-and-comparator-publisher-owner-required"}} : D.Outcome}
def missing_comparator_owner_retains_complete_ordered_suffix(position,rest): {==}

law missing_block_publisher_retains_complete_ordered_suffix:
  for position:C.Position
  for count:Nat
  for rest:List<&2,S.Effect>
  {D.deliver(S.BlockUpdate{position,1n+count} <> rest) ==
    D.Outcome{S.BlockUpdate{position,1n+count} <> rest,Fail{"cooking-effects:block-update-publisher-owner-required"}} : D.Outcome}
def missing_block_publisher_retains_complete_ordered_suffix(position,count,rest): {==}

law missing_event_publisher_retains_complete_ordered_suffix:
  for position:C.Position
  for count:Nat
  for rest:List<&2,S.Effect>
  {D.deliver(S.BlockChange{position,1n+count} <> rest) ==
    D.Outcome{S.BlockChange{position,1n+count} <> rest,Fail{"cooking-effects:game-event-publisher-owner-required"}} : D.Outcome}
def missing_event_publisher_retains_complete_ordered_suffix(position,count,rest): {==}

law acknowledged_local_marker_preserves_remaining_delivery:
  for position:C.Position
  for rest:List<&2,S.Effect>
  {D.deliver(S.OwnerReset{position} <> rest) == D.deliver(rest) : D.Outcome}
def acknowledged_local_marker_preserves_remaining_delivery(position,rest): {==}
