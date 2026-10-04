import Base
import ./superflat_section_shape_laws.bend as Laws
import ./section.bend as S
import ./superflat_population.bend as P

# Witnesses carry the actual returned owner. Original owners used only by the
# semantic equations are erased, so induction never copies an affine array.
def SizeWitness(-a:Array<U32>) -> Type:
  Exists(Array<U32> & U32,r =>
    {Array.size(U32,a) == r : Array<U32> & U32} &
    {Laws.size_owner(r) == a : Array<U32>})

def size_node_pair(-left:Array<U32>,right:Array<U32>,actual:Array<U32> & U32,
    evidence:{Array.size(U32,left) == actual : Array<U32> & U32} & {Laws.size_owner(actual) == left : Array<U32>}) ->
    SizeWitness(ANode{left,right}):
  match actual evidence:
    case Tuple{new_left,+size} Tuple{same,owned}:
      ((ANode{new_left,right},U32.shl(size)),
        ((%Equal.sym(Array<U32> & U32,Array.size(U32,left),(new_left,size),same) :
          {Array.size.node(U32,right,_) == (ANode{new_left,right},U32.shl(size)) : Array<U32> & U32}
        {==}),
        (%Equal.sym(Array<U32>,new_left,left,owned) :
          {ANode{_,right} == ANode{left,right} : Array<U32>}
        {==})))

def size_node(-left:Array<U32>,right:Array<U32>,result:SizeWitness(left)) ->
    SizeWitness(ANode{left,right}):
  match result:
    case Tuple{actual,evidence}: size_node_pair(left,right,actual,evidence)

def size_owned(a:Array<U32>) -> SizeWitness(a):
  match a:
    case ALeaf{value}: ((ALeaf{value},1),({==},{==}))
    case ANode{left,right}: size_node(left,right,size_owned(left))

def size_project_evidence(-a:Array<U32>,-actual:Array<U32> & U32,
    evidence:{Array.size(U32,a) == actual : Array<U32> & U32} & {Laws.size_owner(actual) == a : Array<U32>}) ->
    {Laws.size_owner(Array.size(U32,a)) == a : Array<U32>}:
  match evidence:
    case Tuple{same,owned}:
      %Equal.sym(Array<U32> & U32,Array.size(U32,a),actual,same) :
        {Laws.size_owner(_) == a : Array<U32>}
      owned

def size_project(-a:Array<U32>,result:SizeWitness(a)) ->
    {Laws.size_owner(Array.size(U32,a)) == a : Array<U32>}:
  match result:
    case Tuple{actual,evidence}: size_project_evidence(a,actual,evidence)

def Laws.array_size_returns_exact_owner(a):
  size_project(a,size_owned(a))

def SwapWitness(-a:Array<U32>,-size:U32,-index:U32,-state:U32,-low:Bool) -> Type:
  Exists(Array<U32> & U32,r =>
    {Array.swap.go(U32,a,size,index,state,low) == r : Array<U32> & U32} &
    {Laws.swap_shape(r) == Laws.array_shape(a) : Laws.Shape})

def swap_left_pair(-left:Array<U32>,right:Array<U32>,-size:U32,-index:U32,-state:U32,-low:Bool,
    actual:Array<U32> & U32,
    evidence:{Array.swap.go(U32,left,size,index,state,low) == actual : Array<U32> & U32} &
      {Laws.swap_shape(actual) == Laws.array_shape(left) : Laws.Shape}) ->
    Exists(Array<U32> & U32,r =>
      {Array.swap.lo(U32,right,Array.swap.go(U32,left,size,index,state,low)) == r : Array<U32> & U32} &
      {Laws.swap_shape(r) == Laws.ShapeNode{Laws.array_shape(left),Laws.array_shape(right)} : Laws.Shape}):
  match actual evidence:
    case Tuple{new_left,old} Tuple{same,shaped}:
      ((ANode{new_left,right},old),
        ((%Equal.sym(Array<U32> & U32,Array.swap.go(U32,left,size,index,state,low),(new_left,old),same) :
          {Array.swap.lo(U32,right,_) == (ANode{new_left,right},old) : Array<U32> & U32}
        {==}),
        (%Equal.sym(Laws.Shape,Laws.array_shape(new_left),Laws.array_shape(left),shaped) :
          {Laws.ShapeNode{_,Laws.array_shape(right)} == Laws.ShapeNode{Laws.array_shape(left),Laws.array_shape(right)} : Laws.Shape}
        {==})))

def swap_left(-left:Array<U32>,right:Array<U32>,-size:U32,-index:U32,-state:U32,-low:Bool,
    result:SwapWitness(left,size,index,state,low)) ->
    Exists(Array<U32> & U32,r =>
      {Array.swap.lo(U32,right,Array.swap.go(U32,left,size,index,state,low)) == r : Array<U32> & U32} &
      {Laws.swap_shape(r) == Laws.ShapeNode{Laws.array_shape(left),Laws.array_shape(right)} : Laws.Shape}):
  match result:
    case Tuple{actual,evidence}: swap_left_pair(left,right,size,index,state,low,actual,evidence)

def swap_right_pair(left:Array<U32>,-right:Array<U32>,-size:U32,-index:U32,-state:U32,-low:Bool,
    actual:Array<U32> & U32,
    evidence:{Array.swap.go(U32,right,size,index,state,low) == actual : Array<U32> & U32} &
      {Laws.swap_shape(actual) == Laws.array_shape(right) : Laws.Shape}) ->
    Exists(Array<U32> & U32,r =>
      {Array.swap.hi(U32,left,Array.swap.go(U32,right,size,index,state,low)) == r : Array<U32> & U32} &
      {Laws.swap_shape(r) == Laws.ShapeNode{Laws.array_shape(left),Laws.array_shape(right)} : Laws.Shape}):
  match actual evidence:
    case Tuple{new_right,old} Tuple{same,shaped}:
      ((ANode{left,new_right},old),
        ((%Equal.sym(Array<U32> & U32,Array.swap.go(U32,right,size,index,state,low),(new_right,old),same) :
          {Array.swap.hi(U32,left,_) == (ANode{left,new_right},old) : Array<U32> & U32}
        {==}),
        (%Equal.sym(Laws.Shape,Laws.array_shape(new_right),Laws.array_shape(right),shaped) :
          {Laws.ShapeNode{Laws.array_shape(left),_} == Laws.ShapeNode{Laws.array_shape(left),Laws.array_shape(right)} : Laws.Shape}
        {==})))

def swap_right(left:Array<U32>,-right:Array<U32>,-size:U32,-index:U32,-state:U32,-low:Bool,
    result:SwapWitness(right,size,index,state,low)) ->
    Exists(Array<U32> & U32,r =>
      {Array.swap.hi(U32,left,Array.swap.go(U32,right,size,index,state,low)) == r : Array<U32> & U32} &
      {Laws.swap_shape(r) == Laws.ShapeNode{Laws.array_shape(left),Laws.array_shape(right)} : Laws.Shape}):
  match result:
    case Tuple{actual,evidence}: swap_right_pair(left,right,size,index,state,low,actual,evidence)

def swap_owned(a:Array<U32>,+size:U32,+index:U32,+state:U32,low:Bool) ->
    SwapWitness(a,size,index,state,low):
  match a low:
    case ALeaf{old} _: ((ALeaf{state},old),({==},{==}))
    case ANode{left,right} True{}:
      +half = U32.shr(size)
      swap_left(left,right,half,index,state,U32.is_lt(index,U32.shr(half)),
        swap_owned(left,half,index,state,U32.is_lt(index,U32.shr(half))))
    case ANode{left,right} False{}:
      +half = U32.shr(size)
      +next = U32.sub(index,half)
      swap_right(left,right,half,next,state,U32.is_lt(next,U32.shr(half)),
        swap_owned(right,half,next,state,U32.is_lt(next,U32.shr(half))))

def SetWitness(-a:Array<U32>,-index:U32,-state:U32) -> Type:
  Exists(Array<U32>,written =>
    {Array.set(U32,a,index,state) == written : Array<U32>} &
    {Laws.array_shape(written) == Laws.array_shape(a) : Laws.Shape})

def set_swapped_pair(-original:Array<U32>,-sized:Array<U32>,-size:U32,-index:U32,-state:U32,
    same:{Array.size(U32,original) == (sized,size) : Array<U32> & U32},
    owned:{sized == original : Array<U32>},
    actual:Array<U32> & U32,
    evidence:{Array.swap.go(U32,sized,size,U32.and(index,U32.sub(size,1)),state,
      U32.is_lt(U32.and(index,U32.sub(size,1)),U32.shr(size))) == actual : Array<U32> & U32} &
      {Laws.swap_shape(actual) == Laws.array_shape(sized) : Laws.Shape}) ->
    SetWitness(original,index,state):
  match actual evidence:
    case Tuple{written,old} Tuple{swapped,shaped}:
      (written,
        ((%Equal.sym(Array<U32> & U32,Array.size(U32,original),(sized,size),same) :
          {Array.set.fin(U32,Array.swap.at(U32,index,state,_)) == written : Array<U32>}
        %Equal.sym(Array<U32> & U32,
          Array.swap.go(U32,sized,size,U32.and(index,U32.sub(size,1)),state,
            U32.is_lt(U32.and(index,U32.sub(size,1)),U32.shr(size))),
          (written,old),swapped) :
          {Array.set.fin(U32,_) == written : Array<U32>}
        {==}),
        Equal.trans(Laws.Shape,Laws.array_shape(written),Laws.array_shape(sized),Laws.array_shape(original),
          shaped,Equal.cong(Array<U32>,Laws.Shape,Laws.array_shape,sized,original,owned))))

def set_swapped(-original:Array<U32>,-sized:Array<U32>,-size:U32,-index:U32,-state:U32,
    same:{Array.size(U32,original) == (sized,size) : Array<U32> & U32},
    owned:{sized == original : Array<U32>},
    result:SwapWitness(sized,size,U32.and(index,U32.sub(size,1)),state,
      U32.is_lt(U32.and(index,U32.sub(size,1)),U32.shr(size)))) ->
    SetWitness(original,index,state):
  match result:
    case Tuple{actual,evidence}: set_swapped_pair(original,sized,size,index,state,same,owned,actual,evidence)

def set_sized_pair(-a:Array<U32>,+index:U32,+state:U32,actual:Array<U32> & U32,
    evidence:{Array.size(U32,a) == actual : Array<U32> & U32} & {Laws.size_owner(actual) == a : Array<U32>}) ->
    SetWitness(a,index,state):
  match actual evidence:
    case Tuple{owner,+size} Tuple{same,owned}:
      set_swapped(a,owner,size,index,state,same,owned,
        swap_owned(owner,size,U32.and(index,U32.sub(size,1)),state,
          U32.is_lt(U32.and(index,U32.sub(size,1)),U32.shr(size))))

def set_sized(-a:Array<U32>,+index:U32,+state:U32,result:SizeWitness(a)) ->
    SetWitness(a,index,state):
  match result:
    case Tuple{actual,evidence}: set_sized_pair(a,index,state,actual,evidence)

def set_owned(a:Array<U32>,+index:U32,+state:U32) -> SetWitness(a,index,state):
  set_sized(a,index,state,size_owned(a))

def set_project_evidence(-a:Array<U32>,-index:U32,-state:U32,-written:Array<U32>,
    evidence:{Array.set(U32,a,index,state) == written : Array<U32>} &
      {Laws.array_shape(written) == Laws.array_shape(a) : Laws.Shape}) ->
    {Laws.array_shape(Array.set(U32,a,index,state)) == Laws.array_shape(a) : Laws.Shape}:
  match evidence:
    case Tuple{same,shaped}:
      %Equal.sym(Array<U32>,Array.set(U32,a,index,state),written,same) :
        {Laws.array_shape(_) == Laws.array_shape(a) : Laws.Shape}
      shaped

def set_project(-a:Array<U32>,-index:U32,-state:U32,result:SetWitness(a,index,state)) ->
    {Laws.array_shape(Array.set(U32,a,index,state)) == Laws.array_shape(a) : Laws.Shape}:
  match result:
    case Tuple{written,evidence}: set_project_evidence(a,index,state,written,evidence)

def Laws.array_set_preserves_complete_shape(a,index,state):
  set_project(a,index,state,set_owned(a,index,state))

def WriteWitness(-section:S.Section,-index:U32,-state:U32) -> Type:
  Exists(S.Section,written =>
    {P.fill_result(S.Section.set_index(section,index,state)) == written : S.Section} &
    {Laws.section_shape(written) == Laws.section_shape(section) : Laws.Shape})

def section_written_evidence(-a:Array<U32>,-index:U32,-state:U32,written:Array<U32>,
    evidence:{Array.set(U32,a,index,state) == written : Array<U32>} &
      {Laws.array_shape(written) == Laws.array_shape(a) : Laws.Shape}) ->
    Exists(S.Section,written =>
      {P.fill_result(S.Section.set_index.fin(S.Section{a},index,state,True{})) == written : S.Section} &
      {Laws.section_shape(written) == Laws.array_shape(a) : Laws.Shape}):
  match evidence:
    case Tuple{same,shaped}:
      (S.Section{written},
        ((%Equal.sym(Array<U32>,Array.set(U32,a,index,state),written,same) :
          {S.Section{_} == S.Section{written} : S.Section}
        {==}),shaped))

def section_written(-a:Array<U32>,-index:U32,-state:U32,result:SetWitness(a,index,state)) ->
    Exists(S.Section,written =>
      {P.fill_result(S.Section.set_index.fin(S.Section{a},index,state,True{})) == written : S.Section} &
      {Laws.section_shape(written) == Laws.array_shape(a) : Laws.Shape}):
  match result:
    case Tuple{written,evidence}: section_written_evidence(a,index,state,written,evidence)

def section_checked(section:S.Section,+index:U32,+state:U32,valid:Bool) ->
    Exists(S.Section,written =>
      {P.fill_result(S.Section.set_index.fin(section,index,state,valid)) == written : S.Section} &
      {Laws.section_shape(written) == Laws.section_shape(section) : Laws.Shape}):
  match section valid:
    case S.Section{a} False{}: (S.Section{a},({==},{==}))
    case S.Section{a} True{}: section_written(a,index,state,set_owned(a,index,state))

def write_owned(section:S.Section,+index:U32,+state:U32) -> WriteWitness(section,index,state):
  section_checked(section,index,state,U32.is_lt(index,4096))

def write_project_evidence(-section:S.Section,-index:U32,-state:U32,-written:S.Section,
    evidence:{P.fill_result(S.Section.set_index(section,index,state)) == written : S.Section} &
      {Laws.section_shape(written) == Laws.section_shape(section) : Laws.Shape}) ->
    {Laws.section_shape(P.fill_result(S.Section.set_index(section,index,state))) == Laws.section_shape(section) : Laws.Shape}:
  match evidence:
    case Tuple{same,shaped}:
      %Equal.sym(S.Section,P.fill_result(S.Section.set_index(section,index,state)),written,same) :
        {Laws.section_shape(_) == Laws.section_shape(section) : Laws.Shape}
      shaped

def write_project(-section:S.Section,-index:U32,-state:U32,result:WriteWitness(section,index,state)) ->
    {Laws.section_shape(P.fill_result(S.Section.set_index(section,index,state))) == Laws.section_shape(section) : Laws.Shape}:
  match result:
    case Tuple{written,evidence}: write_project_evidence(section,index,state,written,evidence)

def Laws.section_set_preserves_complete_shape(section,index,state):
  write_project(section,index,state,write_owned(section,index,state))

def FillWitness(-fuel:Nat,-index:U32,-origin:U32,-flat:P.Flat,-section:S.Section) -> Type:
  Exists(S.Section,filled =>
    {P.fill(fuel,index,origin,flat,section) == filled : S.Section} &
    {Laws.section_shape(filled) == Laws.section_shape(section) : Laws.Shape})

def fill_join_evidence(-rest:Nat,-index:U32,-origin:U32,-flat:P.Flat,-section:S.Section,-written:S.Section,
    same:{P.fill_result(S.Section.set_index(section,index,P.state_at(flat,U32.add(origin,U32.div(index,256))))) == written : S.Section},
    shaped:{Laws.section_shape(written) == Laws.section_shape(section) : Laws.Shape},
    filled:S.Section,
    evidence:{P.fill(rest,U32.inc(index),origin,flat,written) == filled : S.Section} &
      {Laws.section_shape(filled) == Laws.section_shape(written) : Laws.Shape}) ->
    FillWitness(1n+rest,index,origin,flat,section):
  match evidence:
    case Tuple{tail_same,tail_shaped}:
      (filled,
        ((%Equal.sym(S.Section,
          P.fill_result(S.Section.set_index(section,index,P.state_at(flat,U32.add(origin,U32.div(index,256))))),written,same) :
          {P.fill(rest,U32.inc(index),origin,flat,_) == filled : S.Section}
        tail_same),
        Equal.trans(Laws.Shape,Laws.section_shape(filled),Laws.section_shape(written),Laws.section_shape(section),tail_shaped,shaped)))

def fill_join(-rest:Nat,-index:U32,-origin:U32,-flat:P.Flat,-section:S.Section,-written:S.Section,
    same:{P.fill_result(S.Section.set_index(section,index,P.state_at(flat,U32.add(origin,U32.div(index,256))))) == written : S.Section},
    shaped:{Laws.section_shape(written) == Laws.section_shape(section) : Laws.Shape},
    result:FillWitness(rest,U32.inc(index),origin,flat,written)) ->
    FillWitness(1n+rest,index,origin,flat,section):
  match result:
    case Tuple{filled,evidence}: fill_join_evidence(rest,index,origin,flat,section,written,same,shaped,filled,evidence)

def fill_step_evidence(-rest:Nat,-index:U32,-origin:U32,-flat:P.Flat,-section:S.Section,written:S.Section,
    evidence:{P.fill_result(S.Section.set_index(section,index,P.state_at(flat,U32.add(origin,U32.div(index,256))))) == written : S.Section} &
      {Laws.section_shape(written) == Laws.section_shape(section) : Laws.Shape},
    next:(@written:S.Section -> FillWitness(rest,U32.inc(index),origin,flat,written))) ->
    FillWitness(1n+rest,index,origin,flat,section):
  match evidence:
    case Tuple{same,shaped}:
      fill_join(rest,index,origin,flat,section,written,same,shaped,next(written))

def fill_step(-rest:Nat,-index:U32,-origin:U32,-flat:P.Flat,-section:S.Section,
    result:WriteWitness(section,index,P.state_at(flat,U32.add(origin,U32.div(index,256)))),
    next:(@written:S.Section -> FillWitness(rest,U32.inc(index),origin,flat,written))) ->
    FillWitness(1n+rest,index,origin,flat,section):
  match result:
    case Tuple{written,evidence}: fill_step_evidence(rest,index,origin,flat,section,written,evidence,next)

def fill_owned(fuel:Nat,+index:U32,+origin:U32,+flat:P.Flat,section:S.Section) ->
    FillWitness(fuel,index,origin,flat,section):
  match fuel:
    case 0n: (section,({==},{==}))
    case 1n+rest:
      fill_step(rest,index,origin,flat,section,
        write_owned(section,index,P.state_at(flat,U32.add(origin,U32.div(index,256)))),
        written => fill_owned(rest,U32.inc(index),origin,flat,written))

def fill_project_evidence(-fuel:Nat,-index:U32,-origin:U32,-flat:P.Flat,-section:S.Section,-filled:S.Section,
    evidence:{P.fill(fuel,index,origin,flat,section) == filled : S.Section} &
      {Laws.section_shape(filled) == Laws.section_shape(section) : Laws.Shape}) ->
    {Laws.section_shape(P.fill(fuel,index,origin,flat,section)) == Laws.section_shape(section) : Laws.Shape}:
  match evidence:
    case Tuple{same,shaped}:
      %Equal.sym(S.Section,P.fill(fuel,index,origin,flat,section),filled,same) :
        {Laws.section_shape(_) == Laws.section_shape(section) : Laws.Shape}
      shaped

def fill_project(-fuel:Nat,-index:U32,-origin:U32,-flat:P.Flat,-section:S.Section,
    result:FillWitness(fuel,index,origin,flat,section)) ->
    {Laws.section_shape(P.fill(fuel,index,origin,flat,section)) == Laws.section_shape(section) : Laws.Shape}:
  match result:
    case Tuple{filled,evidence}: fill_project_evidence(fuel,index,origin,flat,section,filled,evidence)

def Laws.fill_preserves_complete_shape(fuel,index,origin,flat,section):
  fill_project(fuel,index,origin,flat,section,fill_owned(fuel,index,origin,flat,section))

def Laws.array_new_has_perfect_shape(depth,initial):
  match depth:
    case 0n: {==}
    case 1n+rest:
      Equal.cong(Laws.Shape,Laws.Shape,shape => Laws.twin(shape),
        Laws.array_shape(Array.new(U32,rest,initial)),Laws.perfect(rest),Laws.array_new_has_perfect_shape(rest,initial))

def add_zero(n:Nat) -> {Nat.add(n,0n) == n : Nat}:
  match n:
    case 0n: {==}
    case 1n+rest:
      Equal.cong(Nat,Nat,n => 1n+n,Nat.add(rest,0n),rest,add_zero(rest))

def multiply_two(+n:Nat) -> {Nat.mul(2n,n) == Laws.double(n) : Nat}:
  %Equal.sym(Nat,Nat.add(n,0n),n,add_zero(n)) :
    {Nat.add(n,_) == Nat.add(n,n) : Nat}
  {==}

def Laws.perfect_shape_capacity(depth):
  match depth:
    case 0n: {==}
    case 1n+rest:
      Equal.trans(Nat,Laws.double(Laws.leaves(Laws.perfect(rest))),Laws.double(Nat.pow(2n,rest)),Nat.mul(2n,Nat.pow(2n,rest)),
        Equal.cong(Nat,Nat,n => Laws.double(n),Laws.leaves(Laws.perfect(rest)),Nat.pow(2n,rest),Laws.perfect_shape_capacity(rest)),
        Equal.sym(Nat,Nat.mul(2n,Nat.pow(2n,rest)),Laws.double(Nat.pow(2n,rest)),multiply_two(Nat.pow(2n,rest))))

def Laws.section_new_has_perfect_shape(initial):
  Laws.array_new_has_perfect_shape(12n,initial)

