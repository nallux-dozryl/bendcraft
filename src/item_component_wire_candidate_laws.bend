import Base
import ./inventory.bend as Inv
import ./player_inventory.bend as I
import ./item_component_wire_candidate.bend as C

# Preserve tree topology and every raw leaf, including invalid/hidden cells.
type Backing is Data:
  BackingLeaf{value:Inv.Slot}
  BackingNode{left:Backing,right:Backing}

def backing(array:Array<Inv.Slot>) -> Backing:
  match array:
    case ALeaf{value}: BackingLeaf{value}
    case ANode{left,right}: BackingNode{backing(left),backing(right)}

def backings(owners:Array<Inv.Slot> & Array<Inv.Slot>) -> Backing & Backing:
  (first,second) = owners
  (backing(first),backing(second))

def duplicated(+value:Backing) -> Backing & Backing: (value,value)

def nodes(left:Backing & Backing,right:Backing & Backing) -> Backing & Backing:
  (a,b) = left
  (c,d) = right
  (BackingNode{a,c},BackingNode{b,d})

law clone_node_rejoins_complete_backings:
  for left:Array<Inv.Slot> & Array<Inv.Slot>
  for right:Array<Inv.Slot> & Array<Inv.Slot>
  {backings(Array.clone.node(Inv.Slot,left,right)) == nodes(backings(left),backings(right)) : Backing & Backing}

law actual_array_clone_preserves_every_raw_leaf_and_tree:
  for array:Array<Inv.Slot>
  {backings(Array.clone(Inv.Slot,array)) == duplicated(backing(array)) : Backing & Backing}

law clone_producer_retains_complete_profiles_and_lengths:
  for original:Array<Inv.Slot>
  for candidate:Array<Inv.Slot>
  for +length:U32
  for +selected:U32
  for +abilities:I.Abilities
  for +profile:I.Profile
  {C.cloned(length,selected,abilities,profile,(original,candidate)) ==
    (I.State{Inv.Inventory{original,length},selected,abilities,profile},I.State{Inv.Inventory{candidate,length},selected,abilities,profile}) : I.State & I.State}

law prospective_encoding_refusal_retains_complete_original_owner:
  for -A:Data
  for original:I.State
  for candidate:I.State
  for value:A
  for +message:String
  {C.finish(A,original,candidate,value,Fail{message}) == (original,Fail{message}) : I.State & Result<&2,&2,String,A>}

law prospective_encoding_admission_publishes_complete_candidate:
  for -A:Data
  for original:I.State
  for candidate:I.State
  for +value:A
  for text:String
  {C.finish(A,original,candidate,value,Done{text}) == (candidate,Done{value}) : I.State & Result<&2,&2,String,A>}
