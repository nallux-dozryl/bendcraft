import Base
import ../src/core.bend as C
import ../src/schedule.bend as Q
import ../src/section.bend as S
import ../src/section_map.bend as M
import ../src/section_map_update.bend as U

# Native observations preserve and compare the actual Array and trie topology,
# every payload word, collision ordering, and every complete World field.
type Cells is Data:
  Word{value:U32}
  Node{left:Cells,right:Cells}
type EntryImage is Data:
  EntryImage{key:String,cells:Cells}
type Tree is Data:
  Void{}
  Fork{left:Tree,right:Tree}
  Entries{entries:List<&2,EntryImage>}
type WorldImage is Data:
  WorldImage{tick:Nat,time:Nat,paused:Bool,daylight:Bool,revision:Nat,count:U32,
    tree:Tree,pending:List<&2,Q.Pending<C.Mutation>>,events:List<&2,C.CoreEvent>}

def paired(-A:Type,-B:Type,-T:Type,value:A & B,finish:A -> B -> T) -> T:
  match value:
    case (a,b): finish(a,b)

def array_image(array:Array<U32>) -> Array<U32> & Cells:
  match array:
    case ALeaf{+value}: (ALeaf{value},Word{value})
    case ANode{left,right}:
      paired(Array<U32>,Cells,Array<U32> & Cells,array_image(left),left => a =>
        paired(Array<U32>,Cells,Array<U32> & Cells,array_image(right),right => b =>
          (ANode{left,right},Node{a,b})))

def section_image(section:S.Section) -> S.Section & Cells:
  S.Section{array} = section
  paired(Array<U32>,Cells,S.Section & Cells,array_image(array),array => cells => (S.Section{array},cells))

def entries_image(entries:List<&1,M.Entry>) -> List<&1,M.Entry> & List<&2,EntryImage>:
  match entries:
    case Nil{}: ([],[])
    case M.Entry{+key,section} <> tail:
      paired(S.Section,Cells,List<&1,M.Entry> & List<&2,EntryImage>,section_image(section),section => cells =>
        paired(List<&1,M.Entry>,List<&2,EntryImage>,List<&1,M.Entry> & List<&2,EntryImage>,entries_image(tail),tail => remaining =>
          (M.Entry{key,section} <> tail,EntryImage{key,cells} <> remaining)))

def tree_image(sections:M.Sections) -> M.Sections & Tree:
  match sections:
    case M.EmptySections{}: (M.EmptySections{},Void{})
    case M.Bucket{entries}:
      paired(List<&1,M.Entry>,List<&2,EntryImage>,M.Sections & Tree,entries_image(entries),entries => image => (M.Bucket{entries},Entries{image}))
    case M.Branch{left,right}:
      paired(M.Sections,Tree,M.Sections & Tree,tree_image(left),left => a =>
        paired(M.Sections,Tree,M.Sections & Tree,tree_image(right),right => b => (M.Branch{left,right},Fork{a,b})))

def world_image(world:C.World) -> C.World & WorldImage:
  C.World{+tick,+time,+paused,+daylight,+revision,+count,sections,+pending,+events} = world
  paired(M.Sections,Tree,C.World & WorldImage,tree_image(sections),sections => tree =>
    (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},WorldImage{tick,time,paused,daylight,revision,count,tree,pending,events}))

def cells_equal(a:Cells,b:Cells) -> Bool:
  match a b:
    case Word{x} Word{y}: U32.is_eq(x,y)
    case Node{left,right} Node{other_left,other_right}: cells_equal(left,other_left) && cells_equal(right,other_right)
    case _ _: False{}

def entries_equal(a:List<&2,EntryImage>,b:List<&2,EntryImage>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case EntryImage{key,cells} <> tail EntryImage{other_key,other_cells} <> remaining:
      String.eq(key,other_key) && cells_equal(cells,other_cells) && entries_equal(tail,remaining)
    case _ _: False{}

def trees_equal(a:Tree,b:Tree) -> Bool:
  match a b:
    case Void{} Void{}: True{}
    case Entries{entries} Entries{other}: entries_equal(entries,other)
    case Fork{left,right} Fork{other_left,other_right}: trees_equal(left,other_left) && trees_equal(right,other_right)
    case _ _: False{}

def bool_equal(a:Bool,b:Bool) -> Bool:
  Bool.not(Bool.xor(a,b))

def position_equal(a:C.Position,b:C.Position) -> Bool:
  match a b:
    case C.Position{d,x,y,z} C.Position{dd,xx,yy,zz}: String.eq(d,dd) && U32.is_eq(x,xx) && U32.is_eq(y,yy) && U32.is_eq(z,zz)

def stamp_equal(a:Q.Stamp,b:Q.Stamp) -> Bool:
  match a b:
    case Q.Stamp{tick,peer,seq} Q.Stamp{other_tick,other_peer,other_seq}: Nat.is_eq(tick,other_tick) && U32.is_eq(peer,other_peer) && Nat.is_eq(seq,other_seq)

def error_equal(a:C.Error,b:C.Error) -> Bool:
  match a b:
    case C.PermissionDenied{} C.PermissionDenied{}: True{}
    case C.UnknownDimension{d} C.UnknownDimension{other}: String.eq(d,other)
    case C.InvalidState{s} C.InvalidState{other}: U32.is_eq(s,other)
    case C.MissingSection{k} C.MissingSection{other}: String.eq(k,other)
    case C.SectionExists{k} C.SectionExists{other}: String.eq(k,other)
    case C.InvalidCoordinate{} C.InvalidCoordinate{}: True{}
    case C.PastTick{} C.PastTick{}: True{}
    case C.TooManyPending{} C.TooManyPending{}: True{}
    case _ _: False{}

def mutation_equal(a:C.Mutation,b:C.Mutation) -> Bool:
  match a b:
    case C.SectionCreate{p,fill} C.SectionCreate{other,other_fill}: position_equal(p,other) && U32.is_eq(fill,other_fill)
    case C.BlockSet{p,state} C.BlockSet{other,other_state}: position_equal(p,other) && U32.is_eq(state,other_state)
    case C.TimeSet{time} C.TimeSet{other}: Nat.is_eq(time,other)
    case C.DaylightSet{enabled} C.DaylightSet{other}: bool_equal(enabled,other)
    case _ _: False{}

def pending_equal(a:List<&2,Q.Pending<C.Mutation>>,b:List<&2,Q.Pending<C.Mutation>>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Q.Pending{stamp,mutation} <> tail Q.Pending{other_stamp,other_mutation} <> remaining:
      stamp_equal(stamp,other_stamp) && mutation_equal(mutation,other_mutation) && pending_equal(tail,remaining)
    case _ _: False{}

def events_equal(a:List<&2,C.CoreEvent>,b:List<&2,C.CoreEvent>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case C.Applied{stamp,revision} <> tail C.Applied{other_stamp,other_revision} <> remaining:
      stamp_equal(stamp,other_stamp) && Nat.is_eq(revision,other_revision) && events_equal(tail,remaining)
    case C.Rejected{stamp,error} <> tail C.Rejected{other_stamp,other_error} <> remaining:
      stamp_equal(stamp,other_stamp) && error_equal(error,other_error) && events_equal(tail,remaining)
    case _ _: False{}

def worlds_equal(a:WorldImage,b:WorldImage) -> Bool:
  match a b:
    case WorldImage{tick,time,paused,daylight,rev,count,tree,pending,events} WorldImage{t,tm,p,d,r,c,tr,ps,es}:
      Nat.is_eq(tick,t) && Nat.is_eq(time,tm) && bool_equal(paused,p) && bool_equal(daylight,d) && Nat.is_eq(rev,r) && U32.is_eq(count,c) && trees_equal(tree,tr) && pending_equal(pending,ps) && events_equal(events,es)

def require(ok:Bool,message:String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)

def checked_world(before:WorldImage,label:String,observed:C.World & WorldImage) -> IO(C.World):
  (world,after) = observed
  do IO<C.World>:
    require(worlds_equal(before,after),label)
    return world

def refused(expected:C.Error,before:WorldImage,label:String,result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(C.World):
  (world,status) = result
  match status:
    case Done{unit}: IO.die(C.World,1,"Core refusal unexpectedly succeeded")
    case Fail{cause}:
      do IO<C.World>:
        require(error_equal(cause,expected),"Core refusal error differs")
        checked_world(before,label,world_image(world))

def refusal(world:C.World,+mutation:C.Mutation,error:C.Error,label:String) -> IO(C.World):
  paired(C.World,WorldImage,IO(C.World),world_image(world),world => before => refused(error,before,label,C.apply(world,mutation)))

def read_checked(expected:U32,before:WorldImage,result:C.World & Result<&2,&2,C.Error,U32>) -> IO(C.World):
  (world,status) = result
  match status:
    case Fail{cause}: IO.die(C.World,1,"collision read unexpectedly failed")
    case Done{value}:
      do IO<C.World>:
        require(U32.is_eq(expected,value),"collision block payload differs")
        checked_world(before,"collision query changed raw full world",world_image(world))

def query(world:C.World,position:C.Position,expected:U32) -> IO(C.World):
  paired(C.World,WorldImage,IO(C.World),world_image(world),world => before => read_checked(expected,before,C.read_block(world,position)))

def applied(result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(C.World):
  (world,status) = result
  match status:
    case Fail{cause}: IO.die(C.World,1,"valid in-place write unexpectedly failed")
    case Done{unit}: IO.pure(C.World,world)

def fixture(sections:M.Sections,+position:C.Position) -> C.World:
  C.World{73n,12001n,False{},False{},19n,32,sections,
    [Q.Pending{Q.Stamp{81n,7,12n},C.BlockSet{position,3}},Q.Pending{Q.Stamp{90n,9,14n},C.TimeSet{600n}}],
    [C.Rejected{Q.Stamp{70n,5,10n},C.PermissionDenied{}},C.Applied{Q.Stamp{72n,6,11n},19n}]}

def odd_path(route:List<&2,Bool>,leaf:M.Sections) -> M.Sections:
  match route:
    case Nil{}: leaf
    case False{} <> rest: M.Branch{odd_path(rest,leaf),M.Bucket{[]}}
    case True{} <> rest: M.Branch{M.Branch{M.EmptySections{},M.Bucket{[]}},odd_path(rest,leaf)}

def invalid_write_after(before:Tree,result:M.Sections & Result<&2,&2,U.Error,Unit>) -> IO(M.Sections):
  (sections,status) = result
  match status:
    case Fail{U.SectionRejected{S.BadLocal{16,0,0}}}:
      paired(M.Sections,Tree,IO(M.Sections),tree_image(sections),sections => after =>
        do IO<M.Sections>:
          require(trees_equal(before,after),"invalid local write changed raw map or array")
          return sections)
    case _: IO.die(M.Sections,1,"invalid local write error differs")

def invalid_write(sections:M.Sections,+key:String) -> IO(M.Sections):
  paired(M.Sections,Tree,IO(M.Sections),tree_image(sections),sections => before => invalid_write_after(before,U.write(sections,key,16,0,0,29)))

def main() -> IO(Unit):
  +first = {C.Position{"minecraft:overworld",192145824,578455600,1247992560} : C.Position}
  +second = {C.Position{"minecraft:overworld",343086944,1893213456,2117633648} : C.Position}
  +absent = {C.Position{"minecraft:overworld",0,0,0} : C.Position}
  +a = C.section_key(first)
  +b = C.section_key(second)
  +missing = C.section_key(absent)
  do IO<Unit>:
    require(String.eq(a,"minecraft:overworld/12009114/36153475/77999535") && String.eq(b,"minecraft:overworld/21442934/118325841/132352103"),"canonical collision positions differ")
    require(U32.is_eq(M.hash(a),4257771677) && U32.is_eq(M.hash(a),M.hash(b)),"actual canonical FNV collision differs")
    map0 : M.Sections = M.set(M.set(M.EmptySections{},a,S.Section.new(2)),b,S.Section.new(7))
    world0 : C.World = fixture(map0,first)
    world1 : C.World <- refusal(world0,C.SectionCreate{first,31},C.SectionExists{a},"duplicate tail create changed raw world")
    world2 : C.World <- query(world1,second,7)
    world3 : C.World <- query(world2,first,2)
    world4 : C.World <- refusal(world3,C.SectionCreate{second,30},C.SectionExists{b},"duplicate head create changed raw world")
    world5 : C.World <- query(world4,first,2)
    world6 : C.World <- query(world5,second,7)
    world7 : C.World <- refusal(world6,C.SectionCreate{first,28},C.SectionExists{a},"repeated duplicate changed raw world")
    world8 : C.World <- refusal(world7,C.BlockSet{absent,27},C.MissingSection{missing},"missing write changed occupied trie")
    world9 : C.World <- applied(C.apply(world8,C.BlockSet{first,11}))
    world10 : C.World <- query(world9,first,11)
    world11 : C.World <- query(world10,second,7)
    world12 : C.World <- refusal(world11,C.SectionCreate{first,26},C.SectionExists{a},"duplicate after success changed raw world")
    empty_leaf : C.World = fixture(odd_path(U.path(32n,M.hash(missing)),M.Bucket{[]}),absent)
    empty_after : C.World <- refusal(empty_leaf,C.BlockSet{absent,1},C.MissingSection{missing},"missing write normalized empty bucket or side branch")
    malformed0 : C.World = fixture(M.Bucket{[M.Entry{missing,S.Section{ANode{ALeaf{3},ALeaf{5}}}}]},absent)
    malformed1 : C.World <- refusal(malformed0,C.BlockSet{absent,1},C.MissingSection{missing},"malformed-depth write changed arbitrary array/trie")
    malformed2 : C.World <- refusal(malformed1,C.SectionCreate{absent,1},C.InvalidCoordinate{},"malformed-depth create discarded owned bucket")
    map1 : M.Sections = M.set(M.set(M.EmptySections{},a,S.Section.new(2)),b,S.Section.new(7))
    map2 : M.Sections <- invalid_write(map1,a)
    invalid_world0 : C.World = fixture(map2,first)
    invalid_world1 : C.World <- query(invalid_world0,first,2)
    invalid_world2 : C.World <- query(invalid_world1,second,7)
    IO.print("PASS Core refusal: actual canonical collision, duplicate/missing C.apply, full World/trie/bucket/array identity, invalid local, malformed depth, queried success isolation")
