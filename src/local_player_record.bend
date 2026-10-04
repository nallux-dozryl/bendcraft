import Base
import ./player_record.bend as PR
import ./player_codec.bend as P
import ./player_tick.bend as PT
import ./local_input.bend as LI
import ./player_input.bend as PI
import ./player_pose.bend as Pose
import ./local_move_world.bend as LM
import ./player_fall_history.bend as H
import ./entity_common_tick.bend as ECT
import ./movement.bend as M
import ./f64.bend as F
import ./nbt.bend as N

# One immutable save projection; runtime Body remains the sole live owner.
# Previous sampled LI keys are durable; physical held keys/mouse are not here.
type Record is Data:
  Record{motion:PR.Record,local:LI.State,sprinting:Bool,pose:Pose.State,
    minor:LM.MinorState,history:H.History,entity:ECT.Metadata}

type Error is Data:
  MotionError{cause:PR.Error}
  InputError{cause:LI.Error}
  PoseError{cause:Pose.Error}
  HistoryError{cause:H.Error}
  EntityError{cause:ECT.Error}
  UnsupportedPose{}
  UnsupportedDimension{}
  SchemaError{message:String}
  NbtError{message:String}

def limits() -> N.Limits:
  N.Limits{16384,2,8192}

def error_text(error:Error) -> String:
  match error:
    case MotionError{cause}: "invalid local-player motion/look projection"
    case InputError{cause}: "invalid local-player sampled-input cache"
    case PoseError{cause}: "incoherent local-player pose/dimensions/eye/box"
    case HistoryError{cause}: "invalid local-player fall history"
    case EntityError{cause}: "invalid local-player historical position"
    case UnsupportedPose{}: "local-player record requires standing or crouching"
    case UnsupportedDimension{}: "local-player record requires minecraft:overworld"
    case SchemaError{message}: message
    case NbtError{message}: message

def first(first:Maybe<&2,Error>,rest:Maybe<&2,Error>) -> Maybe<&2,Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def motion_error(error:Maybe<&2,PR.Error>) -> Maybe<&2,Error>:
  match error:
    case Some{cause}: Some{MotionError{cause}}
    case None{}: None{}

def input_error(error:Maybe<&2,LI.Error>) -> Maybe<&2,Error>:
  match error:
    case Some{cause}: Some{InputError{cause}}
    case None{}: None{}

def pose_error(error:Maybe<&2,Pose.Error>) -> Maybe<&2,Error>:
  match error:
    case Some{cause}: Some{PoseError{cause}}
    case None{}: None{}

def history_error(error:Maybe<&2,H.Error>) -> Maybe<&2,Error>:
  match error:
    case Some{cause}: Some{HistoryError{cause}}
    case None{}: None{}

def entity_error(error:Maybe<&2,ECT.Error>) -> Maybe<&2,Error>:
  match error:
    case Some{cause}: Some{EntityError{cause}}
    case None{}: None{}

def body(motion:PR.Record) -> M.Body:
  PR.Record{P.Snapshot{PT.State{body,input,jumping,delay,trigger,sync,speed,head},support,yaw,pitch,dimension},look} = motion
  body

def dimension_error(motion:PR.Record) -> Maybe<&2,Error>:
  match motion:
    case PR.Record{P.Snapshot{state,support,yaw,pitch,"minecraft:overworld"},look}: None{}
    case _: Some{UnsupportedDimension{}}

def stable_pose_error(pose:Pose.State) -> Maybe<&2,Error>:
  match pose:
    case Pose.State{Pose.Standing{},eye,tail}: None{}
    case Pose.State{Pose.Crouching{},eye,tail}: None{}
    case _: Some{UnsupportedPose{}}

def record_error(record:Record) -> Maybe<&2,Error>:
  Record{+motion,+local,sprinting,+pose,minor,+history,+entity} = record
  first(motion_error(PR.record_error(motion)),first(dimension_error(motion),
    first(input_error(LI.state_error(local)),first(stable_pose_error(pose),
    first(pose_error(Pose.state_error(pose,body(motion))),
    first(history_error(H.history_error(history)),entity_error(ECT.metadata_error(entity))))))))

def validated(record:Record,error:Maybe<&2,Error>) -> Result<&2,&2,Error,Record>:
  match error:
    case Some{cause}: Fail{cause}
    case None{}: Done{record}

def validate(+record:Record) -> Result<&2,&2,Error,Record>:
  validated(record,record_error(record))

def schema(-A:Data,result:Result<&2,&2,P.Error,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{cause}: Fail{SchemaError{"invalid local-player NBT field"}}
    case Done{value}: Done{value}

def motion_result(-A:Data,result:Result<&2,&2,PR.Error,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{cause}: Fail{MotionError{cause}}
    case Done{value}: Done{value}

def nbt_result(-A:Data,result:Result<&2,&2,String,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{message}: Fail{NbtError{message}}
    case Done{value}: Done{value}

def byte_bool(value:Bool) -> U32:
  match value:
    case False{}: 0
    case True{}: 1

def keys_tag(keys:PI.Buttons) -> N.Value:
  PI.Buttons{f,b,l,r,j,s,c} = keys
  N.ByteArray{[byte_bool(f),byte_bool(b),byte_bool(l),byte_bool(r),byte_bool(j),byte_bool(s),byte_bool(c)]}

def local_tags(local:LI.State) -> List<&2,N.Member>:
  LI.State{keys,PI.Vector{x,z},trigger,crouch,bx,by,ox,oy} = local
  [P.member("local_keys",keys_tag(keys)),
   P.member("local_floats",N.ListTag{5,[N.Float{F32.bits(x)},N.Float{F32.bits(z)},N.Float{F32.bits(bx)},N.Float{F32.bits(by)},N.Float{F32.bits(ox)},N.Float{F32.bits(oy)}]}),
   P.member("local_trigger",N.Int{trigger}),P.member("local_crouching",P.bool_tag(crouch))]

def pose_tags(pose:Pose.State) -> List<&2,N.Member>:
  Pose.State{pose,eye,tail} = pose
  [P.member("pose",N.Int{Pose.pose_id(pose)}),P.member("eye",N.Float{F32.bits(eye)})]

def old_tag(entity:ECT.Metadata) -> N.Value:
  ECT.Metadata{M.Vec3{x,y,z},M.Vec3{ox,oy,oz},invulnerable,count} = entity
  N.ListTag{6,[P.double_tag(x),P.double_tag(y),P.double_tag(z),P.double_tag(ox),P.double_tag(oy),P.double_tag(oz)]}

def entity_tags(+entity:ECT.Metadata) -> List<&2,N.Member>:
  ECT.Metadata{o,old,invulnerable,count} = entity
  [P.member("old_positions",old_tag(entity)),P.member("invulnerable_time",N.Int{invulnerable}),P.member("tick_count",N.Int{count})]

def root(record:Record,motion_bytes:List<&2,U32>) -> N.Root:
  Record{motion,local,sprinting,pose,LM.MinorState{minor},H.History{distance},entity} = record
  N.Root{P.text("bendex:local-player-record"),N.Compound{
    List.append(&2,N.Member,[P.member("format",N.Int{1}),P.member("motion",N.ByteArray{motion_bytes})],
      List.append(&2,N.Member,local_tags(local),
        List.append(&2,N.Member,[P.member("sprinting",P.bool_tag(sprinting))],
          List.append(&2,N.Member,pose_tags(pose),
            List.append(&2,N.Member,[P.member("minor",P.bool_tag(minor)),P.member("fall_distance",P.double_tag(distance))],entity_tags(entity))))))}}

def encode_validated(result:Result<&2,&2,Error,Record>) -> Result<&2,&2,Error,List<&2,U32>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{+record}:
      Record{motion,local,sprinting,pose,minor,history,entity} = record
      do Result<&2,&2,Error,List<&2,U32>>:
        bytes : List<&2,U32> <- motion_result(List<&2,U32>,PR.encode(motion))
        nbt_result(List<&2,U32>,N.encode_with(limits(),root(record,bytes)))

def encode(record:Record) -> Result<&2,&2,Error,List<&2,U32>>:
  encode_validated(validate(record))

def bool_word(word:U32) -> Result<&2,&2,Error,Bool>:
  schema(Bool,P.bool_value(N.Byte{word},"local_keys"))

def keys_value(value:N.Value) -> Result<&2,&2,Error,PI.Buttons>:
  match value:
    case N.ByteArray{f <> b <> l <> r <> j <> s <> c <> Nil{}}:
      do Result<&2,&2,Error,PI.Buttons>:
        f : Bool <- bool_word(f)
        b : Bool <- bool_word(b)
        l : Bool <- bool_word(l)
        r : Bool <- bool_word(r)
        j : Bool <- bool_word(j)
        s : Bool <- bool_word(s)
        c : Bool <- bool_word(c)
        return PI.Buttons{f,b,l,r,j,s,c}
    case _: Fail{SchemaError{"local_keys requires seven Boolean bytes"}}

def local_value(keys:PI.Buttons,trigger:U32,crouching:Bool,value:N.Value) -> Result<&2,&2,Error,LI.State>:
  match value:
    case N.ListTag{5,N.Float{x} <> N.Float{z} <> N.Float{bx} <> N.Float{by} <> N.Float{ox} <> N.Float{oy} <> Nil{}}:
      Done{LI.State{keys,PI.Vector{P.float_bits(x),P.float_bits(z)},trigger,crouching,P.float_bits(bx),P.float_bits(by),P.float_bits(ox),P.float_bits(oy)}}
    case _: Fail{SchemaError{"local_floats requires six Float tags"}}

def pose_value(id:U32,eye:F32) -> Result<&2,&2,Error,Pose.State>:
  match id:
    case 0: Done{Pose.State{Pose.Standing{},eye,[]}}
    case 5: Done{Pose.State{Pose.Crouching{},eye,[]}}
    case _: Fail{UnsupportedPose{}}

def history_value(value:N.Value) -> Result<&2,&2,Error,H.History>:
  match value:
    case N.Double{N.Word64{hi,lo}}: Done{H.History{F.F64{hi,lo}}}
    case _: Fail{SchemaError{"fall_distance requires a Double tag"}}

def entity_value(invulnerable:U32,count:U32,value:N.Value) -> Result<&2,&2,Error,ECT.Metadata>:
  match value:
    case N.ListTag{6,N.Double{N.Word64{a,b}} <> N.Double{N.Word64{c,d}} <> N.Double{N.Word64{e,f}} <>
         N.Double{N.Word64{g,h}} <> N.Double{N.Word64{i,j}} <> N.Double{N.Word64{k,l}} <> Nil{}}:
      Done{ECT.Metadata{M.Vec3{F.F64{a,b},F.F64{c,d},F.F64{e,f}},M.Vec3{F.F64{g,h},F.F64{i,j},F.F64{k,l}},invulnerable,count}}
    case _: Fail{SchemaError{"old_positions requires six Double tags"}}

def motion_value(value:N.Value) -> Result<&2,&2,Error,PR.Record>:
  match value:
    case N.ByteArray{bytes}: motion_result(PR.Record,PR.decode(bytes))
    case _: Fail{SchemaError{"motion requires a ByteArray"}}

def decode_fields(value:N.Value) -> Result<&2,&2,Error,Record>:
  do Result<&2,&2,Error,Record>:
    +fields : List<&2,P.Field> <- schema(List<&2,P.Field>,P.fields(value,["format","motion","local_keys","local_floats","local_trigger","local_crouching","sprinting","pose","eye","minor","fall_distance","old_positions","invulnerable_time","tick_count"]))
    unit : Unit <- schema(Unit,P.version_value(P.field(fields,"format")))
    motion : PR.Record <- motion_value(P.field(fields,"motion"))
    keys : PI.Buttons <- keys_value(P.field(fields,"local_keys"))
    trigger : U32 <- schema(U32,P.int_value(P.field(fields,"local_trigger"),"local_trigger"))
    crouching : Bool <- schema(Bool,P.bool_value(P.field(fields,"local_crouching"),"local_crouching"))
    local : LI.State <- local_value(keys,trigger,crouching,P.field(fields,"local_floats"))
    sprinting : Bool <- schema(Bool,P.bool_value(P.field(fields,"sprinting"),"sprinting"))
    pose_id : U32 <- schema(U32,P.int_value(P.field(fields,"pose"),"pose"))
    eye : F32 <- schema(F32,P.float_value(P.field(fields,"eye"),"eye"))
    pose : Pose.State <- pose_value(pose_id,eye)
    minor : Bool <- schema(Bool,P.bool_value(P.field(fields,"minor"),"minor"))
    history : H.History <- history_value(P.field(fields,"fall_distance"))
    invulnerable : U32 <- schema(U32,P.int_value(P.field(fields,"invulnerable_time"),"invulnerable_time"))
    count : U32 <- schema(U32,P.int_value(P.field(fields,"tick_count"),"tick_count"))
    entity : ECT.Metadata <- entity_value(invulnerable,count,P.field(fields,"old_positions"))
    validate(Record{motion,local,sprinting,pose,LM.MinorState{minor},history,entity})

def decode_named(value:N.Value,name:String) -> Result<&2,&2,Error,Record>:
  match name:
    case "bendex:local-player-record": decode_fields(value)
    case _: Fail{SchemaError{"unexpected local-player record root name"}}

def decode_root(root:N.Root) -> Result<&2,&2,Error,Record>:
  N.Root{name,value} = root
  do Result<&2,&2,Error,Record>:
    name : String <- schema(String,P.read_text(name))
    decode_named(value,name)

def decode(bytes:List<&2,U32>) -> Result<&2,&2,Error,Record>:
  do Result<&2,&2,Error,Record>:
    root : N.Root <- nbt_result(N.Root,N.decode_with(limits(),bytes))
    decode_root(root)

law validation_failure_retains_exact_error:
  for record:Record
  for +error:Error
  {validated(record,Some{error}) == Fail{error} : Result<&2,&2,Error,Record>}

def validation_failure_retains_exact_error(record,error):
  {==}

law refused_encoding_retains_exact_error:
  for +error:Error
  {encode_validated(Fail{error}) == Fail{error} : Result<&2,&2,Error,List<&2,U32>>}

def refused_encoding_retains_exact_error(error):
  {==}
