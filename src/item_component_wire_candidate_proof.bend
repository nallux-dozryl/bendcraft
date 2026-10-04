import Base
import ./inventory.bend as Inv
import ./item_component_wire_candidate_laws.bend as L

def L.clone_node_rejoins_complete_backings(left,right):
  (a,b) = left
  (c,d) = right
  {==}

def CloneWitness(-array:Array<Inv.Slot>) -> Type:
  Exists(Array<Inv.Slot> & Array<Inv.Slot>,actual =>
    {Array.clone(Inv.Slot,array) == actual : Array<Inv.Slot> & Array<Inv.Slot>} &
    {L.backings(actual) == L.duplicated(L.backing(array)) : L.Backing & L.Backing})

def cloned_node_pair(-left:Array<Inv.Slot>,-right:Array<Inv.Slot>,
    first:Array<Inv.Slot> & Array<Inv.Slot>,second:Array<Inv.Slot> & Array<Inv.Slot>,
    first_evidence:{Array.clone(Inv.Slot,left) == first : Array<Inv.Slot> & Array<Inv.Slot>} &
      {L.backings(first) == L.duplicated(L.backing(left)) : L.Backing & L.Backing},
    second_evidence:{Array.clone(Inv.Slot,right) == second : Array<Inv.Slot> & Array<Inv.Slot>} &
      {L.backings(second) == L.duplicated(L.backing(right)) : L.Backing & L.Backing}) -> CloneWitness(ANode{left,right}):
  match first second first_evidence second_evidence:
    case Tuple{a,b} Tuple{c,d} Tuple{same_left,owned_left} Tuple{same_right,owned_right}:
      ((ANode{a,c},ANode{b,d}),
        ((%Equal.sym(Array<Inv.Slot> & Array<Inv.Slot>,Array.clone(Inv.Slot,left),(a,b),same_left) :
          {Array.clone.node(Inv.Slot,_,Array.clone(Inv.Slot,right)) == (ANode{a,c},ANode{b,d}) : Array<Inv.Slot> & Array<Inv.Slot>}
        %Equal.sym(Array<Inv.Slot> & Array<Inv.Slot>,Array.clone(Inv.Slot,right),(c,d),same_right) :
          {Array.clone.node(Inv.Slot,(a,b),_) == (ANode{a,c},ANode{b,d}) : Array<Inv.Slot> & Array<Inv.Slot>}
        {==}),
        (%Equal.sym(L.Backing & L.Backing,L.backings((a,b)),L.duplicated(L.backing(left)),owned_left) :
          {L.nodes(_,L.backings((c,d))) == L.duplicated(L.BackingNode{L.backing(left),L.backing(right)}) : L.Backing & L.Backing}
        %Equal.sym(L.Backing & L.Backing,L.backings((c,d)),L.duplicated(L.backing(right)),owned_right) :
          {L.nodes(L.duplicated(L.backing(left)),_) == L.duplicated(L.BackingNode{L.backing(left),L.backing(right)}) : L.Backing & L.Backing}
        {==})))

def cloned_node(-left:Array<Inv.Slot>,-right:Array<Inv.Slot>,first:CloneWitness(left),second:CloneWitness(right)) -> CloneWitness(ANode{left,right}):
  match first second:
    case Tuple{actual_left,evidence_left} Tuple{actual_right,evidence_right}:
      cloned_node_pair(left,right,actual_left,actual_right,evidence_left,evidence_right)

def cloned_owned(array:Array<Inv.Slot>) -> CloneWitness(array):
  match array:
    case ALeaf{+value}: ((ALeaf{value},ALeaf{value}),({==},{==}))
    case ANode{left,right}: cloned_node(left,right,cloned_owned(left),cloned_owned(right))

def clone_project(-array:Array<Inv.Slot>,result:CloneWitness(array)) ->
    {L.backings(Array.clone(Inv.Slot,array)) == L.duplicated(L.backing(array)) : L.Backing & L.Backing}:
  match result:
    case Tuple{actual,Tuple{same,owned}}:
      %Equal.sym(Array<Inv.Slot> & Array<Inv.Slot>,Array.clone(Inv.Slot,array),actual,same) :
        {L.backings(_) == L.duplicated(L.backing(array)) : L.Backing & L.Backing}
      owned

def L.actual_array_clone_preserves_every_raw_leaf_and_tree(array):
  clone_project(array,cloned_owned(array))

def L.clone_producer_retains_complete_profiles_and_lengths(original,candidate,length,selected,abilities,profile): {==}
def L.prospective_encoding_refusal_retains_complete_original_owner(A,original,candidate,value,message): {==}
def L.prospective_encoding_admission_publishes_complete_candidate(A,original,candidate,value,text): {==}
