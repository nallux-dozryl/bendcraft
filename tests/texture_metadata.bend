import Base
import ../src/texture_metadata.bend as T
import ../src/json.bend as J
import ../src/resource_json.bend as Q

# Narrow driver: no imports of other test modules or asset/model render graphs.
def text(value:String) -> J.Value:
  J.JString{value}

def metadata(value:T.Metadata) -> J.Value:
  T.Metadata{blur,clamp,strategy,bias} = value
  J.JObject{[J.JMember{"status",text("ok")},J.JMember{"blur",J.JBool{blur}},J.JMember{"clamp",J.JBool{clamp}},J.JMember{"strategy",text(T.strategy_name(strategy))},J.JMember{"alpha_cutoff_bias_u32",J.JNumber{U32.show(F32.bits(bias))}}]}

def error(value:T.Error) -> J.Value:
  T.Error{code,field,message} = value
  J.JObject{[J.JMember{"status",text("error")},J.JMember{"code",text(code)},J.JMember{"field",text(field)},J.JMember{"message",text(message)}]}

def section_result(value:Result<&2,&2,T.Error,T.Metadata>) -> J.Value:
  match value:
    case Fail{e}: error(e)
    case Done{m}: metadata(m)

def section(value:Result<&2,&2,String,J.Value>) -> J.Value:
  match value:
    case Fail{message}: error(T.Error{"InvalidJson","",message})
    case Done{v}: section_result(T.decode_section(v))

def document(value:Result<&2,&2,T.Error,Maybe<&2,T.Metadata>>) -> J.Value:
  match value:
    case Fail{e}: error(e)
    case Done{None{}}: J.JObject{[J.JMember{"status",text("absent")}]}
    case Done{Some{m}}: metadata(m)

def lookup(value:Maybe<&2,J.Value>) -> String:
  match value:
    case Some{J.JString{s}}: s
    case _: ""

def integer_result(value:Maybe<&2,U32>,fallback:U32) -> U32:
  match value:
    case Some{n}: n
    case _: fallback

def integer(value:Maybe<&2,J.Value>,fallback:U32) -> U32:
  match value:
    case Some{v}: integer_result(J.as_u32(v),fallback)
    case _: fallback

def limits(+value:J.Value) -> J.Limits:
  J.Limits{U32.to_nat(integer(J.member(value,"max_codepoints"),1048576)),integer(J.member(value,"max_depth"),255)}

def parsed(+value:J.Value,raw:String,mode:String) -> J.Value:
  match mode:
    case "section": section(Q.parse(raw))
    case "number": section_result(T.decode_section(J.JObject{[J.JMember{"alpha_cutoff_bias",J.JNumber{raw}}]}))
    case "limited": document(T.parse_document_with(raw,limits(value)))
    case _: document(T.parse_document(raw))

def config(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{+v}: IO.print(J.encode(parsed(v,lookup(J.member(v,"json")),lookup(J.member(v,"mode")))))

def run_args(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        config(J.parse(arg))
        run_args(rest)

def drop_program(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case program <> rest: run_args(rest)

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),drop_program)
