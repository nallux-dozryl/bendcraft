import Base
import ../src/item_component.bend as C
import ../src/json.bend as J

def rows(values:List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case +raw <> rest:
      do IO<Unit>:
        IO.print(J.encode(J.JArray{[J.JString{raw},J.JBool{C.initial_number_valid(raw)}]}))
        rows(rest)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> rest: rows(rest)
    case _: IO.die(Unit,2,"expected numeric lexeme inputs")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
