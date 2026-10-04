import Base
import ./section.bend as S
import ./superflat_population.bend as P

# Observe the complete topology of the actual owned array, including both
# children. Base.Array.size follows only the left spine and is not sufficient
# to establish that an arbitrary public Section constructor has 4096 cells.
type Shape is Data:
  ShapeLeaf{}
  ShapeNode{left:Shape,right:Shape}

def array_shape(a:Array<U32>) -> Shape:
  match a:
    case ALeaf{value}: ShapeLeaf{}
    case ANode{left,right}: ShapeNode{array_shape(left),array_shape(right)}

def section_shape(section:S.Section) -> Shape:
  S.Section{a} = section
  array_shape(a)

def size_owner(result:Array<U32> & U32) -> Array<U32>:
  (a,size) = result
  a

def swap_shape(result:Array<U32> & U32) -> Shape:
  array_shape(Array.set.fin(U32,result))

def twin(+shape:Shape) -> Shape:
  ShapeNode{shape,shape}

# Independent fixed-capacity contract: a section is a perfect binary tree of
# depth 12. This specification mentions neither fill's loop nor its contents.
def perfect(depth:Nat) -> Shape:
  match depth:
    case 0n: ShapeLeaf{}
    case 1n+rest: twin(perfect(rest))

def leaves(shape:Shape) -> Nat:
  match shape:
    case ShapeLeaf{}: 1n
    case ShapeNode{left,right}: Nat.add(leaves(left),leaves(right))

def double(+n:Nat) -> Nat:
  Nat.add(n,n)

law array_size_returns_exact_owner:
  for a:Array<U32>
  {size_owner(Array.size(U32,a)) == a : Array<U32>}

law array_set_preserves_complete_shape:
  for a:Array<U32>
  for +index:U32
  for +state:U32
  {array_shape(Array.set(U32,a,index,state)) == array_shape(a) : Shape}

law section_set_preserves_complete_shape:
  for section:S.Section
  for +index:U32
  for +state:U32
  {section_shape(P.fill_result(S.Section.set_index(section,index,state))) == section_shape(section) : Shape}

# This generic invariant includes rejected indices and U32 index wrap. Shape
# preservation does not require a premise about values, origin or flat layers.
law fill_preserves_complete_shape:
  for fuel:Nat
  for +index:U32
  for +origin:U32
  for +flat:P.Flat
  for section:S.Section
  {section_shape(P.fill(fuel,index,origin,flat,section)) == section_shape(section) : Shape}

law array_new_has_perfect_shape:
  for depth:Nat
  for +initial:U32
  {array_shape(Array.new(U32,depth,initial)) == perfect(depth) : Shape}

law perfect_shape_capacity:
  for +depth:Nat
  {leaves(perfect(depth)) == Nat.pow(2n,depth) : Nat}

law section_new_has_perfect_shape:
  for initial:U32
  {section_shape(S.Section.new(initial)) == perfect(12n) : Shape}

