import Base
import ./player_codec.bend as P
import ./player_look.bend as L
import ./nbt.bend as N

# Saved raw Entity degree fields accompany the neutral motion snapshot. The
# snapshot's renderer radians are checked projections, never the degree source.
type Record is Data:
  Record{motion:P.Snapshot,look:L.State}

type Error is Data:
  PlayerError{cause:P.Error}
  LookError{cause:L.Error}
  ViewMismatch{axis:U32}
  SchemaError{message:String}
  NbtError{message:String}

def limits() -> N.Limits:
  N.Limits{8192,2,4096}

def projected(look:L.State) -> F32 & F32:
  L.State{yaw,pitch,previous_yaw,previous_pitch} = look
  (L.mul(yaw,L.float_bits(1016003125)),L.mul(pitch,L.float_bits(1016003125)))

def view_match(motion:P.Snapshot,angles:F32 & F32) -> Maybe<&2,Error>:
  P.Snapshot{state,support,yaw,pitch,dimension} = motion
  (expected_yaw,expected_pitch) = angles
  N.choose(Maybe<&2,Error>,
    N.choose(Maybe<&2,Error>,None{},Some{ViewMismatch{1}},U32.is_eq(F32.bits(pitch),F32.bits(expected_pitch))),
    Some{ViewMismatch{0}},U32.is_eq(F32.bits(yaw),F32.bits(expected_yaw)))

def look_match(motion:P.Snapshot,+look:L.State,result:Maybe<&2,L.Error>) -> Maybe<&2,Error>:
  match result:
    case Some{error}: Some{LookError{error}}
    case None{}: view_match(motion,projected(look))

def first_error(motion:P.Snapshot,+look:L.State,result:Maybe<&2,P.Error>) -> Maybe<&2,Error>:
  match result:
    case Some{error}: Some{PlayerError{error}}
    case None{}: look_match(motion,look,L.state_error(look))

def record_error(record:Record) -> Maybe<&2,Error>:
  Record{+motion,look} = record
  first_error(motion,look,P.snapshot_error(motion))

def validated(record:Record,result:Maybe<&2,Error>) -> Result<&2,&2,Error,Record>:
  match result:
    case Some{error}: Fail{error}
    case None{}: Done{record}

def validate(+record:Record) -> Result<&2,&2,Error,Record>:
  validated(record,record_error(record))

def player_result(-A:Data,result:Result<&2,&2,P.Error,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{error}: Fail{PlayerError{error}}
    case Done{value}: Done{value}

def nbt_result(-A:Data,result:Result<&2,&2,String,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{error}: Fail{NbtError{error}}
    case Done{value}: Done{value}

def look_tag(look:L.State) -> N.Value:
  L.State{yaw,pitch,previous_yaw,previous_pitch} = look
  N.ListTag{5,[N.Float{F32.bits(yaw)},N.Float{F32.bits(pitch)},N.Float{F32.bits(previous_yaw)},N.Float{F32.bits(previous_pitch)}]}

def root(look:L.State,motion:List<&2,U32>) -> N.Root:
  N.Root{P.text("bendex:player-record"),N.Compound{[
    P.member("format",N.Int{1}),P.member("motion",N.ByteArray{motion}),
    P.member("look",look_tag(look))]}}

def encode_validated(result:Result<&2,&2,Error,Record>) -> Result<&2,&2,Error,List<&2,U32>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Record{motion,look}}:
      do Result<&2,&2,Error,List<&2,U32>>:
        bytes : List<&2,U32> <- player_result(List<&2,U32>,P.encode(motion))
        nbt_result(List<&2,U32>,N.encode_with(limits(),root(look,bytes)))

def encode(record:Record) -> Result<&2,&2,Error,List<&2,U32>>:
  encode_validated(validate(record))

def motion_value(value:N.Value) -> Result<&2,&2,Error,P.Snapshot>:
  match value:
    case N.ByteArray{bytes}: player_result(P.Snapshot,P.decode(bytes))
    case _: Fail{SchemaError{"motion must be a ByteArray"}}

def look_values(values:List<&2,N.Value>) -> Result<&2,&2,Error,L.State>:
  match values:
    case N.Float{yaw} <> N.Float{pitch} <> N.Float{previous_yaw} <> N.Float{previous_pitch} <> Nil{}:
      Done{L.State{L.float_bits(yaw),L.float_bits(pitch),L.float_bits(previous_yaw),L.float_bits(previous_pitch)}}
    case _: Fail{SchemaError{"look must contain exactly four Float tags"}}

def look_value(value:N.Value) -> Result<&2,&2,Error,L.State>:
  match value:
    case N.ListTag{5,values}: look_values(values)
    case _: Fail{SchemaError{"look must declare Float list element type"}}

def decode_fields(value:N.Value) -> Result<&2,&2,Error,Record>:
  do Result<&2,&2,Error,Record>:
    +fields : List<&2,P.Field> <- player_result(List<&2,P.Field>,P.fields(value,["format","motion","look"]))
    unit : Unit <- player_result(Unit,P.version_value(P.field(fields,"format")))
    motion : P.Snapshot <- motion_value(P.field(fields,"motion"))
    look : L.State <- look_value(P.field(fields,"look"))
    validate(Record{motion,look})

def decode_named(value:N.Value,name:String) -> Result<&2,&2,Error,Record>:
  match name:
    case "bendex:player-record": decode_fields(value)
    case _: Fail{SchemaError{"unexpected record root name"}}

def decode_root(root:N.Root) -> Result<&2,&2,Error,Record>:
  N.Root{name,value} = root
  do Result<&2,&2,Error,Record>:
    name : String <- player_result(String,P.read_text(name))
    decode_named(value,name)

def decode(bytes:List<&2,U32>) -> Result<&2,&2,Error,Record>:
  do Result<&2,&2,Error,Record>:
    root : N.Root <- nbt_result(N.Root,N.decode_with(limits(),bytes))
    decode_root(root)

law validation_failure_returns_exact_error:
  for record:Record
  for +error:Error
  {validated(record,Some{error}) == Fail{error} : Result<&2,&2,Error,Record>}

def validation_failure_returns_exact_error(record,error):
  {==}

law rejected_encoding_preserves_error:
  for +error:Error
  {encode_validated(Fail{error}) == Fail{error} : Result<&2,&2,Error,List<&2,U32>>}

def rejected_encoding_preserves_error(error):
  {==}
