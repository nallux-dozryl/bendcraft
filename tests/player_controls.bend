import Base
import ../src/f64.bend as F
import ../src/player_input.bend as PI
import ../src/player_look.bend as PL
import ../src/mouse_input.bend as MI
import ../src/client_controls.bend as CC
import ../src/player_controls.bend as C

law release_clears_without_admission:
  for buttons: PI.Buttons
  for +look: PL.State
  for +x: F.F64
  for +y: F.F64
  for ax: F.F64
  for ay: F.F64
  for first: Bool
  for +options: MI.Options
  {C.release(C.Controller{buttons,look,MI.State{x,y,ax,ay,first},options}) == C.Controller{PI.empty(),look,MI.State{x,y,F.F64{0,0},F.F64{0,0},True{}},options} : C.Controller}

def release_clears_without_admission(buttons,look,x,y,ax,ay,first,options):
  {==}

law release_is_idempotent:
  for +controller: C.Controller
  {C.release(C.release(controller)) == C.release(controller) : C.Controller}

def release_is_idempotent(controller):
  match controller:
    case C.Controller{buttons,look,MI.State{x,y,ax,ay,first},options}: {==}

law uncaptured_key_preserves_controller:
  for +controller: C.Controller
  for bindings: PI.Bindings
  for code: U32
  for down: Bool
  {C.key_event(False{},controller,bindings,code,down) == Done{controller} : Result<&2,&2,C.Error,C.Controller>}

def uncaptured_key_preserves_controller(controller,bindings,code,down):
  {==}

law release_action_is_total:
  for +controller: C.Controller
  for bindings: PI.Bindings
  {C.action(CC.Release{},controller,bindings) == Done{C.release(controller)} : Result<&2,&2,C.Error,C.Controller>}

def release_action_is_total(controller,bindings):
  {==}

law failed_fold_is_sticky:
  for actions: List<&2,CC.Action>
  for bindings: PI.Bindings
  for +error: C.Error
  {C.fold(actions,bindings,Fail{error}) == Fail{error} : Result<&2,&2,C.Error,C.Controller>}

def failed_fold_is_sticky(actions,bindings,error):
  match actions:
    case Nil{}: {==}
    case action <> rest: {==}

law failed_packet_retains_owner:
  for +controller: C.Controller
  for bindings: PI.Bindings
  for packet: CC.Packet
  for +error: C.Error
  {(controller,C.apply_gate(Some{error},controller,bindings,packet)) == (controller,Fail{error}) : C.Controller & Result<&2,&2,C.Error,C.Controller>}

def failed_packet_retains_owner(controller,bindings,packet,error):
  {==}

law inactive_turn_preserves_controller:
  for +controller: C.Controller
  {C.turn_once(None{},controller) == Done{controller} : Result<&2,&2,C.Error,C.Controller>}

def inactive_turn_preserves_controller(controller):
  match controller:
    case C.Controller{buttons,look,mouse,options}: {==}

law failed_finish_never_publishes_controller:
  for controller: C.Controller
  for +error: MI.Error
  {C.frame_finished(Fail{error},controller) == Fail{C.MouseFailure{error}} : Result<&2,&2,C.Error,C.Controller>}

def failed_finish_never_publishes_controller(controller,error):
  match controller:
    case C.Controller{buttons,look,mouse,options}: {==}

# Numeric pipe packets form a test observer only. They are not a production
# serialization or platform adapter. A parsed sequence really carries each
# accepted Controller; a rejected packet retains its preceding owner.
type ParsedController is Data:
  ParsedController{controller:C.Controller,rest:List<&2,U32>}

type ParsedActions is Data:
  ParsedActions{actions:List<&2,CC.Action>,rest:List<&2,U32>}

type ParsedPacket is Data:
  ParsedPacket{packet:CC.Packet,rest:List<&2,U32>}

type ParsedPackets is Data:
  ParsedPackets{packets:List<&2,CC.Packet>,rest:List<&2,U32>}

type Fixture is Data:
  ReleaseFixture{controller:C.Controller}
  PacketFixture{controller:C.Controller,bindings:PI.Bindings,packets:List<&2,CC.Packet>}

def numbers_cons(head:Maybe<&2,U32>,tail:Maybe<&2,List<&2,U32>>) -> Maybe<&2,List<&2,U32>>:
  match head tail:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def numbers(texts:List<&2,String>) -> Maybe<&2,List<&2,U32>>:
  match texts:
    case Nil{}: Some{Nil{}}
    case head <> tail: numbers_cons(U32.read(head),numbers(tail))

def controller_valid(valid:Bool,controller:C.Controller,rest:List<&2,U32>) -> Maybe<&2,ParsedController>:
  match valid:
    case True{}: Some{ParsedController{controller,rest}}
    case False{}: None{}

def parse_controller(words:List<&2,U32>) -> Maybe<&2,ParsedController>:
  match words:
    case +mask <> a <> b <> c <> d <> xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> +first <> sh <> sl <> +ix <> +iy <> +smooth <> +scope <> rest:
      controller_valid(U32.is_le(mask,127) && U32.is_le(first,1) && U32.is_le(ix,1) && U32.is_le(iy,1) && U32.is_le(smooth,1) && U32.is_le(scope,1),C.Controller{PI.from_mask(mask),PL.State{PL.float_bits(a),PL.float_bits(b),PL.float_bits(c),PL.float_bits(d)},MI.State{F.F64{xh,xl},F.F64{yh,yl},F.F64{ah,al},F.F64{bh,bl},U32.is_eq(first,1)},MI.Options{F.F64{sh,sl},U32.is_eq(ix,1),U32.is_eq(iy,1),U32.is_eq(smooth,1),U32.is_eq(scope,1)}},rest)
    case _: None{}

def action_valid(valid:Bool,action:CC.Action) -> Maybe<&2,CC.Action>:
  match valid:
    case True{}: Some{action}
    case False{}: None{}

def parse_action(tag:U32,+a:U32,+b:U32,+c:U32,+d:U32,+e:U32) -> Maybe<&2,CC.Action>:
  match tag:
    case 0: action_valid(U32.is_eq(a,0) && U32.is_eq(b,0) && U32.is_eq(c,0) && U32.is_eq(d,0) && U32.is_eq(e,0),CC.Release{})
    case 1: action_valid(U32.is_le(b,1) && U32.is_le(c,1) && U32.is_eq(d,0) && U32.is_eq(e,0),CC.PlatformEvent{Key{a,U32.is_eq(b,1)},U32.is_eq(c,1)})
    case 2: action_valid(U32.is_le(c,1) && U32.is_eq(d,0) && U32.is_eq(e,0),CC.PlatformEvent{Look{PL.float_bits(a),PL.float_bits(b)},U32.is_eq(c,1)})
    case 3: action_valid(U32.is_le(d,1) && U32.is_le(e,1),CC.PlatformEvent{Mouse{a,b,c,U32.is_eq(d,1)},U32.is_eq(e,1)})
    case 4: action_valid(U32.is_le(c,1) && U32.is_eq(d,0) && U32.is_eq(e,0),CC.PlatformEvent{Move{a,b},U32.is_eq(c,1)})
    case 5: action_valid(U32.is_le(e,1),CC.PlatformEvent{Scroll{a,b,PL.float_bits(c),PL.float_bits(d)},U32.is_eq(e,1)})
    case 6: action_valid(U32.is_eq(a,0) && U32.is_eq(b,0) && U32.is_le(c,1) && U32.is_eq(d,0) && U32.is_eq(e,0),CC.PlatformEvent{Close{},U32.is_eq(c,1)})
    case _: None{}

def actions_cons(action:Maybe<&2,CC.Action>,tail:Maybe<&2,ParsedActions>) -> Maybe<&2,ParsedActions>:
  match action tail:
    case Some{action} Some{ParsedActions{actions,rest}}: Some{ParsedActions{action <> actions,rest}}
    case _ _: None{}

def parse_actions(count:Nat,words:List<&2,U32>) -> Maybe<&2,ParsedActions>:
  match count words:
    case 0n _: Some{ParsedActions{Nil{},words}}
    case 1n+rest tag <> a <> b <> c <> d <> e <> words: actions_cons(parse_action(tag,a,b,c,d,e),parse_actions(rest,words))
    case _ _: None{}

def packet_actions(actions:Maybe<&2,ParsedActions>,focused:Bool,captured:Bool) -> Maybe<&2,ParsedPacket>:
  match actions:
    case Some{ParsedActions{actions,rest}}: Some{ParsedPacket{CC.Packet{actions,focused,captured},rest}}
    case None{}: None{}

def packet_valid(valid:Bool,count:U32,rest:List<&2,U32>,focused:Bool,captured:Bool) -> Maybe<&2,ParsedPacket>:
  match valid:
    case True{}: packet_actions(parse_actions(U32.to_nat(count),rest),focused,captured)
    case False{}: None{}

def parse_packet(words:List<&2,U32>) -> Maybe<&2,ParsedPacket>:
  match words:
    case +focused <> +captured <> +count <> rest: packet_valid(U32.is_le(focused,1) && U32.is_le(captured,1) && U32.is_le(count,4096),count,rest,U32.is_eq(focused,1),U32.is_eq(captured,1))
    case _: None{}

def packet_cons(head:CC.Packet,tail:Maybe<&2,ParsedPackets>) -> Maybe<&2,ParsedPackets>:
  match tail:
    case Some{ParsedPackets{packets,rest}}: Some{ParsedPackets{head <> packets,rest}}
    case None{}: None{}

def parsed_packet_tail(parsed:Maybe<&2,ParsedPacket>) -> List<&2,U32>:
  match parsed:
    case Some{ParsedPacket{_,rest}}: rest
    case None{}: Nil{}

def packets_cons(head:Maybe<&2,ParsedPacket>,tail:Maybe<&2,ParsedPackets>) -> Maybe<&2,ParsedPackets>:
  match head:
    case Some{ParsedPacket{packet,_}}: packet_cons(packet,tail)
    case None{}: None{}

def parse_packets(count:Nat,words:List<&2,U32>) -> Maybe<&2,ParsedPackets>:
  match count:
    case 0n: Some{ParsedPackets{Nil{},words}}
    case 1n+rest:
      +parsed = parse_packet(words)
      packets_cons(parsed,parse_packets(rest,parsed_packet_tail(parsed)))

def fixture_packets(parsed:Maybe<&2,ParsedPackets>,controller:C.Controller,bindings:PI.Bindings) -> Maybe<&2,Fixture>:
  match parsed:
    case Some{ParsedPackets{packets,Nil{}}}: Some{PacketFixture{controller,bindings,packets}}
    case _: None{}

def fixture_count(valid:Bool,count:U32,words:List<&2,U32>,controller:C.Controller,bindings:PI.Bindings) -> Maybe<&2,Fixture>:
  match valid:
    case True{}: fixture_packets(parse_packets(U32.to_nat(count),words),controller,bindings)
    case False{}: None{}

def fixture_bound(mode:U32,controller:C.Controller,bindings:PI.Bindings,words:List<&2,U32>) -> Maybe<&2,Fixture>:
  match mode words:
    case 0 _: fixture_packets(parse_packets(1n,words),controller,bindings)
    case 2 +count <> rest: fixture_count(U32.is_le(count,64),count,rest,controller,bindings)
    case _ _: None{}

def fixture_controller(mode:U32,parsed:Maybe<&2,ParsedController>) -> Maybe<&2,Fixture>:
  match mode parsed:
    case 1 Some{ParsedController{controller,Nil{}}}: Some{ReleaseFixture{controller}}
    case _ Some{ParsedController{controller,f <> b <> l <> r <> j <> h <> s <> rest}}: fixture_bound(mode,controller,PI.Bindings{f,b,l,r,j,h,s},rest)
    case _ _: None{}

def fixture_numbers(words:Maybe<&2,List<&2,U32>>) -> Maybe<&2,Fixture>:
  match words:
    case Some{mode <> rest}: fixture_controller(mode,parse_controller(rest))
    case _: None{}

def wide_words(value:F.F64) -> String:
  match value:
    case F.F64{hi,lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def controller_words(controller:C.Controller) -> String:
  match controller:
    case C.Controller{buttons,PL.State{a,b,c,d},MI.State{x,y,ax,ay,first},MI.Options{s,ix,iy,smooth,scope}}:
      "[" ++ U32.show(PI.mask(buttons)) ++ "," ++ U32.show(PL.raw(a)) ++ "," ++ U32.show(PL.raw(b)) ++ "," ++ U32.show(PL.raw(c)) ++ "," ++ U32.show(PL.raw(d)) ++ "," ++ wide_words(x) ++ "," ++ wide_words(y) ++ "," ++ wide_words(ax) ++ "," ++ wide_words(ay) ++ "," ++ U32.show(Bool.to_u32(first)) ++ "," ++ wide_words(s) ++ "," ++ U32.show(Bool.to_u32(ix)) ++ "," ++ U32.show(Bool.to_u32(iy)) ++ "," ++ U32.show(Bool.to_u32(smooth)) ++ "," ++ U32.show(Bool.to_u32(scope)) ++ "]"

def sample_words(sample:PI.Sample) -> String:
  match sample:
    case PI.Sample{buttons,PI.Vector{x,y},forward}: "[" ++ U32.show(PI.mask(buttons)) ++ "," ++ U32.show(PL.raw(x)) ++ "," ++ U32.show(PL.raw(y)) ++ "," ++ U32.show(Bool.to_u32(forward)) ++ "]"

def keyboard_words(controller:C.Controller) -> String:
  match controller:
    case C.Controller{buttons,_,_,_}: sample_words(PI.sample(buttons))

def mouse_error_words(error:MI.Error) -> String:
  match error:
    case MI.InvalidState{field}: "\"kind\":\"InvalidState\",\"field\":" ++ U32.show(field)
    case MI.InvalidMove{field}: "\"kind\":\"InvalidMove\",\"field\":" ++ U32.show(field)
    case MI.InvalidSensitivity{}: "\"kind\":\"InvalidSensitivity\""
    case MI.UnsupportedSmoothCamera{}: "\"kind\":\"UnsupportedSmoothCamera\""
    case MI.UnsupportedScoping{}: "\"kind\":\"UnsupportedScoping\""
    case MI.UnsupportedRelativeMode{}: "\"kind\":\"UnsupportedRelativeMode\""
    case MI.NonFiniteAccumulation{axis}: "\"kind\":\"NonFiniteAccumulation\",\"field\":" ++ U32.show(axis)
    case MI.NonFiniteDeltas{axis}: "\"kind\":\"NonFiniteDeltas\",\"field\":" ++ U32.show(axis)

def look_error_words(error:PL.Error) -> String:
  match error:
    case PL.InvalidState{field}: "\"kind\":\"InvalidState\",\"field\":" ++ U32.show(field)
    case PL.InvalidInput{axis}: "\"kind\":\"InvalidInput\",\"field\":" ++ U32.show(axis)
    case PL.NonFiniteResult{field}: "\"kind\":\"NonFiniteResult\",\"field\":" ++ U32.show(field)

def error_words(error:C.Error) -> String:
  match error:
    case C.MouseFailure{cause}: "{\"family\":\"Mouse\"," ++ mouse_error_words(cause) ++ "}"
    case C.LookFailure{cause}: "{\"family\":\"Look\"," ++ look_error_words(cause) ++ "}"

def report(result:Result<&2,&2,C.Error,C.Controller>,prior:C.Controller) -> String:
  match result:
    case Done{+controller}: "{\"ok\":true,\"controller\":" ++ controller_words(controller) ++ ",\"keyboard\":" ++ keyboard_words(controller) ++ "}"
    case Fail{error}: "{\"ok\":false,\"error\":" ++ error_words(error) ++ ",\"retained_controller\":" ++ controller_words(prior) ++ "}"

def commit(result:Result<&2,&2,C.Error,C.Controller>,prior:C.Controller) -> C.Controller:
  match result:
    case Done{controller}: controller
    case Fail{_}: prior

def run_packets(packets:List<&2,CC.Packet>,+bindings:PI.Bindings,+controller:C.Controller) -> IO(Unit):
  match packets:
    case Nil{}: IO.pure(Unit,Unit{})
    case packet <> rest:
      +result = C.apply(controller,bindings,packet)
      do IO<Unit>:
        IO.print(report(result,controller))
        run_packets(rest,bindings,commit(result,controller))

def run_fixture(fixture:Maybe<&2,Fixture>) -> IO(Unit):
  match fixture:
    case Some{ReleaseFixture{+controller}}: IO.print(report(Done{C.release(controller)},controller))
    case Some{PacketFixture{controller,bindings,packets}}: run_packets(packets,bindings,controller)
    case None{}: IO.die(Unit,2,"invalid controller packet fixture")

def batch(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        run_fixture(fixture_numbers(numbers(String.split(arg,'|'))))
        batch(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1,String,args))
