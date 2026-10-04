import Base
import ./block_light.bend as B

# Effective face IDs already apply the pinned engine's canOcclude &&
# useShapeForLightOcclusion gate. A row is a packed exact face-union table.
type Faces is Data:
  Faces{down:U32,up:U32,north:U32,south:U32,west:U32,east:U32}
type Entry is Data:
  Entry{emission:U32,dampening:U32,faces:Faces}
type Catalog is Data:
  Catalog{identity:String,state_count:U32,shape_count:U32,
    states:Map<&2,Maybe<&2,Entry>>,rows:Map<&2,Maybe<&2,List<&2,U32>>>}
type Error is Data:
  UnknownState{state:U32}
  InvalidFace{face:U32}
  MissingRow{face:U32}
  MissingWord{face:U32,word:U32}

def face(faces:Faces,direction:B.Direction) -> U32:
  Faces{down,up,north,south,west,east} = faces
  match direction:
    case B.Down{}: down
    case B.Up{}: up
    case B.North{}: north
    case B.South{}: south
    case B.West{}: west
    case B.East{}: east

def state_read(+state:U32,result:Map<&2,Maybe<&2,Entry>> & Maybe<&2,Entry>) ->
    Maybe<&2,B.Descriptor>:
  (entries,found) = result
  match found:
    case None{}: None{}
    case Some{Entry{emission,dampening,faces}}: Some{B.Descriptor{state,emission,dampening}}
def properties_valid(catalog:Catalog,+state:U32,valid:Bool) -> Maybe<&2,B.Descriptor>:
  Catalog{identity,count,shapes,entries,rows} = catalog
  match valid:
    case False{}: None{}
    case True{}: state_read(state,Map.get(Maybe<&2,Entry>,None{},entries,U32.show(state)))
def properties_id(catalog:Catalog,+state:U32) -> Maybe<&2,B.Descriptor>:
  Catalog{identity,+count,shapes,entries,rows} = catalog
  properties_valid(Catalog{identity,count,shapes,entries,rows},state,U32.is_lt(state,count))

# None is an absent registry descriptor; it does not manufacture a dark cell.
# World residency and section enablement remain owned by BlockLightWorld.
def properties(catalog:Catalog,state:U32) -> Maybe<&2,B.Descriptor>:
  properties_id(catalog,state)

def face_read(state:U32,direction:B.Direction,
    result:Map<&2,Maybe<&2,Entry>> & Maybe<&2,Entry>) -> Result<&2,&2,Error,U32>:
  (entries,found) = result
  match found:
    case None{}: Fail{UnknownState{state}}
    case Some{Entry{emission,dampening,faces}}: Done{face(faces,direction)}
def state_face_valid(catalog:Catalog,+state:U32,direction:B.Direction,valid:Bool) -> Result<&2,&2,Error,U32>:
  Catalog{identity,count,shapes,entries,rows} = catalog
  match valid:
    case False{}: Fail{UnknownState{state}}
    case True{}: face_read(state,direction,Map.get(Maybe<&2,Entry>,None{},entries,U32.show(state)))
def state_face(catalog:Catalog,+state:U32,direction:B.Direction) -> Result<&2,&2,Error,U32>:
  Catalog{identity,+count,shapes,entries,rows} = catalog
  state_face_valid(Catalog{identity,count,shapes,entries,rows},state,direction,U32.is_lt(state,count))

def word_at(words:List<&2,U32>,index:Nat) -> Maybe<&2,U32>:
  match words index:
    case Nil{} _: None{}
    case word <> tail 0n: Some{word}
    case word <> tail 1n+p: word_at(tail,p)
def bit(word:U32,index:U32) -> Bool:
  U32.is_ne(U32.and(word,U32.shln(1,U32.to_nat(U32.mod(index,32)))),0)
def row_word(source:U32,+target:U32,result:Maybe<&2,U32>) -> Result<&2,&2,Error,Bool>:
  match result:
    case None{}: Fail{MissingWord{source,U32.div(target,32)}}
    case Some{word}: Done{bit(word,target)}
def row_read(+source:U32,+target:U32,
    result:Map<&2,Maybe<&2,List<&2,U32>>> & Maybe<&2,List<&2,U32>>) -> Result<&2,&2,Error,Bool>:
  (rows,found) = result
  match found:
    case None{}: Fail{MissingRow{source}}
    case Some{words}: row_word(source,target,word_at(words,U32.to_nat(U32.div(target,32))))
def face_pair_valid(catalog:Catalog,+source:U32,+target:U32,valid:Bool) -> Result<&2,&2,Error,Bool>:
  Catalog{identity,count,shapes,entries,rows} = catalog
  match valid:
    case False{}: Fail{InvalidFace{U32.max(source,target)}}
    case True{}:
      row_read(source,target,Map.get(Maybe<&2,List<&2,U32>>,None{},rows,U32.show(source)))
def face_pair(catalog:Catalog,+source:U32,+target:U32) -> Result<&2,&2,Error,Bool>:
  Catalog{identity,count,+shapes,entries,rows} = catalog
  face_pair_valid(Catalog{identity,count,shapes,entries,rows},source,target,
    U32.is_lt(source,shapes) && U32.is_lt(target,shapes))
def occlusion_faces(catalog:Catalog,source:Result<&2,&2,Error,U32>,
    target:Result<&2,&2,Error,U32>) -> Result<&2,&2,Error,Bool>:
  match source target:
    case Fail{error} _: Fail{error}
    case Done{from} Fail{error}: Fail{error}
    case Done{from} Done{to}: face_pair(catalog,from,to)

# Direction is SOURCE->TARGET. The target contributes its opposite face.
def occlusion(+catalog:Catalog,source:U32,target:U32,+direction:B.Direction) ->
    Result<&2,&2,Error,Bool>:
  occlusion_faces(catalog,state_face(catalog,source,direction),
    state_face(catalog,target,B.opposite(direction)))
def conservative(result:Result<&2,&2,Error,Bool>) -> Bool:
  match result:
    case Fail{error}: True{}
    case Done{closed}: closed
def occludes(catalog:Catalog,source:B.Descriptor,target:B.Descriptor,direction:B.Direction) -> Bool:
  B.Descriptor{from,se,sd} = source
  B.Descriptor{to,te,td} = target
  conservative(occlusion(catalog,from,to,direction))
