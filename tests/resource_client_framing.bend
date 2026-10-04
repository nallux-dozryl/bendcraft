import Base
import ../src/resource_client_framing.bend as P
import ../src/framing.bend as F
import ../src/resource_client_wire.bend as W
import ./resource_client_interaction_wire.bend as Fixture

def require(valid:Bool,message:String) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,"private framing: " ++ message)

def bytes(value:String) -> List<&2,U32>:
  match value:
    case SNil{}: [10]
    case SCon{Chr{head},tail}: head <> bytes(tail)

def repeated(left:Nat,tail:List<&2,U32>) -> List<&2,U32>:
  match left:
    case Zero{}: tail
    case Succ{remaining}: 97 <> repeated(remaining,tail)

def refused(result:Result<&1,&1,String,F.Buffer & List<&2,String>>,expected:String) -> Bool:
  match result:
    case Fail{message}: String.eq(message,expected)
    case Done{other}: False{}

def one_line(result:Result<&1,&1,String,F.Buffer & List<&2,String>>,size:U32) -> Bool:
  match result:
    case Done{Tuple{F.Buffer{Nil{},0},line <> Nil{}}}: Nat.is_eq(String.length(line),U32.to_nat(size))
    case _: False{}

def resumed_completed(result:Result<&1,&1,String,F.Buffer & List<&2,String>>,expected:String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{Tuple{F.Buffer{Nil{},0},+line <> Nil{}}}:
      do IO<Unit>:
        require(String.eq(line,expected),"complete fragmented real256-row frame retained")
        Fixture.large_frame_decoded(W.decode_reply(line))
    case _: IO.die(Unit,1,"fragmented frame boundary differs")

def resumed(buffer:F.Buffer,lines:List<&2,String>,remaining:List<&2,U32>,expected:String) -> IO(Unit):
  match lines:
    case Nil{}: resumed_completed(P.feed(buffer,remaining),expected)
    case _: IO.die(Unit,1,"partial frame dispatched")

def fragmented(result:Result<&1,&1,String,F.Buffer & List<&2,String>>,remaining:List<&2,U32>,expected:String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{Tuple{buffer,lines}}: resumed(buffer,lines,remaining,expected)

def split(left:Nat,values:List<&2,U32>,reversed:List<&2,U32>) -> List<&2,U32> & List<&2,U32>:
  match left values:
    case Zero{} _: (List.reverse(&2,U32,reversed),values)
    case _ Nil{}: (List.reverse(&2,U32,reversed),[])
    case Succ{remaining} head <> tail: split(remaining,tail,head <> reversed)

def real_frame(parts:List<&2,U32> & List<&2,U32>,expected:String) -> IO(Unit):
  (first,remaining) = parts
  fragmented(P.feed(F.new(),first),remaining,expected)

def main() -> IO(Unit):
  +json = Fixture.budget_frame_json(256)
  do IO<Unit>:
    require(Nat.is_eq(String.length(json),U32.to_nat(19784)),"real frame exceeds old16384 scalar bound")
    real_frame(split(10000n,bytes(json),[]),json)
    require(one_line(P.feed(F.new(),repeated(65536n,[10])),65536),"exact65536 ASCII byte/scalar line admitted")
    require(refused(P.feed(F.new(),repeated(65537n,[10])),"line exceeds 65536 bytes before LF"),"65537 bytes refused atomically")
    require(refused(P.feed(F.new(),[97,10,128,10]),"private wire requires ASCII bytes"),"non-ASCII refuses entire feed including prior complete line")
    require(one_line(P.feed(F.new(),[97,13,10]),1),"terminal CR removed before LF")
    IO.print("PASS private framing: real19784-byte frame, fragmented authority,65536 boundary,oversize/non-ASCII atomic refusal,CRLF")
