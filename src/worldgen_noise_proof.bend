import Base
import ./worldgen_noise_laws.bend as Laws
import ./superflat_section_shape_proof.bend as ShapeProof
import ./superflat_section_shape_laws.bend as ShapeLaws
import ./worldgen_perlin_noise.bend as P
import ./worldgen_blended_noise.bend as B
import ./f64.bend as F
import ./random.bend as R

# Each existential carries the actual returned affine owner and its equation.
# The prior owner and semantic-only function arguments are erased. No owned
# permutation is used twice to obtain a projection theorem and an induction.
def ReadWitness(-a:Array<U32>,-size:U32,-index:U32,-low:Bool) -> Type:
  Exists(Array<U32> & U32,r =>
    {Array.get.go(U32,a,size,index,low) == r : Array<U32> & U32} &
    {Laws.array_owner(U32,r) == a : Array<U32>})

def read_left_pair(-left:Array<U32>,right:Array<U32>,-size:U32,-index:U32,-low:Bool,
    actual:Array<U32> & U32,
    evidence:{Array.get.go(U32,left,size,index,low) == actual : Array<U32> & U32} &
      {Laws.array_owner(U32,actual) == left : Array<U32>}) ->
    Exists(Array<U32> & U32,r =>
      {Array.swap.lo(U32,right,Array.get.go(U32,left,size,index,low)) == r : Array<U32> & U32} &
      {Laws.array_owner(U32,r) == ANode{left,right} : Array<U32>}):
  match actual evidence:
    case Tuple{new_left,value} Tuple{same,owned}:
      ((ANode{new_left,right},value),
        ((%Equal.sym(Array<U32> & U32,Array.get.go(U32,left,size,index,low),(new_left,value),same) :
          {Array.swap.lo(U32,right,_) == (ANode{new_left,right},value) : Array<U32> & U32}
        {==}),
        (%Equal.sym(Array<U32>,new_left,left,owned) :
          {ANode{_,right} == ANode{left,right} : Array<U32>}
        {==})))

def read_left(-left:Array<U32>,right:Array<U32>,-size:U32,-index:U32,-low:Bool,
    result:ReadWitness(left,size,index,low)) ->
    Exists(Array<U32> & U32,r =>
      {Array.swap.lo(U32,right,Array.get.go(U32,left,size,index,low)) == r : Array<U32> & U32} &
      {Laws.array_owner(U32,r) == ANode{left,right} : Array<U32>}):
  match result:
    case Tuple{actual,evidence}: read_left_pair(left,right,size,index,low,actual,evidence)

def read_right_pair(left:Array<U32>,-right:Array<U32>,-size:U32,-index:U32,-low:Bool,
    actual:Array<U32> & U32,
    evidence:{Array.get.go(U32,right,size,index,low) == actual : Array<U32> & U32} &
      {Laws.array_owner(U32,actual) == right : Array<U32>}) ->
    Exists(Array<U32> & U32,r =>
      {Array.swap.hi(U32,left,Array.get.go(U32,right,size,index,low)) == r : Array<U32> & U32} &
      {Laws.array_owner(U32,r) == ANode{left,right} : Array<U32>}):
  match actual evidence:
    case Tuple{new_right,value} Tuple{same,owned}:
      ((ANode{left,new_right},value),
        ((%Equal.sym(Array<U32> & U32,Array.get.go(U32,right,size,index,low),(new_right,value),same) :
          {Array.swap.hi(U32,left,_) == (ANode{left,new_right},value) : Array<U32> & U32}
        {==}),
        (%Equal.sym(Array<U32>,new_right,right,owned) :
          {ANode{left,_} == ANode{left,right} : Array<U32>}
        {==})))

def read_right(left:Array<U32>,-right:Array<U32>,-size:U32,-index:U32,-low:Bool,
    result:ReadWitness(right,size,index,low)) ->
    Exists(Array<U32> & U32,r =>
      {Array.swap.hi(U32,left,Array.get.go(U32,right,size,index,low)) == r : Array<U32> & U32} &
      {Laws.array_owner(U32,r) == ANode{left,right} : Array<U32>}):
  match result:
    case Tuple{actual,evidence}: read_right_pair(left,right,size,index,low,actual,evidence)

def read_go_owned(a:Array<U32>,+size:U32,+index:U32,low:Bool) -> ReadWitness(a,size,index,low):
  match a low:
    case ALeaf{+value} _: ((ALeaf{value},value),({==},{==}))
    case ANode{left,right} True{}:
      +half = U32.shr(size)
      read_left(left,right,half,index,U32.is_lt(index,U32.shr(half)),
        read_go_owned(left,half,index,U32.is_lt(index,U32.shr(half))))
    case ANode{left,right} False{}:
      +half = U32.shr(size)
      +next = U32.sub(index,half)
      read_right(left,right,half,next,U32.is_lt(next,U32.shr(half)),
        read_go_owned(right,half,next,U32.is_lt(next,U32.shr(half))))

def OwnerWitness(-T:Data,-a:Array<U32>,-actual:Array<U32> & T) -> Type:
  Exists(Array<U32> & T,r =>
    {actual == r : Array<U32> & T} &
    {Laws.array_owner(T,r) == a : Array<U32>})

def get_read_pair(-a:Array<U32>,-sized:Array<U32>,-size:U32,-index:U32,
    same:{Array.size(U32,a) == (sized,size) : Array<U32> & U32},
    owned:{sized == a : Array<U32>},actual:Array<U32> & U32,
    evidence:{Array.get.go(U32,sized,size,U32.and(index,U32.sub(size,1)),
        U32.is_lt(U32.and(index,U32.sub(size,1)),U32.shr(size))) == actual : Array<U32> & U32} &
      {Laws.array_owner(U32,actual) == sized : Array<U32>}) ->
    OwnerWitness(U32,a,Array.get(U32,(a),index)):
  match actual evidence:
    case Tuple{read,value} Tuple{read_same,read_owned}:
      ((read,value),
        ((%Equal.sym(Array<U32> & U32,Array.size(U32,a),(sized,size),same) :
          {Array.get.at(U32,index,_) == (read,value) : Array<U32> & U32}
        read_same),
        Equal.trans(Array<U32>,read,sized,a,read_owned,owned)))

def get_read(-a:Array<U32>,-sized:Array<U32>,-size:U32,-index:U32,
    same:{Array.size(U32,a) == (sized,size) : Array<U32> & U32},
    owned:{sized == a : Array<U32>},
    result:ReadWitness(sized,size,U32.and(index,U32.sub(size,1)),
      U32.is_lt(U32.and(index,U32.sub(size,1)),U32.shr(size)))) ->
    OwnerWitness(U32,a,Array.get(U32,(a),index)):
  match result:
    case Tuple{actual,evidence}: get_read_pair(a,sized,size,index,same,owned,actual,evidence)

def get_sized_pair(-a:Array<U32>,+index:U32,actual:Array<U32> & U32,
    evidence:{Array.size(U32,a) == actual : Array<U32> & U32} &
      {ShapeLaws.size_owner(actual) == a : Array<U32>}) ->
    OwnerWitness(U32,a,Array.get(U32,(a),index)):
  match actual evidence:
    case Tuple{owner,+size} Tuple{same,owned}:
      get_read(a,owner,size,index,same,owned,
        read_go_owned(owner,size,U32.and(index,U32.sub(size,1)),
          U32.is_lt(U32.and(index,U32.sub(size,1)),U32.shr(size))))

def get_sized(-a:Array<U32>,+index:U32,result:ShapeProof.SizeWitness(a)) ->
    OwnerWitness(U32,a,Array.get(U32,(a),index)):
  match result:
    case Tuple{actual,evidence}: get_sized_pair(a,index,actual,evidence)

def get_owned(a:Array<U32>,+index:U32) -> OwnerWitness(U32,a,Array.get(U32,(a),index)):
  get_sized(a,index,ShapeProof.size_owned(a))

def owner_project_evidence(-T:Data,-a:Array<U32>,-read:Array<U32> -> Array<U32> & T,
    -actual:Array<U32> & T,
    evidence:{read(a) == actual : Array<U32> & T} & {Laws.array_owner(T,actual) == a : Array<U32>}) ->
    {Laws.array_owner(T,read(a)) == a : Array<U32>}:
  match evidence:
    case Tuple{same,owned}:
      %Equal.sym(Array<U32> & T,read(a),actual,same) :
        {Laws.array_owner(T,_) == a : Array<U32>}
      owned

def owner_project(-T:Data,-a:Array<U32>,-read:Array<U32> -> Array<U32> & T,
    result:OwnerWitness(T,a,read(a))) -> {Laws.array_owner(T,read(a)) == a : Array<U32>}:
  match result:
    case Tuple{actual,evidence}: owner_project_evidence(T,a,read,actual,evidence)

def Laws.array_get_returns_exact_owner(a,index):
  owner_project(U32,a,b => Array.get(U32,b,index),get_owned(a,index))

def permute_pair(-a:Array<U32>,-index:U32,actual:Array<U32> & U32,
    evidence:{Array.get(U32,a,U32.and(index,255)) == actual : Array<U32> & U32} &
      {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(U32,a,P.permute((a),index)):
  match actual evidence:
    case Tuple{read,value} Tuple{same,owned}:
      ((read,U32.and(value,255)),
        ((%Equal.sym(Array<U32> & U32,Array.get(U32,a,U32.and(index,255)),(read,value),same) :
          {P.paired(Array<U32>,U32,Array<U32> & U32,_,b => v => (b,U32.and(v,255))) ==
            (read,U32.and(value,255)) : Array<U32> & U32}
        {==}),owned))

def permute_result(-a:Array<U32>,-index:U32,
    result:OwnerWitness(U32,a,Array.get(U32,(a),U32.and(index,255)))) ->
    OwnerWitness(U32,a,P.permute((a),index)):
  match result:
    case Tuple{actual,evidence}: permute_pair(a,index,actual,evidence)

def permute_owned(a:Array<U32>,+index:U32) -> OwnerWitness(U32,a,P.permute((a),index)):
  permute_result(a,index,get_owned(a,U32.and(index,255)))

def Laws.permute_returns_exact_owner(a,index):
  owner_project(U32,a,b => P.permute(b,index),permute_owned(a,index))

# Proof-only pair elimination for each actual read of corner_hashes. All
# equations use the literal production read fragments. Keeping the closed
# callbacks in place avoids the kernel's quantity/eta mismatch on an erased
# generic function parameter; no alternate sampler or numeric model is used.
def hash_14_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,+n001:U32,+n101:U32,+n011:U32,+n111:U32) -> OwnerWitness(P.Corners,a,(a,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})):
  ((a,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}),({==},{==}))

def hash_13_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,-n110:U32,-n001:U32,-n101:U32,-n011:U32,-n111:U32,
    same:{P.permute(a,U32.inc(U32.add(py11,z))) == (read,n111) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{(read,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.inc(U32.add(py11,z))),(read,n111),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_13_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,-n110:U32,-n001:U32,-n101:U32,-n011:U32,-n111:U32,
    same:{P.permute(a,U32.inc(U32.add(py11,z))) == (read,n111) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,(read,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))):
  match result:
    case Tuple{actual,evidence}: hash_13_finished(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,n011,n111,same,owned,actual,evidence)

def hash_13_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,+n001:U32,+n101:U32,+n011:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.inc(U32.add(py11,z))) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))):
  match actual evidence:
    case Tuple{read,+n111} Tuple{same,owned}:
      hash_13_continued(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,n011,n111,same,owned,hash_14_owned(read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,n011,n111))

def hash_13_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,+n001:U32,+n101:U32,+n011:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.inc(U32.add(py11,z))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))):
  match result:
    case Tuple{actual,evidence}: hash_13_read_pair(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,n011,actual,evidence)

def hash_13_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,+n001:U32,+n101:U32,+n011:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))):
  hash_13_read_result(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,n011,permute_owned(a,U32.inc(U32.add(py11,z))))

def hash_12_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,-n110:U32,-n001:U32,-n101:U32,-n011:U32,
    same:{P.permute(a,U32.inc(U32.add(py01,z))) == (read,n011) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.inc(U32.add(py01,z))),(read,n011),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_12_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,-n110:U32,-n001:U32,-n101:U32,-n011:U32,
    same:{P.permute(a,U32.inc(U32.add(py01,z))) == (read,n011) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))):
  match result:
    case Tuple{actual,evidence}: hash_12_finished(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,n011,same,owned,actual,evidence)

def hash_12_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,+n001:U32,+n101:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.inc(U32.add(py01,z))) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))):
  match actual evidence:
    case Tuple{read,+n011} Tuple{same,owned}:
      hash_12_continued(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,n011,same,owned,hash_13_owned(read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,n011))

def hash_12_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,+n001:U32,+n101:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.inc(U32.add(py01,z))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))):
  match result:
    case Tuple{actual,evidence}: hash_12_read_pair(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,actual,evidence)

def hash_12_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,+n001:U32,+n101:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))):
  hash_12_read_result(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,permute_owned(a,U32.inc(U32.add(py01,z))))

def hash_11_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,-n110:U32,-n001:U32,-n101:U32,
    same:{P.permute(a,U32.inc(U32.add(py10,z))) == (read,n101) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.inc(U32.add(py10,z))),(read,n101),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_11_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,-n110:U32,-n001:U32,-n101:U32,
    same:{P.permute(a,U32.inc(U32.add(py10,z))) == (read,n101) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))):
  match result:
    case Tuple{actual,evidence}: hash_11_finished(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,same,owned,actual,evidence)

def hash_11_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,+n001:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.inc(U32.add(py10,z))) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))):
  match actual evidence:
    case Tuple{read,+n101} Tuple{same,owned}:
      hash_11_continued(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101,same,owned,hash_12_owned(read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,n101))

def hash_11_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,+n001:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.inc(U32.add(py10,z))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))):
  match result:
    case Tuple{actual,evidence}: hash_11_read_pair(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,actual,evidence)

def hash_11_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,+n001:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))):
  hash_11_read_result(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,permute_owned(a,U32.inc(U32.add(py10,z))))

def hash_10_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,-n110:U32,-n001:U32,
    same:{P.permute(a,U32.inc(U32.add(py00,z))) == (read,n001) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.inc(U32.add(py00,z))),(read,n001),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_10_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,-n110:U32,-n001:U32,
    same:{P.permute(a,U32.inc(U32.add(py00,z))) == (read,n001) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))):
  match result:
    case Tuple{actual,evidence}: hash_10_finished(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,same,owned,actual,evidence)

def hash_10_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.inc(U32.add(py00,z))) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))):
  match actual evidence:
    case Tuple{read,+n001} Tuple{same,owned}:
      hash_10_continued(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001,same,owned,hash_11_owned(read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,n001))

def hash_10_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.inc(U32.add(py00,z))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))):
  match result:
    case Tuple{actual,evidence}: hash_10_read_pair(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,actual,evidence)

def hash_10_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,+n110:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))):
  hash_10_read_result(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,permute_owned(a,U32.inc(U32.add(py00,z))))

def hash_9_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,-n110:U32,
    same:{P.permute(a,U32.add(py11,z)) == (read,n110) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.add(py11,z)),(read,n110),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_9_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,-n110:U32,
    same:{P.permute(a,U32.add(py11,z)) == (read,n110) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))):
  match result:
    case Tuple{actual,evidence}: hash_9_finished(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,same,owned,actual,evidence)

def hash_9_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.add(py11,z)) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))):
  match actual evidence:
    case Tuple{read,+n110} Tuple{same,owned}:
      hash_9_continued(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110,same,owned,hash_10_owned(read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,n110))

def hash_9_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.add(py11,z)))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))):
  match result:
    case Tuple{actual,evidence}: hash_9_read_pair(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,actual,evidence)

def hash_9_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,+n010:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))):
  hash_9_read_result(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,permute_owned(a,U32.add(py11,z)))

def hash_8_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,
    same:{P.permute(a,U32.add(py01,z)) == (read,n010) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.add(py01,z)),(read,n010),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_8_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,-n010:U32,
    same:{P.permute(a,U32.add(py01,z)) == (read,n010) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))):
  match result:
    case Tuple{actual,evidence}: hash_8_finished(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,same,owned,actual,evidence)

def hash_8_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.add(py01,z)) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))):
  match actual evidence:
    case Tuple{read,+n010} Tuple{same,owned}:
      hash_8_continued(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010,same,owned,hash_9_owned(read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,n010))

def hash_8_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.add(py01,z)))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))):
  match result:
    case Tuple{actual,evidence}: hash_8_read_pair(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,actual,evidence)

def hash_8_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,+n100:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))):
  hash_8_read_result(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,permute_owned(a,U32.add(py01,z)))

def hash_7_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,
    same:{P.permute(a,U32.add(py10,z)) == (read,n100) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.add(py10,z)),(read,n100),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_7_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,-n100:U32,
    same:{P.permute(a,U32.add(py10,z)) == (read,n100) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))):
  match result:
    case Tuple{actual,evidence}: hash_7_finished(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,same,owned,actual,evidence)

def hash_7_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.add(py10,z)) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))):
  match actual evidence:
    case Tuple{read,+n100} Tuple{same,owned}:
      hash_7_continued(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100,same,owned,hash_8_owned(read,x,y,z,px0,px1,py00,py01,py10,py11,n000,n100))

def hash_7_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.add(py10,z)))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))):
  match result:
    case Tuple{actual,evidence}: hash_7_read_pair(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,actual,evidence)

def hash_7_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,+n000:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))):
  hash_7_read_result(a,x,y,z,px0,px1,py00,py01,py10,py11,n000,permute_owned(a,U32.add(py10,z)))

def hash_6_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,
    same:{P.permute(a,U32.add(py00,z)) == (read,n000) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.add(py00,z)),(read,n000),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_6_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,-n000:U32,
    same:{P.permute(a,U32.add(py00,z)) == (read,n000) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))):
  match result:
    case Tuple{actual,evidence}: hash_6_finished(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,same,owned,actual,evidence)

def hash_6_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.add(py00,z)) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))):
  match actual evidence:
    case Tuple{read,+n000} Tuple{same,owned}:
      hash_6_continued(a,read,x,y,z,px0,px1,py00,py01,py10,py11,n000,same,owned,hash_7_owned(read,x,y,z,px0,px1,py00,py01,py10,py11,n000))

def hash_6_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.add(py00,z)))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))):
  match result:
    case Tuple{actual,evidence}: hash_6_read_pair(a,x,y,z,px0,px1,py00,py01,py10,py11,actual,evidence)

def hash_6_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,+py11:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))):
  hash_6_read_result(a,x,y,z,px0,px1,py00,py01,py10,py11,permute_owned(a,U32.add(py00,z)))

def hash_5_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,
    same:{P.permute(a,U32.inc(U32.add(px1,y))) == (read,py11) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.inc(U32.add(px1,y))),(read,py11),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_5_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,-py11:U32,
    same:{P.permute(a,U32.inc(U32.add(px1,y))) == (read,py11) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_5_finished(a,read,x,y,z,px0,px1,py00,py01,py10,py11,same,owned,actual,evidence)

def hash_5_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.inc(U32.add(px1,y))) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))):
  match actual evidence:
    case Tuple{read,+py11} Tuple{same,owned}:
      hash_5_continued(a,read,x,y,z,px0,px1,py00,py01,py10,py11,same,owned,hash_6_owned(read,x,y,z,px0,px1,py00,py01,py10,py11))

def hash_5_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.inc(U32.add(px1,y))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_5_read_pair(a,x,y,z,px0,px1,py00,py01,py10,actual,evidence)

def hash_5_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,+py10:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))):
  hash_5_read_result(a,x,y,z,px0,px1,py00,py01,py10,permute_owned(a,U32.inc(U32.add(px1,y))))

def hash_4_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,
    same:{P.permute(a,U32.add(px1,y)) == (read,py10) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.add(px1,y)),(read,py10),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_4_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,-py10:U32,
    same:{P.permute(a,U32.add(px1,y)) == (read,py10) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_4_finished(a,read,x,y,z,px0,px1,py00,py01,py10,same,owned,actual,evidence)

def hash_4_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.add(px1,y)) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))):
  match actual evidence:
    case Tuple{read,+py10} Tuple{same,owned}:
      hash_4_continued(a,read,x,y,z,px0,px1,py00,py01,py10,same,owned,hash_5_owned(read,x,y,z,px0,px1,py00,py01,py10))

def hash_4_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.add(px1,y)))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_4_read_pair(a,x,y,z,px0,px1,py00,py01,actual,evidence)

def hash_4_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,+py01:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))):
  hash_4_read_result(a,x,y,z,px0,px1,py00,py01,permute_owned(a,U32.add(px1,y)))

def hash_3_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,
    same:{P.permute(a,U32.inc(U32.add(px0,y))) == (read,py01) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.inc(U32.add(px0,y))),(read,py01),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_3_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,-py01:U32,
    same:{P.permute(a,U32.inc(U32.add(px0,y))) == (read,py01) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_3_finished(a,read,x,y,z,px0,px1,py00,py01,same,owned,actual,evidence)

def hash_3_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.inc(U32.add(px0,y))) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))):
  match actual evidence:
    case Tuple{read,+py01} Tuple{same,owned}:
      hash_3_continued(a,read,x,y,z,px0,px1,py00,py01,same,owned,hash_4_owned(read,x,y,z,px0,px1,py00,py01))

def hash_3_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.inc(U32.add(px0,y))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_3_read_pair(a,x,y,z,px0,px1,py00,actual,evidence)

def hash_3_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,+py00:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))):
  hash_3_read_result(a,x,y,z,px0,px1,py00,permute_owned(a,U32.inc(U32.add(px0,y))))

def hash_2_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,
    same:{P.permute(a,U32.add(px0,y)) == (read,py00) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.add(px0,y)),(read,py00),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_2_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,-py00:U32,
    same:{P.permute(a,U32.add(px0,y)) == (read,py00) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_2_finished(a,read,x,y,z,px0,px1,py00,same,owned,actual,evidence)

def hash_2_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.add(px0,y)) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))):
  match actual evidence:
    case Tuple{read,+py00} Tuple{same,owned}:
      hash_2_continued(a,read,x,y,z,px0,px1,py00,same,owned,hash_3_owned(read,x,y,z,px0,px1,py00))

def hash_2_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.add(px0,y)))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_2_read_pair(a,x,y,z,px0,px1,actual,evidence)

def hash_2_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,+px1:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))):
  hash_2_read_result(a,x,y,z,px0,px1,permute_owned(a,U32.add(px0,y)))

def hash_1_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,
    same:{P.permute(a,U32.inc(x)) == (read,px1) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,U32.inc(x)),(read,px1),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_1_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,-px1:U32,
    same:{P.permute(a,U32.inc(x)) == (read,px1) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_1_finished(a,read,x,y,z,px0,px1,same,owned,actual,evidence)

def hash_1_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,U32.inc(x)) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))))):
  match actual evidence:
    case Tuple{read,+px1} Tuple{same,owned}:
      hash_1_continued(a,read,x,y,z,px0,px1,same,owned,hash_2_owned(read,x,y,z,px0,px1))

def hash_1_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32,
    result:OwnerWitness(U32,a,P.permute(a,U32.inc(x)))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_1_read_pair(a,x,y,z,px0,actual,evidence)

def hash_1_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32,+px0:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))))):
  hash_1_read_result(a,x,y,z,px0,permute_owned(a,U32.inc(x)))

def hash_0_finished(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,
    same:{P.permute(a,x) == (read,px0) : Array<U32> & U32},owned:{read == a : Array<U32>},
    actual:Array<U32> & P.Corners,evidence:{P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))) == actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == read : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,x),perms => +px0 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))))):
  match actual evidence:
    case Tuple{final,corners} Tuple{continued,retained}:
      ((final,corners),
        ((%Equal.sym(Array<U32> & U32,P.permute(a,x),(read,px0),same) :
          {P.paired(Array<U32>,U32,Array<U32> & P.Corners,_,perms => +px0 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111}))))))))))))))) == (final,corners) : Array<U32> & P.Corners}
        continued),
        Equal.trans(Array<U32>,final,read,a,retained,owned)))

def hash_0_continued(-a:Array<U32>,-read:Array<U32>,-x:U32,-y:U32,-z:U32,-px0:U32,
    same:{P.permute(a,x) == (read,px0) : Array<U32> & U32},owned:{read == a : Array<U32>},
    result:OwnerWitness(P.Corners,read,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(read,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,x),perms => +px0 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_0_finished(a,read,x,y,z,px0,same,owned,actual,evidence)

def hash_0_read_pair(-a:Array<U32>,+x:U32,+y:U32,+z:U32,actual:Array<U32> & U32,
    evidence:{P.permute(a,x) == actual : Array<U32> & U32} & {Laws.array_owner(U32,actual) == a : Array<U32>}) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,x),perms => +px0 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))))):
  match actual evidence:
    case Tuple{read,+px0} Tuple{same,owned}:
      hash_0_continued(a,read,x,y,z,px0,same,owned,hash_1_owned(read,x,y,z,px0))

def hash_0_read_result(-a:Array<U32>,+x:U32,+y:U32,+z:U32,
    result:OwnerWitness(U32,a,P.permute(a,x))) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,x),perms => +px0 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))))):
  match result:
    case Tuple{actual,evidence}: hash_0_read_pair(a,x,y,z,actual,evidence)

def hash_0_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32) ->
    OwnerWitness(P.Corners,a,P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(a,x),perms => +px0 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(x)),perms => +px1 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px0,y)),perms => +py00 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px0,y))),perms => +py01 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(px1,y)),perms => +py10 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(px1,y))),perms => +py11 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py00,z)),perms => n000 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py10,z)),perms => n100 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py01,z)),perms => n010 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.add(py11,z)),perms => n110 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py00,z))),perms => n001 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py10,z))),perms => n101 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py01,z))),perms => n011 => P.paired(Array<U32>,U32,Array<U32> & P.Corners,P.permute(perms,U32.inc(U32.add(py11,z))),perms => n111 => (perms,P.Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))))):
  hash_0_read_result(a,x,y,z,permute_owned(a,x))

def hashes_owned(a:Array<U32>,+x:U32,+y:U32,+z:U32) ->
    OwnerWitness(P.Corners,a,P.corner_hashes(a,x,y,z)):
  hash_0_owned(a,x,y,z)

def Laws.corner_hashes_returns_exact_owner(a,x,y,z):
  owner_project(P.Corners,a,b => P.corner_hashes(b,x,y,z),hashes_owned(a,x,y,z))

def StateWitness(-O:Type,-V:Type,-owner:O,-actual:O & V) -> Type:
  Exists(O & V,r => {actual == r : O & V} & {Laws.state_owner(O,V,r) == owner : O})

def state_project_evidence(-O:Type,-V:Type,-owner:O,-read:O -> O & V,-actual:O & V,
    evidence:{read(owner) == actual : O & V} & {Laws.state_owner(O,V,actual) == owner : O}) ->
    {Laws.state_owner(O,V,read(owner)) == owner : O}:
  match evidence:
    case Tuple{same,owned}:
      %Equal.sym(O & V,read(owner),actual,same) : {Laws.state_owner(O,V,_) == owner : O}
      owned

def state_project(-O:Type,-V:Type,-owner:O,-read:O -> O & V,
    result:StateWitness(O,V,owner,read(owner))) -> {Laws.state_owner(O,V,read(owner)) == owner : O}:
  match result:
    case Tuple{actual,evidence}: state_project_evidence(O,V,owner,read,actual,evidence)

def perlin_sample_pair(-a:Array<U32>,+offset_x:F.F64,+offset_y:F.F64,+offset_z:F.F64,+mode:P.Mode,
    +farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,actual:Array<U32> & P.Corners,
    evidence:{P.corner_hashes(a,P.floor_word(F.add(P.wrap(x,farlands),offset_x)),
        P.floor_word(F.add(P.wrap(y,farlands),offset_y)),P.floor_word(F.add(P.wrap(z,farlands),offset_z))) ==
        actual : Array<U32> & P.Corners} & {Laws.array_owner(P.Corners,actual) == a : Array<U32>}) ->
    StateWitness(P.Noise,F32,P.Noise{a,offset_x,offset_y,offset_z,mode},P.get((P.Noise{a,offset_x,offset_y,offset_z,mode}),farlands,x,y,z)):
  match actual evidence:
    case Tuple{read,corners} Tuple{same,owned}:
      +sx = F.add(P.wrap(x,farlands),offset_x)
      +sy = F.add(P.wrap(y,farlands),offset_y)
      +sz = F.add(P.wrap(z,farlands),offset_z)
      +iy = P.floor_word(sy)
      +fraction_y = F.sub(sy,F.from_i32(iy))
      +value = P.sample_corners(corners,F.to_f32(F.sub(sx,F.from_i32(P.floor_word(sx)))),
        F.to_f32(P.gradient_y(mode,y,fraction_y)),F.to_f32(F.sub(sz,F.from_i32(P.floor_word(sz)))),F.to_f32(fraction_y))
      ((P.Noise{read,offset_x,offset_y,offset_z,mode},value),
        ((%Equal.sym(Array<U32> & P.Corners,
          P.corner_hashes(a,P.floor_word(sx),iy,P.floor_word(sz)),(read,corners),same) :
          {P.paired(Array<U32>,F32,P.Noise & F32,
            P.sample_result(F.to_f32(F.sub(sx,F.from_i32(P.floor_word(sx)))),
              F.to_f32(P.gradient_y(mode,y,fraction_y)),F.to_f32(F.sub(sz,F.from_i32(P.floor_word(sz)))),
              F.to_f32(fraction_y),_),b => v => (P.Noise{b,offset_x,offset_y,offset_z,mode},v)) ==
            (P.Noise{read,offset_x,offset_y,offset_z,mode},value) : P.Noise & F32}
        {==}),
        (%Equal.sym(Array<U32>,read,a,owned) :
          {P.Noise{_,offset_x,offset_y,offset_z,mode} == P.Noise{a,offset_x,offset_y,offset_z,mode} : P.Noise}
        {==})))

def perlin_sample_result(-a:Array<U32>,+offset_x:F.F64,+offset_y:F.F64,+offset_z:F.F64,+mode:P.Mode,
    +farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,
    result:OwnerWitness(P.Corners,a,P.corner_hashes((a),P.floor_word(F.add(P.wrap(x,farlands),offset_x)),
      P.floor_word(F.add(P.wrap(y,farlands),offset_y)),P.floor_word(F.add(P.wrap(z,farlands),offset_z))))) ->
    StateWitness(P.Noise,F32,P.Noise{a,offset_x,offset_y,offset_z,mode},P.get((P.Noise{a,offset_x,offset_y,offset_z,mode}),farlands,x,y,z)):
  match result:
    case Tuple{actual,evidence}: perlin_sample_pair(a,offset_x,offset_y,offset_z,mode,farlands,x,y,z,actual,evidence)

def perlin_owned(noise:P.Noise,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64) ->
    StateWitness(P.Noise,F32,noise,P.get((noise),farlands,x,y,z)):
  match noise:
    case P.Noise{a,+offset_x,+offset_y,+offset_z,mode}:
      perlin_sample_result(a,offset_x,offset_y,offset_z,mode,farlands,x,y,z,
        hashes_owned(a,P.floor_word(F.add(P.wrap(x,farlands),offset_x)),
          P.floor_word(F.add(P.wrap(y,farlands),offset_y)),P.floor_word(F.add(P.wrap(z,farlands),offset_z))))

def Laws.perlin_get_returns_exact_owner(noise,farlands,x,y,z):
  state_project(P.Noise,F32,noise,n => P.get(n,farlands,x,y,z),perlin_owned(noise,farlands,x,y,z))

def layers_rest_pair(-original:P.Noise,-rest:List<&1,B.Layer>,frequency:F.F64,amplitude:F32,
    -farlands:Bool,-x:F.F64,-y:F.F64,-z:F.F64,-accumulator:F32,
    noise:P.Noise,+sample:F32,
    sampled:{P.get(original,farlands,F.mul(x,frequency),F.mul(y,frequency),F.mul(z,frequency)) ==
      (noise,sample) : P.Noise & F32},
    retained:{noise == original : P.Noise},actual:List<&1,B.Layer> & F32,
    evidence:{B.stack_layers(rest,farlands,x,y,z,F32.add(accumulator,F32.mul(amplitude,sample))) ==
      actual : List<&1,B.Layer> & F32} & {Laws.state_owner(List<&1,B.Layer>,F32,actual) == rest : List<&1,B.Layer>}) ->
    StateWitness(List<&1,B.Layer>,F32,B.Layer{original,frequency,amplitude} <> rest,B.stack_layers((B.Layer{original,frequency,amplitude} <> rest),farlands,x,y,z,accumulator)):
  match actual evidence:
    case Tuple{new_rest,total} Tuple{continued,rest_owned}:
      ((B.Layer{noise,frequency,amplitude} <> new_rest,total),
        ((%Equal.sym(P.Noise & F32,
          P.get(original,farlands,F.mul(x,frequency),F.mul(y,frequency),F.mul(z,frequency)),(noise,sample),sampled) :
          {P.paired(P.Noise,F32,List<&1,B.Layer> & F32,_,n => v =>
            P.paired(List<&1,B.Layer>,F32,List<&1,B.Layer> & F32,
              B.stack_layers(rest,farlands,x,y,z,F32.add(accumulator,F32.mul(amplitude,v))),
              tail => t => (B.Layer{n,frequency,amplitude} <> tail,t))) ==
            (B.Layer{noise,frequency,amplitude} <> new_rest,total) : List<&1,B.Layer> & F32}
        %Equal.sym(List<&1,B.Layer> & F32,
          B.stack_layers(rest,farlands,x,y,z,F32.add(accumulator,F32.mul(amplitude,sample))),
          (new_rest,total),continued) :
          {P.paired(List<&1,B.Layer>,F32,List<&1,B.Layer> & F32,_,
            tail => t => (B.Layer{noise,frequency,amplitude} <> tail,t)) ==
            (B.Layer{noise,frequency,amplitude} <> new_rest,total) : List<&1,B.Layer> & F32}
        {==}),
        (%Equal.sym(P.Noise,noise,original,retained) :
          {B.Layer{_,frequency,amplitude} <> new_rest == B.Layer{original,frequency,amplitude} <> rest : List<&1,B.Layer>}
        %Equal.sym(List<&1,B.Layer>,new_rest,rest,rest_owned) :
          {B.Layer{original,frequency,amplitude} <> _ == B.Layer{original,frequency,amplitude} <> rest : List<&1,B.Layer>}
        {==})))

def layers_rest_result(-original:P.Noise,-rest:List<&1,B.Layer>,+frequency:F.F64,+amplitude:F32,
    +farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,+accumulator:F32,
    noise:P.Noise,+sample:F32,
    sampled:{P.get(original,farlands,F.mul(x,frequency),F.mul(y,frequency),F.mul(z,frequency)) ==
      (noise,sample) : P.Noise & F32},retained:{noise == original : P.Noise},
    result:StateWitness(List<&1,B.Layer>,F32,rest,B.stack_layers((rest),farlands,x,y,z,F32.add(accumulator,F32.mul(amplitude,sample))))) ->
    StateWitness(List<&1,B.Layer>,F32,B.Layer{original,frequency,amplitude} <> rest,B.stack_layers((B.Layer{original,frequency,amplitude} <> rest),farlands,x,y,z,accumulator)):
  match result:
    case Tuple{actual,evidence}: layers_rest_pair(original,rest,frequency,amplitude,farlands,x,y,z,accumulator,
      noise,sample,sampled,retained,actual,evidence)

def layers_sample_pair(-original:P.Noise,-rest:List<&1,B.Layer>,+frequency:F.F64,+amplitude:F32,
    +farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,+accumulator:F32,
    actual:P.Noise & F32,
    evidence:{P.get(original,farlands,F.mul(x,frequency),F.mul(y,frequency),F.mul(z,frequency)) ==
      actual : P.Noise & F32} & {Laws.state_owner(P.Noise,F32,actual) == original : P.Noise},
    next:(@+sample:F32 -> StateWitness(List<&1,B.Layer>,F32,rest,B.stack_layers((rest),farlands,x,y,z,F32.add(accumulator,F32.mul(amplitude,sample)))))) ->
    StateWitness(List<&1,B.Layer>,F32,B.Layer{original,frequency,amplitude} <> rest,B.stack_layers((B.Layer{original,frequency,amplitude} <> rest),farlands,x,y,z,accumulator)):
  match actual evidence:
    case Tuple{noise,+sample} Tuple{sampled,retained}:
      layers_rest_result(original,rest,frequency,amplitude,farlands,x,y,z,accumulator,
        noise,sample,sampled,retained,next(sample))

def layers_sample_result(-original:P.Noise,-rest:List<&1,B.Layer>,+frequency:F.F64,+amplitude:F32,
    +farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,+accumulator:F32,
    result:StateWitness(P.Noise,F32,original,P.get((original),farlands,F.mul(x,frequency),F.mul(y,frequency),F.mul(z,frequency))),
    next:(@+sample:F32 -> StateWitness(List<&1,B.Layer>,F32,rest,B.stack_layers((rest),farlands,x,y,z,F32.add(accumulator,F32.mul(amplitude,sample)))))) ->
    StateWitness(List<&1,B.Layer>,F32,B.Layer{original,frequency,amplitude} <> rest,B.stack_layers((B.Layer{original,frequency,amplitude} <> rest),farlands,x,y,z,accumulator)):
  match result:
    case Tuple{actual,evidence}: layers_sample_pair(original,rest,frequency,amplitude,farlands,x,y,z,accumulator,
      actual,evidence,next)

def layers_owned(layers:List<&1,B.Layer>,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,+accumulator:F32) ->
    StateWitness(List<&1,B.Layer>,F32,layers,B.stack_layers((layers),farlands,x,y,z,accumulator)):
  match layers:
    case Nil{}: (([],accumulator),({==},{==}))
    case B.Layer{noise,+frequency,+amplitude} <> rest:
      layers_sample_result(noise,rest,frequency,amplitude,farlands,x,y,z,accumulator,
        perlin_owned(noise,farlands,F.mul(x,frequency),F.mul(y,frequency),F.mul(z,frequency)),
        +sample => layers_owned(rest,farlands,x,y,z,F32.add(accumulator,F32.mul(amplitude,sample))))

def stack_layers_pair(-layers:List<&1,B.Layer>,-farlands:Bool,-x:F.F64,-y:F.F64,-z:F.F64,
    actual:List<&1,B.Layer> & F32,
    evidence:{B.stack_layers(layers,farlands,x,y,z,0.0) == actual : List<&1,B.Layer> & F32} &
      {Laws.state_owner(List<&1,B.Layer>,F32,actual) == layers : List<&1,B.Layer>}) ->
    StateWitness(B.Stack,F32,B.Stack{layers},B.stack_get((B.Stack{layers}),farlands,x,y,z)):
  match actual evidence:
    case Tuple{new_layers,value} Tuple{same,owned}:
      ((B.Stack{new_layers},value),
        ((%Equal.sym(List<&1,B.Layer> & F32,B.stack_layers(layers,farlands,x,y,z,0.0),(new_layers,value),same) :
          {P.paired(List<&1,B.Layer>,F32,B.Stack & F32,_,ls => v => (B.Stack{ls},v)) ==
            (B.Stack{new_layers},value) : B.Stack & F32}
        {==}),
        (%Equal.sym(List<&1,B.Layer>,new_layers,layers,owned) :
          {B.Stack{_} == B.Stack{layers} : B.Stack}
        {==})))

def stack_layers_result(-layers:List<&1,B.Layer>,-farlands:Bool,-x:F.F64,-y:F.F64,-z:F.F64,
    result:StateWitness(List<&1,B.Layer>,F32,layers,B.stack_layers((layers),farlands,x,y,z,0.0))) ->
    StateWitness(B.Stack,F32,B.Stack{layers},B.stack_get((B.Stack{layers}),farlands,x,y,z)):
  match result:
    case Tuple{actual,evidence}: stack_layers_pair(layers,farlands,x,y,z,actual,evidence)

def stack_owned(stack:B.Stack,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64) ->
    StateWitness(B.Stack,F32,stack,B.stack_get((stack),farlands,x,y,z)):
  match stack:
    case B.Stack{layers}: stack_layers_result(layers,farlands,x,y,z,layers_owned(layers,farlands,x,y,z,0.0))

def Laws.stack_get_returns_exact_owner(stack,farlands,x,y,z):
  state_project(B.Stack,F32,stack,s => B.stack_get(s,farlands,x,y,z),stack_owned(stack,farlands,x,y,z))

def limits_owner(result:B.Stack & (B.Stack & F32)) -> B.Stack & B.Stack:
  (first,tail) = result
  (second,value) = tail
  (first,second)

def LimitsWitness(-first:B.Stack,-second:B.Stack,-farlands:Bool,-x:F.F64,-y:F.F64,-z:F.F64,
    -alpha:F32,-which:B.BlendCase) -> Type:
  Exists(B.Stack & (B.Stack & F32),r =>
    {B.blend_limits(first,second,farlands,x,y,z,alpha,which) == r : B.Stack & (B.Stack & F32)} &
    {limits_owner(r) == (first,second) : B.Stack & B.Stack})

def limits_first_pair(-first:B.Stack,second:B.Stack,-farlands:Bool,-x:F.F64,-y:F.F64,-z:F.F64,-alpha:F32,
    actual:B.Stack & F32,
    evidence:{B.stack_get(first,farlands,x,y,z) == actual : B.Stack & F32} &
      {Laws.state_owner(B.Stack,F32,actual) == first : B.Stack}) ->
    LimitsWitness(first,second,farlands,x,y,z,alpha,B.FirstOnly{}):
  match actual evidence:
    case Tuple{new_first,value} Tuple{same,owned}:
      ((new_first,(second,value)),
        ((%Equal.sym(B.Stack & F32,B.stack_get(first,farlands,x,y,z),(new_first,value),same) :
          {P.paired(B.Stack,F32,B.Stack & (B.Stack & F32),_,s => v => (s,(second,v))) ==
            (new_first,(second,value)) : B.Stack & (B.Stack & F32)}
        {==}),
        (%Equal.sym(B.Stack,new_first,first,owned) : {(_,second) == (first,second) : B.Stack & B.Stack}
        {==})))

def limits_first_result(-first:B.Stack,second:B.Stack,-farlands:Bool,-x:F.F64,-y:F.F64,-z:F.F64,-alpha:F32,
    result:StateWitness(B.Stack,F32,first,B.stack_get((first),farlands,x,y,z))) ->
    LimitsWitness(first,second,farlands,x,y,z,alpha,B.FirstOnly{}):
  match result:
    case Tuple{actual,evidence}: limits_first_pair(first,second,farlands,x,y,z,alpha,actual,evidence)

def limits_second_pair(first:B.Stack,-second:B.Stack,-farlands:Bool,-x:F.F64,-y:F.F64,-z:F.F64,-alpha:F32,
    actual:B.Stack & F32,
    evidence:{B.stack_get(second,farlands,x,y,z) == actual : B.Stack & F32} &
      {Laws.state_owner(B.Stack,F32,actual) == second : B.Stack}) ->
    LimitsWitness(first,second,farlands,x,y,z,alpha,B.SecondOnly{}):
  match actual evidence:
    case Tuple{new_second,value} Tuple{same,owned}:
      ((first,(new_second,value)),
        ((%Equal.sym(B.Stack & F32,B.stack_get(second,farlands,x,y,z),(new_second,value),same) :
          {P.paired(B.Stack,F32,B.Stack & (B.Stack & F32),_,s => v => (first,(s,v))) ==
            (first,(new_second,value)) : B.Stack & (B.Stack & F32)}
        {==}),
        (%Equal.sym(B.Stack,new_second,second,owned) : {(first,_) == (first,second) : B.Stack & B.Stack}
        {==})))

def limits_second_result(first:B.Stack,-second:B.Stack,-farlands:Bool,-x:F.F64,-y:F.F64,-z:F.F64,-alpha:F32,
    result:StateWitness(B.Stack,F32,second,B.stack_get((second),farlands,x,y,z))) ->
    LimitsWitness(first,second,farlands,x,y,z,alpha,B.SecondOnly{}):
  match result:
    case Tuple{actual,evidence}: limits_second_pair(first,second,farlands,x,y,z,alpha,actual,evidence)

def limits_both_second_pair(-first:B.Stack,-second:B.Stack,-farlands:Bool,-x:F.F64,-y:F.F64,-z:F.F64,
    alpha:F32,new_first:B.Stack,+a:F32,
    first_same:{B.stack_get(first,farlands,x,y,z) == (new_first,a) : B.Stack & F32},
    first_owned:{new_first == first : B.Stack},actual:B.Stack & F32,
    evidence:{B.stack_get(second,farlands,x,y,z) == actual : B.Stack & F32} &
      {Laws.state_owner(B.Stack,F32,actual) == second : B.Stack}) ->
    LimitsWitness(first,second,farlands,x,y,z,alpha,B.Both{}):
  match actual evidence:
    case Tuple{new_second,b} Tuple{second_same,second_owned}:
      ((new_first,(new_second,P.lerp(alpha,a,b))),
        ((%Equal.sym(B.Stack & F32,B.stack_get(first,farlands,x,y,z),(new_first,a),first_same) :
          {P.paired(B.Stack,F32,B.Stack & (B.Stack & F32),_,f => v =>
            P.paired(B.Stack,F32,B.Stack & (B.Stack & F32),B.stack_get(second,farlands,x,y,z),
              s => w => (f,(s,P.lerp(alpha,v,w))))) ==
            (new_first,(new_second,P.lerp(alpha,a,b))) : B.Stack & (B.Stack & F32)}
        %Equal.sym(B.Stack & F32,B.stack_get(second,farlands,x,y,z),(new_second,b),second_same) :
          {P.paired(B.Stack,F32,B.Stack & (B.Stack & F32),_,s => w => (new_first,(s,P.lerp(alpha,a,w)))) ==
            (new_first,(new_second,P.lerp(alpha,a,b))) : B.Stack & (B.Stack & F32)}
        {==}),
        (%Equal.sym(B.Stack,new_first,first,first_owned) :
          {(_,new_second) == (first,second) : B.Stack & B.Stack}
        %Equal.sym(B.Stack,new_second,second,second_owned) :
          {(first,_) == (first,second) : B.Stack & B.Stack}
        {==})))

def limits_both_second_result(-first:B.Stack,-second:B.Stack,-farlands:Bool,-x:F.F64,-y:F.F64,-z:F.F64,
    alpha:F32,new_first:B.Stack,+a:F32,
    first_same:{B.stack_get(first,farlands,x,y,z) == (new_first,a) : B.Stack & F32},
    first_owned:{new_first == first : B.Stack},
    result:StateWitness(B.Stack,F32,second,B.stack_get((second),farlands,x,y,z))) ->
    LimitsWitness(first,second,farlands,x,y,z,alpha,B.Both{}):
  match result:
    case Tuple{actual,evidence}: limits_both_second_pair(first,second,farlands,x,y,z,alpha,new_first,a,
      first_same,first_owned,actual,evidence)

def limits_both_first_pair(-first:B.Stack,second:B.Stack,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,
    alpha:F32,actual:B.Stack & F32,
    evidence:{B.stack_get(first,farlands,x,y,z) == actual : B.Stack & F32} &
      {Laws.state_owner(B.Stack,F32,actual) == first : B.Stack}) ->
    LimitsWitness(first,second,farlands,x,y,z,alpha,B.Both{}):
  match actual evidence:
    case Tuple{new_first,+a} Tuple{same,owned}:
      limits_both_second_result(first,second,farlands,x,y,z,alpha,new_first,a,same,owned,
        stack_owned(second,farlands,x,y,z))

def limits_both_first_result(-first:B.Stack,second:B.Stack,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,
    alpha:F32,result:StateWitness(B.Stack,F32,first,B.stack_get((first),farlands,x,y,z))) ->
    LimitsWitness(first,second,farlands,x,y,z,alpha,B.Both{}):
  match result:
    case Tuple{actual,evidence}: limits_both_first_pair(first,second,farlands,x,y,z,alpha,actual,evidence)

def limits_owned(first:B.Stack,second:B.Stack,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,alpha:F32,which:B.BlendCase) ->
    LimitsWitness(first,second,farlands,x,y,z,alpha,which):
  match which:
    case B.FirstOnly{}:
      limits_first_result(first,second,farlands,x,y,z,alpha,stack_owned(first,farlands,x,y,z))
    case B.SecondOnly{}:
      limits_second_result(first,second,farlands,x,y,z,alpha,stack_owned(second,farlands,x,y,z))
    case B.Both{}:
      limits_both_first_result(first,second,farlands,x,y,z,alpha,stack_owned(first,farlands,x,y,z))

def rebuild_blended(config:B.Config,main:B.Stack,owners:B.Stack & B.Stack) -> B.Blended:
  (first,second) = owners
  B.Blended{config,first,second,main}

def blended_limits_pair(+xz_scale:F.F64,+y_scale:F.F64,+xz_factor:F.F64,+y_factor:F.F64,+smear:F.F64,
    -min_limit:B.Stack,-max_limit:B.Stack,-main:B.Stack,new_main:B.Stack,+main_value:F32,
    +farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,
    main_same:{B.stack_get(main,farlands,F.mul(x,F.div(F.mul(B.base_scale(),xz_scale),xz_factor)),
      F.mul(y,F.div(F.mul(B.base_scale(),y_scale),y_factor)),F.mul(z,F.div(F.mul(B.base_scale(),xz_scale),xz_factor))) ==
      (new_main,main_value) : B.Stack & F32},main_owned:{new_main == main : B.Stack},
    actual:B.Stack & (B.Stack & F32),
    evidence:{B.blend_limits(min_limit,max_limit,farlands,F.mul(x,F.mul(B.base_scale(),xz_scale)),
      F.mul(y,F.mul(B.base_scale(),y_scale)),F.mul(z,F.mul(B.base_scale(),xz_scale)),
      B.clamp_alpha(F32.add(main_value,0.5)),B.blend_case(B.clamp_alpha(F32.add(main_value,0.5)))) ==
      actual : B.Stack & (B.Stack & F32)} & {limits_owner(actual) == (min_limit,max_limit) : B.Stack & B.Stack}) ->
    StateWitness(B.Blended,F32,B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,main},B.get((B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,main}),farlands,x,y,z)):
  match actual evidence:
    case Tuple{new_min,Tuple{new_max,value}} Tuple{limits_same,limits_owned}:
      ((B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},new_min,new_max,new_main},value),
        ((%Equal.sym(B.Stack & F32,
          B.stack_get(main,farlands,F.mul(x,F.div(F.mul(B.base_scale(),xz_scale),xz_factor)),
            F.mul(y,F.div(F.mul(B.base_scale(),y_scale),y_factor)),F.mul(z,F.div(F.mul(B.base_scale(),xz_scale),xz_factor))),
          (new_main,main_value),main_same) :
          {P.paired(B.Stack,F32,B.Blended & F32,_,m => +v =>
            B.blended_result(B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},m,
              B.blend_limits(min_limit,max_limit,farlands,F.mul(x,F.mul(B.base_scale(),xz_scale)),
                F.mul(y,F.mul(B.base_scale(),y_scale)),F.mul(z,F.mul(B.base_scale(),xz_scale)),
                B.clamp_alpha(F32.add(v,0.5)),B.blend_case(B.clamp_alpha(F32.add(v,0.5)))))) ==
            (B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},new_min,new_max,new_main},value) : B.Blended & F32}
        %Equal.sym(B.Stack & (B.Stack & F32),
          B.blend_limits(min_limit,max_limit,farlands,F.mul(x,F.mul(B.base_scale(),xz_scale)),
            F.mul(y,F.mul(B.base_scale(),y_scale)),F.mul(z,F.mul(B.base_scale(),xz_scale)),
            B.clamp_alpha(F32.add(main_value,0.5)),B.blend_case(B.clamp_alpha(F32.add(main_value,0.5)))),
          (new_min,(new_max,value)),limits_same) :
          {B.blended_result(B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},new_main,_) ==
            (B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},new_min,new_max,new_main},value) : B.Blended & F32}
        {==}),
        (%Equal.sym(B.Stack & B.Stack,(new_min,new_max),(min_limit,max_limit),limits_owned) :
          {rebuild_blended(B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},new_main,_) ==
            B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,main} : B.Blended}
        %Equal.sym(B.Stack,new_main,main,main_owned) :
          {B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,_} ==
            B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,main} : B.Blended}
        {==})))

def blended_limits_result(+xz_scale:F.F64,+y_scale:F.F64,+xz_factor:F.F64,+y_factor:F.F64,+smear:F.F64,
    -min_limit:B.Stack,-max_limit:B.Stack,-main:B.Stack,new_main:B.Stack,+main_value:F32,
    +farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,
    main_same:{B.stack_get(main,farlands,F.mul(x,F.div(F.mul(B.base_scale(),xz_scale),xz_factor)),
      F.mul(y,F.div(F.mul(B.base_scale(),y_scale),y_factor)),F.mul(z,F.div(F.mul(B.base_scale(),xz_scale),xz_factor))) ==
      (new_main,main_value) : B.Stack & F32},main_owned:{new_main == main : B.Stack},
    result:LimitsWitness(min_limit,max_limit,farlands,F.mul(x,F.mul(B.base_scale(),xz_scale)),
      F.mul(y,F.mul(B.base_scale(),y_scale)),F.mul(z,F.mul(B.base_scale(),xz_scale)),
      B.clamp_alpha(F32.add(main_value,0.5)),B.blend_case(B.clamp_alpha(F32.add(main_value,0.5))))) ->
    StateWitness(B.Blended,F32,B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,main},B.get((B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,main}),farlands,x,y,z)):
  match result:
    case Tuple{actual,evidence}: blended_limits_pair(xz_scale,y_scale,xz_factor,y_factor,smear,
      min_limit,max_limit,main,new_main,main_value,farlands,x,y,z,main_same,main_owned,actual,evidence)

def blended_main_pair(+xz_scale:F.F64,+y_scale:F.F64,+xz_factor:F.F64,+y_factor:F.F64,+smear:F.F64,
    min_limit:B.Stack,max_limit:B.Stack,-main:B.Stack,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,
    actual:B.Stack & F32,
    evidence:{B.stack_get(main,farlands,F.mul(x,F.div(F.mul(B.base_scale(),xz_scale),xz_factor)),
      F.mul(y,F.div(F.mul(B.base_scale(),y_scale),y_factor)),F.mul(z,F.div(F.mul(B.base_scale(),xz_scale),xz_factor))) ==
      actual : B.Stack & F32} & {Laws.state_owner(B.Stack,F32,actual) == main : B.Stack}) ->
    StateWitness(B.Blended,F32,B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,main},B.get((B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,main}),farlands,x,y,z)):
  match actual evidence:
    case Tuple{new_main,+main_value} Tuple{same,owned}:
      blended_limits_result(xz_scale,y_scale,xz_factor,y_factor,smear,min_limit,max_limit,main,new_main,main_value,
        farlands,x,y,z,same,owned,
        limits_owned(min_limit,max_limit,farlands,F.mul(x,F.mul(B.base_scale(),xz_scale)),
          F.mul(y,F.mul(B.base_scale(),y_scale)),F.mul(z,F.mul(B.base_scale(),xz_scale)),
          B.clamp_alpha(F32.add(main_value,0.5)),B.blend_case(B.clamp_alpha(F32.add(main_value,0.5)))))

def blended_main_result(+xz_scale:F.F64,+y_scale:F.F64,+xz_factor:F.F64,+y_factor:F.F64,+smear:F.F64,
    min_limit:B.Stack,max_limit:B.Stack,-main:B.Stack,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,
    result:StateWitness(B.Stack,F32,main,B.stack_get((main),farlands,
      F.mul(x,F.div(F.mul(B.base_scale(),xz_scale),xz_factor)),
      F.mul(y,F.div(F.mul(B.base_scale(),y_scale),y_factor)),F.mul(z,F.div(F.mul(B.base_scale(),xz_scale),xz_factor))))) ->
    StateWitness(B.Blended,F32,B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,main},B.get((B.Blended{B.Config{xz_scale,y_scale,xz_factor,y_factor,smear},min_limit,max_limit,main}),farlands,x,y,z)):
  match result:
    case Tuple{actual,evidence}: blended_main_pair(xz_scale,y_scale,xz_factor,y_factor,smear,min_limit,max_limit,main,
      farlands,x,y,z,actual,evidence)

def blended_owned(blended:B.Blended,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64) ->
    StateWitness(B.Blended,F32,blended,B.get((blended),farlands,x,y,z)):
  match blended:
    case B.Blended{B.Config{+xz_scale,+y_scale,+xz_factor,+y_factor,smear},min_limit,max_limit,main}:
      blended_main_result(xz_scale,y_scale,xz_factor,y_factor,smear,min_limit,max_limit,main,farlands,x,y,z,
        stack_owned(main,farlands,F.mul(x,F.div(F.mul(B.base_scale(),xz_scale),xz_factor)),
          F.mul(y,F.div(F.mul(B.base_scale(),y_scale),y_factor)),F.mul(z,F.div(F.mul(B.base_scale(),xz_scale),xz_factor))))

def Laws.blended_get_returns_exact_owner(blended,farlands,x,y,z):
  state_project(B.Blended,F32,blended,b => B.get(b,farlands,x,y,z),blended_owned(blended,farlands,x,y,z))

def Laws.invalid_config_preserves_source(fuel,source,config,invalid):
  %Equal.sym(Bool,B.config_valid(config),False{},invalid) :
    {B.create_gate(fuel,source,config,_) ==
      (source,Fail{"blended-noise configuration is outside the pinned finite codec ranges"}) :
      R.Source & Result<&2,&1,String,B.Blended>}
  {==}

def Laws.exhausted_perlin_constructor_preserves_source(source,mode):
  match source:
    case R.Legacy{R.Bits64{hi,lo}}: {==}
    case R.Xoroshiro{R.Bits64{lh,ll},R.Bits64{hh,hl}}: {==}

def Laws.exhausted_blended_constructor_preserves_source(source,config):
  match source config:
    case R.Legacy{R.Bits64{hi,lo}} B.Config{xs,ys,xf,yf,smear}: {==}
    case R.Xoroshiro{R.Bits64{lh,ll},R.Bits64{hh,hl}} B.Config{xs,ys,xf,yf,smear}: {==}
