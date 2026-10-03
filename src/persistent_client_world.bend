import Base
import ./persistence.bend as P
import ./client_world.bend as W
import ./game.bend as G
import ./core.bend as C
import ./section_map.bend as SM
import ./schedule.bend as Q
import ./movement.bend as M
import ./client_render.bend as R
import ./live.bend as L
import ./json.bend as J
import ./world_lock.bend as WL
import ./registry.bend as B

# The lease/save wrapper owns the only Engine. A view is immutable Data;
# local queries temporarily transfer that Engine and return it to the wrapper.
type State is Type:
  State{simulation:P.State,view:W.View}

def view_result(-A:Type,+identity:String,+path:String,+highwater:U32,+limits:P.Limits,lease:WL.Lease,value:A,result:G.Engine & W.View) -> State & A:
  (engine,view) = result
  (State{P.State{engine,identity,path,highwater,limits,lease},view},value)

def query_result(-A:Type,+identity:String,+path:String,+highwater:U32,+limits:P.Limits,lease:WL.Lease,result:W.State & A) -> State & A:
  (state,value) = result
  view_result(A,identity,path,highwater,limits,lease,value,W.take(state))

def query(-A:Type,state:State,operation:W.State -> W.State & A) -> State & A:
  State{P.State{engine,identity,path,highwater,limits,lease},view} = state
  query_result(A,identity,path,highwater,limits,lease,operation(W.attach(engine,view)))

def snapshot(state:State,width:U32,height:U32) -> State & Result<&2,&2,String,R.Snapshot>:
  query(Result<&2,&2,String,R.Snapshot>,state,w => W.relative_snapshot(w,width,height))

def move(state:State,delta:M.Vec3,maximum:F32) -> State & Result<&2,&2,String,M.Transition>:
  query(Result<&2,&2,String,M.Transition>,state,w => W.move(w,delta,maximum))

def look(state:State,yaw:F32,pitch:F32) -> State & Result<&2,&2,String,Unit>:
  query(Result<&2,&2,String,Unit>,state,w => W.look(w,yaw,pitch))

def body(state:State) -> State & M.Body:
  query(M.Body,state,w => W.body(w))

def invalidate_cache(state:State) -> State:
  State{simulation,view} = state
  W.View{body,yaw,pitch,palette,region,cache} = view
  State{simulation,W.View{body,yaw,pitch,palette,region,None{}}}

def step(state:State) -> State:
  State{simulation,view} = state
  State{P.realtime_step(simulation),view}

def dispatched(view:W.View,result:P.State & L.Session & J.Value) -> State & L.Session & J.Value:
  (simulation,session,value) = result
  (State{simulation,view},session,value)

def dispatch(state:State,session:L.Session,token:String,request:J.Value) -> IO(State & L.Session & J.Value):
  State{simulation,view} = state
  do IO<State & L.Session & J.Value>:
    result : P.State & L.Session & J.Value <- P.dispatch(simulation,session,token,request)
    return dispatched(view,result)

def pristine_sections(sections:SM.Sections) -> SM.Sections & Bool:
  match sections:
    case SM.EmptySections{}: (SM.EmptySections{},True{})
    case other: (other,False{})

def pristine_result(registry:B.Registry,+tick:Nat,+time:Nat,+paused:Bool,+daylight:Bool,+revision:Nat,+count:U32,+pending:List<&2,Q.Pending<C.Mutation>>,+events:List<&2,C.CoreEvent>,result:SM.Sections & Bool) -> G.Engine & Bool:
  (sections,empty) = result
  (G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},empty && Nat.is_eq(tick,0n) && Nat.is_eq(revision,0n) && List.is_empty(&2,Q.Pending<C.Mutation>,pending) && List.is_empty(&2,C.CoreEvent,events))

def pristine(engine:G.Engine) -> G.Engine & Bool:
  G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry} = engine
  pristine_result(registry,tick,time,paused,daylight,revision,count,pending,events,pristine_sections(sections))

def new_selected(initialize:Bool,engine:G.Engine) -> W.State & Result<&2,&2,String,Unit>:
  match initialize:
    case True{}: W.fixture(engine)
    case False{}: W.new(engine)

def new_pristine(+initialize:Bool,+identity:String,+path:String,+highwater:U32,+limits:P.Limits,lease:WL.Lease,result:G.Engine & Bool) -> State & Result<&2,&2,String,Unit>:
  (engine,pristine) = result
  query_result(Result<&2,&2,String,Unit>,identity,path,highwater,limits,lease,new_selected(initialize && pristine,engine))

def new(simulation:P.State,initialize_fixture:Bool) -> State & Result<&2,&2,String,Unit>:
  P.State{engine,identity,path,highwater,limits,lease} = simulation
  new_pristine(initialize_fixture,identity,path,highwater,limits,lease,pristine(engine))
