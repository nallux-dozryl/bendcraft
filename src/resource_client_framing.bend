import Base
import ./framing.bend as F
import ./resource_client_wire.bend as W

# Private requests and replies are ASCII JSON, including escaped Unicode fields. Their
# scalar and byte bounds are therefore identical. The general UTF-8 framer's
# 16384-scalar policy remains appropriate for the separate public protocol.
def text(reversed:List<&2,U32>,result:String) -> String:
  match reversed:
    case Nil{}: result
    case head <> tail: text(tail,SCon{Chr{head},result})

def admitted(valid:Bool,progress:F.Progress,+byte:U32) -> Result<&2,&2,String,F.Progress>:
  match valid progress:
    case False{} _: Fail{"private wire requires ASCII bytes"}
    case True{} F.Progress{F.Buffer{reversed,+size},lines}:
      match byte:
        case 10: Done{F.Progress{F.new(),text(F.trim_cr(reversed),SNil{}) <> lines}}
        case _: F.append_byte(U32.is_lt(size,W.transport_bytes()),byte,reversed,size,lines)

def loop(bytes:List<&2,U32>,result:Result<&2,&2,String,F.Progress>) -> Result<&1,&1,String,F.Buffer & List<&2,String>>:
  match bytes result:
    case _ Fail{message}: Fail{message}
    case Nil{} Done{F.Progress{buffer,lines}}: Done{(buffer,List.reverse(&2,String,lines))}
    case +head <> tail Done{progress}: loop(tail,admitted(U32.is_lt(head,128),progress,head))

# Preserve framing's atomic failure, partial-line buffer and forward line order.
def feed(buffer:F.Buffer,bytes:List<&2,U32>) -> Result<&1,&1,String,F.Buffer & List<&2,String>>:
  loop(bytes,Done{F.Progress{buffer,[]}})
