import Base
import ./player_record.bend as R
import ./player_codec.bend as C
import ./player_look.bend as L
import ./player_tick.bend as T
import ./support.bend as S
import ./movement.bend as M
import ./f64.bend as F
import ./extended_persistence.bend as E

# Closed codec for the currently admitted overworld player. Core and this
# projection are published by the existing leased atomic bundle transaction.
# Physical held keys/mouse accumulation are intentionally ephemeral owners.
def error_text(error:R.Error) -> String:
  match error:
    case R.PlayerError{cause}: "invalid player motion snapshot"
    case R.LookError{cause}: "invalid raw Entity look fields"
    case R.ViewMismatch{axis}: "player view projection mismatch:" ++ U32.show(axis)
    case R.SchemaError{message}: message
    case R.NbtError{message}: message

def converted(-A:Data,result:Result<&2,&2,R.Error,A>) -> Result<&2,&2,String,A>:
  match result:
    case Fail{error}: Fail{error_text(error)}
    case Done{value}: Done{value}

def admit(record:R.Record) -> Result<&2,&2,String,R.Record>:
  match record:
    case R.Record{C.Snapshot{state,support,yaw,pitch,"minecraft:overworld"},look}:
      converted(R.Record,R.validate(R.Record{C.Snapshot{state,support,yaw,pitch,"minecraft:overworld"},look}))
    case _: Fail{"current player runtime requires minecraft:overworld"}

def encoding(result:Result<&2,&2,String,R.Record>) -> Result<&2,&2,String,List<&2,U32>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{record}: converted(List<&2,U32>,R.encode(record))

def encoded_result(record:R.Record,result:Result<&2,&2,String,List<&2,U32>>) -> R.Record & Result<&2,&2,String,List<&2,U32>>:
  (record,result)

def encode_copy(+record:R.Record) -> R.Record & Result<&2,&2,String,List<&2,U32>>:
  encoded_result(record,encoding(admit(record)))

def encode(record:R.Record) -> R.Record & Result<&2,&2,String,List<&2,U32>>:
  encode_copy(record)

def admitted(result:Result<&2,&2,String,R.Record>) -> Result<&2,&1,String,R.Record>:
  match result:
    case Fail{message}: Fail{message}
    case Done{record}: Done{record}

def decoded(result:Result<&2,&2,R.Error,R.Record>) -> Result<&2,&1,String,R.Record>:
  match result:
    case Fail{error}: Fail{error_text(error)}
    case Done{record}: admitted(admit(record))

def decode(schema:U32,bytes:List<&2,U32>) -> Result<&2,&1,String,R.Record>:
  match schema:
    case 1: decoded(R.decode(bytes))
    case _: Fail{"unsupported player-record schema"}

def initial(unit:Unit) -> Result<&2,&1,String,R.Record>:
  body : M.Body = M.Body.new(M.Vec3{F.from_f32(0.5),F.from_u32(1),F.from_f32(F32.neg(2.5))},0.6,1.8,M.Vec3.zero(),True{})
  Done{R.Record{C.Snapshot{T.State{body,T.Input{0.0,0.0,0.0},False{},0,0,False{},0.0,0.0},S.State{None{},False{}},0.0,0.0,"minecraft:overworld"},L.State{0.0,0.0,0.0,0.0}}}

def refuse_core_only(unit:Unit) -> Result<&2,&1,String,R.Record>:
  Fail{"Core-only saves require an explicit player initialization migration"}

def codec() -> E.Codec<R.Record>:
  E.Codec{"bendex:player-record",1,encode,decode,initial,refuse_core_only}

def limits() -> E.Limits:
  E.Limits{E.core_limits(E.default_limits()),8192,E.file_limit(E.default_limits())}

law unsupported_player_schema_is_rejected:
  for bytes:List<&2,U32>
  {decode(0,bytes) == Fail{"unsupported player-record schema"} : Result<&2,&1,String,R.Record>}

def unsupported_player_schema_is_rejected(bytes):
  {==}

law core_only_save_requires_explicit_player_migration:
  for unit:Unit
  {refuse_core_only(unit) == Fail{"Core-only saves require an explicit player initialization migration"} : Result<&2,&1,String,R.Record>}

def core_only_save_requires_explicit_player_migration(unit):
  {==}
