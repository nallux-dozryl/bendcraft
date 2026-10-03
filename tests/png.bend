import Base
import ../src/png.bend as P
import ../src/compression.bend as C

def numbers(pixels: List<&2,U32>, first: Bool) -> String:
  match pixels:
    case Nil{}: ""
    case p <> rest: P.choose(String,"",",",first) ++ U32.show(p) ++ numbers(rest,False{})

def report(name: String,result: Result<&2,&1,P.Error,P.Decoded>,all: Bool) -> String:
  match result:
    case Fail{P.Error{code}}: "{\"path\":\"" ++ name ++ "\",\"error\":\"" ++ code ++ "\"}"
    case Done{P.Decoded{w,h,+pixels}}:
      "{\"path\":\"" ++ name ++ "\",\"width\":" ++ U32.show(w) ++ ",\"height\":" ++ U32.show(h) ++ ",\"rgba_crc32\":" ++ U32.show(C.crc32(P.rgba_bytes(pixels))) ++ P.choose(String,",\"pixels\":[" ++ numbers(pixels,True{}) ++ "]","",all) ++ "}"

def show_read(name: String,result: Result<&1,&1,U32 & String,List<&2,U32>>,all: Bool) -> IO(Unit):
  match result:
    case Fail{(code,message)}: IO.print("{\"error\":\"FileIO\"}")
    case Done{bytes}: IO.print(report(name,P.decode(bytes,P.default_limits()),all))

def read_done(name: String,read: File & Result<&1,&1,U32 & String,List<&2,U32>>,all: Bool) -> IO(Unit):
  (file,result) = read
  do IO<Unit>:
    File.close(file)
    show_read(name,result,all)

def one(+path: String,all: Bool) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"r"))
    read : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,16777217)
    read_done(path,read,all)

def files(paths: List<String>,+all: Bool) -> IO(Unit):
  match paths:
    case Nil{}: IO.pure(Unit,Unit{})
    case path <> tail:
      do IO<Unit>:
        one(path,all)
        files(tail,all)

def options_flag(tail: List<String>,is_flag: Bool,flag: String) -> IO(Unit):
  match is_flag:
    case True{}: files(tail,True{})
    case False{}: files(flag <> tail,False{})

def options(args: List<String>) -> IO(Unit):
  match args:
    case +flag <> tail: options_flag(tail,String.eq(flag,"--pixels"),flag)
    case Nil{}: IO.die(Unit,1,"expected PNG paths")

def start(args: List<String>) -> IO(Unit):
  match args:
    case program <> tail: options(tail)
    case Nil{}: IO.die(Unit,1,"missing argv")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(args)
