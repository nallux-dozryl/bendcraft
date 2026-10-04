import Base
import ../src/player_pose_world.bend as X
import ../src/player_pose.bend as P
import ../src/local_collision_world.bend as E
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/schedule.bend as Q
import ../src/section.bend as S
import ../src/section_map.bend as SM

# Independent raw receiver protocol; no test-only imports.
type Slot<-T: Data> is Data:
  Slot{value:T,tail:List<&2,Slot<T>>}

type Case is Data:
  Case{id:String,pose:P.State,body:M.Body,request:X.Request,tail:List<&2,Case>}

def slot_value(-T:Data,slot:Slot<T>) -> T:
  Slot{value,tail} = slot
  value

def state_tails(values:List<&2,P.State>) -> String:
  match values:
    case Nil{}: ""
    case P.State{pose,eye,tail} <> rest:
      U32.show(P.pose_id(pose)) ++ "," ++ U32.show(P.raw(eye)) ++ "{" ++ Nat.show(List.length(&2,P.State,tail)) ++ "}/" ++ state_tails(rest)

def state_complete(value:P.State) -> String:
  P.State{pose,eye,tail} = value
  U32.show(P.pose_id(pose)) ++ "," ++ U32.show(P.raw(eye)) ++ "[" ++ state_tails(tail) ++ "]"

def movement_error_show(error: M.Error) -> String:
  match error:
    case M.InvalidBody{component, field}: "body|" ++ U32.show(component) ++ "|" ++ U32.show(field)
    case M.InvalidDimensions{field}: "dimensions|" ++ U32.show(field)
    case M.InvalidRequest{axis}: "request|" ++ U32.show(axis)
    case M.InvalidStepHeight{}: "step"
    case M.InvalidCollider{phase, index, field}: "collider|" ++ U32.show(phase) ++ "|" ++ U32.show(index) ++ "|" ++ U32.show(field)
    case M.ReversedCollider{phase, index, axis}: "reversed|" ++ U32.show(phase) ++ "|" ++ U32.show(index) ++ "|" ++ U32.show(axis)
    case M.NonFiniteResult{component, field}: "result|" ++ U32.show(component) ++ "|" ++ U32.show(field)

def error_show(error: P.Error) -> String:
  match error:
    case P.NonCanonicalTail{owner}: "tail|" ++ U32.show(owner)
    case P.UnsupportedContext{}: "context"
    case P.UnsupportedScale{}: "scale"
    case P.UnsupportedAge{}: "age"
    case P.UnknownPose{id}: "pose|" ++ U32.show(id)
    case P.InvalidBody{cause}: "body|" ++ movement_error_show(cause)
    case P.StaleDimensions{}: "dimensions"
    case P.StaleEyeHeight{}: "eye"
    case P.StaleBox{}: "box"
    case P.InvalidQuery{field}: "query|" ++ U32.show(field)
    case P.MismatchedPose{}: "query_pose"
    case P.MismatchedQuery{}: "query_box"
    case P.QueryDenied{reason}: "denied|" ++ reason
    case P.MissingObservation{}: "missing"
    case P.ExtraObservations{}: "extra"
    case P.UnexpectedAnswer{}: "unexpected"
    case P.InvalidProgress{}: "progress"

def x_error(error:X.Error) -> String:
  match error:
    case X.NonCanonicalTail{}: "request-tail"
    case X.PoseError{cause}: "pose:" ++ error_show(cause)
    case X.WorldError{cause}: "world:" ++ E.error_text(cause)
    case X.BodyOutsideInterior{}: "body-outside"
    case X.QueryBudget{}: "fuel"

# Exact lossless section contents, with run lengths only for compact output.

def choose_text(valid:Bool,accepted:Unit -> String,rejected:Unit -> String) -> String:
  match valid:
    case True{}: accepted(Unit{})
    case False{}: rejected(Unit{})

def runs(values:List<&2,U32>, +value:U32, +count:Nat) -> String:
  match values:
    case Nil{}: Nat.show(count) ++ "," ++ U32.show(value) ++ "/"
    case +next <> +rest:
      choose_text(U32.is_eq(next,value),unit => runs(rest,value,1n+count),
        unit => Nat.show(count) ++ "," ++ U32.show(value) ++ "/" ++ runs(rest,next,1n))

def section_words(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case value <> rest: runs(rest,value,1n)

def entries_snapshot(entries:List<&1,SM.Entry>) -> List<&1,SM.Entry> & String:
  match entries:
    case Nil{}: ([],"")
    case SM.Entry{+key,section} <> rest:
      W.paired(S.Section,List<&2,U32>,List<&1,SM.Entry> & String,S.Section.snapshot(section),
        next => words => W.paired(List<&1,SM.Entry>,String,List<&1,SM.Entry> & String,entries_snapshot(rest),
          remaining => text => (SM.Entry{key,next} <> remaining,key ++ "=" ++ section_words(words) ++ ";" ++ text)))

def sections_snapshot(sections:SM.Sections) -> SM.Sections & String:
  match sections:
    case SM.EmptySections{}: (SM.EmptySections{},"E")
    case SM.Bucket{entries}:
      W.paired(List<&1,SM.Entry>,String,SM.Sections & String,entries_snapshot(entries),
        next => text => (SM.Bucket{next},"K(" ++ text ++ ")"))
    case SM.Branch{left,right}:
      W.paired(SM.Sections,String,SM.Sections & String,sections_snapshot(left),
        next => text => W.paired(SM.Sections,String,SM.Sections & String,sections_snapshot(right),
          other => suffix => (SM.Branch{next,other},"B(" ++ text ++ "," ++ suffix ++ ")")))

def report_sections(+id:String,+saved:Slot<W.View>,registry:B.Registry,
                    tick:Nat,time:Nat,paused:Bool,daylight:Bool,revision:Nat,count:U32,
                    pending:List<&2,Q.Pending<C.Mutation>>,events:List<&2,C.CoreEvent>,
                    result:SM.Sections & String) -> IO(W.State):
  (sections,text) = result
  IO.bind(Unit,W.State,IO.print(id ++ "|sections|" ++ text),unit =>
    IO.pure(W.State,W.attach(G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},slot_value(W.View,saved))))

def f64_show(value: F.F64) -> String:
  F.F64{hi, lo} = value
  U32.show(hi) ++ "|" ++ U32.show(lo)

def vector_show(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  f64_show(x) ++ "|" ++ f64_show(y) ++ "|" ++ f64_show(z)

def box_show(value: A.AABB) -> String:
  A.AABB{a, b, c, d, e, f} = value
  f64_show(a) ++ "|" ++ f64_show(b) ++ "|" ++ f64_show(c) ++ "|" ++ f64_show(d) ++ "|" ++ f64_show(e) ++ "|" ++ f64_show(f)

def body_show(value: M.Body) -> String:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = value
  vector_show(position) ++ "|" ++ box_show(box) ++ "|" ++ vector_show(velocity) ++ "|" ++ U32.show(P.raw(width)) ++ "|" ++ U32.show(P.raw(height)) ++ "|" ++ U32.show(Bool.to_u32(ground)) ++ "|" ++ U32.show(Bool.to_u32(horizontal)) ++ "|" ++ U32.show(Bool.to_u32(vertical)) ++ "|" ++ U32.show(Bool.to_u32(below))

def flag(value: Bool) -> String:
  U32.show(Bool.to_u32(value))

def bounds(value: W.Bounds) -> String:
  W.Bounds{x, y, z, w, h, d} = value
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(d)

def colors(value: W.Palette) -> String:
  W.Palette{a, b, c, d} = value
  U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def position(value: C.Position) -> String:
  C.Position{dimension, x, y, z} = value
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def raw_blocks(values: List<&2, W.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case W.RawBlock{W.Cell{x, y, z, edge}, state, material} <> rest:
      position(C.Position{"minecraft:overworld", x, y, z}) ++ "," ++ U32.show(edge) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ raw_blocks(rest)

def cache(value: Maybe<&2, W.SnapshotCache>) -> String:
  match value:
    case None{}: "none"
    case Some{W.SnapshotCache{revision, region, palette, blocks}}:
      Nat.show(revision) ++ "/" ++ bounds(region) ++ "/" ++ colors(palette) ++ "/" ++ raw_blocks(blocks)

def view(value: W.View) -> String:
  match value:
    case W.View{body, yaw, pitch, None{}, region, cached}:
      U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|none|" ++ bounds(region) ++ "|" ++ cache(cached)
    case W.View{body, yaw, pitch, Some{palette}, region, cached}:
      U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|" ++ colors(palette) ++ "|" ++ bounds(region) ++ "|" ++ cache(cached)

def stamp(value: Q.Stamp) -> String:
  Q.Stamp{tick, peer, sequence} = value
  Nat.show(tick) ++ "," ++ U32.show(peer) ++ "," ++ Nat.show(sequence)

def mutation(value: C.Mutation) -> String:
  match value:
    case C.SectionCreate{point, fill}: "section," ++ position(point) ++ "," ++ U32.show(fill)
    case C.BlockSet{point, state}: "block," ++ position(point) ++ "," ++ U32.show(state)
    case C.TimeSet{time}: "time," ++ Nat.show(time)
    case C.DaylightSet{enabled}: "daylight," ++ flag(enabled)

def pending_show(values: List<&2, Q.Pending<C.Mutation>>) -> String:
  match values:
    case Nil{}: ""
    case Q.Pending{when, operation} <> rest: stamp(when) ++ "," ++ mutation(operation) ++ ";" ++ pending_show(rest)

def events_show(values: List<&2, C.CoreEvent>) -> String:
  match values:
    case Nil{}: ""
    case C.Applied{when, revision} <> rest: "applied," ++ stamp(when) ++ "," ++ Nat.show(revision) ++ ";" ++ events_show(rest)
    case C.Rejected{when, reason} <> rest: "rejected," ++ stamp(when) ++ "," ++ W.error_text(reason) ++ ";" ++ events_show(rest)

def report_engine(+id:String,engine:G.Engine,+saved:Slot<W.View>) -> IO(W.State):
  G.Engine{C.World{+tick,+time,+paused,+daylight,+revision,+count,sections,+pending,+events},registry} = engine
  do IO<W.State>:
    IO.print(id ++ "|body|" ++ body_show(E.view_body(slot_value(W.View,saved))))
    IO.print(id ++ "|clock|" ++ Nat.show(tick) ++ "|" ++ Nat.show(time) ++ "|" ++ flag(paused) ++ "|" ++ flag(daylight) ++ "|" ++ Nat.show(revision) ++ "|" ++ Nat.show(Q.length(C.Mutation,pending)) ++ "|" ++ Nat.show(List.length(&2,C.CoreEvent,events)) ++ "|" ++ U32.show(count))
    IO.print(id ++ "|queue|" ++ pending_show(pending) ++ "|" ++ events_show(events))
    IO.print(id ++ "|view|" ++ view(slot_value(W.View,saved)))
    report_sections(id,saved,registry,tick,time,paused,daylight,revision,count,pending,events,sections_snapshot(sections))

def report_taken(id:String,result:G.Engine & W.View) -> IO(W.State):
  (engine,view) = result
  report_engine(id,engine,Slot{view,[]})

def report(id:String,world:W.State) -> IO(W.State):
  report_taken(id,W.take(world))

def reads(values: List<&2, E.Read>) -> String:
  match values:
    case Nil{}: ""
    case E.Read{point, state} <> rest: position(point) ++ "," ++ U32.show(state) ++ ";" ++ reads(rest)

def yielded(value: Maybe<&2, A.AABB>) -> String:
  match value:
    case None{}: "none"
    case Some{box}: box_show(box)

def x_queries(+id:String,values:List<&2,X.QueryRecord>,+index:Nat) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case X.QueryRecord{pose,E.QueryRecord{box,clear,hit,observed}} <> rest:
      do IO<Unit>:
        IO.print(id ++ "|query|" ++ Nat.show(index) ++ "|" ++ U32.show(P.pose_id(pose)) ++ "|" ++ box_show(box) ++ "|" ++ flag(clear) ++ "|" ++ yielded(hit) ++ "|" ++ reads(observed))
        x_queries(id,rest,1n+index)

def observation_transition(observation:X.Observation) -> P.Transition:
  X.Observation{transition,queries,tail} = observation
  transition

def observation_queries(observation:X.Observation) -> List<&2,X.QueryRecord>:
  X.Observation{transition,queries,tail} = observation
  queries

def desired_show(value: Maybe<&2, P.Pose>) -> String:
  match value:
    case None{}: "none"
    case Some{pose}: U32.show(P.pose_id(pose))

def records_show(value: List<&2, P.QueryRecord>) -> String:
  match value:
    case Nil{}: ""
    case P.QueryRecord{pose, box, clear} <> rest:
      U32.show(P.pose_id(pose)) ++ "|" ++ box_show(box) ++ "|" ++ U32.show(Bool.to_u32(clear)) ++ "/" ++ records_show(rest)

def transition_header(transition:P.Transition) -> String:
  P.Transition{state,body,desired,selected,changed,refreshed,queries,tail} = transition
  desired_show(desired) ++ "|" ++ U32.show(P.pose_id(selected)) ++ "|" ++ flag(changed) ++ "|" ++ flag(refreshed) ++ "|" ++ records_show(queries)

def eye_show(state: P.State, body: M.Body) -> String:
  vector_show(P.eye_position(P.Request{state, body, P.Context{P.Flags{False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}}, P.float_bits(1065353216), False{}, P.AdultUnscaledClient{}}, Nil{}}))

def transition_eye(transition:P.Transition) -> String:
  P.Transition{state,body,desired,selected,changed,refreshed,queries,tail} = transition
  eye_show(state,body)

def outcome(+id:String,world:W.State,pose:P.State,status:Result<&2,&2,X.Error,X.Observation>) -> IO(W.State):
  match status:
    case Fail{error}:
      do IO<W.State>:
        IO.print(id ++ "|error|" ++ x_error(error))
        IO.print(id ++ "|pose|" ++ state_complete(pose))
        report(id ++ "-after",world)
    case Done{+observation}:
      do IO<W.State>:
        IO.print(id ++ "|pose|" ++ state_complete(pose))
        IO.print(id ++ "|ok|" ++ transition_header(observation_transition(observation)))
        IO.print(id ++ "|eye|" ++ transition_eye(observation_transition(observation)))
        IO.print(id ++ "|transition-body|" ++ body_show(X.transition_body(observation_transition(observation))))
        x_queries(id,observation_queries(observation),0n)
        report(id ++ "-after",world)

def result_report(id:String,result:W.State & P.State & Result<&2,&2,X.Error,X.Observation>) -> IO(W.State):
  (world,pose,status) = result
  outcome(id,world,pose,status)

def install_body(world:W.State,body:M.Body) -> W.State:
  W.State{engine,old,yaw,pitch,palette,region,cache} = world
  W.State{engine,body,yaw,pitch,palette,region,cache}

def call_case(world:W.State,+fixture:Case) -> IO(W.State):
  Case{+id,+pose,body,+request,tail} = fixture
  do IO<W.State>:
    IO.print(id ++ "-before|pose|" ++ state_complete(pose))
    prior:W.State <- report(id ++ "-before",install_body(world,body))
    result_report(id,X.update_checked(prior,pose,request))

def parsed_case(world:W.State,parsed:Maybe<&2,Case>) -> IO(W.State):
  match parsed:
    case None{}: IO.die(W.State,2,"invalid player-pose-world request")
    case Some{value}: call_case(world,value)

def altered_request(alteration:U32,+request:X.Request) -> X.Request:
  match alteration:
    case 6:
      X.Request{context,environment,fuel,tail} = request
      X.Request{context,environment,fuel,[request]}
    case _: request

def alter_state(+state: P.State, alteration: U32) -> P.State:
  P.State{pose, eye, tail} = state
  match alteration:
    case 1: P.State{pose, P.float_bits(U32.inc(P.raw(eye))), Nil{}}
    case 27: P.State{pose, P.float_bits(2143289344), Nil{}}
    case 4: P.State{P.UnsupportedPose{99}, eye, Nil{}}
    case 5: P.State{pose, eye, state <> Nil{}}
    case _: state

def alter_box(box: A.AABB, alteration: U32) -> A.AABB:
  A.AABB{F.F64{ah, al}, F.F64{bh, bl}, c, d, e, f} = box
  match alteration:
    case 16: A.AABB{F.F64{2146435072, 0}, F.F64{bh, bl}, c, d, e, f}
    case 18: A.AABB{F.F64{ah, al}, F.F64{2147483648, 0}, c, d, e, f}
    case _: A.AABB{F.F64{ah, U32.inc(al)}, F.F64{bh, bl}, c, d, e, f}

def margin_body(body:M.Body,x:U32) -> M.Body:
  M.Body{M.Vec3{old,y,z},box,velocity,+width,+height,ground,horizontal,vertical,below} = body
  +position : M.Vec3 = M.Vec3{F.from_i32(x),y,z}
  M.Body{position,M.make_box(position,width,height),velocity,width,height,ground,horizontal,vertical,below}

def alter_body(+body: M.Body, alteration: U32) -> M.Body:
  M.Body{position, +box, velocity, +width, height, ground, horizontal, vertical, below} = body
  match alteration:
    case 2: M.Body{position, box, velocity, P.float_bits(U32.inc(P.raw(width))), height, ground, horizontal, vertical, below}
    case 3: M.Body{position, alter_box(box, alteration), velocity, width, height, ground, horizontal, vertical, below}
    case 10: M.Body{M.Vec3{F.F64{2146435072, 0}, F.F64{0, 0}, F.F64{0, 0}}, box, velocity, width, height, ground, horizontal, vertical, below}
    case 11: M.Body{position, box, M.Vec3{F.F64{2146959360, 0}, F.F64{0, 0}, F.F64{0, 0}}, width, height, ground, horizontal, vertical, below}
    case 28: M.Body{position, alter_box(box, 16), velocity, width, height, ground, horizontal, vertical, below}
    case 29: M.Body{position, box, velocity, P.float_bits(2139095040), height, ground, horizontal, vertical, below}
    case 32: margin_body(body,2147483647)
    case 33: margin_body(body,2147483648)
    case _: body

def case_values(id:String,+alteration:U32,fuel:Nat,body:Maybe<&2,Slot<M.Body>>,
                pose:Maybe<&2,Slot<P.State>>,context:Maybe<&2,Slot<P.Context>>,
                environment:Maybe<&2,Slot<E.Environment>>) -> Maybe<&2,Case>:
  match body pose context environment:
    case Some{body} Some{pose} Some{context} Some{environment}:
      Some{Case{id,alter_state(slot_value(P.State,pose),alteration),alter_body(slot_value(M.Body,body),alteration),
        altered_request(alteration,X.Request{slot_value(P.Context,context),slot_value(E.Environment,environment),fuel,[]}),[]}}
    case _ _ _ _: None{}

def number(value: Maybe<&2, U32>, rest: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match value rest:
    case Some{word} Some{rest}: Some{word <> rest}
    case _ _: None{}

def numbers(fields: List<&2, String>) -> Maybe<&2, List<&2, U32>>:
  match fields:
    case Nil{}: Some{Nil{}}
    case field <> rest: number(U32.read(field), numbers(rest))

def bit(value: U32) -> Bool:
  U32.is_ne(value, 0)

def parse_body(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, M.Body>:
  match words:
    case Some{xh <> xl <> yh <> yl <> zh <> zl <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> Nil{}}:
      Some{M.Body{M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}, A.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}, M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, P.float_bits(width), P.float_bits(height), bit(ground), bit(horizontal), bit(vertical), bit(below)} }
    case _: None{}

def pose(value: U32) -> P.Pose:
  match value:
    case 0: P.Standing{}
    case 1: P.FallFlying{}
    case 2: P.Sleeping{}
    case 3: P.Swimming{}
    case 4: P.SpinAttack{}
    case 5: P.Crouching{}
    case 7: P.Dying{}
    case _: P.UnsupportedPose{value}

def parse_state(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, P.State>:
  match words:
    case Some{id <> eye <> Nil{}}: Some{P.State{pose(id), P.float_bits(eye), Nil{}}}
    case _: None{}

def mode(value: U32) -> P.Mode:
  match value:
    case 0: P.AdultUnscaledClient{}
    case _: P.UnsupportedLifecycle{}

def mask_bit(mask: U32, flag: U32) -> Bool:
  U32.is_ne(U32.and(mask, flag), 0)

def parse_context(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, P.Context>:
  match words:
    case Some{+mask <> scale <> baby <> admit <> Nil{}}:
      Some{P.Context{P.Flags{mask_bit(mask, 1), mask_bit(mask, 2), mask_bit(mask, 4), mask_bit(mask, 8), mask_bit(mask, 16), mask_bit(mask, 32), mask_bit(mask, 64), mask_bit(mask, 128)}, P.float_bits(scale), bit(baby), mode(admit)}}
    case _: None{}

def parse_environment(fields: List<&2, U32>) -> Maybe<&2, E.Environment>:
  match fields:
    case entities <> border <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}:
      Some{E.Environment{
        W.choose(E.EntityPolicy, E.KnownEmptyEntityCollisions{}, E.UnresolvedEntityCollisions{}, U32.is_eq(entities, 0)),
        W.choose(E.BorderPolicy, E.KnownClearBorderInterior{A.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}}, E.UnresolvedWorldBorder{}, U32.is_eq(border, 0))}}
    case _: None{}

def optional_environment(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, E.Environment>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_environment(fields)

def update_header(id:String,alteration:Maybe<&2,U32>,budget:Maybe<&2,U32>,body:String,pose:String,context:String,environment:String,world:W.State) -> IO(W.State):
  match alteration budget:
    case Some{alteration} Some{budget}:
      parsed_case(world,case_values(id,alteration,U32.to_nat(budget),
        Maybe.map(&2,M.Body,Slot<M.Body>,value => Slot{value,[]},parse_body(numbers(String.split(body,'|')))),
        Maybe.map(&2,P.State,Slot<P.State>,value => Slot{value,[]},parse_state(numbers(String.split(pose,'|')))),
        Maybe.map(&2,P.Context,Slot<P.Context>,value => Slot{value,[]},parse_context(numbers(String.split(context,'|')))),
        Maybe.map(&2,E.Environment,Slot<E.Environment>,value => Slot{value,[]},optional_environment(numbers(String.split(environment,'|'))))))
    case _ _: IO.die(W.State,2,"invalid player-pose-world numeric header")

def mutation_done(registry:B.Registry,saved:Slot<W.View>,result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(W.State):
  match result:
    case (world,Done{unit}): IO.pure(W.State,W.attach(G.Engine{world,registry},slot_value(W.View,saved)))
    case (world,Fail{cause}): IO.die(W.State,3,"player-pose-world mutation:" ++ W.error_text(cause))

def mutation_done_allow_exists(registry:B.Registry,saved:Slot<W.View>,result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(W.State):
  match result:
    case (world,Fail{C.SectionExists{key}}): IO.pure(W.State,W.attach(G.Engine{world,registry},slot_value(W.View,saved)))
    case other: mutation_done(registry,saved,other)

def mutate_world(world:W.State,mutation:C.Mutation) -> IO(W.State):
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  mutation_done(registry,Slot{W.View{body,yaw,pitch,palette,region,cache},[]},C.apply(core,mutation))

def section(world:W.State,x:U32,y:U32,z:U32) -> IO(W.State):
  match world:
    case W.State{G.Engine{core,registry},body,yaw,pitch,Some{W.Palette{+air,+stone,+dirt,+planks}},region,cache}:
      mutation_done_allow_exists(registry,Slot{W.View{body,yaw,pitch,Some{W.Palette{air,stone,dirt,planks}},region,cache},[]},
        C.apply(core,C.SectionCreate{C.Position{"minecraft:overworld",x,y,z},air}))
    case _: IO.die(W.State,3,"player-pose-world section needs palette")

def edit_value(world: W.State, x: U32, y: U32, z: U32, value: U32) -> IO(W.State):
  mutate_world(world, C.BlockSet{C.Position{"minecraft:overworld", x, y, z}, value})

def edit_resolved(x:U32,y:U32,z:U32,core:C.World,saved:Slot<W.View>,
                  result:B.Registry & Result<&2,&2,String,U32>) -> IO(W.State):
  match result:
    case (registry,Fail{error}): IO.die(W.State,3,"player-pose-world edit:" ++ error)
    case (registry,Done{value}): edit_value(W.attach(G.Engine{core,registry},slot_value(W.View,saved)),x,y,z,value)

def snapshot_kept(result: W.State & Result<&2, &2, String, R.Snapshot>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-collision-world snapshot:" ++ error)
    case Done{snapshot}: IO.pure(W.State, world)

def held_pending(world: W.State) -> IO(W.State):
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  mutation_done(registry, Slot{W.View{body, yaw, pitch, palette, region, cache}, []},
    C.admit(core, C.Developer{}, Q.Stamp{100n, 9, 0n}, C.TimeSet{999n}))

def with_palette(view: W.View, palette: W.Palette) -> W.View:
  W.View{body, yaw, pitch, old, region, cache} = view
  W.View{body, yaw, pitch, Some{palette}, region, cache}

def refreshed_palette(core: C.World, saved: W.View,
                      result: B.Registry & Result<&2, &2, E.Error, W.Palette>) -> IO(W.State):
  (registry, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-collision-world palette:" ++ E.error_text(error))
    case Done{palette}: IO.pure(W.State, W.attach(G.Engine{core, registry}, with_palette(saved, palette)))

def seeded_clock(world: W.State) -> IO(W.State):
  do IO<W.State>:
    timed : W.State <- mutate_world(world, C.TimeSet{777n})
    mutate_world(timed, C.DaylightSet{False{}})

def original_special(op: String, world: W.State) -> IO(W.State):
  match op world:
    case "no-palette" W.State{engine, body, yaw, pitch, palette, region, cache}:
      IO.pure(W.State, W.State{engine, body, yaw, pitch, None{}, region, cache})
    case "stale-palette" W.State{engine, body, yaw, pitch, Some{W.Palette{a, b, c, d}}, region, cache}:
      IO.pure(W.State, W.State{engine, body, yaw, pitch, Some{W.Palette{a, c, b, d}}, region, cache})
    case "palette-refresh" W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache}:
      refreshed_palette(core, W.View{body, yaw, pitch, palette, region, cache}, E.current_palette(registry))
    case "running" W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache}:
      IO.pure(W.State, W.State{G.Engine{C.set_paused(core, False{}), registry}, body, yaw, pitch, palette, region, cache})
    case "clock" _: seeded_clock(world)
    case "pending" _: held_pending(world)
    case "warm" _: snapshot_kept(W.snapshot(world, 64, 48))
    case _ _: IO.die(W.State, 2, "invalid local-collision-world scalar")

def event_admitted(registry:B.Registry,saved:Slot<W.View>,result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(W.State):
  match result:
    case (world,Fail{error}): IO.die(W.State,3,"player-pose-world event seed:" ++ W.error_text(error))
    case (world,Done{unit}):
      seeded_clock(W.attach(G.Engine{C.step(world),registry},slot_value(W.View,saved)))

def seed_event(world:W.State) -> IO(W.State):
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  event_admitted(registry,Slot{W.View{body,yaw,pitch,palette,region,cache},[]},
    C.admit(core,C.Developer{},Q.Stamp{1n,8,1n},C.TimeSet{333n}))

def special(op:String,world:W.State) -> IO(W.State):
  match op world:
    case "clear-sections" W.State{G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},body,yaw,pitch,palette,region,cache}:
      IO.pure(W.State,W.State{G.Engine{C.World{tick,time,paused,daylight,revision,count,SM.EmptySections{},pending,events},registry},body,yaw,pitch,palette,region,cache})
    case "invalidate" _: IO.pure(W.State,W.invalidate_cache(world))
    case "seed-event" _: seed_event(world)
    case _ _: original_special(op,world)

def default_block(result: B.Registry & Result<&2, &2, B.Error, B.Block>) -> B.Registry & Result<&2, &2, String, U32>:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, Fail{B.error_text(error)})
    case Done{B.Block{protocol, name, first, count, default_id, properties}}: (registry, Done{default_id})

def edit_glass(x: U32, y: U32, z: U32, world: W.State) -> IO(W.State):
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  edit_resolved(x, y, z, core, Slot{W.View{body, yaw, pitch, palette, region, cache}, []}, default_block(B.Registry.block(registry, "minecraft:glass")))

def edit_material(+kind: U32, x: U32, y: U32, z: U32, world: W.State, palette: W.Palette) -> IO(W.State):
  match kind palette:
    case 4 _: edit_glass(x, y, z, world)
    case _ W.Palette{air, stone, dirt, planks}:
      edit_value(world, x, y, z, W.choose(U32, air, W.choose(U32, stone, W.choose(U32, dirt, planks, U32.is_eq(kind, 2)), U32.is_eq(kind, 1)), U32.is_eq(kind, 0)))

def scalar_numeric(op:String,fields:Maybe<&2,List<&2,U32>>,world:W.State) -> IO(W.State):
  match op fields world:
    case "section" Some{x <> y <> z <> Nil{}} _: section(world,x,y,z)
    case "edit" Some{x <> y <> z <> kind <> Nil{}} W.State{engine,body,yaw,pitch,Some{+palette},region,cache}:
      edit_material(kind,x,y,z,W.State{engine,body,yaw,pitch,Some{palette},region,cache},palette)
    case _ _ _: IO.die(W.State,2,"invalid player-pose-world edit")

def dispatch(parts:List<&2,String>,world:W.State) -> IO(W.State):
  match parts:
    case "update" <> id <> alteration <> budget <> body <> pose <> context <> environment <> Nil{}:
      update_header(id,U32.read(alteration),U32.read(budget),body,pose,context,environment,world)
    case "scalar" <> op <> Nil{}: special(op,world)
    case op <> fields <> Nil{}: scalar_numeric(op,numbers(String.split(fields,'|')),world)
    case _: IO.die(W.State,2,"invalid player-pose-world protocol")

def run_args(args:List<String>,world:W.State) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        next:W.State <- dispatch(String.split(arg,';'),world)
        run_args(rest,next)

def section_setup(n: Nat, +index: U32, +air: U32, world: W.State) -> IO(W.State):
  match n:
    case 0n: IO.pure(W.State, world)
    case 1n+rest:
      x = W.choose(U32, 0, 4294967280, U32.is_eq(U32.and(index, 1), 0))
      y = W.choose(U32, 0, 4294967280, U32.is_eq(U32.and(index, 2), 0))
      z = W.choose(U32, 0, 4294967280, U32.is_eq(U32.and(index, 4), 0))
      do IO<W.State>:
        next : W.State <- mutate_world(world, C.SectionCreate{C.Position{"minecraft:overworld", x, y, z}, air})
        section_setup(rest, U32.inc(index), air, next)

def floor_setup(n: Nat, +index: U32, +stone: U32, world: W.State) -> IO(W.State):
  match n:
    case 0n: IO.pure(W.State, world)
    case 1n+rest:
      x = U32.add(4294967294, U32.mod(index, 5))
      z = U32.add(4294967294, U32.div(index, 5))
      do IO<W.State>:
        next : W.State <- mutate_world(world, C.BlockSet{C.Position{"minecraft:overworld", x, 0, z}, stone})
        floor_setup(rest, U32.inc(index), stone, next)

def fixture_palette(world: W.State, palette: W.Palette) -> IO(W.State):
  W.Palette{air, stone, dirt, planks} = palette
  do IO<W.State>:
    sections : W.State <- section_setup(8n, 0, air, world)
    floor_setup(25n, 0, stone, sections)

def loaded(args:List<String>,result:W.State & Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case (world,Fail{cause}): IO.die(Unit,3,"player-pose-world setup:" ++ cause)
    case (W.State{engine,body,yaw,pitch,Some{+palette},region,cache},Done{unit}):
      do IO<Unit>:
        fixture:W.State <- fixture_palette(W.State{engine,body,0.375,F32.neg(0.25),Some{palette},region,cache},palette)
        clocked:W.State <- seeded_clock(fixture)
        pending:W.State <- held_pending(clocked)
        cached:W.State <- snapshot_kept(W.snapshot(pending,64,48))
        run_args(args,cached)
    case (world,Done{unit}): IO.die(Unit,3,"player-pose-world palette missing")

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> rest:
      do IO<Unit>:
        engine:G.Engine <- G.load()
        loaded(rest,W.new(engine))
    case _: IO.die(Unit,2,"player-pose-world arguments required")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)

def state_show(value: P.State) -> String:
  P.State{pose, eye, tail} = value
  U32.show(P.pose_id(pose)) ++ "|" ++ U32.show(P.raw(eye))

def float_bits(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}
