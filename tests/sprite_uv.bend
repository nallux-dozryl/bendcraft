import Base
import ../src/sprite_uv.bend as S
import ../src/json.bend as J

type Case is Data:
  Case{id:String,input:S.Input,queries:List<&2,U32>}

def map(~A:Data,~B:Data,~f:A -> B,values:List<&2,A>) -> List<&2,B>:
  match values:
    case Nil{}: []
    case h <> rest: f(h) <> map(~A,~B,~f,rest)
def number(value:U32) -> J.Value:
  J.JNumber{U32.show(value)}
def integer(found:Maybe<&2,J.Value>) -> U32:
  match found:
    case Some{v}: Maybe.default(&2,U32,J.as_u32(v),0)
    case _: 0
def string(found:Maybe<&2,J.Value>) -> String:
  match found:
    case Some{J.JString{s}}: s
    case _: ""
def raw(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}
def input(value:S.Input) -> J.Value:
  S.Input{aw,ah,w,h,x,y,p} = value
  J.JObject{[J.JMember{"atlas_width",number(aw)},J.JMember{"atlas_height",number(ah)},J.JMember{"width",number(w)},J.JMember{"height",number(h)},J.JMember{"x",number(x)},J.JMember{"y",number(y)},J.JMember{"padding",number(p)}]}
def uv(value:S.UV) -> J.Value:
  S.UV{u,v} = value
  J.JArray{[number(F32.bits(u)),number(F32.bits(v))]}
def corners(value:S.Corners) -> J.Value:
  S.Corners{a,b,c,d} = value
  J.JArray{[uv(a),uv(b),uv(c),uv(d)]}
def query(+value:U32,+m:S.Mapping) -> J.Value:
  J.JObject{[J.JMember{"query",number(value)},J.JMember{"u",number(F32.bits(S.get_u(m,raw(value))))},J.JMember{"v",number(F32.bits(S.get_v(m,raw(value))))},J.JMember{"map",uv(S.map(m,S.UV{raw(value),raw(value)}))}]}
def queries(values:List<&2,U32>,+m:S.Mapping) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case q <> rest: query(q,m) <> queries(rest,m)
def mapping(+value:S.Mapping,qs:List<&2,U32>) -> J.Value:
  S.Mapping{original,cx,cy,u0,v0,u1,v1} = value
  J.JObject{[J.JMember{"input",input(original)},J.JMember{"content_x",number(cx)},J.JMember{"content_y",number(cy)},J.JMember{"u0",number(F32.bits(u0))},J.JMember{"v0",number(F32.bits(v0))},J.JMember{"u1",number(F32.bits(u1))},J.JMember{"v1",number(F32.bits(v1))},J.JMember{"corners",corners(S.corners(value))},J.JMember{"mapped_corners",corners(S.mapped_corners(value))},J.JMember{"queries",J.JArray{queries(qs,value)}}]}
def derived(value:Result<&2,&2,S.Error,S.Mapping>) -> J.Value:
  match value:
    case Fail{S.Error{code}}: J.JObject{[J.JMember{"status",J.JString{"error"}},J.JMember{"code",J.JString{code}}]}
    case Done{S.Mapping{i,cx,cy,u0,v0,u1,v1}}: J.JObject{[J.JMember{"status",J.JString{"ok"}},J.JMember{"u0",number(F32.bits(u0))},J.JMember{"v0",number(F32.bits(v0))},J.JMember{"u1",number(F32.bits(u1))},J.JMember{"v1",number(F32.bits(v1))}]}
def result(value:Case) -> J.Value:
  Case{id,+i,qs} = value
  J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"raw",mapping(S.raw_mapping(i),qs)},J.JMember{"derive",derived(S.derive(i))}]}

def parse_input(+value:J.Value) -> S.Input:
  S.Input{integer(J.member(value,"atlas_width")),integer(J.member(value,"atlas_height")),integer(J.member(value,"width")),integer(J.member(value,"height")),integer(J.member(value,"x")),integer(J.member(value,"y")),integer(J.member(value,"padding"))}
def parse_word(value:J.Value) -> U32:
  Maybe.default(&2,U32,J.as_u32(value),0)
def parse_queries(found:Maybe<&2,J.Value>) -> List<&2,U32>:
  match found:
    case Some{J.JArray{qs}}: map(~J.Value,~U32,~parse_word,qs)
    case _: []
def parse_case(+value:J.Value) -> Case:
  Case{string(J.member(value,"id")),parse_input(value),parse_queries(J.member(value,"queries"))}
def parse_cases(value:Result<&2,&2,String,J.Value>) -> Result<&2,&2,String,List<&2,Case>>:
  match value:
    case Fail{e}: Fail{e}
    case Done{J.JArray{values}}: Done{map(~J.Value,~Case,~(v => parse_case(v)),values)}
    case _: Fail{"Expected fixture array"}
def run(values:List<&2,Case>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case c <> rest:
      do IO<Unit>:
        IO.print(J.encode(result(c)))
        run(rest)
def parsed(value:Result<&2,&2,String,List<&2,Case>>) -> IO(Unit):
  match value:
    case Fail{e}: IO.die(Unit,1,e)
    case Done{values}: run(values)
def loaded(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,read) = value
  do IO<Unit>:
    File.close(file)
    source : String <- IO.pass(String,read)
    parsed(parse_cases(J.parse_with(source,J.Limits{1048576n,32})))
def file(path:String) -> IO(Unit):
  do IO<Unit>:
    input : File <- IO.try(File,File.open(path,"r"))
    value : File & Result<&1,&1,U32 & String,String> <- File.read(input,1048576)
    loaded(value)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case path <> rest:
      do IO<Unit>:
        file(path)
        arguments(rest)
def drop_program(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case program <> rest: arguments(rest)
def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),drop_program)
