import Base
import ../src/local_player_record.bend as R
import ../src/player_pose.bend as Pose
import ../src/player_record.bend as PR
import ../src/local_input.bend as LI
import ../src/local_move_world.bend as LM
import ../src/player_fall_history.bend as H
import ../src/entity_common_tick.bend as ECT

def error_name(error:R.Error) -> String:
  match error:
    case R.MotionError{cause}: "MotionError"
    case R.InputError{cause}: "InputError"
    case R.PoseError{cause}: "PoseError"
    case R.HistoryError{cause}: "HistoryError"
    case R.EntityError{cause}: "EntityError"
    case R.UnsupportedPose{}: "UnsupportedPose"
    case R.UnsupportedDimension{}: "UnsupportedDimension"
    case R.SchemaError{message}: "SchemaError"
    case R.NbtError{message}: "NbtError"

def written(result:File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    IO.pass(Unit,status)

def publish(path:String,bytes:List<&2,U32>) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"w"))
    result : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
    written(result)

def loaded(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = result
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)

def read(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,16385)
    loaded(result)

def encoded(output:String,result:Result<&2,&2,R.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("error=" ++ error_name(error))
    case Done{bytes}:
      do IO<Unit>:
        publish(output,bytes)
        IO.print("ok=record")

def pose_tail(record:R.Record) -> R.Record:
  R.Record{motion,local,sprinting,Pose.State{+pose,+eye,tail},minor,history,entity} = record
  R.Record{motion,local,sprinting,Pose.State{pose,eye,[Pose.State{pose,eye,[]}]},minor,history,entity}

def execute_record(mode:String,output:String,record:R.Record) -> IO(Unit):
  match mode:
    case "record": encoded(output,R.encode(record))
    case "pose-tail": encoded(output,R.encode(pose_tail(record)))
    case _: IO.die(Unit,2,"unsupported mode")

def decoded(mode:String,output:String,result:Result<&2,&2,R.Error,R.Record>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("error=" ++ error_name(error))
    case Done{record}: execute_record(mode,output,record)

def execute(mode:String,input:String,output:String) -> IO(Unit):
  do IO<Unit>:
    bytes : List<&2,U32> <- read(input)
    decoded(mode,output,R.decode(bytes))

def batch(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case mode <> input <> output <> rest:
      do IO<Unit>:
        execute(mode,input,output)
        batch(rest)
    case _: IO.die(Unit,2,"expected MODE INPUT OUTPUT triples")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1,String,args))

law pose_tail_mutation_preserves_all_other_durable_fields:
  for motion:PR.Record
  for local:LI.State
  for sprinting:Bool
  for +pose:Pose.Pose
  for +eye:F32
  for tail:List<&2,Pose.State>
  for minor:LM.MinorState
  for history:H.History
  for entity:ECT.Metadata
  {pose_tail(R.Record{motion,local,sprinting,Pose.State{pose,eye,tail},minor,history,entity}) ==
    R.Record{motion,local,sprinting,Pose.State{pose,eye,[Pose.State{pose,eye,[]}]},minor,history,entity} : R.Record}

def pose_tail_mutation_preserves_all_other_durable_fields(motion,local,sprinting,pose,eye,tail,minor,history,entity):
  {==}
