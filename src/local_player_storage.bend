import Base
import ./local_player_record.bend as R
import ./player_record.bend as PR
import ./player_codec.bend as C
import ./player_look.bend as PL
import ./player_tick.bend as PT
import ./local_input.bend as LI
import ./player_pose.bend as Pose
import ./local_move_world.bend as LM
import ./player_fall_history.bend as H
import ./entity_common_tick.bend as ECT
import ./support.bend as SP
import ./movement.bend as M
import ./f64.bend as F
import ./extended_persistence.bend as E

# Closed custom codec; E owns locking, Core and atomic durable publication.
# Successful and failed encode return the entire immutable record unchanged.
def converted(-A:Data,result:Result<&2,&2,R.Error,A>) -> Result<&2,&2,String,A>:
  match result:
    case Fail{error}: Fail{R.error_text(error)}
    case Done{value}: Done{value}

def encode_copy(+record:R.Record) -> R.Record & Result<&2,&2,String,List<&2,U32>>:
  (record,converted(List<&2,U32>,R.encode(record)))

def encode(record:R.Record) -> R.Record & Result<&2,&2,String,List<&2,U32>>:
  encode_copy(record)

def decoded(result:Result<&2,&2,R.Error,R.Record>) -> Result<&2,&1,String,R.Record>:
  match result:
    case Fail{error}: Fail{R.error_text(error)}
    case Done{record}: Done{record}

def decode(schema:U32,bytes:List<&2,U32>) -> Result<&2,&1,String,R.Record>:
  match schema:
    case 1: decoded(R.decode(bytes))
    case _: Fail{"unsupported local-player-record schema"}

def initial(unit:Unit) -> Result<&2,&1,String,R.Record>:
  +position : M.Vec3 = M.Vec3{F.from_f32(0.5),F.from_u32(1),F.from_f32(F32.neg(2.5))}
  body : M.Body = M.Body.new(position,0.6,1.8,M.Vec3.zero(),True{})
  Done{R.Record{
    PR.Record{C.Snapshot{PT.State{body,PT.Input{0.0,0.0,0.0},False{},0,0,False{},0.0,0.0},SP.State{None{},False{}},0.0,0.0,"minecraft:overworld"},PL.State{0.0,0.0,0.0,0.0}},
    LI.initial(),False{},Pose.State{Pose.Standing{},PL.float_bits(1070554153),[]},LM.MinorState{False{}},H.History{F.from_u32(0)},ECT.Metadata{position,position,0,0}}}

def refuse_core_only(unit:Unit) -> Result<&2,&1,String,R.Record>:
  Fail{"Core-only or plain-Player saves require explicit LocalPlayer migration"}

def codec() -> E.Codec<R.Record>:
  E.Codec{"bendex:local-player-record",1,encode,decode,initial,refuse_core_only}

def limits() -> E.Limits:
  E.Limits{E.core_limits(E.default_limits()),16384,E.file_limit(E.default_limits())}

law unsupported_schema_is_rejected:
  for bytes:List<&2,U32>
  {decode(0,bytes) == Fail{"unsupported local-player-record schema"} : Result<&2,&1,String,R.Record>}

def unsupported_schema_is_rejected(bytes):
  {==}

law no_implicit_migration:
  for unit:Unit
  {refuse_core_only(unit) == Fail{"Core-only or plain-Player saves require explicit LocalPlayer migration"} : Result<&2,&1,String,R.Record>}

def no_implicit_migration(unit):
  {==}
