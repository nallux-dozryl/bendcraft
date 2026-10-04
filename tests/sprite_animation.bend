import Base
import ../src/sprite_animation.bend as S
import ../src/texture_metadata.bend as T
import ../src/texture_mipmap.bend as M
import ../src/resource_json.bend as Q
import ../src/json.bend as J

type InputLevel is Data:
  InputLevel{width:U32,height:U32,capacity:U32,pixels:List<&2,U32>}
type Query is Data:
  Query{index:U32,mip:U32}
type Case is Data:
  Decode{id:String,mode:String,text:String}
  CPU{id:String,text:String,raw_metadata:Maybe<&2,S.Metadata>,levels:List<&2,InputLevel>,generate:Bool,target:U32,path:String,ticks:U32,limits:S.Limits,forge:String,queries:List<&2,Query>}
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
def optional(found:Maybe<&2,J.Value>) -> Maybe<&2,U32>:
  match found:
    case None{}: None{}
    case Some{J.JNull{}}: None{}
    case Some{v}: Some{integer(Some{v})}
def word(v:J.Value) -> U32:
  integer(Some{v})
def words(found:Maybe<&2,J.Value>) -> List<&2,U32>:
  match found:
    case Some{J.JArray{values}}: map(~J.Value,~U32,~word,values)
    case _: []
def raw_frame(+v:J.Value) -> S.FrameSpec:
  S.FrameSpec{integer(J.member(v,"index")),optional(J.member(v,"time"))}
def raw_frames(found:Maybe<&2,J.Value>) -> Maybe<&2,List<&2,S.FrameSpec>>:
  match found:
    case Some{J.JArray{values}}: Some{map(~J.Value,~S.FrameSpec,~(v => raw_frame(v)),values)}
    case _: None{}
def raw_metadata(found:Maybe<&2,J.Value>) -> Maybe<&2,S.Metadata>:
  match found:
    case None{}: None{}
    case Some{+v}: Some{S.Metadata{raw_frames(J.member(v,"frames")),optional(J.member(v,"width")),optional(J.member(v,"height")),integer(J.member(v,"default_time")),boolean(J.member(v,"interpolate"))}}
def input_level(+v:J.Value) -> InputLevel:
  InputLevel{integer(J.member(v,"width")),integer(J.member(v,"height")),integer(J.member(v,"capacity")),words(J.member(v,"pixels"))}
def input_levels(found:Maybe<&2,J.Value>) -> List<&2,InputLevel>:
  match found:
    case Some{J.JArray{values}}: map(~J.Value,~InputLevel,~(v => input_level(v)),values)
    case _: []
def query(+v:J.Value) -> Query:
  Query{integer(J.member(v,"index")),integer(J.member(v,"mip"))}
def queries(found:Maybe<&2,J.Value>) -> List<&2,Query>:
  match found:
    case Some{J.JArray{values}}: map(~J.Value,~Query,~(v => query(v)),values)
    case _: []
def limits(found:Maybe<&2,J.Value>) -> S.Limits:
  match found:
    case None{}: S.defaults()
    case Some{+v}: S.Limits{integer(J.member(v,"max_dimension")),integer(J.member(v,"max_levels")),integer(J.member(v,"max_frames")),integer(J.member(v,"max_entries")),integer(J.member(v,"max_capacity")),integer(J.member(v,"max_work_pixels"))}
def parse_kind(+v:J.Value,kind:String) -> Case:
  match kind:
    case "decode": Decode{string(J.member(v,"id")),string(J.member(v,"mode")),string(J.member(v,"json"))}
    case _: CPU{string(J.member(v,"id")),string(J.member(v,"json")),raw_metadata(J.member(v,"raw_metadata")),input_levels(J.member(v,"levels")),boolean(J.member(v,"generate")),integer(J.member(v,"mip_level")),string(J.member(v,"path")),integer(J.member(v,"ticks")),limits(J.member(v,"limits")),string(J.member(v,"forge")),queries(J.member(v,"queries"))}
def parse_case(+v:J.Value) -> Case:
  parse_kind(v,string(J.member(v,"kind")))
def write_pixels(values:List<&2,U32>,pixels:Array<U32>,+index:U32) -> Array<U32>:
  match values:
    case Nil{}: pixels
    case v <> rest: write_pixels(rest,Array.set(U32,pixels,index,v),U32.add(index,1))
def make_level(value:InputLevel) -> M.Level:
  InputLevel{w,h,capacity,values} = value
  M.Level{w,h,write_pixels(values,Array.new(U32,M.array_depth(24n,capacity,1),0),0)}
def make_levels(values:List<&2,InputLevel>) -> List<&1,M.Level>:
  match values:
    case Nil{}: []
    case h <> rest: make_level(h) <> make_levels(rest)
def append(values:List<&2,U32>,tail:List<&2,U32>) -> List<&2,U32>:
  match values:
    case Nil{}: tail
    case h <> rest: h <> append(rest,tail)
def borrow(pixels:Array<U32>) -> Array<U32> & List<&2,U32>:
  match pixels:
    case ALeaf{+p}: (ALeaf{p},[p])
    case ANode{left,right}: M.paired(Array<U32>,List<&2,U32>,Array<U32> & List<&2,U32>,borrow(left),left => a => M.paired(Array<U32>,List<&2,U32>,Array<U32> & List<&2,U32>,borrow(right),right => b => (ANode{left,right},append(a,b))))
def level_json(+w:U32,+h:U32,+pixels:List<&2,U32>) -> J.Value:
  J.JObject{[J.JMember{"width",number(w)},J.JMember{"height",number(h)},J.JMember{"capacity",number(U32.from_nat(List.length(&2,U32,pixels)))},J.JMember{"pixels",J.JArray{map(~U32,~J.Value,~number,pixels)}}]}
def snapshot_level(value:M.Level) -> M.Level & J.Value:
  M.Level{+w,+h,pixels} = value
  M.paired(Array<U32>,List<&2,U32>,M.Level & J.Value,borrow(pixels),pixels => values => (M.Level{w,h,pixels},level_json(w,h,values)))
def snapshot_levels(values:List<&1,M.Level>) -> List<&1,M.Level> & List<&2,J.Value>:
  match values:
    case Nil{}: ([],[])
    case h <> rest: M.paired(M.Level,J.Value,List<&1,M.Level> & List<&2,J.Value>,snapshot_level(h),h => head => M.paired(List<&1,M.Level>,List<&2,J.Value>,List<&1,M.Level> & List<&2,J.Value>,snapshot_levels(rest),rest => tail => (h<>rest,head<>tail)))
def snapshot(chain:M.Chain) -> M.Chain & J.Value:
  M.Chain{levels} = chain
  M.paired(List<&1,M.Level>,List<&2,J.Value>,M.Chain & J.Value,snapshot_levels(levels),levels => values => (M.Chain{levels},J.JArray{values}))
def error(value:S.Error) -> J.Value:
  S.Error{code,field,index} = value
  J.JObject{[J.JMember{"status",J.JString{"error"}},J.JMember{"code",J.JString{code}},J.JMember{"field",J.JString{field}},J.JMember{"index",number(index)}]}
def option(value:Maybe<&2,U32>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{v}: number(v)
def spec(value:S.FrameSpec) -> J.Value:
  S.FrameSpec{index,time} = value
  J.JObject{[J.JMember{"index",number(index)},J.JMember{"time",option(time)}]}
def specs(value:Maybe<&2,List<&2,S.FrameSpec>>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{values}: J.JArray{map(~S.FrameSpec,~J.Value,~spec,values)}
def metadata(value:S.Metadata) -> J.Value:
  S.Metadata{frames,w,h,t,interp} = value
  J.JObject{[J.JMember{"status",J.JString{"ok"}},J.JMember{"frames",specs(frames)},J.JMember{"width",option(w)},J.JMember{"height",option(h)},J.JMember{"default_time",number(t)},J.JMember{"interpolate",J.JBool{interp}}]}
def decoded(value:Result<&2,&2,S.Error,Maybe<&2,S.Metadata>>) -> J.Value:
  match value:
    case Fail{e}: error(e)
    case Done{None{}}: J.JObject{[J.JMember{"status",J.JString{"absent"}}]}
    case Done{Some{m}}: metadata(m)
def section_result(value:Result<&2,&2,S.Error,S.Metadata>) -> Result<&2,&2,S.Error,Maybe<&2,S.Metadata>>:
  match value:
    case Fail{e}: Fail{e}
    case Done{m}: Done{Some{m}}
def parsed_section(value:Result<&2,&2,String,J.Value>) -> Result<&2,&2,S.Error,Maybe<&2,S.Metadata>>:
  match value:
    case Fail{e}: S.fail(Maybe<&2,S.Metadata>,"InvalidJson","")
    case Done{v}: section_result(S.decode_section(v))
def decode(mode:String,text:String) -> Result<&2,&2,S.Error,Maybe<&2,S.Metadata>>:
  match mode:
    case "section": parsed_section(Q.parse(text))
    case _: S.parse_document(text)
def dimension(value:M.Dimension) -> J.Value:
  M.Dimension{w,h,c} = value
  J.JObject{[J.JMember{"width",number(w)},J.JMember{"height",number(h)},J.JMember{"capacity",number(c)}]}
def frame(value:S.FrameInfo) -> J.Value:
  S.FrameInfo{index,time} = value
  J.JObject{[J.JMember{"index",number(index)},J.JMember{"time",number(time)}]}
def rect(value:S.Rect) -> J.Value:
  S.Rect{m,x,y,w,h} = value
  J.JObject{[J.JMember{"mip",number(m)},J.JMember{"x",number(x)},J.JMember{"y",number(y)},J.JMember{"width",number(w)},J.JMember{"height",number(h)}]}
def plan(value:S.Plan) -> J.Value:
  S.Plan{w,h,rows,count,frames,us,interp,animated,dimensions,capacity,work} = value
  J.JObject{[J.JMember{"width",number(w)},J.JMember{"height",number(h)},J.JMember{"row_size",number(rows)},J.JMember{"frame_count",number(count)},J.JMember{"frames",J.JArray{map(~S.FrameInfo,~J.Value,~frame,frames)}},J.JMember{"unique_frames",J.JArray{map(~U32,~J.Value,~number,us)}},J.JMember{"interpolate",J.JBool{interp}},J.JMember{"animated",J.JBool{animated}},J.JMember{"dimensions",J.JArray{map(~M.Dimension,~J.Value,~dimension,dimensions)}},J.JMember{"capacity",number(capacity)},J.JMember{"work",number(work)}]}
def selection(value:S.Selection) -> J.Value:
  match value:
    case S.NoAnimation{w,h}: J.JObject{[J.JMember{"status",J.JString{"static"}},J.JMember{"width",number(w)},J.JMember{"height",number(h)}]}
    case S.Animated{entry,current,next,sub,time,dirty,draw,cr,nr}: J.JObject{[J.JMember{"status",J.JString{"animated"}},J.JMember{"entry",number(entry)},J.JMember{"current",number(current)},J.JMember{"next",number(next)},J.JMember{"sub_frame",number(sub)},J.JMember{"duration",number(time)},J.JMember{"dirty",J.JBool{dirty}},J.JMember{"needs_to_draw",J.JBool{draw}},J.JMember{"current_rects",J.JArray{map(~S.Rect,~J.Value,~rect,cr)}},J.JMember{"next_rects",J.JArray{map(~S.Rect,~J.Value,~rect,nr)}}]}
def selected(value:Result<&2,&2,S.Error,S.Selection>) -> J.Value:
  match value:
    case Fail{e}: error(e)
    case Done{v}: selection(v)
def observed(value:Result<&2,&2,S.Error,S.Observation>) -> J.Value:
  match value:
    case Fail{e}: error(e)
    case Done{S.Observation{p,s}}: J.JObject{[J.JMember{"status",J.JString{"ok"}},J.JMember{"plan",plan(p)},J.JMember{"selection",selection(s)}]}
def timeline(fuel:Nat,value:S.Contents) -> S.Contents & List<&2,J.Value>:
  match fuel:
    case 0n: (value,[])
    case 1n+p: M.paired(S.Contents,Result<&2,&2,S.Error,S.Selection>,S.Contents & List<&2,J.Value>,S.tick(value),value => found => M.paired(S.Contents,List<&2,J.Value>,S.Contents & List<&2,J.Value>,timeline(p,value),value => rest => (value,selected(found)<>rest)))
def crop_closed(closed:Unit,value:J.Value) -> J.Value:
  value
def cropped(value:Result<&2,&1,S.Error,M.Level>) -> J.Value:
  match value:
    case Fail{e}: error(e)
    case Done{image}: M.paired(M.Level,J.Value,J.Value,snapshot_level(image),image => pixels => crop_closed(M.close_chain(M.Chain{[image]}),J.JObject{[J.JMember{"status",J.JString{"ok"}},J.JMember{"image",pixels}]}))
def read_done(f:S.Contents -> S.Contents & List<&2,J.Value>,value:S.Contents,row:J.Value) -> S.Contents & List<&2,J.Value>:
  M.paired(S.Contents,List<&2,J.Value>,S.Contents & List<&2,J.Value>,f(value),value => tail => (value,row<>tail))
def read_queries(values:List<&2,Query>,value:S.Contents) -> S.Contents & List<&2,J.Value>:
  match values:
    case Nil{}: (value,[])
    case Query{+index,+mip} <> rest: M.paired(S.Contents,Result<&2,&1,S.Error,M.Level>,S.Contents & List<&2,J.Value>,S.read_frame(value,index,mip),value => image => read_done(value => read_queries(rest,value),value,J.JObject{[J.JMember{"index",number(index)},J.JMember{"mip",number(mip)},J.JMember{"result",cropped(image)}]}))
def snapshot_tail(f:Maybe<&1,S.Contents> -> J.Value -> S.Contents & J.Value,tail:Maybe<&1,S.Contents>,chain_json:J.Value) -> S.Contents & J.Value:
  f(tail)(chain_json)
def snapshot_contents(value:S.Contents) -> S.Contents & J.Value:
  match value:
    case S.Contents{chain,metadata,limits,timeline,None{}}: M.paired(M.Chain,J.Value,S.Contents & J.Value,snapshot(chain),chain => values => (S.Contents{chain,metadata,limits,timeline,None{}},J.JObject{[J.JMember{"chain",values},J.JMember{"tail",J.JNull{}}]}))
    case S.Contents{chain,metadata,limits,timeline,Some{rest}}: M.paired(M.Chain,J.Value,S.Contents & J.Value,snapshot(chain),chain => values => M.paired(S.Contents,J.Value,S.Contents & J.Value,snapshot_contents(rest),rest => tail => (S.Contents{chain,metadata,limits,timeline,Some{rest}},J.JObject{[J.JMember{"chain",values},J.JMember{"tail",tail}]})))
def forged(kind:String,value:S.Contents) -> S.Contents:
  match kind:
    case "nested": S.Contents{M.Chain{[M.Level{1,1,ALeaf{305419896}}]},None{},S.defaults(),S.NoTimeline{},Some{value}}
    case "entry":
      S.Contents{chain,metadata,limits,timeline,tail} = value
      S.Contents{chain,metadata,limits,S.Running{4294967295,0,True{}},tail}
    case "sub":
      S.Contents{chain,metadata,limits,timeline,tail} = value
      S.Contents{chain,metadata,limits,S.Running{0,4294967295,True{}},tail}
    case "kind":
      S.Contents{chain,metadata,limits,timeline,tail} = value
      S.Contents{chain,metadata,limits,S.NoTimeline{},tail}
    case _: value
def recovered_result(value:Result<&1,&1,S.Rejected,S.Contents>) -> J.Value:
  match value:
    case Fail{S.Rejected{chain,e}}: M.paired(M.Chain,J.Value,J.Value,snapshot(chain),chain => image => crop_closed(M.close_chain(chain),J.JObject{[J.JMember{"result",error(e)},J.JMember{"owners",image}]}))
    case Done{value}: M.paired(S.Contents,Result<&2,&2,S.Error,S.Observation>,J.Value,S.inspect(value),value => result => M.paired(S.Contents,J.Value,J.Value,snapshot_contents(value),value => owners => crop_closed(S.close_contents(value),J.JObject{[J.JMember{"result",observed(result)},J.JMember{"owners",owners}]})))
def recover(chain:M.Chain) -> J.Value:
  recovered_result(S.admit(chain,None{},S.defaults()))
def success_finish(value:S.Contents,initial:J.Value,states:List<&2,J.Value>,images:List<&2,J.Value>) -> J.Value:
  M.paired(S.Contents,J.Value,J.Value,snapshot_contents(value),value => owners => crop_closed(S.close_contents(value),J.JObject{[J.JMember{"status",J.JString{"ok"}},J.JMember{"initial",initial},J.JMember{"timeline",J.JArray{states}},J.JMember{"crops",J.JArray{images}},J.JMember{"owners",owners}]}))
def admitted(value:Result<&1,&1,S.Rejected,S.Contents>,ticks:U32,qs:List<&2,Query>,kind:String) -> J.Value:
  match value:
    case Fail{S.Rejected{chain,e}}: M.paired(M.Chain,J.Value,J.Value,snapshot(chain),chain => owners => J.JObject{[J.JMember{"status",J.JString{"error"}},J.JMember{"error",error(e)},J.JMember{"owners",owners},J.JMember{"recovery",recover(chain)}]})
    case Done{value}: M.paired(S.Contents,Result<&2,&2,S.Error,S.Observation>,J.Value,S.inspect(forged(kind,value)),value => initial => M.paired(S.Contents,List<&2,J.Value>,J.Value,timeline(U32.to_nat(ticks),value),value => states => M.paired(S.Contents,List<&2,J.Value>,J.Value,read_queries(qs,value),value => images => success_finish(value,observed(initial),states,images))))
def mip_strategy(value:T.Strategy) -> M.Strategy:
  match value:
    case T.Auto{}: M.Auto{}
    case T.Mean{}: M.Mean{}
    case T.Cutout{}: M.Cutout{}
    case T.StrictCutout{}: M.StrictCutout{}
    case T.DarkCutout{}: M.DarkCutout{}
def texture_decoded(value:Result<&2,&2,T.Error,Maybe<&2,T.Metadata>>) -> T.Metadata:
  match value:
    case Done{Some{m}}: m
    case _: T.defaults()
def mip_config(texture:T.Metadata,path:String,target:U32,transparency:M.Transparency) -> M.Config:
  T.Metadata{blur,clamp,strategy,bias} = texture
  M.Config{path,target,mip_strategy(strategy),bias,transparency}
def mip_result(value:Result<&2,&2,M.Error,M.Summary>) -> J.Value:
  match value:
    case Fail{M.Error{code,index}}: J.JObject{[J.JMember{"status",J.JString{"error"}},J.JMember{"code",J.JString{code}},J.JMember{"level",number(index)}]}
    case Done{M.Summary{strategy,early,pre,count,dims}}: J.JObject{[J.JMember{"status",J.JString{"ok"}},J.JMember{"effective",J.JString{M.strategy_name(strategy)}},J.JMember{"early",J.JBool{early}},J.JMember{"preconditioned",J.JBool{pre}}]}
def generate_with(chain:M.Chain,texture:T.Metadata,path:String,target:U32,result:Result<&2,&2,M.Error,M.Transparency>) -> M.Chain & J.Value:
  match result:
    case Fail{M.Error{code,index}}: (chain,J.JObject{[J.JMember{"status",J.JString{"error"}},J.JMember{"code",J.JString{code}},J.JMember{"level",number(index)}]})
    case Done{tr}: M.paired(M.Chain,Result<&2,&2,M.Error,M.Summary>,M.Chain & J.Value,M.generate(chain,mip_config(texture,path,target,tr),M.defaults()),chain => result => (chain,mip_result(result)))
def generated(enabled:Bool,chain:M.Chain,texture:T.Metadata,path:String,target:U32) -> M.Chain & J.Value:
  match enabled chain:
    case False{} _: (chain,J.JString{"not-requested"})
    case True{} M.Chain{Nil{}}: (M.Chain{[]},J.JString{"empty"})
    case True{} M.Chain{first<>rest}: M.paired(M.Level,Result<&2,&2,M.Error,M.Transparency>,M.Chain & J.Value,M.compute_transparency(first,M.defaults()),first => tr => generate_with(M.Chain{first<>rest},texture,path,target,tr))
def chosen_metadata(raw:Maybe<&2,S.Metadata>,text:String) -> Result<&2,&2,S.Error,Maybe<&2,S.Metadata>>:
  match raw:
    case Some{m}: Done{Some{m}}
    case None{}: S.parse_document(text)
def cpu_parsed(chain:M.Chain,limits:S.Limits,ticks:U32,qs:List<&2,Query>,kind:String,result:Result<&2,&2,S.Error,Maybe<&2,S.Metadata>>) -> J.Value:
  match result:
    case Fail{e}: M.paired(M.Chain,J.Value,J.Value,snapshot(chain),chain => owners => crop_closed(M.close_chain(chain),J.JObject{[J.JMember{"status",J.JString{"metadata-error"}},J.JMember{"error",error(e)},J.JMember{"owners",owners}]}))
    case Done{m}: admitted(S.admit(chain,m,limits),ticks,qs,kind)
def cpu(id:String,+text:String,raw:Maybe<&2,S.Metadata>,chain:M.Chain,generate:Bool,target:U32,path:String,ticks:U32,limits:S.Limits,kind:String,qs:List<&2,Query>) -> J.Value:
  M.paired(M.Chain,J.Value,J.Value,snapshot(chain),chain => before => M.paired(M.Chain,J.Value,J.Value,generated(generate,chain,texture_decoded(T.parse_document(text)),path,target),chain => mip_status => J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"before",before},J.JMember{"mip_status",mip_status},J.JMember{"result",cpu_parsed(chain,limits,ticks,qs,kind,chosen_metadata(raw,text))}]}))
def result(value:Case) -> J.Value:
  match value:
    case Decode{id,mode,text}: J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"result",decoded(decode(mode,text))}]}
    case CPU{id,text,raw,levels,generate,target,path,ticks,limits,kind,qs}: cpu(id,text,raw,M.Chain{make_levels(levels)},generate,target,path,ticks,limits,kind,qs)
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
    run_parsed(parsed(J.parse_with(text,J.Limits{33554432n,32})))
def file(path:String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"r"))
    value : File & Result<&1,&1,U32 & String,String> <- File.read(file,33554432)
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
