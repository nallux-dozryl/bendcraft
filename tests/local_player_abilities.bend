import Base
import ./local_input.bend as Old
import ../src/local_input.bend as LI
import ../src/player_tick.bend as P
import ../src/travel.bend as T
import ../src/locomotion.bend as L

def flight_mode(flying:Bool,speed:F32) -> T.Mode:
  match flying:
    case False{}: T.NeutralDryAir{}
    case True{}: T.ResolvedFlight{speed}

def with_ability(context:LI.ApplyContext,fields:List<&2,U32>) -> Maybe<&2,LI.ApplyContext>:
  match context fields:
    case LI.ApplyContext{P.Context{T.Context{ground,attrs,yaw,maximum,sprinting,no_gravity,discard,travel_mode},strength,factor,affected,tick_mode},sneak_speed,pitch}
         mayfly <> +flying <> +speed <> trigger <> takeoff <> jump <> sneak <> Nil{}:
      Some{LI.ApplyContext{P.Context{T.Context{ground,attrs,yaw,maximum,sprinting,no_gravity,discard,flight_mode(Old.bit(flying),L.float_bits(speed))},
        strength,factor,Bool.not(Old.bit(flying)),P.AbilityInput{Old.bit(mayfly),Old.bit(flying),L.float_bits(speed),trigger,Old.bit(takeoff),Old.bit(jump),Old.bit(sneak)}},sneak_speed,pitch}}
    case _ _: None{}

def ability_context(context:Maybe<&2,LI.ApplyContext>,fields:Maybe<&2,List<&2,U32>>) -> Maybe<&2,LI.ApplyContext>:
  match context fields:
    case Some{context} Some{fields}: with_ability(context,fields)
    case _ _: None{}

def dispatch(parts:List<&2,String>,tables:L.Tables) -> IO(L.Tables):
  match parts:
    case id <> local <> player <> context <> ability <> Nil{}:
      Old.phase_parsed(id,"prepare",tables,Old.optional_numbers(Old.numbers(String.split(local,'|')),0),
        Old.optional_player(Old.numbers(String.split(player,'|'))),
        ability_context(Old.optional_apply(Old.numbers(String.split(context,'|'))),Old.numbers(String.split(ability,'|'))))
    case _: IO.die(L.Tables,2,"invalid ability phase packet")

def run_args(args:List<String>,tables:L.Tables) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        tables : L.Tables <- dispatch(String.split(arg,';'),tables)
        run_args(rest,tables)

def loaded(args:List<String>,result:Result<&2,&1,L.Error,L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,3,"invalid ability table")
    case Done{tables}: run_args(args,tables)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> rest:
      do IO<Unit>:
        result : Result<&2,&1,L.Error,L.Tables> <- L.Tables.load(path)
        loaded(rest,result)
    case _: IO.die(Unit,2,"ability table required")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
