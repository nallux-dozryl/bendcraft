import Base
import ./entity_chunk_loading_model.bend as L
import ./entity_chunk_loading_math.bend as A
import ./entity_chunk_loading_tickets.bend as T
import ./entity_section_membership_model.bend as M

def visibility(value:L.FullStatus) -> M.Visibility:
  match value:
    case L.Inaccessible{}: M.Hidden{}
    case L.EntityTicking{}: M.Ticking{}
    case _: M.Tracked{}
def chunks(values:List<&2,L.Chunk>,+dimension:String) -> List<&2,M.Chunk>:
  match values:
    case Nil{}: []
    case L.Chunk{L.ChunkKey{x,z},level,status,loaded,promotion,entity_phase,holder} <> rest:
      M.Chunk{dimension,x,z,loaded,visibility(status)} <> chunks(rest,dimension)
def observed_guard(values:List<&2,L.Chunk>,dimension:String,valid:Bool) -> Result<&2,&2,String,List<&2,M.Chunk>>:
  match valid:
    case False{}: Fail{"current loader facts belong to another actual world/epoch"}
    case True{}: Done{chunks(values,dimension)}
def observed(+view:L.View,scope:L.Scope) -> Result<&2,&2,String,List<&2,M.Chunk>>:
  L.View{context,active,inactive,values,next,journal}=view
  L.Context{+actual,types,maximum}=context
  L.Scope{world,dimension,epoch}=actual
  observed_guard(values,dimension,A.scope_equal(actual,scope))
# The recovery consumer passes Done{facts} as Some{facts} to its actual
# prepare(image,entities,current). Fail is missing authority, not a substitute
# empty/visible/ticking snapshot. No Core read, camera or saved flags are used.
def current(state:L.State,scope:L.Scope) -> L.State & Result<&2,&2,String,List<&2,M.Chunk>>:
  match state:
    case L.Unavailable{actual,+reason}:
      (L.Unavailable{actual,reason},Fail{"actual chunk ticket/status/load-completion provider is unavailable: " ++ reason})
    case L.State{+view}: (L.State{view},observed(view,scope))
