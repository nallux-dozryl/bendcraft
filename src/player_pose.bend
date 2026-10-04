import Base
import ./f64.bend as F
import ./geometry.bend as G
import ./movement.bend as M

# Conditional Player.updatePlayerPose phase only. This module owns no world.
type Pose is Data:
  Standing{}
  FallFlying{}
  Sleeping{}
  Swimming{}
  SpinAttack{}
  Crouching{}
  Dying{}
  UnsupportedPose{id: U32}

type Mode is Data:
  AdultUnscaledClient{}
  UnsupportedLifecycle{}

type Metadata is Data:
  Metadata{width: F32, height: F32, eye_height: F32, fixed: Bool}

# Pose and cached eye only; Request.body remains the single body authority.
# Recursive tails box the native ABI and must always be empty.
type State is Data:
  State{pose: Pose, eye_height: F32, tail: List<&2, State>}

type Flags is Data:
  Flags{sleeping: Bool, swimming: Bool, fall_flying: Bool,
        auto_spin_attack: Bool, shift: Bool, flying: Bool,
        spectator: Bool, passenger: Bool}

type Context is Data:
  Context{flags: Flags, scale: F32, baby: Bool, mode: Mode}

type Request is Data:
  Request{state: State, body: M.Body, context: Context,
          tail: List<&2, Request>}

type Error is Data:
  NonCanonicalTail{owner: U32}
  UnsupportedContext{}
  UnsupportedScale{}
  UnsupportedAge{}
  UnknownPose{id: U32}
  InvalidBody{cause: M.Error}
  StaleDimensions{}
  StaleEyeHeight{}
  StaleBox{}
  InvalidQuery{field: U32}
  MismatchedPose{}
  MismatchedQuery{}
  QueryDenied{reason: String}
  MissingObservation{}
  ExtraObservations{}
  UnexpectedAnswer{}
  InvalidProgress{}

type FitQuery is Data:
  FitQuery{pose: Pose, box: G.AABB}

type FitAnswer is Data:
  FitAnswer{pose: Pose, box: G.AABB,
            answer: Result<&2, &2, String, Bool>}

type QueryRecord is Data:
  QueryRecord{pose: Pose, box: G.AABB, clear: Bool}

type Phase is Data:
  InitialSwimming{}
  Desired{}
  FallbackCrouching{}

type Work is Data:
  Work{request: Request, phase: Phase, desired: Maybe<&2, Pose>,
       query: FitQuery, history: List<&2, QueryRecord>}

type Transition is Data:
  Transition{state: State, body: M.Body, desired: Maybe<&2, Pose>,
             selected: Pose, changed: Bool, refreshed: Bool,
             queries: List<&2, QueryRecord>, tail: List<&2, Transition>}

type Progress is Data:
  Query{work: Work, tail: List<&2, Progress>}
  Finished{transition: Transition, tail: List<&2, Progress>}

def float_bits(bits: U32) -> F32:
  match bits:
    case U32{word}: F32{word}

def raw(value: F32) -> U32:
  match value:
    case F32{word}: U32{word}

def same_float(a: F32, b: F32) -> Bool:
  U32.is_eq(raw(a), raw(b))

def pose_id(pose: Pose) -> U32:
  match pose:
    case Standing{}: 0
    case FallFlying{}: 1
    case Sleeping{}: 2
    case Swimming{}: 3
    case SpinAttack{}: 4
    case Crouching{}: 5
    case Dying{}: 7
    case UnsupportedPose{id}: id

def same_pose(a: Pose, b: Pose) -> Bool:
  match a b:
    case UnsupportedPose{x} UnsupportedPose{y}: U32.is_eq(x, y)
    case UnsupportedPose{x} _: False{}
    case _ UnsupportedPose{y}: False{}
    case _ _: U32.is_eq(pose_id(a), pose_id(b))

# Actual Avatar dimensions/eye values, not an eye/body-height ratio.
def metadata(pose: Pose) -> Result<&2, &2, Error, Metadata>:
  match pose:
    case Standing{}: Done{Metadata{float_bits(1058642330), float_bits(1072064102), float_bits(1070554153), False{}}}
    case Crouching{}: Done{Metadata{float_bits(1058642330), float_bits(1069547520), float_bits(1067618140), False{}}}
    case Sleeping{}: Done{Metadata{float_bits(1045220557), float_bits(1045220557), float_bits(1045220557), True{}}}
    case Dying{}: Done{Metadata{float_bits(1045220557), float_bits(1045220557), float_bits(1070554153), True{}}}
    case UnsupportedPose{id}: Fail{UnknownPose{id}}
    case _: Done{Metadata{float_bits(1058642330), float_bits(1058642330), float_bits(1053609165), False{}}}

def same_box(a: G.AABB, b: G.AABB) -> Bool:
  match a b:
    case G.AABB{a0, a1, a2, a3, a4, a5} G.AABB{b0, b1, b2, b3, b4, b5}:
      M.same_bits(a0, b0) && M.same_bits(a1, b1) && M.same_bits(a2, b2) && M.same_bits(a3, b3) && M.same_bits(a4, b4) && M.same_bits(a5, b5)

def first(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def gate_error(error: Error, valid: Bool) -> Maybe<&2, Error>:
  match valid:
    case True{}: None{}
    case False{}: Some{error}

def body_error(error: Maybe<&2, M.Error>) -> Maybe<&2, Error>:
  match error:
    case None{}: None{}
    case Some{cause}: Some{InvalidBody{cause}}

def context_error(context: Context) -> Maybe<&2, Error>:
  match context:
    case Context{flags, scale, baby, UnsupportedLifecycle{}}: Some{UnsupportedContext{}}
    case Context{flags, scale, True{}, AdultUnscaledClient{}}: Some{UnsupportedAge{}}
    case Context{flags, scale, False{}, AdultUnscaledClient{}}:
      gate_error(UnsupportedScale{}, U32.is_eq(raw(scale), 1065353216))

def coherent_fields(state: State, body: M.Body, values: Metadata) -> Maybe<&2, Error>:
  match state body values:
    case State{pose, eye, tail} M.Body{+position, box, velocity, +width, +height, grounded, horizontal, vertical, below} Metadata{+expected_width, +expected_height, expected_eye, fixed}:
      first(gate_error(StaleDimensions{}, same_float(width, expected_width) && same_float(height, expected_height)),
        first(gate_error(StaleEyeHeight{}, same_float(eye, expected_eye)),
          gate_error(StaleBox{}, same_box(box, M.make_box(position, expected_width, expected_height)))))

def coherent_metadata(state: State, body: M.Body, values: Result<&2, &2, Error, Metadata>) -> Maybe<&2, Error>:
  match values:
    case Fail{error}: Some{error}
    case Done{values}: coherent_fields(state, body, values)

def state_error(state: State, +body: M.Body) -> Maybe<&2, Error>:
  match state:
    case State{pose, eye, _ <> _}: Some{NonCanonicalTail{0}}
    case State{+pose, +eye, Nil{}}:
      first(body_error(M.Body.invalid(body)), coherent_metadata(State{pose, eye, Nil{}}, body, metadata(pose)))

def request_error(request: Request) -> Maybe<&2, Error>:
  match request:
    case Request{state, body, context, _ <> _}: Some{NonCanonicalTail{1}}
    case Request{state, body, context, Nil{}}:
      first(context_error(context), state_error(state, body))

def desired_flags(flags: Flags) -> Pose:
  match flags:
    case Flags{True{}, swimming, gliding, spin, shift, flying, spectator, passenger}: Sleeping{}
    case Flags{False{}, True{}, gliding, spin, shift, flying, spectator, passenger}: Swimming{}
    case Flags{False{}, False{}, True{}, spin, shift, flying, spectator, passenger}: FallFlying{}
    case Flags{False{}, False{}, False{}, True{}, shift, flying, spectator, passenger}: SpinAttack{}
    case Flags{False{}, False{}, False{}, False{}, True{}, False{}, spectator, passenger}: Crouching{}
    case _: Standing{}

def fit_query(position: M.Vec3, pose: Pose, values: Metadata) -> FitQuery:
  match values:
    case Metadata{width, height, eye, fixed}:
      FitQuery{pose, G.AABB.deflate(M.make_box(position, width, height), G.epsilon(), G.epsilon(), G.epsilon())}

def position(request: Request) -> M.Vec3:
  Request{state, M.Body{position, box, velocity, width, height, grounded, horizontal, vertical, below}, context, tail} = request
  position

def query_values(+request: Request, pose: Pose, phase: Phase, desired: Maybe<&2, Pose>, history: List<&2, QueryRecord>, values: Result<&2, &2, Error, Metadata>) -> Result<&2, &2, Error, Progress>:
  match values:
    case Fail{error}: Fail{error}
    case Done{values}:
      Done{Query{Work{request, phase, desired, fit_query(position(request), pose, values), history}, Nil{}}}

def query(request: Request, +pose: Pose, phase: Phase, desired: Maybe<&2, Pose>, history: List<&2, QueryRecord>) -> Result<&2, &2, Error, Progress>:
  query_values(request, pose, phase, desired, history, metadata(pose))

def begin_gate(request: Request, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Progress>:
  match error:
    case Some{error}: Fail{error}
    case None{}: query(request, Swimming{}, InitialSwimming{}, None{}, Nil{})

def begin_checked(+request: Request) -> Result<&2, &2, Error, Progress>:
  begin_gate(request, request_error(request))

def eye_position(request: Request) -> M.Vec3:
  Request{State{pose, eye, tail}, M.Body{M.Vec3{x, y, z}, box, velocity, width, height, grounded, horizontal, vertical, below}, context, request_tail} = request
  M.Vec3{x, F.add(y, F.from_f32(eye)), z}

def eye_gate(request: Request, error: Maybe<&2, Error>) -> Result<&2, &2, Error, M.Vec3>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{eye_position(request)}

def eye_position_checked(+request: Request) -> Result<&2, &2, Error, M.Vec3>:
  eye_gate(request, request_error(request))

# A changed client pose refreshes dimensions and re-applies the same feet.
# Keep every velocity/flag field; Body.new would reset collision flags.
def resize_body(body: M.Body, values: Metadata) -> M.Body:
  match body values:
    case M.Body{+position, old_box, velocity, old_width, old_height, grounded, horizontal, vertical, below} Metadata{+width, +height, eye, fixed}:
      M.Body{position, M.make_box(position, width, height), velocity, width, height, grounded, horizontal, vertical, below}

def finish_metadata(request: Request, desired: Maybe<&2, Pose>, +selected: Pose, history: List<&2, QueryRecord>, values: Metadata) -> Result<&2, &2, Error, Progress>:
  Request{state, body, context, tail} = request
  Metadata{+width, +height, +eye, +fixed} = values
  Done{Finished{Transition{State{selected, eye, Nil{}}, resize_body(body, Metadata{width, height, eye, fixed}), desired, selected, True{}, True{}, history, Nil{}}, Nil{}}}

def finish_unchanged(request: Request, desired: Maybe<&2, Pose>, selected: Pose, history: List<&2, QueryRecord>) -> Result<&2, &2, Error, Progress>:
  Request{state, body, context, tail} = request
  Done{Finished{Transition{state, body, desired, selected, False{}, False{}, history, Nil{}}, Nil{}}}

def finish_changed(request: Request, desired: Maybe<&2, Pose>, selected: Pose, history: List<&2, QueryRecord>, values: Result<&2, &2, Error, Metadata>) -> Result<&2, &2, Error, Progress>:
  match values:
    case Fail{error}: Fail{error}
    case Done{values}: finish_metadata(request, desired, selected, history, values)



def finish_gate(request: Request, desired: Maybe<&2, Pose>, +selected: Pose, history: List<&2, QueryRecord>, changed: Bool) -> Result<&2, &2, Error, Progress>:
  match changed:
    case False{}: finish_unchanged(request, desired, selected, history)
    case True{}: finish_changed(request, desired, selected, history, metadata(selected))

def finish(+request: Request, desired: Maybe<&2, Pose>, +selected: Pose, history: List<&2, QueryRecord>) -> Result<&2, &2, Error, Progress>:
  Request{State{pose, eye, state_tail}, body, context, tail} = request
  finish_gate(request, desired, selected, history, Bool.not(same_pose(pose, selected)))

def desired_gate(request: Request, +desired: Pose, history: List<&2, QueryRecord>, exempt: Bool) -> Result<&2, &2, Error, Progress>:
  match exempt:
    case True{}: finish(request, Some{desired}, desired, history)
    case False{}: query(request, desired, Desired{}, Some{desired}, history)

def early_return(+request: Request, history: List<&2, QueryRecord>) -> Result<&2, &2, Error, Progress>:
  Request{State{pose, eye, state_tail}, body, context, tail} = request
  finish(request, None{}, pose, history)

def start_desired(+request: Request, history: List<&2, QueryRecord>) -> Result<&2, &2, Error, Progress>:
  Request{state, body, Context{+flags, scale, baby, mode}, tail} = request
  Flags{sleeping, swimming, gliding, spin, shift, flying, spectator, passenger} = flags
  desired_gate(request, desired_flags(flags), history, spectator || passenger)

def append_record(history: List<&2, QueryRecord>, record: QueryRecord) -> List<&2, QueryRecord>:
  match history:
    case Nil{}: record <> Nil{}
    case first <> rest: first <> append_record(rest, record)

def after_initial(request: Request, history: List<&2, QueryRecord>, clear: Bool) -> Result<&2, &2, Error, Progress>:
  match clear:
    case False{}: early_return(request, history)
    case True{}: start_desired(request, history)



def advance_phase(request: Request, phase: Phase, desired: Maybe<&2, Pose>, pose: Pose, history: List<&2, QueryRecord>, clear: Bool) -> Result<&2, &2, Error, Progress>:
  match phase clear:
    case InitialSwimming{} _: after_initial(request, history, clear)
    case Desired{} True{}: finish(request, desired, pose, history)
    case Desired{} False{}: query(request, Crouching{}, FallbackCrouching{}, desired, history)
    case FallbackCrouching{} True{}: finish(request, desired, Crouching{}, history)
    case FallbackCrouching{} False{}: finish(request, desired, Swimming{}, history)

def advance(work: Work, +clear: Bool) -> Result<&2, &2, Error, Progress>:
  match work:
    case Work{request, phase, desired, FitQuery{+pose, box}, history}:
      advance_phase(request, phase, desired, pose, append_record(history, QueryRecord{pose, box, clear}), clear)


def query_finite(field: Maybe<&2, U32>) -> Maybe<&2, Error>:
  match field:
    case Some{field}: Some{InvalidQuery{field}}
    case None{}: None{}

def query_error(expected: FitQuery, observed: FitAnswer) -> Maybe<&2, Error>:
  match expected observed:
    case FitQuery{pose, box} FitAnswer{observed_pose, +observed_box, answer}:
      first(query_finite(G.AABB.invalid_field(observed_box)),
        first(gate_error(MismatchedPose{}, same_pose(pose, observed_pose)),
          gate_error(MismatchedQuery{}, same_box(box, observed_box))))


def answer_valid(work: Work, answer: Result<&2, &2, String, Bool>) -> Result<&2, &2, Error, Progress>:
  match answer:
    case Fail{reason}: Fail{QueryDenied{reason}}
    case Done{clear}: advance(work, clear)

def answer_payload(work: Work, answer: FitAnswer) -> Result<&2, &2, Error, Progress>:
  FitAnswer{pose, box, answer} = answer
  answer_valid(work, answer)

def answer_gate(work: Work, answer: FitAnswer, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Progress>:
  match error:
    case Some{error}: Fail{error}
    case None{}: answer_payload(work, answer)


def expected(work: Work) -> FitQuery:
  Work{request, phase, desired, query, history} = work
  query

# Validate public progress by rebuilding its exact finite prefix. Callers may
# construct Data, but cannot forge a phase, desired pose or candidate box.
def prefix(history: List<&2, QueryRecord>, progress: Result<&2, &2, Error, Progress>) -> Result<&2, &2, Error, Progress>:
  match history progress:
    case _ Fail{error}: Fail{error}
    case Nil{} _: progress
    case _ Done{Finished{transition, tail}}: Fail{InvalidProgress{}}
    case QueryRecord{+pose, +box, +clear} <> rest Done{Query{+work, tail}}:
      prefix(rest, answer_gate(work, FitAnswer{pose, box, Done{clear}}, query_error(expected(work), FitAnswer{pose, box, Done{clear}})))

def same_phase(a: Phase, b: Phase) -> Bool:
  match a b:
    case InitialSwimming{} InitialSwimming{}: True{}
    case Desired{} Desired{}: True{}
    case FallbackCrouching{} FallbackCrouching{}: True{}
    case _ _: False{}

def same_desired(a: Maybe<&2, Pose>, b: Maybe<&2, Pose>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{a} Some{b}: same_pose(a, b)
    case _ _: False{}

def work_matches(work: Work, prior: Work) -> Maybe<&2, Error>:
  match work prior:
    case Work{request, phase, desired, FitQuery{pose, box}, history} Work{prior_request, prior_phase, prior_desired, FitQuery{prior_pose, prior_box}, prior_history}:
      gate_error(InvalidProgress{}, same_phase(phase, prior_phase) && same_desired(desired, prior_desired) && same_pose(pose, prior_pose) && same_box(box, prior_box))

def progress_matches(work: Work, rebuilt: Result<&2, &2, Error, Progress>) -> Maybe<&2, Error>:
  match rebuilt:
    case Fail{error}: Some{error}
    case Done{Finished{transition, tail}}: Some{InvalidProgress{}}
    case Done{Query{prior, tail}}: work_matches(work, prior)


def work_error(+work: Work) -> Maybe<&2, Error>:
  Work{+request, phase, desired, query, +history} = work
  progress_matches(work, prefix(history, begin_checked(request)))

def answer_checked(progress: Progress, +answer: FitAnswer) -> Result<&2, &2, Error, Progress>:
  match progress:
    case Query{work, _ <> _}: Fail{NonCanonicalTail{2}}
    case Finished{transition, _ <> _}: Fail{NonCanonicalTail{2}}
    case Finished{transition, Nil{}}: Fail{UnexpectedAnswer{}}
    case Query{+work, Nil{}}:
      answer_gate(work, answer, first(work_error(work), query_error(expected(work), answer)))

def replay(answers: List<&2, FitAnswer>, progress: Result<&2, &2, Error, Progress>) -> Result<&2, &2, Error, Transition>:
  match answers progress:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{Finished{transition, Nil{}}}: Done{transition}
    case _ Done{Finished{transition, _ <> _}}: Fail{NonCanonicalTail{2}}
    case _ Done{Finished{transition, Nil{}}}: Fail{ExtraObservations{}}
    case Nil{} Done{Query{work, tail}}: Fail{MissingObservation{}}
    case answer <> rest Done{progress}: replay(rest, answer_checked(progress, answer))

def replay_checked(request: Request, answers: List<&2, FitAnswer>) -> Result<&2, &2, Error, Transition>:
  replay(answers, begin_checked(request))

law invalid_admission_does_not_query:
  for request: Request
  for +error: Error
  {begin_gate(request, Some{error}) == Fail{error} : Result<&2, &2, Error, Progress>}

def invalid_admission_does_not_query(request, error):
  {==}

law query_refusal_does_not_advance:
  for work: Work
  for +reason: String
  {answer_valid(work, Fail{reason}) == Fail{QueryDenied{reason}} : Result<&2, &2, Error, Progress>}

def query_refusal_does_not_advance(work, reason):
  {==}

law mismatched_observation_does_not_advance:
  for work: Work
  for answer: FitAnswer
  for +error: Error
  {answer_gate(work, answer, Some{error}) == Fail{error} : Result<&2, &2, Error, Progress>}

def mismatched_observation_does_not_advance(work, answer, error):
  {==}

law unchanged_pose_retains_entire_state_and_body:
  for +state: State
  for +body: M.Body
  for context: Context
  for +desired: Maybe<&2, Pose>
  for +selected: Pose
  for +history: List<&2, QueryRecord>
  {finish_unchanged(Request{state, body, context, Nil{}}, desired, selected, history) ==
    Done{Finished{Transition{state, body, desired, selected, False{}, False{}, history, Nil{}}, Nil{}}} : Result<&2, &2, Error, Progress>}

def unchanged_pose_retains_entire_state_and_body(state, body, context, desired, selected, history):
  {==}
