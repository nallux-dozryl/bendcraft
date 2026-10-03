import Base
import ../src/f64.bend as F
import ../src/geometry.bend as G
import ../src/movement.bend as M
import ./geometry.bend as T

type Operation is Data:
  Collide{}
  Heights{}
  Resolve{}
  MoveBody{}
  CheckedMove{}
  BlockQuery{}
  EntityQuery{}
  StepQuery{}
  MakeBox{}

def operation(value: String) -> Maybe<&2, Operation>:
  match value:
    case "collide": Some{Collide{}}
    case "heights": Some{Heights{}}
    case "resolve": Some{Resolve{}}
    case "move": Some{MoveBody{}}
    case "checked_move": Some{CheckedMove{}}
    case "block_query": Some{BlockQuery{}}
    case "entity_query": Some{EntityQuery{}}
    case "step_query": Some{StepQuery{}}
    case "make_box": Some{MakeBox{}}
    case _: None{}

def float_word(value: U32) -> F32:
  match value:
    case U32{word}: F32{word}

def vector_show(vector: M.Vec3) -> String:
  match vector:
    case M.Vec3{x, y, z}: T.f64_show(x) ++ "|" ++ T.f64_show(y) ++ "|" ++ T.f64_show(z)

def heights_show(values: List<&2, F.F64>) -> String:
  match values:
    case Nil{}: ""
    case value <> rest: "|" ++ T.f64_show(value) ++ heights_show(rest)

def resolution_show(id: String, result: M.Resolution) -> IO(Unit):
  match result:
    case M.Resolution{displacement, stepped}: IO.print(id ++ "|resolve|" ++ vector_show(displacement) ++ "|" ++ U32.show(Bool.to_u32(stepped)))

def transition_show(id: String, transition: M.Transition) -> IO(Unit):
  match transition:
    case M.Transition{M.Body{position, box, velocity, width, height, grounded, horizontal, vertical, below}, displacement, stepped, changed}:
      IO.print(id ++ "|move|" ++ vector_show(displacement) ++ "|" ++ U32.show(Bool.to_u32(stepped)) ++ "|" ++ vector_show(position) ++ "|" ++ T.box_show(box) ++ "|" ++ vector_show(velocity) ++ "|" ++ U32.show(Bool.to_u32(grounded)) ++ "|" ++ U32.show(Bool.to_u32(horizontal)) ++ "|" ++ U32.show(Bool.to_u32(vertical)) ++ "|" ++ U32.show(Bool.to_u32(below)) ++ "|" ++ U32.show(Bool.to_u32(changed)))

def error_show(error: M.Error) -> String:
  match error:
    case M.InvalidBody{component, field}: "body|" ++ U32.show(component) ++ "|" ++ U32.show(field)
    case M.InvalidDimensions{field}: "dimensions|" ++ U32.show(field)
    case M.InvalidRequest{axis}: "request|" ++ U32.show(axis)
    case M.InvalidStepHeight{}: "maximum"
    case M.InvalidCollider{phase, index, field}: "collider|" ++ U32.show(phase) ++ "|" ++ U32.show(index) ++ "|" ++ U32.show(field)
    case M.ReversedCollider{phase, index, axis}: "reversed|" ++ U32.show(phase) ++ "|" ++ U32.show(index) ++ "|" ++ U32.show(axis)
    case M.NonFiniteResult{component, field}: "result|" ++ U32.show(component) ++ "|" ++ U32.show(field)

def checked_show(id: String, result: Result<&2, &2, M.Error, M.Transition>) -> IO(Unit):
  match result:
    case Done{value}: transition_show(id, value)
    case Fail{error}: IO.print(id ++ "|error|" ++ error_show(error))

def execute(id: String, operation: Operation, box: G.AABB, requested: M.Vec3,
             grounded: Bool, maximum: F32, previous: F32, position: M.Vec3, velocity: M.Vec3,
             width: F32, height: F32, initial: List<&2, G.Collider>, step: List<&2, G.Collider>) -> IO(Unit):
  match operation:
    case Collide{}: IO.print(id ++ "|collide|" ++ vector_show(M.collide_with_shapes(requested, T.normalize(box), initial)))
    case Heights{}: IO.print(id ++ "|heights" ++ heights_show(M.candidate_step_heights(T.normalize(box), step, maximum, previous)))
    case Resolve{}: resolution_show(id, M.resolve(T.normalize(box), grounded, maximum, requested, initial, step))
    case MoveBody{}:
      body = {M.Body{position, T.normalize(box), velocity, width, height, grounded, False{}, False{}, False{}} : M.Body}
      transition_show(id, M.move(body, requested, maximum, initial, step))
    case CheckedMove{}:
      body = {M.Body{position, box, velocity, width, height, grounded, False{}, False{}, False{}} : M.Body}
      checked_show(id, M.move_checked(body, requested, maximum, initial, step))
    case BlockQuery{}: IO.print(id ++ "|box|" ++ T.box_show(M.initial_block_query(T.normalize(box), requested)))
    case EntityQuery{}: IO.print(id ++ "|box|" ++ T.box_show(M.initial_entity_query(T.normalize(box), requested, maximum)))
    case StepQuery{}: IO.print(id ++ "|box|" ++ T.box_show(M.step_query(T.normalize(box), requested, velocity, maximum)))
    case MakeBox{}: IO.print(id ++ "|box|" ++ T.box_show(M.make_box(position, width, height)))

def parsed(id: String, op: Operation, box: G.AABB, fields: List<&2, U32>, initial: Maybe<&2, List<&2, G.Collider>>, step: Maybe<&2, List<&2, G.Collider>>) -> IO(Unit):
  match fields initial step:
    case xh <> xl <> yh <> yl <> zh <> zl <> grounded <> maximum <> previous <> pxh <> pxl <> pyh <> pyl <> pzh <> pzl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> Nil{} Some{initial} Some{step}:
      execute(id, op, box, M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}, U32.is_ne(grounded, 0), float_word(maximum), float_word(previous),
              M.Vec3{F.F64{pxh, pxl}, F.F64{pyh, pyl}, F.F64{pzh, pzl}}, M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, float_word(width), float_word(height), initial, step)
    case _ _ _: IO.die(Unit, 2, "invalid movement fields")

def boxed(id: String, op: Operation, box: Maybe<&2, T.BoxRead>, initial: List<&2, String>, step: List<&2, String>) -> IO(Unit):
  match box:
    case Some{T.BoxRead{box, rest}}: parsed(id, op, box, T.numbers(rest), T.read_colliders(initial), T.read_colliders(step))
    case _: IO.die(Unit, 2, "invalid movement box")

def header_operation(id: String, op: Maybe<&2, Operation>, fields: List<&2, String>, initial: List<&2, String>, step: List<&2, String>) -> IO(Unit):
  match op:
    case Some{value}: boxed(id, value, T.read_box(fields), initial, step)
    case _: IO.die(Unit, 2, "invalid movement operation")

def header(header: List<&2, String>, initial: List<&2, String>, step: List<&2, String>) -> IO(Unit):
  match header:
    case id <> text <> rest: header_operation(id, operation(text), rest, initial, step)
    case _: IO.die(Unit, 2, "invalid movement header")

def shape_fields(value: String) -> List<&2, String>:
  match value:
    case "": Nil{}
    case _: String.split(value, '|')

def dispatch(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case first <> initial <> step <> Nil{}: header(String.split(first, '|'), shape_fields(initial), shape_fields(step))
    case _: IO.die(Unit, 2, "invalid movement protocol")

def run_args(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        dispatch(String.split(arg, ';'))
        run_args(rest)

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case program <> rest: run_args(rest)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
