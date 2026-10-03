import Base
import ../src/f64.bend as F
import ../src/geometry.bend as G

type BoxRead is Data:
  BoxRead{box: G.AABB, rest: List<&2, String>}

type Operation is Data:
  OpConstruct{}
  OpMove{}
  OpInflate{}
  OpDeflate{}
  OpContains{}
  OpIntersects{}
  OpCheckedNew{}
  OpClipColliders{}
  OpClipCollider{}
  OpClipBoxes{}
  OpCheckedClip{}

def read_operation(value: String) -> Maybe<&2, Operation>:
  match value:
    case "constructor": Some{OpConstruct{}}
    case "move": Some{OpMove{}}
    case "inflate": Some{OpInflate{}}
    case "deflate": Some{OpDeflate{}}
    case "contains": Some{OpContains{}}
    case "intersects": Some{OpIntersects{}}
    case "checked_new": Some{OpCheckedNew{}}
    case "clip": Some{OpClipColliders{}}
    case "clip_collider": Some{OpClipCollider{}}
    case "clip_boxes": Some{OpClipBoxes{}}
    case "checked_clip": Some{OpCheckedClip{}}
    case _: None{}

def number_result(value: Maybe<&2, U32>) -> U32:
  match value:
    case Some{x}: x
    case None{}: 0

def number(value: String) -> U32:
  number_result(U32.read(value))

def f64_show(value: F.F64) -> String:
  match value:
    case F.F64{hi, lo}: U32.show(hi) ++ "|" ++ U32.show(lo)

def box_show(value: G.AABB) -> String:
  match value:
    case G.AABB{a, b, c, d, e, f}:
      f64_show(a) ++ "|" ++ f64_show(b) ++ "|" ++ f64_show(c) ++ "|" ++ f64_show(d) ++ "|" ++ f64_show(e) ++ "|" ++ f64_show(f)

def normalize(value: G.AABB) -> G.AABB:
  match value:
    case G.AABB{a, b, c, d, e, f}: G.AABB.new(a, b, c, d, e, f)

def numbers(values: List<&2, String>) -> List<&2, U32>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: number(value) <> numbers(rest)

def read_box_numbers(values: List<&2, U32>, rest: List<&2, String>) -> Maybe<&2, BoxRead>:
  match values:
    case ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}:
      Some{BoxRead{G.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}, rest}}
    case _: None{}

def read_box(fields: List<&2, String>) -> Maybe<&2, BoxRead>:
  match fields:
    case ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> rest:
      read_box_numbers(numbers(ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}), rest)
    case _: None{}

def read_colliders_add(box: G.AABB, tail: Maybe<&2, List<&2, G.Collider>>) -> Maybe<&2, List<&2, G.Collider>>:
  match tail:
    case None{}: None{}
    case Some{rest}: Some{G.BoxCollider{box} <> rest}

def read_colliders_box(box: Maybe<&2, BoxRead>, tail: Maybe<&2, List<&2, G.Collider>>) -> Maybe<&2, List<&2, G.Collider>>:
  match box:
    case None{}: None{}
    case Some{BoxRead{box, rest}}: read_colliders_add(box, tail)

def read_colliders_empty(tail: Maybe<&2, List<&2, G.Collider>>) -> Maybe<&2, List<&2, G.Collider>>:
  match tail:
    case None{}: None{}
    case Some{rest}: Some{G.EmptyCollider{} <> rest}

def read_colliders(fields: List<&2, String>) -> Maybe<&2, List<&2, G.Collider>>:
  match fields:
    case Nil{}: Some{Nil{}}
    case "empty" <> rest: read_colliders_empty(read_colliders(rest))
    case "box" <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> rest:
      read_colliders_box(read_box(ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}), read_colliders(rest))
    case _: None{}

def colliders_boxes(shapes: List<&2, G.Collider>) -> List<&2, G.AABB>:
  match shapes:
    case Nil{}: Nil{}
    case G.EmptyCollider{} <> rest: colliders_boxes(rest)
    case G.BoxCollider{box} <> rest: box <> colliders_boxes(rest)

def read_axis(value: String) -> Maybe<&2, G.Axis>:
  match value:
    case "X": Some{G.AxisX{}}
    case "Y": Some{G.AxisY{}}
    case "Z": Some{G.AxisZ{}}
    case _: None{}

def error_show(value: G.Error) -> String:
  match value:
    case G.NonFiniteCoordinate{field}: "coordinate|" ++ U32.show(field)
    case G.NonFiniteMoving{field}: "moving|" ++ U32.show(field)
    case G.NonFiniteObstacle{index, field}: "obstacle|" ++ U32.show(index) ++ "|" ++ U32.show(field)
    case G.NonFiniteDelta{}: "delta"

def report_checked_box(id: String, result: Result<&2, &2, G.Error, G.AABB>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print(id ++ "|error|" ++ error_show(error))
    case Done{box}: IO.print(id ++ "|box|" ++ box_show(box))

def report_checked_clip(id: String, result: Result<&2, &2, G.Error, F.F64>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print(id ++ "|error|" ++ error_show(error))
    case Done{value}: IO.print(id ++ "|f64|" ++ f64_show(value))

def report_clip(id: String, operation: Operation, axis: Maybe<&2, G.Axis>, moving: G.AABB, delta: F.F64, shapes: Maybe<&2, List<&2, G.Collider>>) -> IO(Unit):
  match operation axis shapes:
    case _ None{} _: IO.die(Unit, 2, "invalid geometry axis")
    case _ _ None{}: IO.die(Unit, 2, "invalid geometry collider protocol")
    case OpCheckedClip{} Some{axis} Some{shapes}: report_checked_clip(id, G.clip_checked(axis, moving, colliders_boxes(shapes), delta))
    case OpClipBoxes{} Some{axis} Some{shapes}: IO.print(id ++ "|f64|" ++ f64_show(G.clip(axis, moving, colliders_boxes(shapes), delta)))
    case OpClipCollider{} Some{axis} Some{shapes}:
      match shapes:
        case shape <> Nil{}: IO.print(id ++ "|f64|" ++ f64_show(G.clip_collider(axis, moving, shape, delta)))
        case _: IO.die(Unit, 2, "clip_collider requires one collider")
    case _ Some{axis} Some{shapes}: IO.print(id ++ "|f64|" ++ f64_show(G.clip_colliders(axis, moving, shapes, delta)))

def dispatch_intersects(id: String, box: G.AABB, other: Maybe<&2, BoxRead>) -> IO(Unit):
  match other:
    case Some{BoxRead{other, Nil{}}}: IO.print(id ++ "|bool|" ++ U32.show(Bool.to_u32(G.AABB.intersects(box, normalize(other)))))
    case _: IO.die(Unit, 2, "invalid geometry intersects protocol")

def dispatch_box(id: String, operation: Operation, box: G.AABB, fields: List<&2, String>) -> IO(Unit):
  match operation box fields:
    case OpConstruct{} _ Nil{}: IO.print(id ++ "|box|" ++ box_show(normalize(box)))
    case OpCheckedNew{} G.AABB{a, b, c, d, e, f} Nil{}: report_checked_box(id, G.AABB.checked_new(a, b, c, d, e, f))
    case OpIntersects{} _ _: dispatch_intersects(id, normalize(box), read_box(fields))
    case OpMove{} _ ah <> al <> bh <> bl <> ch <> cl <> Nil{}:
      IO.print(id ++ "|box|" ++ box_show(G.AABB.move(normalize(box), F.F64{number(ah), number(al)}, F.F64{number(bh), number(bl)}, F.F64{number(ch), number(cl)})))
    case OpInflate{} _ ah <> al <> bh <> bl <> ch <> cl <> Nil{}:
      IO.print(id ++ "|box|" ++ box_show(G.AABB.inflate(normalize(box), F.F64{number(ah), number(al)}, F.F64{number(bh), number(bl)}, F.F64{number(ch), number(cl)})))
    case OpDeflate{} _ ah <> al <> bh <> bl <> ch <> cl <> Nil{}:
      IO.print(id ++ "|box|" ++ box_show(G.AABB.deflate(normalize(box), F.F64{number(ah), number(al)}, F.F64{number(bh), number(bl)}, F.F64{number(ch), number(cl)})))
    case OpContains{} _ ah <> al <> bh <> bl <> ch <> cl <> Nil{}:
      IO.print(id ++ "|bool|" ++ U32.show(Bool.to_u32(G.AABB.contains(normalize(box), F.F64{number(ah), number(al)}, F.F64{number(bh), number(bl)}, F.F64{number(ch), number(cl)}))))
    case _ _ axis <> hi <> lo <> rest:
      report_clip(id, operation, read_axis(axis), normalize(box), F.F64{number(hi), number(lo)}, read_colliders(rest))
    case _ _ _: IO.die(Unit, 2, "invalid geometry operation protocol")

def dispatch_parsed(id: String, operation: Maybe<&2, Operation>, parsed: Maybe<&2, BoxRead>) -> IO(Unit):
  match operation parsed:
    case None{} _: IO.die(Unit, 2, "invalid geometry operation")
    case _ None{}: IO.die(Unit, 2, "invalid geometry box protocol")
    case Some{operation} Some{BoxRead{box, rest}}: dispatch_box(id, operation, box, rest)

def dispatch(fields: List<&2, String>) -> IO(Unit):
  match fields:
    case id <> operation <> rest: dispatch_parsed(id, read_operation(operation), read_box(rest))
    case _: IO.die(Unit, 2, "invalid geometry protocol")

def run_args(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{arg, rest}:
      do IO<Unit>:
        dispatch(String.split(arg, '|'))
        run_args(rest)

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{program, rest}: run_args(rest)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
