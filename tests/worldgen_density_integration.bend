import Base
import ./worldgen_density_intervals.bend as Intervals
import ./worldgen_density_router.bend as Router

def arguments(args:List<&1,String>) -> IO(Unit):
  match args:
    case executable <> "router" <> fixture <> Nil{}: Router.file(fixture)
    case executable <> fixture <> Nil{}: IO.print(Intervals.run(String.split(fixture,'|')))
    case _: IO.print("fail|density fixture or router fixture file required")

def main() -> IO(Unit):
  do IO<Unit>:
    args:List<&1,String> <- IO.args()
    arguments(args)
