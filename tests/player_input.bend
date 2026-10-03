import Base
import ../src/player_input.bend as P

def boolean(value:Bool) -> String:
  match value:
    case False{}: "0"
    case True{}: "1"

def sample_show(value:P.Sample) -> String:
  P.Sample{buttons,movement,forward} = value
  P.Vector{x,z} = movement
  U32.show(P.mask(buttons)) ++ "|" ++ U32.show(F32.bits(x)) ++ "|" ++ U32.show(F32.bits(z)) ++ "|" ++ boolean(forward)

def show(buttons:P.Buttons) -> String:
  sample_show(P.sample(buttons))

def number(value:Maybe<&2,U32>,rest:Maybe<&2,List<&2,U32>>) -> Maybe<&2,List<&2,U32>>:
  match value rest:
    case Some{value} Some{rest}: Some{value <> rest}
    case _ _: None{}

def numbers(fields:List<&2,String>) -> Maybe<&2,List<&2,U32>>:
  match fields:
    case Nil{}: Some{[]}
    case field <> rest:
      number(U32.read(field),numbers(rest))

def parsed(fields:Maybe<&2,List<&2,U32>>) -> IO(Unit):
  match fields:
    case Some{mask <> Nil{}}:
      IO.print(show(P.from_mask(mask)))
    case Some{mask <> f <> b <> l <> r <> j <> h <> s <> code <> down <> Nil{}}:
      IO.print(show(P.key(P.Bindings{f,b,l,r,j,h,s},P.from_mask(mask),code,U32.is_ne(down,0))))
    case Some{mask <> 4294967295 <> Nil{}}:
      IO.print(show(P.clear(P.from_mask(mask))))
    case Some{mask <> 4294967294 <> Nil{}}:
      IO.print(show(P.make_jump(P.from_mask(mask))))
    case _: IO.die(Unit,2,"invalid player input protocol")

def run(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        parsed(numbers(String.split(arg,'|')))
        run(rest)

def start(args:List<String>) -> IO(Unit):
  match args:
    case program <> rest: run(rest)
    case _: IO.die(Unit,2,"missing player input arguments")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),start)
