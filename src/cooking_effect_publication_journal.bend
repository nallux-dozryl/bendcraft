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
def maximum_sequence() -> Nat:
  Nat.add(Nat.mul(65536n,4294967295n),65535n)
def chunk_valid(value:Chunk) -> Bool:
  Chunk{dimension,x,z} = value
  C.dimension_known(dimension) && Section.Coord.section_valid(x) && Section.Coord.section_valid(z)
def chunk_key(value:Chunk) -> String:
  Chunk{dimension,x,z} = value
  dimension ++ "/" ++ U32.show(x) ++ "/" ++ U32.show(z)
def unique_checked(+key:String,result:Set() & Bool,next:Set() -> Bool) -> Bool:
  match result:
    case (seen,True{}): False{}
    case (seen,False{}): next(Set.add(seen,key))
def chunks_valid(values:List<&2,DirtyChunk>,+sequence:Nat,seen:Set()) -> Bool:
  match values:
    case Nil{}: True{}
    case DirtyChunk{+target,+revision} <> +rest:
      chunk_valid(target) && Nat.is_gt(revision,0n) && Nat.is_le(revision,sequence) &&
        unique_checked(chunk_key(target),Set.has(seen,chunk_key(target)),
          seen => chunks_valid(rest,sequence,seen))
def source_valid(source:Source) -> Bool:
  Source{position,B.Binding{+state,block,family,+lit,+dark,+bright},incarnation} = source
  C.dimension_known(C.dimension(position)) && Nat.is_le(incarnation,maximum_sequence()) &&
    U32.is_eq(state,Bool.pick(U32,lit,bright,dark))
def last_valid(sequence:Nat,value:Maybe<&2,Receipt>) -> Bool:
  match sequence value:
    case 0n None{}: True{}
    case 1n+previous Some{Receipt{+position,+source,target,revision}}:
      Source{captured,binding,incarnation} = source
      Nat.is_eq(1n+previous,revision) && B.equal_position(position,captured) &&
        chunk_equal(chunk(position),target) && source_valid(source)
    case _ _: False{}
def view_valid(view:View) -> Bool:
  View{+sequence,unsaved,last} = view
  Nat.is_le(sequence,maximum_sequence()) && chunks_valid(unsaved,sequence,Set.new()) && last_valid(sequence,last)
def restore_checked(view:View,valid:Bool) -> Result<&2,&1,String,State>:
  match valid:
    case False{}: Fail{"cooking-publication:invalid-recovered-journal"}
    case True{}: Done{State{view}}
def restore(+view:View) -> Result<&2,&1,String,State>:
  restore_checked(view,view_valid(view))
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
def saved_view_valid(view:View,snapshot:Snapshot,valid:Bool) -> View:
  match view snapshot valid:
    case view _ False{}: view
    case View{sequence,unsaved,last} Snapshot{saved,chunks} True{}:
      View{sequence,retained(unsaved,chunks),last}
# Immutable save-image projection; the caller's sole live State remains owned
# until the real full save issues its affine successful commit receipt.
def saved_view(+view:View,+snapshot:Snapshot) -> View:
  View{+sequence,unsaved,last} = view
  Snapshot{+saved,+chunks} = snapshot
  saved_view_valid(view,snapshot,Nat.is_le(saved,sequence) && chunks_valid(chunks,saved,Set.new()))
def committed_valid(owner:State,snapshot:Snapshot,valid:Bool) -> State:
  State{view} = owner
  State{saved_view_valid(view,snapshot,valid)}
def committed(owner:State,+snapshot:Snapshot) -> State:
  State{View{+sequence,unsaved,last}} = owner
  Snapshot{+saved,+chunks} = snapshot
  committed_valid(State{View{sequence,unsaved,last}},snapshot,
    Nat.is_le(saved,sequence) && chunks_valid(chunks,saved,Set.new()))
def save_completed(owner:State,result:Result<&2,&1,String,SaveCommit>) -> State:
  match result:
    case Fail{message}: owner
    case Done{FullCookingSaveCommitted{snapshot}}: committed(owner,snapshot)
