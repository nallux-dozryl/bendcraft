import Base
import ./client_render.bend as R
import ./server.bend as S
import ./png.bend as P
import ./movement.bend as M
import ./f64.bend as F

# Closed typed callbacks select the sole actor State. No world is copied into
# the window, and render callbacks never advance simulation time.
type Driver<-State:Type> is Type:
  Driver{snapshot:State -> U32 -> U32 -> State & Result<&2,&2,String,R.Snapshot>,
    move:State -> M.Vec3 -> F32 -> State & Result<&2,&2,String,M.Transition>,
    look:State -> F32 -> F32 -> State & Result<&2,&2,String,Unit>}

def snapshot(-State:Type,driver:Driver<State>,state:State,width:U32,height:U32) -> State & Result<&2,&2,String,R.Snapshot>:
  Driver{snapshot,move,look} = driver
  snapshot(state,width,height)

def move(-State:Type,driver:Driver<State>,state:State,delta:M.Vec3,step:F32) -> State & Result<&2,&2,String,M.Transition>:
  Driver{snapshot,move,look} = driver
  move(state,delta,step)

def look(-State:Type,driver:Driver<State>,state:State,yaw:F32,pitch:F32) -> State & Result<&2,&2,String,Unit>:
  Driver{snapshot,move,look} = driver
  look(state,yaw,pitch)

def snapshot_ready(result:Result<&2,&2,String,R.Snapshot>) -> IO(R.Snapshot):
  match result:
    case Fail{message}: IO.die(R.Snapshot,1,"snapshot: " ++ message)
    case Done{snapshot}: IO.pure(R.Snapshot,snapshot)

def result_unit(result:Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("control rejected: " ++ message)
    case Done{unit}: IO.pure(Unit,Unit{})

def result_motion(result:Result<&2,&2,String,M.Transition>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("motion rejected: " ++ message)
    case Done{transition}: IO.pure(Unit,Unit{})

def move_delta(+yaw:F32,+forward:F32,+right:F32,vertical:F32) -> M.Vec3:
  M.Vec3{F.from_f32(F32.mul(F32.add(F32.mul(F32.cos(yaw),right),F32.neg(F32.mul(F32.sin(yaw),forward))),0.25)),F.from_f32(F32.mul(vertical,0.25)),F.from_f32(F32.mul(F32.add(F32.mul(F32.sin(yaw),right),F32.mul(F32.cos(yaw),forward)),0.25))}

def move_control(~State:Type,~driver:Driver<State>,handle:S.Handle<State>,yaw:F32,forward:F32,right:F32,vertical:F32) -> IO(Unit):
  delta = move_delta(yaw,forward,right,vertical)
  do IO<Unit>:
    result : Result<&2,&2,String,M.Transition> <- S.local_call(State,Result<&2,&2,String,M.Transition>,handle,state => move(State,driver,state,delta,0.6))
    result_motion(result)

def key_control(~State:Type,~driver:Driver<State>,code:U32,handle:S.Handle<State>,yaw:F32) -> IO(Bool):
  match code:
    case 27: IO.pure(Bool,False{})
    case 119:
      do IO<Bool>:
        move_control(~State,~driver,handle,yaw,1.0,0.0,0.0)
        return True{}
    case 115:
      do IO<Bool>:
        move_control(~State,~driver,handle,yaw,F32.neg(1.0),0.0,0.0)
        return True{}
    case 97:
      do IO<Bool>:
        move_control(~State,~driver,handle,yaw,0.0,F32.neg(1.0),0.0)
        return True{}
    case 100:
      do IO<Bool>:
        move_control(~State,~driver,handle,yaw,0.0,1.0,0.0)
        return True{}
    case 113:
      do IO<Bool>:
        move_control(~State,~driver,handle,yaw,0.0,0.0,F32.neg(1.0))
        return True{}
    case 101:
      do IO<Bool>:
        move_control(~State,~driver,handle,yaw,0.0,0.0,1.0)
        return True{}
    case _: IO.pure(Bool,True{})

def events_go(~State:Type,~driver:Driver<State>,events:List<Event>,+handle:S.Handle<State>,+yaw:F32,+pitch:F32,keep:Bool) -> IO(Bool):
  match events:
    case Nil{}: IO.pure(Bool,keep)
    case Close{} <> tail: events_go(~State,~driver,tail,handle,yaw,pitch,False{})
    case Key{code,True{}} <> tail:
      do IO<Bool>:
        next : Bool <- key_control(~State,~driver,code,handle,yaw)
        events_go(~State,~driver,tail,handle,yaw,pitch,next && keep)
    case Look{dx,dy} <> tail:
      +next_yaw = F32.add(yaw,F32.mul(dx,0.0025))
      +next_pitch = F32.clamp(F32.add(pitch,F32.mul(dy,0.0025)),F32.neg(1.5707963),1.5707963)
      do IO<Bool>:
        result : Result<&2,&2,String,Unit> <- S.local_call(State,Result<&2,&2,String,Unit>,handle,state => look(State,driver,state,next_yaw,next_pitch))
        result_unit(result)
        events_go(~State,~driver,tail,handle,next_yaw,next_pitch,keep)
    case event <> tail: events_go(~State,~driver,tail,handle,yaw,pitch,keep)

def events_camera(~State:Type,~driver:Driver<State>,events:List<Event>,handle:S.Handle<State>,camera:R.Camera) -> IO(Bool):
  R.Camera{x,y,z,yaw,pitch} = camera
  events_go(~State,~driver,events,handle,yaw,pitch,True{})

def frame_dump(dump:Maybe<&2,String>,image:Image) -> IO(Unit):
  match dump:
    case None{}: IO.pure(Unit,Unit{})
    case Some{path}: R.write_ppm(path,image,128,128)

def remaining(frames:Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match frames:
    case None{}: None{}
    case Some{0n}: Some{0n}
    case Some{1n+p}: Some{p}

def can_continue(frames:Maybe<&2,Nat>) -> Bool:
  match frames:
    case Some{0n}: False{}
    case _: True{}

def closing(-State:Type,window:Window,handle:S.Handle<State>) -> IO(Unit):
  do IO<Unit>:
    Window.close(window)
    S.stop(State,handle)
    IO.die(Unit,0,"client closed")

def camera_of(snapshot:R.Snapshot) -> R.Camera:
  R.Snapshot{tick,revision,blocks,camera} = snapshot
  camera

def frame_summary(snapshot:R.Snapshot) -> String:
  R.Snapshot{tick,revision,blocks,camera} = snapshot
  "{\"event\":\"client.snapshot\",\"tick\":" ++ Nat.show(tick) ++ ",\"revision\":" ++ Nat.show(revision) ++ ",\"blocks\":" ++ Nat.show(List.length(&2,R.Block,blocks)) ++ "}"

def loop_next(-State:Type,window:Window,assets:R.Assets,handle:S.Handle<State>,keep:Bool,rest:Window -> R.Assets -> S.Handle<State> -> IO(Unit)) -> IO(Unit):
  match keep:
    case False{}: closing(State,window,handle)
    case True{}:
      do IO<Unit>:
        IO.sleep(8)
        rest(window,assets,handle)

# Only OS-driven client lifetime is unsafe; world, snapshots, asset codecs
# and rendering remain checked Bend. Events submit serialized actor queries.
@unsafe
def loop(~State:Type,~driver:Driver<State>,window:Window,assets:R.Assets,+handle:S.Handle<State>,frames:Maybe<&2,Nat>,+dump:Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,String,R.Snapshot> <- S.local_call(State,Result<&2,&2,String,R.Snapshot>,handle,state => snapshot(State,driver,state,128,128))
    +snapshot : R.Snapshot <- snapshot_ready(result)
    IO.print(frame_summary(snapshot))
    camera : R.Camera = camera_of(snapshot)
    pair : R.Assets & Image = R.render(snapshot,assets,128,128)
    P.paired(R.Assets,Image,IO(Unit),pair,assets => +image => (
      do IO<Unit>:
        frame_dump(dump,image)
        shown : Window & Image & List<Event> <- Window.frame(window,image)
        P.paired(Window,Image & List<Event>,IO(Unit),shown,window => pair => (
          P.paired(Image,List<Event>,IO(Unit),pair,image => events => (
            do IO<Unit>:
              keep : Bool <- events_camera(~State,~driver,events,handle,camera)
              +next : Maybe<&2,Nat> = remaining(frames)
              loop_next(State,window,assets,handle,keep && can_continue(next),w => a => h => loop(~State,~driver,w,a,h,next,dump))
          ))
        ))
    ))

def interactive(result:Result<&1,&1,U32 & String,String>) -> Bool:
  match result:
    case Fail{error}: True{}
    case Done{text}: Bool.not(String.eq(text,"hidden"))

def window_start(~State:Type,~driver:Driver<State>,assets:R.Assets,handle:S.Handle<State>,human:Bool,frames:Maybe<&2,Nat>,dump:Maybe<&2,String>,title:String) -> IO(Unit):
  do IO<Unit>:
    window : Window <- IO.try(Window,Window.open(title,512,512))
    window : Window <- Window.grab(window,human)
    loop(~State,~driver,window,assets,handle,frames,dump)

