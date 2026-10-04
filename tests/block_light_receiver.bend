import Base
import ../src/block_light.bend as B
import ../src/core.bend as C

# Input-only native receiver for the actual production module. Oracle levels
# never enter this executable. Occlusion is an actual-Java observed provider.
def number_read(value:Maybe<&2,U32>) -> U32:
  match value:
    case Some{n}: n
    case None{}: 0

def number(value:String) -> U32:
  number_read(U32.read(value))

def edge_key(source:U32,target:U32,direction:U32) -> String:
  U32.show(source) ++ "/" ++ U32.show(target) ++ "/" ++ U32.show(direction)

def bool_result(pair:Map<&2,Bool> & Bool) -> Bool:
  (context,result) = pair
  result

def occludes(context:Map<&2,Bool>,source:B.Descriptor,target:B.Descriptor,
    direction:B.Direction) -> Bool:
  B.Descriptor{from,e1,d1} = source
  B.Descriptor{to,e2,d2} = target
  bool_result(Map.get(Bool,False{},context,edge_key(from,to,B.direction_id(direction))))

def edges(n:Nat,args:List<String>,context:Map<&2,Bool>) ->
    Map<&2,Bool> & List<String>:
  match n args:
    case 0n rest: (context,rest)
    case 1n+remaining from <> to <> direction <> rest:
      edges(remaining,rest,Map.set(&2,Bool,context,
        edge_key(number(from),number(to),number(direction)),True{}))
    case _ _: (context,[])

def published(result:B.State & Result<&2,&2,B.Error,Unit>) -> B.State:
  (state,result) = result
  state

def domain_added(n:Nat,+dimension:String,args:List<String>,state:B.State,
    positions:List<&2,C.Position>) -> B.State & List<&2,C.Position> & List<String>:
  match n args:
    case 0n rest: (state,positions,rest)
    case 1n+remaining x <> y <> z <> rest:
      +position : C.Position = C.Position{dimension,number(x),number(y),number(z)}
      domain_added(remaining,dimension,rest,
        published(B.publish(state,position,B.Descriptor{0,0,0})),position <> positions)
    case _ _: (state,positions,[])

def write_kind(kind:String,state:B.State,position:C.Position,
    descriptor:B.Descriptor) -> B.State:
  match kind:
    case "unload": B.unload(state,position)
    case _: published(B.publish(state,position,descriptor))

def writes(n:Nat,+dimension:String,args:List<String>,state:B.State) ->
    B.State & List<String>:
  match n args:
    case 0n rest: (state,rest)
    case 1n+remaining x <> y <> z <> id <> emission <> dampening <> kind <> rest:
      writes(remaining,dimension,rest,write_kind(kind,state,
        C.Position{dimension,number(x),number(y),number(z)},
        B.Descriptor{number(id),number(emission),number(dampening)}))
    case _ _: (state,[])

def settle_result(result:B.State & B.Status,next:B.State -> B.State & B.Status) -> B.State & B.Status:
  (state,status) = result
  match status:
    case B.Stable{}: (state,B.Stable{})
    case B.MoreWork{pending}: next(state)

def settle(fuel:Nat,+context:Map<&2,Bool>,+budget:Nat,state:B.State) -> B.State & B.Status:
  match fuel:
    case 0n: B.status(state)
    case 1n+remaining:
      settle_result(B.advance(~Map<&2,Bool>,~occludes,context,budget,state),
        state => settle(remaining,context,budget,state))

def samples(positions:List<&2,C.Position>,state:B.State) -> B.State & List<&2,Maybe<&2,U32>>:
  match positions:
    case Nil{}: (state,[])
    case position <> rest:
      B.paired(B.State,Maybe<&2,U32>,B.State & List<&2,Maybe<&2,U32>>,
        B.sample(state,position),state => level =>
          B.paired(B.State,List<&2,Maybe<&2,U32>>,B.State & List<&2,Maybe<&2,U32>>,
            samples(rest,state),state => values => (state,level <> values)))

def show_level(level:Maybe<&2,U32>) -> String:
  match level:
    case None{}: "?"
    case Some{n}: U32.show(n)

def show_levels(levels:List<&2,Maybe<&2,U32>>) -> String:
  match levels:
    case Nil{}: ""
    case level <> rest: show_level(level) ++ " " ++ show_levels(rest)

def show_status(status:B.Status) -> String:
  match status:
    case B.Stable{}: "stable"
    case B.MoreWork{pending}: "more:" ++ Nat.show(pending)

def phases(n:Nat,+context:Map<&2,Bool>,+budget:Nat,+dimension:String,
    +positions:List<&2,C.Position>,args:List<String>,state:B.State) -> IO(Unit):
  match n args:
    case 0n _: IO.pure(Unit,Unit{})
    case 1n+remaining count <> rest:
      B.paired(B.State,List<String>,IO(Unit),writes(U32.to_nat(number(count)),dimension,rest,state),state => tail =>
        B.paired(B.State,B.Status,IO(Unit),settle(10000n,context,budget,state),state => status =>
          B.paired(B.State,List<&2,Maybe<&2,U32>>,IO(Unit),samples(positions,state),state => values => (
            do IO<Unit>:
              IO.print(show_status(status) ++ " " ++ show_levels(values))
              phases(remaining,context,budget,dimension,positions,tail,state)
          ))))
    case _ _: IO.die(Unit,1,"block_light_receiver: incomplete phase")

def run_domain_loaded(context:Map<&2,Bool>,budget:Nat,dimension:String,
    loaded:B.State & List<&2,C.Position> & List<String>) -> IO(Unit):
  (state,(positions,tail)) = loaded
  match tail:
    case count <> rest:
      phases(U32.to_nat(number(count)),context,budget,dimension,
        List.reverse(&2,C.Position,positions),rest,state)
    case _: IO.die(Unit,1,"block_light_receiver: missing phase count")

def run_domain(context:Map<&2,Bool>,budget:Nat,+dimension:String,args:List<String>) -> IO(Unit):
  match args:
    case count <> rest:
      run_domain_loaded(context,budget,dimension,
        domain_added(U32.to_nat(number(count)),dimension,rest,B.new(),[]))
    case _: IO.die(Unit,1,"block_light_receiver: missing domain")

# Native contracts beyond Java's valid world-coordinate range: separate
# dimensions, no I32 endpoint wrap, and rejected edits retain settled fields.
def guard_positions() -> List<&2,C.Position>:
  [C.Position{"minecraft:overworld",0,0,0},C.Position{"minecraft:the_nether",0,0,0},
   C.Position{"minecraft:overworld",1,0,0},C.Position{"minecraft:the_nether",1,0,0},
   C.Position{"minecraft:overworld",2147483647,0,0},
   C.Position{"minecraft:overworld",2147483648,0,0},
   C.Position{"minecraft:overworld",2147483649,0,0}]

def guard_state() -> B.State:
  published(B.publish(
  published(B.publish(
  published(B.publish(
  published(B.publish(
  published(B.publish(
  published(B.publish(
  published(B.publish(B.new(),C.Position{"minecraft:overworld",0,0,0},B.Descriptor{4926,14,0})),
    C.Position{"minecraft:the_nether",0,0,0},B.Descriptor{8686,15,15})),
    C.Position{"minecraft:overworld",1,0,0},B.Descriptor{0,0,0})),
    C.Position{"minecraft:the_nether",1,0,0},B.Descriptor{0,0,0})),
    C.Position{"minecraft:overworld",2147483647,0,0},B.Descriptor{4926,14,0})),
    C.Position{"minecraft:overworld",2147483648,0,0},B.Descriptor{0,0,0})),
    C.Position{"minecraft:overworld",2147483649,0,0},B.Descriptor{0,0,0}))

def guard_settled(settled:B.State & B.Status) -> IO(Unit):
  (state,status) = settled
  +position : C.Position = C.Position{"minecraft:overworld",0,0,0}
  retained = published(B.publish(published(B.publish(state,position,
    B.Descriptor{4926,16,0})),position,B.Descriptor{4926,14,16}))
  B.paired(B.State,List<&2,Maybe<&2,U32>>,IO(Unit),samples(guard_positions(),retained),state => values =>
    IO.print(show_status(status) ++ " " ++ show_levels(values)))

def guards() -> IO(Unit):
  guard_settled(settle(1000n,MTip{},1n,guard_state()))

def run(args:List<String>) -> IO(Unit):
  match args:
    case "guards" <> _: guards()
    case budget <> dimension <> count <> rest:
      B.paired(Map<&2,Bool>,List<String>,IO(Unit),edges(U32.to_nat(number(count)),rest,MTip{}),
        context => tail => run_domain(context,U32.to_nat(number(budget)),dimension,tail))
    case _: IO.die(Unit,1,"block_light_receiver: missing arguments")

def run_args(args:List<String>) -> IO(Unit):
  match args:
    case program <> rest: run(rest)
    case _: IO.die(Unit,1,"block_light_receiver: missing argv")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
