import Base
import ./server.bend as S
import ./png.bend as P
import ./window_input.bend as WI
import ./client_controls.bend as CC

# A physical frame becomes one actor operation, including capture transitions.
# This prevents timer pulses from observing half an OS event batch and permits
# exact MouseHandler accumulation followed by a single Entity.turn.
type Driver<-State:Type,-Frame:Data> is Type:
  Driver{snapshot:State -> U32 -> U32 -> State & Result<&2,&2,String,Frame>,
    input:State -> CC.Packet -> State & Result<&2,&2,String,Unit>,
    capture_allowed:Frame -> Bool}

type Renderer<-Frame:Data,-Assets:Type> is Type:
  Renderer{draw:Frame -> Assets -> U32 -> U32 -> Assets & Result<&2,&2,String,Image>,
    describe:Frame -> String,close:Assets -> IO(Unit)}

def snapshot(-State:Type,-Frame:Data,driver:Driver<State,Frame>,state:State,width:U32,height:U32) -> State & Result<&2,&2,String,Frame>:
  Driver{query,input,allowed} = driver
  query(state,width,height)

def input(-State:Type,-Frame:Data,driver:Driver<State,Frame>,state:State,packet:CC.Packet) -> State & Result<&2,&2,String,Unit>:
  Driver{query,input,allowed} = driver
  input(state,packet)

def capture_allowed(-State:Type,-Frame:Data,driver:Driver<State,Frame>,frame:Frame) -> Bool:
  Driver{query,input,allowed} = driver
  allowed(frame)

def draw(-Frame:Data,-Assets:Type,renderer:Renderer<Frame,Assets>,frame:Frame,assets:Assets,width:U32,height:U32) -> Assets & Result<&2,&2,String,Image>:
  Renderer{draw,describe,close} = renderer
  draw(frame,assets,width,height)

def describe(-Frame:Data,-Assets:Type,renderer:Renderer<Frame,Assets>,frame:Frame) -> String:
  Renderer{draw,describe,close} = renderer
  describe(frame)

def assets_close(-Frame:Data,-Assets:Type,renderer:Renderer<Frame,Assets>,assets:Assets) -> IO(Unit):
  Renderer{draw,describe,close} = renderer
  close(assets)

def input_result(result:Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("input rejected: " ++ error)
    case Done{unit}: IO.pure(Unit,unit)

def local_input(~State:Type,~Frame:Data,~driver:Driver<State,Frame>,handle:S.Handle<State>,packet:CC.Packet) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,String,Unit> <- S.local_call(State,Result<&2,&2,String,Unit>,handle,state => input(State,Frame,driver,state,packet))
    input_result(result)

def local_release(~State:Type,~Frame:Data,~driver:Driver<State,Frame>,handle:S.Handle<State>) -> IO(Unit):
  local_input(~State,~Frame,~driver,handle,CC.release())

def lost_actions(actions:List<&2,CC.Action>,lost:Bool) -> List<&2,CC.Action>:
  match lost:
    case False{}: actions
    case True{}: CC.Release{} <> actions

# Actions are accumulated backwards. Actual capture is observed after every
# grab request; Base can refuse capture and emits no focus-loss event.
def events_done(window:Window,captured:Bool,keep:Bool,actions:List<&2,CC.Action>) -> IO(Window & Bool & Bool & List<&2,CC.Action>):
  IO.pure(Window & Bool & Bool & List<&2,CC.Action>,(window,captured,keep,actions))

def events(pending:List<Event>,window:Window,+allow_capture:Bool,+captured:Bool,keep:Bool,actions:List<&2,CC.Action>) -> IO(Window & Bool & Bool & List<&2,CC.Action>):
  match pending captured:
    case Nil{} _: events_done(window,captured,keep,actions)
    case Close{} <> rest _:
      events_done(window,False{},False{},CC.Release{} <> CC.PlatformEvent{Close{},False{}} <> actions)
    case Key{27,True{}} <> rest _:
      do IO<Window & Bool & Bool & List<&2,CC.Action>>:
        window : Window <- Window.grab(window,False{})
        events(rest,window,allow_capture,False{},keep,CC.Release{} <> CC.PlatformEvent{Key{27,True{}},False{}} <> actions)
    case Mouse{x,y,0,True{}} <> rest False{}:
      do IO<Window & Bool & Bool & List<&2,CC.Action>>:
        result : Window & Bool <- WI.capture(window,allow_capture)
        P.paired(Window,Bool,IO(Window & Bool & Bool & List<&2,CC.Action>),result,window => +actual => events(rest,window,allow_capture,actual,keep,CC.PlatformEvent{Mouse{x,y,0,True{}},actual} <> actions))
    case event <> rest _:
      events(rest,window,allow_capture,captured,keep,CC.PlatformEvent{event,captured} <> actions)

def packet_result(window:Window,captured:Bool,keep:Bool) -> Window & Bool & Bool:
  (window,captured,keep)

def packet_flags(~State:Type,~Frame:Data,~driver:Driver<State,Frame>,handle:S.Handle<State>,old:Bool,keep:Bool,actions:List<&2,CC.Action>,window:Window,+focused:Bool,+captured:Bool) -> IO(Window & Bool & Bool):
  do IO<Window & Bool & Bool>:
    local_input(~State,~Frame,~driver,handle,CC.Packet{List.reverse(&2,CC.Action,lost_actions(actions,old && Bool.not(focused && captured))),focused,captured})
    return packet_result(window,focused && captured,keep)

def packet_final(~State:Type,~Frame:Data,~driver:Driver<State,Frame>,handle:S.Handle<State>,old:Bool,keep:Bool,actions:List<&2,CC.Action>,result:Window & Bool & Bool) -> IO(Window & Bool & Bool):
  (window,focused,captured) = result
  packet_flags(~State,~Frame,~driver,handle,old,keep,actions,window,focused,captured)

def packet_events(~State:Type,~Frame:Data,~driver:Driver<State,Frame>,handle:S.Handle<State>,result:Window & Bool & Bool & List<&2,CC.Action>) -> IO(Window & Bool & Bool):
  (window,captured,keep,actions) = result
  do IO<Window & Bool & Bool>:
    status : Window & Bool & Bool <- WI.Native.status(window)
    packet_final(~State,~Frame,~driver,handle,captured,keep,actions,status)

def packet_initial(~State:Type,~Frame:Data,~driver:Driver<State,Frame>,handle:S.Handle<State>,pending:List<Event>,allow_capture:Bool,old:Bool,window:Window,+focused:Bool,+captured:Bool) -> IO(Window & Bool & Bool):
  do IO<Window & Bool & Bool>:
    result : Window & Bool & Bool & List<&2,CC.Action> <- events(pending,window,allow_capture,focused && captured,True{},lost_actions([],old && Bool.not(focused && captured)))
    packet_events(~State,~Frame,~driver,handle,result)

def packet_inspected(~State:Type,~Frame:Data,~driver:Driver<State,Frame>,handle:S.Handle<State>,pending:List<Event>,allow_capture:Bool,old:Bool,result:Window & Bool & Bool) -> IO(Window & Bool & Bool):
  (window,focused,captured) = result
  packet_initial(~State,~Frame,~driver,handle,pending,allow_capture,old,window,focused,captured)

def window_policy(window:Window,allowed:Bool) -> IO(Window):
  match allowed:
    case True{}: IO.pure(Window,window)
    case False{}: Window.grab(window,False{})

def frame_input(~State:Type,~Frame:Data,~driver:Driver<State,Frame>,window:Window,handle:S.Handle<State>,pending:List<Event>,+allow_capture:Bool,old:Bool) -> IO(Window & Bool & Bool):
  do IO<Window & Bool & Bool>:
    window : Window <- window_policy(window,allow_capture)
    status : Window & Bool & Bool <- WI.Native.status(window)
    packet_inspected(~State,~Frame,~driver,handle,pending,allow_capture,old,status)

def remaining(frames:Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match frames:
    case None{}: None{}
    case Some{0n}: Some{0n}
    case Some{1n+rest}: Some{rest}

def continuing(frames:Maybe<&2,Nat>) -> Bool:
  match frames:
    case Some{0n}: False{}
    case _: True{}

def closing(~State:Type,~Frame:Data,~Assets:Type,~driver:Driver<State,Frame>,~renderer:Renderer<Frame,Assets>,window:Window,assets:Assets,+handle:S.Handle<State>,code:U32,message:String) -> IO(Unit):
  do IO<Unit>:
    local_release(~State,~Frame,~driver,handle)
    Window.close(window)
    assets_close(Frame,Assets,renderer,assets)
    S.stop(State,handle)
    IO.die(Unit,code,message)

def next(-State:Type,-Assets:Type,assets:Assets,result:Window & Bool & Bool,rest:Window -> Assets -> Bool -> Bool -> IO(Unit)) -> IO(Unit):
  (window,captured,keep) = result
  rest(window,assets,captured,keep)

def frame_ready(-Frame:Data,-Assets:Type,window:Window,assets:Assets,result:Result<&2,&2,String,Frame>,rest:Window -> Assets -> Frame -> IO(Unit),failed:Window -> Assets -> String -> IO(Unit)) -> IO(Unit):
  match result:
    case Fail{error}: failed(window,assets,error)
    case Done{frame}: rest(window,assets,frame)

def drawing(-Assets:Type,result:Assets & Result<&2,&2,String,Image>,rest:Assets -> Result<&2,&2,String,Image> -> IO(Unit)) -> IO(Unit):
  (assets,status) = result
  rest(assets,status)

def image_ready(-Assets:Type,window:Window,assets:Assets,result:Result<&2,&2,String,Image>,rest:Window -> Assets -> Image -> IO(Unit),failed:Window -> Assets -> String -> IO(Unit)) -> IO(Unit):
  match result:
    case Fail{error}: failed(window,assets,error)
    case Done{image}: rest(window,assets,image)

def scheduled(-Assets:Type,window:Window,assets:Assets,keep:Bool,rest:Window -> Assets -> IO(Unit),closed:Window -> Assets -> IO(Unit)) -> IO(Unit):
  match keep:
    case False{}: closed(window,assets)
    case True{}:
      do IO<Unit>:
        IO.sleep(8)
        rest(window,assets)

@unsafe
def loop(~State:Type,~Frame:Data,~Assets:Type,~driver:Driver<State,Frame>,~renderer:Renderer<Frame,Assets>,window:Window,assets:Assets,+handle:S.Handle<State>,+allow_capture:Bool,captured:Bool,frames:Maybe<&2,Nat>,+width:U32,+height:U32) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,String,Frame> <- S.local_call(State,Result<&2,&2,String,Frame>,handle,state => snapshot(State,Frame,driver,state,width,height))
    frame_ready(Frame,Assets,window,assets,result,window => assets => +frame => (
      do IO<Unit>:
        IO.print(describe(Frame,Assets,renderer,frame))
        drawing(Assets,draw(Frame,Assets,renderer,frame,assets,width,height),assets => status => (
          image_ready(Assets,window,assets,status,w => assets => image => (
            do IO<Unit>:
              shown : Window & Image & List<Event> <- Window.frame(w,image)
              P.paired(Window,Image & List<Event>,IO(Unit),shown,w => pair => (
                P.paired(Image,List<Event>,IO(Unit),pair,image => pending => (
                  do IO<Unit>:
                    result : Window & Bool & Bool <- frame_input(~State,~Frame,~driver,w,handle,pending,allow_capture && capture_allowed(State,Frame,driver,frame),captured)
                    +count : Maybe<&2,Nat> = remaining(frames)
                    next(State,Assets,assets,result,w => a => capture => keep => scheduled(Assets,w,a,keep && continuing(count),w => a => loop(~State,~Frame,~Assets,~driver,~renderer,w,a,handle,allow_capture,capture,count,width,height),w => a => closing(~State,~Frame,~Assets,~driver,~renderer,w,a,handle,0,"client closed")))
                ))
              ))
          ),w => assets => error => closing(~State,~Frame,~Assets,~driver,~renderer,w,assets,handle,1,"render: " ++ error))
        ))
    ),w => assets => error => closing(~State,~Frame,~Assets,~driver,~renderer,w,assets,handle,1,"frame query: " ++ error))

def started(~State:Type,~Frame:Data,~Assets:Type,~driver:Driver<State,Frame>,~renderer:Renderer<Frame,Assets>,window:Window,assets:Assets,+handle:S.Handle<State>,human:Bool,captured:Bool,frames:Maybe<&2,Nat>,width:U32,height:U32) -> IO(Unit):
  match frames:
    case Some{0n}: closing(~State,~Frame,~Assets,~driver,~renderer,window,assets,handle,0,"client closed")
    case _: loop(~State,~Frame,~Assets,~driver,~renderer,window,assets,handle,human,captured,frames,width,height)

def opened(~State:Type,~Frame:Data,~Assets:Type,~driver:Driver<State,Frame>,~renderer:Renderer<Frame,Assets>,assets:Assets,+handle:S.Handle<State>,+human:Bool,frames:Maybe<&2,Nat>,width:U32,height:U32,result:Result<&1,&1,U32 & String,Window>) -> IO(Unit):
  match result:
    case Fail{(code,message)}:
      do IO<Unit>:
        local_release(~State,~Frame,~driver,handle)
        assets_close(Frame,Assets,renderer,assets)
        S.stop(State,handle)
        IO.die(Unit,code,"window open: " ++ message)
    case Done{window}:
      do IO<Unit>:
        captured : Window & Bool <- WI.capture(window,human)
        P.paired(Window,Bool,IO(Unit),captured,window => actual => started(~State,~Frame,~Assets,~driver,~renderer,window,assets,handle,human,actual,frames,width,height))

def open(~State:Type,~Frame:Data,~Assets:Type,~driver:Driver<State,Frame>,~renderer:Renderer<Frame,Assets>,assets:Assets,handle:S.Handle<State>,+human:Bool,frames:Maybe<&2,Nat>,width:U32,height:U32,title:String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1,&1,U32 & String,Window> <- Window.open(title,512,512)
    opened(~State,~Frame,~Assets,~driver,~renderer,assets,handle,human,frames,width,height,result)
