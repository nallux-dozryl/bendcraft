import Base
import ../src/client_presenter.bend as CP
import ../src/client_controls.bend as CC
import ../src/core.bend as C
import ../src/json.bend as J
import ../src/live.bend as L
import ../src/server.bend as S
import ../src/platform.bend as P
import ../src/window_input.bend as WI

# All state transitions, packet inspection, rendering and cleanup occur here.
# Python only starts the real executable and checks its reports/marker file.
type Counts is Data:
  Counts{snapshots:U32,packets:U32,releases:U32,pulses:U32}

type Audit is Data:
  Audit{trace:String,focused:Bool,captured:Bool}

type State is Type:
  State{world:C.World,counts:Counts,audit:Audit,mode:U32}

type Frame is Data:
  Frame{tick:Nat,ordinal:U32,width:U32,height:U32,policy:Bool,fail_draw:Bool}

type Assets is Type:
  Assets{marker:File,handle:S.Handle<State>,draws:U32}

def bit(value:Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"

def json_bool(value:Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

def action_text(action:CC.Action) -> String:
  match action:
    case CC.Release{}: "R|"
    case CC.PlatformEvent{event,captured}:
      match event:
        case Key{code,down}: "K" ++ U32.show(code) ++ bit(down) ++ bit(captured) ++ "|"
        case Mouse{x,y,button,down}: "M" ++ U32.show(button) ++ bit(down) ++ bit(captured) ++ "|"
        case Look{dx,dy}: "L" ++ bit(captured) ++ "|"
        case Move{x,y}: "V" ++ bit(captured) ++ "|"
        case Scroll{x,y,dx,dy}: "S" ++ bit(captured) ++ "|"
        case Close{}: "X" ++ bit(captured) ++ "|"

def release_count(actions:List<&2,CC.Action>) -> U32:
  match actions:
    case Nil{}: 0
    case CC.Release{} <> rest: U32.add(1,release_count(rest))
    case other <> rest: release_count(rest)

def trace(actions:List<&2,CC.Action>) -> String:
  match actions:
    case Nil{}: ""
    case action <> rest: action_text(action) ++ trace(rest)

def packet_result(state:State,rejected:Bool) -> State & Result<&2,&2,String,Unit>:
  match rejected:
    case True{}: (state,Fail{"injected input rejection"})
    case False{}: (state,Done{Unit{}})

def packet(state:State,value:CC.Packet) -> State & Result<&2,&2,String,Unit>:
  State{world,counts,audit,+mode} = state
  Counts{snapshots,packets,releases,pulses} = counts
  Audit{previous,old_focus,old_capture} = audit
  CC.Packet{+actions,focused,captured} = value
  updated : State = State{world,Counts{snapshots,U32.add(packets,1),U32.add(releases,release_count(actions)),pulses},Audit{previous ++ trace(actions),focused,captured},mode}
  packet_result(updated,U32.is_eq(mode,3))


def policy(frame:Frame) -> Bool:
  Frame{tick,ordinal,width,height,allowed,fail_draw} = frame
  allowed

def snapshot_result(state:State,frame:Frame,rejected:Bool) -> State & Result<&2,&2,String,Frame>:
  match rejected:
    case True{}: (state,Fail{"injected snapshot failure"})
    case False{}: (state,Done{frame})

def snapshot_clock(counts:Counts,audit:Audit,+mode:U32,+width:U32,+height:U32,result:C.World & C.Clock) -> State & Result<&2,&2,String,Frame>:
  Counts{+ordinal,packets,releases,pulses} = counts
  (world,clock) = result
  C.Clock{tick,time,paused,daylight,revision,pending} = clock
  frame : Frame = Frame{tick,ordinal,width,height,Bool.not(U32.is_eq(mode,4)),U32.is_eq(mode,2) || (U32.is_eq(mode,10) && U32.is_eq(ordinal,2))}
  snapshot_result(State{world,Counts{ordinal,packets,releases,pulses},audit,mode},frame,U32.is_eq(mode,1) || (U32.is_eq(mode,9) && U32.is_eq(ordinal,2)))

def snapshot(state:State,width:U32,height:U32) -> State & Result<&2,&2,String,Frame>:
  State{world,counts,audit,mode} = state
  Counts{snapshots,packets,releases,pulses} = counts
  snapshot_clock(Counts{U32.add(snapshots,1),packets,releases,pulses},audit,mode,width,height,C.clock(world))

def pulse(state:State) -> State:
  State{world,counts,audit,mode} = state
  Counts{snapshots,packets,releases,pulses} = counts
  State{C.realtime_step(world),Counts{snapshots,packets,releases,U32.add(pulses,1)},audit,mode}

def dispatch_ready(counts:Counts,audit:Audit,mode:U32,result:C.World & L.Session & J.Value) -> State & L.Session & J.Value:
  (world,session,response) = result
  (State{world,counts,audit,mode},session,response)

def dispatch(state:State,session:L.Session,token:String,request:J.Value) -> State & L.Session & J.Value:
  State{world,counts,audit,mode} = state
  dispatch_ready(counts,audit,mode,L.dispatch(world,session,token,request))

def step(state:State) -> State & Unit:
  State{world,counts,audit,mode} = state
  (State{C.step(world),counts,audit,mode},Unit{})

def actor_report(counts:Counts,audit:Audit,mode:U32,clock:C.Clock) -> String:
  Counts{snapshots,packets,releases,pulses} = counts
  Audit{text,focused,captured} = audit
  C.Clock{tick,time,paused,daylight,revision,pending} = clock
  "{\"tick\":" ++ Nat.show(tick) ++ ",\"paused\":" ++ json_bool(paused) ++ ",\"snapshots\":" ++ U32.show(snapshots) ++ ",\"packets\":" ++ U32.show(packets) ++ ",\"releases\":" ++ U32.show(releases) ++ ",\"pulses\":" ++ U32.show(pulses) ++ ",\"trace\":\"" ++ text ++ "\",\"focused\":" ++ json_bool(focused) ++ ",\"captured\":" ++ json_bool(captured) ++ ",\"mode\":" ++ U32.show(mode) ++ "}"

def reported(+counts:Counts,+audit:Audit,+mode:U32,result:C.World & C.Clock) -> State & String:
  (world,clock) = result
  (State{world,counts,audit,mode},actor_report(counts,audit,mode,clock))

def report(state:State) -> State & String:
  State{world,counts,audit,mode} = state
  reported(counts,audit,mode,C.clock(world))

def describe(frame:Frame) -> String:
  Frame{tick,ordinal,width,height,allowed,failed} = frame
  "{\"event\":\"harness.frame\",\"tick\":" ++ Nat.show(tick) ++ ",\"ordinal\":" ++ U32.show(ordinal) ++ ",\"width\":" ++ U32.show(width) ++ ",\"height\":" ++ U32.show(height) ++ ",\"capture_allowed\":" ++ json_bool(allowed) ++ "}"

def draw_result(assets:Assets,rejected:Bool) -> Assets & Result<&2,&2,String,Image>:
  match rejected:
    case True{}: (assets,Fail{"injected draw failure"})
    case False{}: (assets,Done{Pix{4281558681}})

def draw(frame:Frame,assets:Assets,+width:U32,+height:U32) -> Assets & Result<&2,&2,String,Image>:
  Frame{tick,ordinal,fw,fh,allowed,failed} = frame
  Assets{marker,handle,draws} = assets
  draw_result(Assets{marker,handle,U32.add(draws,1)},failed || Bool.not(U32.is_eq(fw,width) && U32.is_eq(fh,height) && U32.is_eq(width,32) && U32.is_eq(height,24)))

def marker_written(result:File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    IO.pass(Unit,status)

def close(assets:Assets) -> IO(Unit):
  Assets{marker,handle,draws} = assets
  do IO<Unit>:
    actor : String <- S.local_call(State,String,handle,report)
    after : String <- P.Platform.observe()
    result : File & Result<&1,&1,U32 & String,Unit> <- File.write(marker,"{\"closed\":true,\"draws\":" ++ U32.show(draws) ++ ",\"actor\":" ++ actor ++ ",\"after\":" ++ after ++ "}\n")
    marker_written(result)

def driver() -> CP.Driver<State,Frame>:
  CP.Driver{snapshot,packet,policy}

def renderer() -> CP.Renderer<Frame,Assets>:
  CP.Renderer{frame => assets => width => height => draw(frame,assets,width,height),describe,close}

def native_status(result:Window & Bool & Bool) -> IO(Window):
  (window,focused,captured) = result
  do IO<Window>:
    IO.print("native_status=" ++ json_bool(focused) ++ "," ++ json_bool(captured))
    return window

def inspected(result:Window & String) -> IO(Window):
  (window,text) = result
  do IO<Window>:
    IO.print("window=" ++ text)
    status : Window & Bool & Bool <- WI.Native.status(window)
    native_status(status)

def sequence_result(assets:Assets,+handle:S.Handle<State>,result:Window & Bool & Bool) -> IO(Unit):
  (window,captured,keep) = result
  do IO<Unit>:
    actor : String <- S.local_call(State,String,handle,report)
    IO.print("{\"event\":\"harness.packet\",\"keep\":" ++ json_bool(keep) ++ ",\"captured\":" ++ json_bool(captured) ++ ",\"actor\":" ++ actor ++ "}")
    CP.closing(~State,~Frame,~Assets,~driver(),~renderer(),window,assets,handle,0,"synthetic packet closed")

def injected_events(mode:U32) -> List<Event>:
  match mode:
    case 5: [Key{87,True{}},Look{1.0,2.0},Mouse{3,4,0,True{}},Key{27,True{}},Key{87,False{}},Close{},Key{88,True{}}]
    case 6: [Mouse{3,4,0,True{}},Key{87,True{}}]
    case other: []

def sequence_frame(+mode:U32,assets:Assets,+handle:S.Handle<State>,result:Window & Image & List<Event>) -> IO(Unit):
  (window,image,physical_events) = result
  do IO<Unit>:
    IO.print("physical_event_count=" ++ Nat.show(List.length(&1,Event,physical_events)))
    packet : Window & Bool & Bool <- CP.frame_input(~State,~Frame,~driver(),window,handle,injected_events(mode),Bool.not(U32.is_eq(mode,5)),Bool.not(U32.is_eq(mode,6)))
    sequence_result(assets,handle,packet)

def budget(mode:U32) -> Maybe<&2,Nat>:
  match mode:
    case 12: Some{0n}
    case 13: Some{1n}
    case _: Some{3n}


def with_inspected(+mode:U32,assets:Assets,+handle:S.Handle<State>,window:Window,sequence:Bool) -> IO(Unit):
  match sequence:
    case True{}:
      do IO<Unit>:
        shown : Window & Image & List<Event> <- Window.frame(window,Pix{4281558681})
        sequence_frame(mode,assets,handle,shown)
    case False{}:
      CP.opened(~State,~Frame,~Assets,~driver(),~renderer(),assets,handle,U32.is_eq(mode,4),budget(mode),32,24,Done{window})

def with_window(+mode:U32,assets:Assets,+handle:S.Handle<State>,window:Window) -> IO(Unit):
  do IO<Unit>:
    observed : Window & String <- P.Platform.inspect(window)
    window : Window <- inspected(observed)
    with_inspected(mode,assets,handle,window,U32.is_gt(mode,4) && U32.is_lt(mode,8))


def actual_opened(+mode:U32,assets:Assets,+handle:S.Handle<State>,result:Result<&1,&1,U32 & String,Window>) -> IO(Unit):
  match result:
    case Fail{error}: CP.opened(~State,~Frame,~Assets,~driver(),~renderer(),assets,handle,False{},budget(mode),32,24,Fail{error})
    case Done{window}: with_window(mode,assets,handle,window)

def launch_actual(+mode:U32,assets:Assets,+handle:S.Handle<State>,wrapper:Bool) -> IO(Unit):
  match wrapper:
    case True{}: CP.open(~State,~Frame,~Assets,~driver(),~renderer(),assets,handle,False{},Some{1n},32,24,"Minecraft hidden presenter wrapper test")
    case False{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,Window> <- Window.open("Minecraft hidden presenter integration test",64,64)
        actual_opened(mode,assets,handle,result)

def launch(+mode:U32,assets:Assets,+handle:S.Handle<State>,injected:Bool) -> IO(Unit):
  match injected:
    case True{}:
      CP.opened(~State,~Frame,~Assets,~driver(),~renderer(),assets,handle,False{},Some{3n},32,24,Fail{(22,"injected open failure")})
    case False{}: launch_actual(mode,assets,handle,U32.is_eq(mode,11))


def run(+mode:U32,path:String) -> IO(Unit):
  do IO<Unit>:
    before : String <- P.Platform.observe()
    IO.print("before=" ++ before)
    +handle : S.Handle<State> <- S.start_handle(~State,~S.Driver{pulse,dispatch},State{C.new(500),Counts{0,0,0,0},Audit{"",False{},False{}},mode})
    first : Unit <- S.local_call(State,Unit,handle,step)
    second : Unit <- S.local_call(State,Unit,handle,step)
    actor : String <- S.local_call(State,String,handle,report)
    marker : File <- IO.try(File,File.open(path,"w"))
    IO.print("{\"event\":\"harness.prepared\",\"actor\":" ++ actor ++ "}")
    IO.sleep(250)
    launch(mode,Assets{marker,handle,0},handle,U32.is_eq(mode,8))

def parsed_mode(path:String,mode:Maybe<&2,U32>) -> IO(Unit):
  match mode:
    case None{}: IO.die(Unit,2,"invalid test mode")
    case Some{value}: run(value,path)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> mode <> path <> Nil{}:
      parsed_mode(path,J.as_u32(J.JNumber{mode}))
    case other: IO.die(Unit,2,"expected numeric test mode and marker path")


def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
