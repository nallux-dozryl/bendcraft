import Base
import ../src/json.bend as J
import ../src/u32_decimal.bend as U
import ../src/f64.bend as F
import ../src/random.bend as R
import ../src/locomotion.bend as L
import ../src/vanilla_lightmap_model.bend as M
import ../src/vanilla_lightmap_eval.bend as E
import ../src/vanilla_lightmap_sample.bend as S
import ../src/vanilla_lightmap.bend as V

type Input is Data:
  Input{sine:String,shaders:List<&2,J.Value>,prepares:List<&2,J.Value>,ticks:List<&2,J.Value>}
type Prepare is Data:
  Prepare{flicker:F32,inputs:M.Inputs}
def raw(value:U32) -> F32:
  U32{word}=value
  F32{word}
def flag(value:U32) -> Bool: Bool.not(U32.is_zero(value))
def num(value:U32) -> J.Value: J.JNumber{U.show(value)}
def color(value:M.Color) -> J.Value:
  M.Color{r,g,b}=value
  J.JArray{[num(F32.bits(r)),num(F32.bits(g)),num(F32.bits(b))]}
def color_result(value:Result<&2,&2,M.Error,M.Color>) -> J.Value:
  match value:
    case Done{rgb}: color(rgb)
    case Fail{M.Refused{message}}: J.JNull{}
def number_result(value:Result<&2,&2,M.Error,U32>) -> J.Value:
  match value:
    case Done{word}: num(word)
    case Fail{M.Refused{message}}: J.JString{message}
def require(~A:Data,value:Maybe<&2,A>) -> Result<&2,&2,String,A>:
  match value:
    case None{}: Fail{"test input missing"}
    case Some{value}: Done{value}
def field(value:J.Value,key:String) -> Result<&2,&2,String,J.Value>:
  require(~J.Value,J.member(value,key))
def array(value:J.Value) -> Result<&2,&2,String,List<&2,J.Value>>:
  match value:
    case J.JArray{items}: Done{items}
    case _: Fail{"test input array"}
def words(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,U32>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,U32>>:
        word:U32 <- require(~U32,J.as_u32(value))
        tail:List<&2,U32> <- words(rest)
        return word <> tail
def row(value:J.Value) -> Result<&2,&2,String,List<&2,U32>>:
  do Result<&2,&2,String,List<&2,U32>>:
    items:List<&2,J.Value> <- array(value)
    words(items)
def uniforms(values:List<&2,U32>) -> Result<&2,&2,String,M.Uniforms>:
  match values:
    case s <> b <> n <> d <> o <> g <> br <> bg <> bb <> sr <> sg <> sb <> ar <> ag <> ab <> nr <> ng <> nb <> Nil{}:
      Done{M.Uniforms{raw(s),raw(b),raw(n),raw(d),raw(o),raw(g),M.Color{raw(br),raw(bg),raw(bb)},M.Color{raw(sr),raw(sg),raw(sb)},M.Color{raw(ar),raw(ag),raw(ab)},M.Color{raw(nr),raw(ng),raw(nb)}}}
    case _: Fail{"test uniform size"}
def read_uniforms(value:J.Value) -> Result<&2,&2,String,M.Uniforms>:
  do Result<&2,&2,String,M.Uniforms>:
    values:List<&2,U32> <- row(value)
    uniforms(values)
def pixel(+index:U32,u:M.Uniforms,storage:Bool) -> J.Value:
  match storage:
    case True{}: number_result(E.storage_pixel(u,U32.mod(index,16),U32.div(index,16)))
    case False{}: color_result(E.pixel(u,U32.mod(index,16),U32.div(index,16)))
def pixels(fuel:Nat,+index:U32,+u:M.Uniforms,+storage:Bool) -> List<&2,J.Value>:
  match fuel:
    case 0n: []
    case 1n+n:
      pixel(index,u,storage) <> pixels(n,U32.add(index,1),u,storage)
def samples(+texture:M.Texture,coords:List<&2,U32>) -> List<&2,J.Value>:
  match coords:
    case Nil{}: []
    case packed <> rest: color_result(S.sample_packed(texture,packed)) <> samples(texture,rest)
def shader(value:Result<&2,&2,String,M.Uniforms>) -> J.Value:
  match value:
    case Fail{message}: J.JString{message}
    case Done{+u}:
      J.JObject{[J.JMember{"raw",J.JArray{pixels(256n,0,u,False{})}},J.JMember{"argb",J.JArray{pixels(256n,0,u,True{})}},J.JMember{"samples",J.JArray{samples(M.Evaluated{u},[0,1,15,16,17,65536,983055,7340153,8388736,15728880,4294967295])}}]}
def shaders(values:List<&2,J.Value>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> tail: shader(read_uniforms(head)) <> shaders(tail)
def duration(valid:Bool,ticks:U32) -> Maybe<&2,U32>:
  match valid:
    case False{}: None{}
    case True{}: Some{ticks}
def flash(valid:Bool,previous:U32,current:U32) -> Maybe<&2,M.Interpolation>:
  match valid:
    case False{}: None{}
    case True{}: Some{M.Interpolation{raw(previous),raw(current)}}
def prepare_words(values:List<&2,U32>) -> Result<&2,&2,String,Prepare>:
  match values:
    case br <> bg <> bb <> sf <> sr <> sg <> sb <> ar <> ag <> ab <> nr <> ng <> nb <> ticks <> blend <> has_nv <> nv <> water <> conduit <> gh <> gl <> dh <> dl <> hidden <> has_flash <> flash_old <> flash_new <> fog <> boss_old <> boss_new <> partial <> flicker <> Nil{}:
      Done{Prepare{raw(flicker),M.Inputs{M.Environment{M.Color{raw(br),raw(bg),raw(bb)},raw(sf),M.Color{raw(sr),raw(sg),raw(sb)},M.Color{raw(ar),raw(ag),raw(ab)},M.Color{raw(nr),raw(ng),raw(nb)}},M.Player{ticks,raw(blend),duration(flag(has_nv),nv),raw(water),flag(conduit)},M.Options{F.F64{gh,gl},F.F64{dh,dl},flag(hidden)},M.Transitions{flash(flag(has_flash),flash_old,flash_new),flag(fog),M.Interpolation{raw(boss_old),raw(boss_new)}},raw(partial)}}}
    case _: Fail{"test prepare size"}
def read_prepare(value:J.Value) -> Result<&2,&2,String,Prepare>:
  do Result<&2,&2,String,Prepare>:
    values:List<&2,U32> <- row(value)
    prepare_words(values)
def show_uniforms(value:M.Uniforms) -> J.Value:
  M.Uniforms{s,b,n,d,o,g,M.Color{br,bg,bb},M.Color{sr,sg,sb},M.Color{ar,ag,ab},M.Color{nr,ng,nb}}=value
  J.JArray{[num(F32.bits(s)),num(F32.bits(b)),num(F32.bits(n)),num(F32.bits(d)),num(F32.bits(o)),num(F32.bits(g)),num(F32.bits(br)),num(F32.bits(bg)),num(F32.bits(bb)),num(F32.bits(sr)),num(F32.bits(sg)),num(F32.bits(sb)),num(F32.bits(ar)),num(F32.bits(ag)),num(F32.bits(ab)),num(F32.bits(nr)),num(F32.bits(ng)),num(F32.bits(nb))]}
def prepared(value:L.Tables & M.Uniforms) -> L.Tables & J.Value:
  (tables,u)=value
  (tables,show_uniforms(u))
def prepare(value:Result<&2,&2,String,Prepare>,tables:L.Tables) -> L.Tables & J.Value:
  match value:
    case Fail{message}: (tables,J.JString{message})
    case Done{Prepare{flicker,inputs}}: prepared(V.prepare(tables,flicker,inputs))
def prepares_tail(head:J.Value,pair:L.Tables & List<&2,J.Value>) -> L.Tables & List<&2,J.Value>:
  (tables,tail)=pair
  (tables,head <> tail)
def prepares_head(next:L.Tables -> L.Tables & List<&2,J.Value>,pair:L.Tables & J.Value) -> L.Tables & List<&2,J.Value>:
  (tables,head)=pair
  prepares_tail(head,next(tables))
def prepares(values:List<&2,J.Value>,tables:L.Tables) -> L.Tables & List<&2,J.Value>:
  match values:
    case Nil{}: (tables,[])
    case head <> rest: prepares_head(tables => prepares(rest,tables),prepare(read_prepare(head),tables))
def source(value:R.Source) -> J.Value:
  match value:
    case R.Legacy{R.Bits64{hi,lo}}: J.JArray{[num(hi),num(lo)]}
    case R.Xoroshiro{lo,hi}: J.JNull{}
def inspected(state:V.State) -> V.State & J.Value:
  V.State{+random,+flicker,+dirty,u,texture}=state
  (V.State{random,flicker,dirty,u,texture},J.JObject{[J.JMember{"flicker",num(F32.bits(flicker))},J.JMember{"dirty",J.JBool{dirty}},J.JMember{"seed",source(random)}]})
def tick_tail(head:J.Value,pair:V.State & List<&2,J.Value>) -> V.State & List<&2,J.Value>:
  (state,tail)=pair
  (state,head <> tail)
def tick_head(next:V.State -> V.State & List<&2,J.Value>,pair:V.State & J.Value) -> V.State & List<&2,J.Value>:
  (state,head)=pair
  tick_tail(head,next(state))
def tick_loop(fuel:Nat,state:V.State) -> V.State & List<&2,J.Value>:
  match fuel:
    case 0n: (state,[])
    case 1n+n: tick_head(state => tick_loop(n,state),inspected(V.tick(state)))
def ticks_finished(pair:V.State & List<&2,J.Value>) -> J.Value:
  (state,rows)=pair
  J.JArray{rows}
def tick_values(values:List<&2,U32>) -> J.Value:
  match values:
    case hi <> lo <> count <> Nil{}: ticks_finished(tick_loop(U32.to_nat(count),V.fresh(R.seeded_legacy(R.Bits64{hi,lo}))))
    case _: J.JString{"test tick size"}
def tick_words(value:Result<&2,&2,String,List<&2,U32>>) -> J.Value:
  match value:
    case Fail{message}: J.JString{message}
    case Done{values}: tick_values(values)
def ticks(values:List<&2,J.Value>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> tail: tick_words(row(head)) <> ticks(tail)
def array_field(value:J.Value,key:String) -> Result<&2,&2,String,List<&2,J.Value>>:
  do Result<&2,&2,String,List<&2,J.Value>>:
    raw:J.Value <- field(value,key)
    array(raw)
def input(+value:J.Value) -> Result<&2,&2,String,Input>:
  do Result<&2,&2,String,Input>:
    sine:J.Value <- field(value,"sine")
    path:String <- require(~String,J.as_string(sine))
    shaders:List<&2,J.Value> <- array_field(value,"shaders")
    prepares:List<&2,J.Value> <- array_field(value,"prepares")
    ticks:List<&2,J.Value> <- array_field(value,"ticks")
    return Input{path,shaders,prepares,ticks}
def output(shaders:List<&2,J.Value>,ticks:List<&2,J.Value>,pair:L.Tables & List<&2,J.Value>) -> IO(Unit):
  (tables,prepared)=pair
  IO.print(J.encode(J.JObject{[J.JMember{"shaders",J.JArray{shaders}},J.JMember{"ticks",J.JArray{ticks}},J.JMember{"prepares",J.JArray{prepared}}]}))
def loaded(shaders:List<&2,J.Value>,prepared:List<&2,J.Value>,tick_rows:List<&2,J.Value>,result:Result<&2,&1,L.Error,L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("sine load failed")
    case Done{tables}: output(shaders,tick_rows,prepares(prepared,tables))
def run(value:Result<&2,&2,String,Input>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print(message)
    case Done{Input{sine,shader_rows,prepare_rows,tick_rows}}:
      do IO<Unit>:
        tables:Result<&2,&1,L.Error,L.Tables> <- L.Tables.load(sine)
        loaded(shaders(shader_rows),prepare_rows,ticks(tick_rows),tables)
def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print(message)
    case Done{value}: run(input(value))
def read_text(value:Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("read failed")
    case Done{text}: parsed(J.parse_bounded(text,1048576n,128))
def read(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,text)=value
  do IO<Unit>:
    File.close(file)
    read_text(text)
def opened(value:Result<&1,&1,U32 & String,File>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("open failed")
    case Done{file}:
      do IO<Unit>:
        value:File & Result<&1,&1,U32 & String,String> <- File.read(file,1048576)
        read(value)
def args(values:List<&1,String>) -> IO(Unit):
  match values:
    case exe <> path <> Nil{}:
      do IO<Unit>:
        value:Result<&1,&1,U32 & String,File> <- File.open(path,"r")
        opened(value)
    case _: IO.print("input required")
def main() -> IO(Unit):
  do IO<Unit>:
    values:List<&1,String> <- IO.args()
    args(values)
