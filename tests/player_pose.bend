import Base
import ../src/f64.bend as F
import ../src/geometry.bend as G
import ../src/movement.bend as M
import ../src/player_pose.bend as P

# Raw-word protocol avoids the inherited JSON decoder proof boundary.
type Case is Data:
  Case{id: String, alteration: U32, request: P.Request,
       answers: List<&2, P.FitAnswer>, tail: List<&2, Case>}

def bit(value: U32) -> Bool:
  U32.is_ne(value, 0)

def number(value: Maybe<&2, U32>, rest: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match value rest:
    case Some{word} Some{rest}: Some{word <> rest}
    case _ _: None{}

def numbers(fields: List<&2, String>) -> Maybe<&2, List<&2, U32>>:
  match fields:
    case Nil{}: Some{Nil{}}
    case field <> rest: number(U32.read(field), numbers(rest))

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

def mode(value: U32) -> P.Mode:
  match value:
    case 0: P.AdultUnscaledClient{}
    case _: P.UnsupportedLifecycle{}

def parse_body(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, M.Body>:
  match words:
    case Some{xh <> xl <> yh <> yl <> zh <> zl <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> Nil{}}:
      Some{M.Body{M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}, G.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}, M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, P.float_bits(width), P.float_bits(height), bit(ground), bit(horizontal), bit(vertical), bit(below)} }
    case _: None{}

def parse_state(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, P.State>:
  match words:
    case Some{id <> eye <> Nil{}}: Some{P.State{pose(id), P.float_bits(eye), Nil{}}}
    case _: None{}

def mask_bit(mask: U32, flag: U32) -> Bool:
  U32.is_ne(U32.and(mask, flag), 0)

def parse_context(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, P.Context>:
  match words:
    case Some{+mask <> scale <> baby <> admit <> Nil{}}:
      Some{P.Context{P.Flags{mask_bit(mask, 1), mask_bit(mask, 2), mask_bit(mask, 4), mask_bit(mask, 8), mask_bit(mask, 16), mask_bit(mask, 32), mask_bit(mask, 64), mask_bit(mask, 128)}, P.float_bits(scale), bit(baby), mode(admit)}}
    case _: None{}

def request(body: Maybe<&2, M.Body>, state: Maybe<&2, P.State>, context: Maybe<&2, P.Context>) -> Maybe<&2, P.Request>:
  match body state context:
    case Some{body} Some{state} Some{context}: Some{P.Request{state, body, context, Nil{}}}
    case _ _ _: None{}

def query_answer(kind: U32, clear: U32) -> Result<&2, &2, String, Bool>:
  match kind:
    case 0: Done{bit(clear)}
    case _: Fail{"fixture-refusal"}

def parse_answer(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, P.FitAnswer>:
  match words:
    case Some{id <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> kind <> clear <> Nil{}}:
      Some{P.FitAnswer{pose(id), G.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}, query_answer(kind, clear)}}
    case _: None{}

def answers_cons(head: Maybe<&2, P.FitAnswer>, tail: Maybe<&2, List<&2, P.FitAnswer>>) -> Maybe<&2, List<&2, P.FitAnswer>>:
  match head tail:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def parse_answers(parts: List<&2, String>) -> Maybe<&2, List<&2, P.FitAnswer>>:
  match parts:
    case Nil{}: Some{Nil{}}
    case head <> rest: answers_cons(parse_answer(numbers(String.split(head, '|'))), parse_answers(rest))

def answers(text: String) -> Maybe<&2, List<&2, P.FitAnswer>>:
  match text:
    case "": Some{Nil{}}
    case _: parse_answers(String.split(text, '/'))

def f64_show(value: F.F64) -> String:
  F.F64{hi, lo} = value
  U32.show(hi) ++ "|" ++ U32.show(lo)

def vector_show(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  f64_show(x) ++ "|" ++ f64_show(y) ++ "|" ++ f64_show(z)

def box_show(value: G.AABB) -> String:
  G.AABB{a, b, c, d, e, f} = value
  f64_show(a) ++ "|" ++ f64_show(b) ++ "|" ++ f64_show(c) ++ "|" ++ f64_show(d) ++ "|" ++ f64_show(e) ++ "|" ++ f64_show(f)

def body_show(value: M.Body) -> String:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = value
  vector_show(position) ++ "|" ++ box_show(box) ++ "|" ++ vector_show(velocity) ++ "|" ++ U32.show(P.raw(width)) ++ "|" ++ U32.show(P.raw(height)) ++ "|" ++ U32.show(Bool.to_u32(ground)) ++ "|" ++ U32.show(Bool.to_u32(horizontal)) ++ "|" ++ U32.show(Bool.to_u32(vertical)) ++ "|" ++ U32.show(Bool.to_u32(below))

def state_show(value: P.State) -> String:
  P.State{pose, eye, tail} = value
  U32.show(P.pose_id(pose)) ++ "|" ++ U32.show(P.raw(eye))

def desired_show(value: Maybe<&2, P.Pose>) -> String:
  match value:
    case None{}: "none"
    case Some{pose}: U32.show(P.pose_id(pose))

def records_show(value: List<&2, P.QueryRecord>) -> String:
  match value:
    case Nil{}: ""
    case P.QueryRecord{pose, box, clear} <> rest:
      U32.show(P.pose_id(pose)) ++ "|" ++ box_show(box) ++ "|" ++ U32.show(Bool.to_u32(clear)) ++ "/" ++ records_show(rest)

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

def eye_show(state: P.State, body: M.Body) -> String:
  vector_show(P.eye_position(P.Request{state, body, P.Context{P.Flags{False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}}, P.float_bits(1065353216), False{}, P.AdultUnscaledClient{}}, Nil{}}))

def result_show(result: Result<&2, &2, P.Error, P.Transition>) -> String:
  match result:
    case Fail{error}: "error;" ++ error_show(error)
    case Done{P.Transition{+state, +body, desired, selected, changed, refreshed, queries, tail}}:
      "ok;" ++ state_show(state) ++ ";" ++ body_show(body) ++ ";" ++ desired_show(desired) ++ ";" ++ U32.show(P.pose_id(selected)) ++ ";" ++ U32.show(Bool.to_u32(changed)) ++ ";" ++ U32.show(Bool.to_u32(refreshed)) ++ ";" ++ records_show(queries) ++ ";" ++ eye_show(state, body)

def original_show(request: P.Request) -> String:
  P.Request{state, body, context, tail} = request
  state_show(state) ++ ";" ++ body_show(body)

def alter_state(+state: P.State, alteration: U32) -> P.State:
  P.State{pose, eye, tail} = state
  match alteration:
    case 1: P.State{pose, P.float_bits(U32.inc(P.raw(eye))), Nil{}}
    case 27: P.State{pose, P.float_bits(2143289344), Nil{}}
    case 4: P.State{P.UnsupportedPose{99}, eye, Nil{}}
    case 5: P.State{pose, eye, state <> Nil{}}
    case _: state

def alter_box(box: G.AABB, alteration: U32) -> G.AABB:
  G.AABB{F.F64{ah, al}, F.F64{bh, bl}, c, d, e, f} = box
  match alteration:
    case 16: G.AABB{F.F64{2146435072, 0}, F.F64{bh, bl}, c, d, e, f}
    case 18: G.AABB{F.F64{ah, al}, F.F64{2147483648, 0}, c, d, e, f}
    case _: G.AABB{F.F64{ah, U32.inc(al)}, F.F64{bh, bl}, c, d, e, f}

def alter_body(+body: M.Body, alteration: U32) -> M.Body:
  M.Body{position, +box, velocity, +width, height, ground, horizontal, vertical, below} = body
  match alteration:
    case 2: M.Body{position, box, velocity, P.float_bits(U32.inc(P.raw(width))), height, ground, horizontal, vertical, below}
    case 3: M.Body{position, alter_box(box, alteration), velocity, width, height, ground, horizontal, vertical, below}
    case 10: M.Body{M.Vec3{F.F64{2146435072, 0}, F.F64{0, 0}, F.F64{0, 0}}, box, velocity, width, height, ground, horizontal, vertical, below}
    case 11: M.Body{position, box, M.Vec3{F.F64{2146959360, 0}, F.F64{0, 0}, F.F64{0, 0}}, width, height, ground, horizontal, vertical, below}
    case 28: M.Body{position, alter_box(box, 16), velocity, width, height, ground, horizontal, vertical, below}
    case 29: M.Body{position, box, velocity, P.float_bits(2139095040), height, ground, horizontal, vertical, below}
    case _: body

def alter_context(context: P.Context, alteration: U32) -> P.Context:
  P.Context{flags, scale, baby, mode} = context
  match alteration:
    case 7: P.Context{flags, P.float_bits(1073741824), baby, mode}
    case 8: P.Context{flags, scale, True{}, mode}
    case 9: P.Context{flags, scale, baby, P.UnsupportedLifecycle{}}
    case _: P.Context{flags, scale, baby, mode}

def alter_request(+request: P.Request, +alteration: U32) -> P.Request:
  P.Request{state, body, context, tail} = request
  match alteration:
    case 6: P.Request{state, body, context, request <> Nil{}}
    case _: P.Request{alter_state(state, alteration), alter_body(body, alteration), alter_context(context, alteration), Nil{}}

def drop_last(values: List<&2, P.FitAnswer>) -> List<&2, P.FitAnswer>:
  match values:
    case Nil{}: Nil{}
    case head <> Nil{}: Nil{}
    case head <> rest: head <> drop_last(rest)

def alter_answer(answer: P.FitAnswer, +alteration: U32) -> P.FitAnswer:
  P.FitAnswer{pose, box, clear} = answer
  match alteration:
    case 14: P.FitAnswer{P.Dying{}, box, clear}
    case 15: P.FitAnswer{pose, alter_box(box, alteration), clear}
    case 16: P.FitAnswer{pose, alter_box(box, alteration), clear}
    case 17: P.FitAnswer{pose, box, Fail{"fixture-refusal"}}
    case 18: P.FitAnswer{pose, alter_box(box, alteration), clear}
    case _: P.FitAnswer{pose, box, clear}

def alter_answers(+answers: List<&2, P.FitAnswer>, +alteration: U32) -> List<&2, P.FitAnswer>:
  match answers alteration:
    case _ 12: drop_last(answers)
    case head <> rest 13: List.append(&2, P.FitAnswer, answers, head <> Nil{})
    case head <> rest _: alter_answer(head, alteration) <> rest
    case Nil{} _: Nil{}

def forged_work(work: P.Work, alteration: U32) -> P.Work:
  P.Work{request, phase, desired, P.FitQuery{pose, +box}, history} = work
  match alteration:
    case 20: P.Work{request, P.Desired{}, desired, P.FitQuery{pose, box}, history}
    case 21: P.Work{request, phase, Some{P.Standing{}}, P.FitQuery{pose, box}, history}
    case 22: P.Work{request, phase, desired, P.FitQuery{pose, alter_box(box, 15)}, history}
    case 25: P.Work{alter_request(request, 2), phase, desired, P.FitQuery{pose, box}, history}
    case 26: P.Work{request, phase, desired, P.FitQuery{pose, box}, P.QueryRecord{P.Swimming{}, box, True{}} <> history}
    case _: P.Work{request, phase, desired, P.FitQuery{pose, box}, history}

def forge(+progress: P.Progress, alteration: U32) -> P.Progress:
  match progress alteration:
    case P.Query{work, Nil{}} 19: P.Query{work, progress <> Nil{}}
    case P.Query{work, Nil{}} _: P.Query{forged_work(work, alteration), Nil{}}
    case _ _: progress

def forged_result(progress: Result<&2, &2, P.Error, P.Progress>, answers: List<&2, P.FitAnswer>, alteration: U32) -> Result<&2, &2, P.Error, P.Transition>:
  match progress answers:
    case Fail{error} _: Fail{error}
    case Done{progress} answer <> rest: P.replay(rest, P.answer_checked(forge(progress, alteration), answer))
    case _ _: Fail{P.MissingObservation{}}

def finished_probe_progress(+transition: P.Transition, answer: P.FitAnswer, tail: Bool) -> Result<&2, &2, P.Error, P.Transition>:
  match tail:
    case True{}: P.replay(Nil{}, P.answer_checked(P.Finished{transition, P.Finished{transition, Nil{}} <> Nil{}}, answer))
    case False{}: P.replay(Nil{}, P.answer_checked(P.Finished{transition, Nil{}}, answer))

def finished_probe(result: Result<&2, &2, P.Error, P.Transition>, answer: P.FitAnswer, tail: Bool) -> Result<&2, &2, P.Error, P.Transition>:
  match result:
    case Fail{error}: Fail{error}
    case Done{transition}: finished_probe_progress(transition, answer, tail)


def observe_finished(result: Result<&2, &2, P.Error, P.Transition>, answers: List<&2, P.FitAnswer>, alteration: U32) -> Result<&2, &2, P.Error, P.Transition>:
  match answers:
    case answer <> rest: finished_probe(result, answer, U32.is_eq(alteration, 23))
    case _: Fail{P.MissingObservation{}}

def observe(+request: P.Request, +answers: List<&2, P.FitAnswer>, +alteration: U32) -> Result<&2, &2, P.Error, P.Transition>:
  match alteration:
    case 19: forged_result(P.begin_checked(request), answers, alteration)
    case 20: forged_result(P.begin_checked(request), answers, alteration)
    case 21: forged_result(P.begin_checked(request), answers, alteration)
    case 22: forged_result(P.begin_checked(request), answers, alteration)
    case 23: observe_finished(P.replay_checked(request, answers), answers, alteration)
    case 24: observe_finished(P.replay_checked(request, answers), answers, alteration)
    case 25: forged_result(P.begin_checked(request), answers, alteration)
    case 26: forged_result(P.begin_checked(request), answers, alteration)
    case _: P.replay_checked(alter_request(request, alteration), alter_answers(answers, alteration))

def execute(value: Case) -> IO(Unit):
  Case{+id, +alteration, +request, +answers, tail} = value
  do IO<Unit>:
    IO.print(id ++ ";" ++ result_show(observe(request, answers, alteration)))
    IO.print(id ++ ";original;" ++ original_show(request))
    IO.print(id ++ ";recovery;" ++ result_show(P.replay_checked(request, answers)))

def parsed(id: String, alteration: Maybe<&2, U32>, request: Maybe<&2, P.Request>, answers: Maybe<&2, List<&2, P.FitAnswer>>) -> IO(Unit):
  match alteration request answers:
    case Some{alteration} Some{request} Some{answers}: execute(Case{id, alteration, request, answers, Nil{}})
    case _ _ _: IO.die(Unit, 2, "invalid player pose fixture")

def metadata_show(result: Result<&2, &2, P.Error, P.Metadata>) -> String:
  match result:
    case Fail{error}: "error;" ++ error_show(error)
    case Done{P.Metadata{width, height, eye, fixed}}:
      "meta;" ++ U32.show(P.raw(width)) ++ "|" ++ U32.show(P.raw(height)) ++ "|" ++ U32.show(P.raw(eye)) ++ "|" ++ U32.show(Bool.to_u32(fixed))

def meta(id: String, word: Maybe<&2, U32>) -> IO(Unit):
  match word:
    case Some{word}: IO.print(id ++ ";" ++ metadata_show(P.metadata(pose(word))))
    case _: IO.die(Unit, 2, "invalid player pose metadata fixture")

def entry(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case "meta" <> id <> word <> Nil{}: meta(id, U32.read(word))
    case id <> alteration <> body <> state <> context <> observations <> Nil{}:
      parsed(id, U32.read(alteration), request(parse_body(numbers(String.split(body, '|'))), parse_state(numbers(String.split(state, '|'))), parse_context(numbers(String.split(context, '|')))), answers(observations))
    case _: IO.die(Unit, 2, "invalid player pose argument framing")

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        entry(String.split(arg, ';'))
        batch(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1, String, args))
