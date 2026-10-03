import Base
import ../src/player_record.bend as R
import ../src/player_codec.bend as P
import ../src/player_look.bend as L

def error_name(error:R.Error) -> String:
  match error:
    case R.PlayerError{cause}: "PlayerError"
    case R.LookError{cause}: "LookError"
    case R.ViewMismatch{axis}: "ViewMismatch" ++ U32.show(axis)
    case R.SchemaError{message}: "SchemaError"
    case R.NbtError{message}: "NbtError"

def failed(error:R.Error) -> IO(Unit):
  IO.print("error=" ++ error_name(error))

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
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,8193)
    loaded(result)

def little_words(bytes:List<&2,U32>,acc:List<&2,U32>) -> Result<&2,&2,String,List<&2,U32>>:
  match bytes:
    case Nil{}: Done{List.reverse(&2,U32,acc)}
    case a <> b <> c <> d <> rest:
      little_words(rest,U32.or(a,U32.or(U32.shln(b,8n),U32.or(U32.shln(c,16n),U32.shln(d,24n)))) <> acc)
    case _: Fail{"look fixture byte count must be divisible by four"}

def look_words(words:List<&2,U32>) -> Result<&2,&2,String,L.State>:
  match words:
    case yaw <> pitch <> previous_yaw <> previous_pitch <> Nil{}:
      Done{L.State{L.float_bits(yaw),L.float_bits(pitch),L.float_bits(previous_yaw),L.float_bits(previous_pitch)}}
    case _: Fail{"look fixture requires four raw words"}

def parse_look(bytes:List<&2,U32>) -> Result<&2,&2,String,L.State>:
  do Result<&2,&2,String,L.State>:
    words : List<&2,U32> <- little_words(bytes,Nil{})
    look_words(words)

def word_bytes(+word:U32) -> List<&2,U32>:
  [U32.and(word,255),U32.and(U32.shrn(word,8n),255),U32.and(U32.shrn(word,16n),255),U32.shrn(word,24n)]

def words_bytes(words:List<&2,U32>) -> List<&2,U32>:
  match words:
    case Nil{}: Nil{}
    case word <> rest: List.append(&2,U32,word_bytes(word),words_bytes(rest))

def look_bytes(look:L.State) -> List<&2,U32>:
  L.State{yaw,pitch,previous_yaw,previous_pitch} = look
  words_bytes([F32.bits(yaw),F32.bits(pitch),F32.bits(previous_yaw),F32.bits(previous_pitch)])

def encoded(output:String,result:Result<&2,&2,R.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Fail{error}: failed(error)
    case Done{bytes}:
      do IO<Unit>:
        publish(output,bytes)
        IO.print("ok=encode")

def encoding_look(motion:P.Snapshot,output:String,result:Result<&2,&2,String,L.State>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{look}: encoded(output,R.encode(R.Record{motion,look}))

def encoding_motion(look_path:String,output:String,result:Result<&2,&2,P.Error,P.Snapshot>) -> IO(Unit):
  match result:
    case Fail{error}: failed(R.PlayerError{error})
    case Done{motion}:
      do IO<Unit>:
        bytes : List<&2,U32> <- read(look_path)
        encoding_look(motion,output,parse_look(bytes))

def decoded_motion(output:String,look_path:String,look:L.State,result:Result<&2,&2,P.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Fail{error}: failed(R.PlayerError{error})
    case Done{bytes}:
      do IO<Unit>:
        publish(output,bytes)
        publish(look_path,look_bytes(look))
        IO.print("ok=decode")

def decoded(output:String,look_path:String,result:Result<&2,&2,R.Error,R.Record>) -> IO(Unit):
  match result:
    case Fail{error}: failed(error)
    case Done{R.Record{motion,look}}: decoded_motion(output,look_path,look,P.encode(motion))

def execute(mode:String,look_path:String,output:String,bytes:List<&2,U32>) -> IO(Unit):
  match mode:
    case "encode": encoding_motion(look_path,output,P.decode(bytes))
    case "decode": decoded(output,look_path,R.decode(bytes))
    case _: IO.die(Unit,2,"expected encode or decode")

def batch(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case mode <> input <> look_path <> output <> rest:
      do IO<Unit>:
        bytes : List<&2,U32> <- read(input)
        execute(mode,look_path,output,bytes)
        batch(rest)
    case _: IO.die(Unit,2,"expected MODE INPUT LOOK OUTPUT groups")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1,String,args))
