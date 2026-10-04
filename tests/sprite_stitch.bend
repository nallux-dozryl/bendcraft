import Base
import ../src/sprite_stitch.bend as S
import ../src/json.bend as J

type Case is Data:
  PackCase{id:String,config:S.Config,entries:List<&2,S.Entry>,limits:S.Limits,recover:Bool}
  RawCase{id:String,value:U32,level:U32,setting:U32}

def map(~A:Data,~B:Data,~f:A -> B,values:List<&2,A>) -> List<&2,B>:
  match values:
    case Nil{}: []
    case h <> rest: f(h) <> map(~A,~B,~f,rest)

def number(value:U32) -> J.Value:
  J.JNumber{U32.show(value)}
def text(value:String) -> J.Value:
  J.JString{value}
def integer(found:Maybe<&2,J.Value>,fallback:U32) -> U32:
  match found:
    case Some{v}: Maybe.default(&2,U32,J.as_u32(v),fallback)
    case _: fallback
def string(found:Maybe<&2,J.Value>) -> String:
  match found:
    case Some{J.JString{s}}: s
    case _: ""
def boolean(found:Maybe<&2,J.Value>) -> Bool:
  match found:
    case Some{J.JBool{b}}: b
    case _: False{}

def entry_members(value:S.Entry) -> List<&2,J.Member>:
  S.Entry{ns,path,w,h,tag} = value
  [J.JMember{"namespace",text(ns)},J.JMember{"path",text(path)},J.JMember{"width",number(w)},J.JMember{"height",number(h)},J.JMember{"tag",number(tag)}]
def entry(value:S.Entry) -> J.Value:
  J.JObject{entry_members(value)}
def entries(values:List<&2,S.Entry>) -> J.Value:
  J.JArray{map(~S.Entry,~J.Value,~entry,values)}
def holder(value:S.Holder) -> J.Value:
  S.Holder{e,w,h} = value
  J.JObject{List.append(&2,J.Member,entry_members(e),[J.JMember{"padded_width",number(w)},J.JMember{"padded_height",number(h)}])}
def placement(value:S.Placement,padding:U32) -> J.Value:
  S.Placement{S.Holder{e,w,h},x,y} = value
  J.JObject{List.append(&2,J.Member,entry_members(e),[J.JMember{"x",number(x)},J.JMember{"y",number(y)},J.JMember{"padding",number(padding)}])}
def placed(values:List<&2,S.Placement>,+padding:U32) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case p <> rest: placement(p,padding) <> placed(rest,padding)
def packed(+value:S.Packed,config:S.Config) -> J.Value:
  S.Packed{w,h,+p,sorted,placements} = value
  J.JObject{[J.JMember{"width",number(w)},J.JMember{"height",number(h)},J.JMember{"padding",number(p)},J.JMember{"sorted",J.JArray{map(~S.Holder,~J.Value,~holder,sorted)}},J.JMember{"placements",J.JArray{placed(placements,p)}},J.JMember{"complete_within",J.JBool{S.complete_within(value,config)}}]}
def optional(value:Maybe<&2,S.Packed>,config:S.Config) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{p}: packed(p,config)
def status(value:Result<&2,&2,S.Error,S.Packed>,config:S.Config) -> J.Value:
  match value:
    case Done{p}: J.JObject{[J.JMember{"status",text("ok")},J.JMember{"packed",packed(p,config)}]}
    case Fail{S.Error{code,tag,partial}}: J.JObject{[J.JMember{"status",text("error")},J.JMember{"code",text(code)},J.JMember{"tag",number(tag)},J.JMember{"partial",optional(partial,config)}]}
def config(value:S.Config) -> J.Value:
  S.Config{w,h,l,p} = value
  J.JObject{[J.JMember{"max_width",number(w)},J.JMember{"max_height",number(h)},J.JMember{"mip_level",number(l)},J.JMember{"padding_setting",number(p)}]}
def closed(value:S.Request & Result<&2,&2,S.Error,S.Packed>) -> J.Value:
  (request,result) = value
  S.Request{+c,es} = request
  status(result,c)
def recovery(value:Bool,request:S.Request) -> J.Value:
  match value:
    case False{}:
      ignored = S.close_request(request)
      J.JNull{}
    case True{}:
      S.Request{old,es} = request
      closed(S.pack(S.Request{S.Config{16384,16384,0,0},es},S.defaults()))
def report(value:S.Request & Result<&2,&2,S.Error,S.Packed>,recover:Bool) -> J.Value:
  (request,result) = value
  S.Request{+c,+es} = request
  J.JObject{[J.JMember{"result",status(result,c)},J.JMember{"owner",J.JObject{[J.JMember{"config",config(c)},J.JMember{"entries",entries(es)}]}},J.JMember{"recovery",recovery(recover,S.Request{c,es})}]}

def parse_entry(+value:J.Value) -> S.Entry:
  S.Entry{string(J.member(value,"namespace")),string(J.member(value,"path")),integer(J.member(value,"width"),0),integer(J.member(value,"height"),0),integer(J.member(value,"tag"),0)}
def parse_entries(found:Maybe<&2,J.Value>) -> List<&2,S.Entry>:
  match found:
    case Some{J.JArray{values}}: map(~J.Value,~S.Entry,~(v => parse_entry(v)),values)
    case _: []
def parse_config(+value:J.Value) -> S.Config:
  S.Config{integer(J.member(value,"max_width"),0),integer(J.member(value,"max_height"),0),integer(J.member(value,"mip_level"),0),integer(J.member(value,"padding_setting"),0)}
def parse_kind(kind:String,+value:J.Value) -> Case:
  match kind:
    case "raw": RawCase{string(J.member(value,"id")),integer(J.member(value,"value"),0),integer(J.member(value,"level"),0),integer(J.member(value,"padding_setting"),0)}
    case _: PackCase{string(J.member(value,"id")),parse_config(value),parse_entries(J.member(value,"entries")),S.Limits{integer(J.member(value,"max_entries"),4096),integer(J.member(value,"max_id_codepoints"),4096)},boolean(J.member(value,"recover"))}
def parse_case(+value:J.Value) -> Case:
  parse_kind(string(J.member(value,"mode")),value)
def parse_cases(value:Result<&2,&2,String,J.Value>) -> Result<&2,&2,String,List<&2,Case>>:
  match value:
    case Fail{e}: Fail{e}
    case Done{J.JArray{values}}: Done{map(~J.Value,~Case,~(v => parse_case(v)),values)}
    case _: Fail{"Expected fixture array"}

def result(value:Case) -> J.Value:
  match value:
    case PackCase{id,+c,es,limits,recover}: report(S.pack(S.Request{c,es},limits),recover)
    case RawCase{id,+v,+level,setting}: J.JObject{[J.JMember{"rounded",number(S.round_raw(v,level))},J.JMember{"power_of_two",number(S.power_raw(v))},J.JMember{"padding",number(S.padding_raw(level,setting))}]}
def case_id(value:Case) -> String:
  match value:
    case PackCase{id,c,es,l,r}: id
    case RawCase{id,v,l,p}: id
def measured(+serialized:String,+id:String,before:Nat) -> IO(Unit):
  do IO<Unit>:
    IO.print("force|" ++ id ++ "|" ++ Nat.show(String.length(serialized)))
    ended : Nat <- IO.now()
    IO.print("time|" ++ id ++ "|" ++ Nat.show(Nat.sub(ended,before)))
    IO.print(serialized)
def run_cases(values:List<&2,Case>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case +c <> rest:
      do IO<Unit>:
        before : Nat <- IO.now()
        measured(J.encode(J.JObject{[J.JMember{"id",text(case_id(c))},J.JMember{"value",result(c)}]}),case_id(c),before)
        run_cases(rest)
def parsed(value:Result<&2,&2,String,List<&2,Case>>) -> IO(Unit):
  match value:
    case Fail{e}: IO.die(Unit,1,e)
    case Done{cs}: run_cases(cs)
def loaded(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,read) = value
  do IO<Unit>:
    File.close(file)
    source : String <- IO.pass(String,read)
    parsed(parse_cases(J.parse_with(source,J.Limits{4194304n,32})))
def file(path:String) -> IO(Unit):
  do IO<Unit>:
    input : File <- IO.try(File,File.open(path,"r"))
    value : File & Result<&1,&1,U32 & String,String> <- File.read(input,4194304)
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
