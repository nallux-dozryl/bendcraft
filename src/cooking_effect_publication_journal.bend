import Base
import ./core.bend as C
import ./section.bend as Section
import ./cooking_world_bindings.bend as B

# Captured at the actual Dirty producer, before another owner can replace it.
# Cached state is retained even when a same-incarnation LIT change follows.
type Source is Data:
  Source{position:C.Position,binding:B.Binding,incarnation:Nat}
type Chunk is Data:
  Chunk{dimension:String,x:U32,z:U32}
type DirtyChunk is Data:
  DirtyChunk{chunk:Chunk,sequence:Nat}
type Receipt is Data:
  Receipt{position:C.Position,source:Source,chunk:Chunk,sequence:Nat}
type View is Data:
  View{sequence:Nat,unsaved:List<&2,DirtyChunk>,last:Maybe<&2,Receipt>}
type State is Type:
  State{view:View}
type Snapshot is Data:
  Snapshot{sequence:Nat,unsaved:List<&2,DirtyChunk>}
# The actual atomic full-cooking-save writer may issue this only after commit.
# A parse result, save request or successful reply encoding is not this token.
type SaveCommit is Type:
  FullCookingSaveCommitted{snapshot:Snapshot}

def new() -> State: State{View{0n,[],None{}}}
def inspect(owner:State) -> State & View:
  State{+view} = owner
  (State{view},view)
def install(view:View) -> State: State{view}
def chunk(position:C.Position) -> Chunk:
  C.Position{dimension,x,y,z} = position
  Chunk{dimension,Section.Coord.section(x),Section.Coord.section(z)}
def chunk_equal(a:Chunk,b:Chunk) -> Bool:
  Chunk{d,x,z} = a
  Chunk{other,u,v} = b
  String.eq(d,other) && U32.is_eq(x,u) && U32.is_eq(z,v)
def same_owner(a:Source,b:Source) -> Bool:
  Source{position,left,i} = a
  Source{other,right,j} = b
  B.equal_position(position,other) && B.same_block(left,right) && Nat.is_eq(i,j)
def remove_cons(+head:DirtyChunk,+target:Chunk,+tail:List<&2,DirtyChunk>) -> List<&2,DirtyChunk>:
  DirtyChunk{candidate,sequence} = head
  Bool.pick(List<&2,DirtyChunk>,chunk_equal(candidate,target),tail,head <> tail)
def remove(values:List<&2,DirtyChunk>,+target:Chunk) -> List<&2,DirtyChunk>:
  match values:
    case Nil{}: []
    case head <> rest: remove_cons(head,target,remove(rest,target))
def marked(+position:C.Position,+source:Source,owner:State) -> State & Receipt:
  State{View{sequence,unsaved,last}} = owner
  +next = {1n+sequence : Nat}
  +target = chunk(position)
  +receipt = {Receipt{position,source,target,next} : Receipt}
  (State{View{next,DirtyChunk{target,next} <> remove(unsaved,target),Some{receipt}}},receipt)
def snapshot(owner:State) -> State & Snapshot:
  State{View{+sequence,+unsaved,last}} = owner
  (State{View{sequence,unsaved,last}},Snapshot{sequence,unsaved})
def included(values:List<&2,DirtyChunk>,+target:Chunk,+revision:Nat) -> Bool:
  match values:
    case Nil{}: False{}
    case DirtyChunk{candidate,saved} <> rest:
      (chunk_equal(candidate,target) && Nat.is_le(revision,saved)) || included(rest,target,revision)
def retained_cons(+head:DirtyChunk,+saved:List<&2,DirtyChunk>,+tail:List<&2,DirtyChunk>) -> List<&2,DirtyChunk>:
  DirtyChunk{target,revision} = head
  Bool.pick(List<&2,DirtyChunk>,included(saved,target,revision),tail,head <> tail)
def retained(values:List<&2,DirtyChunk>,+saved:List<&2,DirtyChunk>) -> List<&2,DirtyChunk>:
  match values:
    case Nil{}: []
    case head <> rest: retained_cons(head,saved,retained(rest,saved))
def bounded(values:List<&2,DirtyChunk>,+sequence:Nat) -> Bool:
  match values:
    case Nil{}: True{}
    case DirtyChunk{target,revision} <> rest:
      Nat.is_le(revision,sequence) && bounded(rest,sequence)
def committed_valid(owner:State,snapshot:Snapshot,valid:Bool) -> State:
  match owner snapshot valid:
    case owner _ False{}: owner
    case State{View{sequence,unsaved,last}} Snapshot{saved,chunks} True{}:
      State{View{sequence,retained(unsaved,chunks),last}}
def committed(owner:State,+snapshot:Snapshot) -> State:
  State{View{+sequence,unsaved,last}} = owner
  Snapshot{+saved,+chunks} = snapshot
  committed_valid(State{View{sequence,unsaved,last}},snapshot,
    Nat.is_le(saved,sequence) && bounded(chunks,saved))
def save_completed(owner:State,result:Result<&2,&1,String,SaveCommit>) -> State:
  match result:
    case Fail{message}: owner
    case Done{FullCookingSaveCommitted{snapshot}}: committed(owner,snapshot)
