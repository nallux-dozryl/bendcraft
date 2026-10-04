import Base
import ../src/texture_mipmap.bend as M
import ../src/json.bend as J

type InputLevel is Data:
  InputLevel{width:U32,height:U32,capacity:U32,pixels:List<&2,U32>,unbalanced:Bool}
type Case is Data:
  FrameCase{id:String,levels:List<&2,InputLevel>,config:M.Config,limits:M.Limits}
  QuadCase{id:String,a:U32,b:U32,c:U32,d:U32}
  TableCase{id:String}
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
def boolean(found:Maybe<&2,J.Value>) -> Bool:
  match found:
    case Some{J.JBool{b}}: b
    case _: False{}
def raw(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}
def word(value:J.Value) -> U32:
  Maybe.default(&2,U32,J.as_u32(value),0)
def words(found:Maybe<&2,J.Value>) -> List<&2,U32>:
  match found:
    case Some{J.JArray{values}}: map(~J.Value,~U32,~word,values)
    case _: []
def parse_strategy(value:String) -> M.Strategy:
  match value:
    case "auto": M.Auto{}
    case "cutout": M.Cutout{}
    case "strict_cutout": M.StrictCutout{}
    case "dark_cutout": M.DarkCutout{}
    case _: M.Mean{}
def parse_level(+v:J.Value) -> InputLevel:
  InputLevel{integer(J.member(v,"width")),integer(J.member(v,"height")),integer(J.member(v,"capacity")),words(J.member(v,"pixels")),boolean(J.member(v,"unbalanced"))}
def parse_levels(value:Maybe<&2,J.Value>) -> List<&2,InputLevel>:
  match value:
    case Some{J.JArray{vs}}: map(~J.Value,~InputLevel,~(v => parse_level(v)),vs)
    case _: []
def parse_config(+v:J.Value) -> M.Config:
  M.Config{string(J.member(v,"path")),integer(J.member(v,"target_level")),parse_strategy(string(J.member(v,"strategy"))),raw(integer(J.member(v,"bias"))),M.Transparency{boolean(J.member(v,"transparent")),boolean(J.member(v,"translucent"))}}
def parse_limits(value:Maybe<&2,J.Value>) -> M.Limits:
  match value:
    case None{}: M.defaults()
    case Some{+v}: M.Limits{integer(J.member(v,"max_dimension")),integer(J.member(v,"max_levels")),integer(J.member(v,"max_capacity")),integer(J.member(v,"max_work_pixels")),integer(J.member(v,"max_path_codepoints"))}
def parse_kind(+v:J.Value,kind:String) -> Case:
  match kind:
    case "quad": QuadCase{string(J.member(v,"id")),integer(J.member(v,"a")),integer(J.member(v,"b")),integer(J.member(v,"c")),integer(J.member(v,"d"))}
    case "table": TableCase{string(J.member(v,"id"))}
    case _: FrameCase{string(J.member(v,"id")),parse_levels(J.member(v,"levels")),parse_config(v),parse_limits(J.member(v,"limits"))}
def parse_case(+v:J.Value) -> Case:
  parse_kind(v,string(J.member(v,"kind")))
def write_pixels(values:List<&2,U32>,pixels:Array<U32>,+index:U32) -> Array<U32>:
  match values:
    case Nil{}: pixels
    case v <> rest: write_pixels(rest,Array.set(U32,pixels,index,v),U32.add(index,1))
def at(values:List<&2,U32>,index:Nat) -> U32:
  match values index:
    case Nil{} _: 0
    case v <> rest 0n: v
    case v <> rest 1n+p: at(rest,p)
def make_array(+values:List<&2,U32>,capacity:U32,unbalanced:Bool) -> Array<U32>:
  match unbalanced:
    case True{}: ANode{ALeaf{at(values,0n)},ANode{ALeaf{at(values,1n)},ALeaf{at(values,2n)}}}
    case False{}: write_pixels(values,Array.new(U32,M.array_depth(24n,capacity,1),0),0)
def make_level(value:InputLevel) -> M.Level:
  InputLevel{w,h,capacity,values,unbalanced} = value
  M.Level{w,h,make_array(values,capacity,unbalanced)}
def make_levels(values:List<&2,InputLevel>) -> List<&1,M.Level>:
  match values:
    case Nil{}: []
    case h <> rest: make_level(h) <> make_levels(rest)
def append(values:List<&2,U32>,tail:List<&2,U32>) -> List<&2,U32>:
  match values:
    case Nil{}: tail
    case h <> rest: h <> append(rest,tail)
# Borrowed scalar diagnostics rebuild the same owned tree shape, never clone it.
def borrow(pixels:Array<U32>) -> Array<U32> & List<&2,U32>:
  match pixels:
    case ALeaf{+p}: (ALeaf{p},[p])
    case ANode{left,right}: M.paired(Array<U32>,List<&2,U32>,Array<U32> & List<&2,U32>,borrow(left),left => a => M.paired(Array<U32>,List<&2,U32>,Array<U32> & List<&2,U32>,borrow(right),right => b => (ANode{left,right},append(a,b))))
def level_json(+w:U32,+h:U32,+pixels:List<&2,U32>) -> J.Value:
  J.JObject{[J.JMember{"width",number(w)},J.JMember{"height",number(h)},J.JMember{"capacity",number(U32.from_nat(List.length(&2,U32,pixels)))},J.JMember{"pixels",J.JArray{map(~U32,~J.Value,~number,pixels)}}]}
def snapshot_level(value:M.Level) -> M.Level & J.Value:
  M.Level{+w,+h,pixels} = value
  M.paired(Array<U32>,List<&2,U32>,M.Level & J.Value,borrow(pixels),pixels => words => (M.Level{w,h,pixels},level_json(w,h,words)))
def snapshot_levels(values:List<&1,M.Level>) -> List<&1,M.Level> & List<&2,J.Value>:
  match values:
    case Nil{}: ([],[])
    case h <> rest: M.paired(M.Level,J.Value,List<&1,M.Level> & List<&2,J.Value>,snapshot_level(h),h => head => M.paired(List<&1,M.Level>,List<&2,J.Value>,List<&1,M.Level> & List<&2,J.Value>,snapshot_levels(rest),rest => tail => (h<>rest,head<>tail)))
def snapshot(value:M.Chain) -> M.Chain & J.Value:
  M.Chain{levels} = value
  M.paired(List<&1,M.Level>,List<&2,J.Value>,M.Chain & J.Value,snapshot_levels(levels),levels => values => (M.Chain{levels},J.JArray{values}))
def dimension(value:M.Dimension) -> J.Value:
  M.Dimension{w,h,c} = value
  J.JObject{[J.JMember{"width",number(w)},J.JMember{"height",number(h)},J.JMember{"capacity",number(c)}]}
def summary(value:Result<&2,&2,M.Error,M.Summary>) -> J.Value:
  match value:
    case Fail{M.Error{code,index}}: J.JObject{[J.JMember{"status",J.JString{"error"}},J.JMember{"code",J.JString{code}},J.JMember{"level",number(index)}]}
    case Done{M.Summary{s,early,pre,count,dims}}: J.JObject{[J.JMember{"status",J.JString{"ok"}},J.JMember{"effective",J.JString{M.strategy_name(s)}},J.JMember{"early_return",J.JBool{early}},J.JMember{"base_preconditioned",J.JBool{pre}},J.JMember{"original_levels",number(count)},J.JMember{"dimensions",J.JArray{map(~M.Dimension,~J.Value,~dimension,dims)}}]}
def close_output(chain:M.Chain,value:J.Value) -> J.Value:
  M.Chain{levels} = chain
  value
def transparency(value:Result<&2,&2,M.Error,M.Transparency>) -> J.Value:
  match value:
    case Done{M.Transparency{a,b}}: J.JObject{[J.JMember{"status",J.JString{"ok"}},J.JMember{"transparent",J.JBool{a}},J.JMember{"translucent",J.JBool{b}}]}
    case Fail{M.Error{c,i}}: J.JObject{[J.JMember{"status",J.JString{"error"}},J.JMember{"code",J.JString{c}},J.JMember{"level",number(i)}]}
def compute(value:M.Chain) -> M.Chain & J.Value:
  match value:
    case M.Chain{Nil{}}: (M.Chain{[]},J.JObject{[J.JMember{"status",J.JString{"empty"}}]})
    case M.Chain{first<>rest}: M.paired(M.Level,Result<&2,&2,M.Error,M.Transparency>,M.Chain & J.Value,M.compute_transparency(first,M.defaults()),first => found => (M.Chain{first<>rest},transparency(found)))
def recover(id:String,computed:J.Value,before:J.Value,result:J.Value,after:J.Value,chain:M.Chain) -> J.Value:
  M.paired(M.Chain,Result<&2,&2,M.Error,M.Summary>,J.Value,M.generate(chain,M.Config{"item/recovery",0,M.Mean{},0.0,M.Transparency{False{},False{}}},M.defaults()),chain => recovery => M.paired(M.Chain,J.Value,J.Value,snapshot(chain),chain => recovered => close_output(chain,J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"computed",computed},J.JMember{"before",before},J.JMember{"result",result},J.JMember{"after",after},J.JMember{"recovery",summary(recovery)},J.JMember{"recovered",recovered}]})))
def frame(id:String,chain:M.Chain,+config:M.Config,+limits:M.Limits) -> J.Value:
  M.paired(M.Chain,J.Value,J.Value,compute(chain),chain => computed => M.paired(M.Chain,J.Value,J.Value,snapshot(chain),chain => before => M.paired(M.Chain,Result<&2,&2,M.Error,M.Summary>,J.Value,M.generate(chain,config,limits),chain => result => M.paired(M.Chain,J.Value,J.Value,snapshot(chain),chain => after => recover(id,computed,before,summary(result),after,chain)))))
def table_value(t:M.Tables,index:U32,inverse:Bool) -> U32:
  match inverse:
    case True{}: M.inverse(t,index)
    case False{}: M.linear(t,index)
def table_values(fuel:Nat,+t:M.Tables,+index:U32,+inverse:Bool) -> List<&2,J.Value>:
  match fuel:
    case 0n: []
    case 1n+p: number(table_value(t,index,inverse)) <> table_values(p,t,U32.add(index,1),inverse)
def result(value:Case) -> J.Value:
  match value:
    case FrameCase{id,levels,config,limits}: frame(id,M.Chain{make_levels(levels)},config,limits)
    case QuadCase{id,+a,+b,+c,+d}: J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"mean",number(M.mean(M.tables(),a,b,c,d))},J.JMember{"dark",number(M.dark(M.tables(),a,b,c,d))}]}
    case TableCase{id}: J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"srgb_to_linear",J.JArray{table_values(256n,M.tables(),0,False{})}},J.JMember{"linear_to_srgb",J.JArray{table_values(1024n,M.tables(),0,True{})}}]}
def parsed(value:Result<&2,&2,String,J.Value>) -> Result<&2,&2,String,List<&2,Case>>:
  match value:
    case Done{J.JArray{values}}: Done{map(~J.Value,~Case,~(v => parse_case(v)),values)}
    case Done{_}: Fail{"Expected cases array"}
    case Fail{e}: Fail{e}
def run(values:List<&2,Case>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case c <> rest:
      do IO<Unit>:
        IO.print(J.encode(result(c)))
        run(rest)
def run_parsed(value:Result<&2,&2,String,List<&2,Case>>) -> IO(Unit):
  match value:
    case Done{values}: run(values)
    case Fail{e}: IO.die(Unit,1,e)
def loaded(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,result) = value
  do IO<Unit>:
    File.close(file)
    text : String <- IO.pass(String,result)
    run_parsed(parsed(J.parse_with(text,J.Limits{8388608n,32})))
def file(path:String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"r"))
    value : File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
    loaded(value)
def arguments(values:List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case path <> rest:
      do IO<Unit>:
        file(path)
        arguments(rest)
def drop_program(values:List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case p <> rest: arguments(rest)
def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),drop_program)
