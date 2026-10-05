import Base
import ../src/json.bend as J
import ../src/block_model.bend as B
import ../src/u32_decimal.bend as Decimal
import ../src/vanilla_block_lighting.bend as L
import ../src/vanilla_block_lighting_model.bend as M
import ../src/vanilla_block_lighting_math.bend as F
import ../src/vanilla_block_lighting_geometry.bend as G

def field(v:J.Value,+key:String) -> Result<&2,&2,B.Error,J.Value>: B.required(J.member(v,key),key)
def uint_maybe(value:Maybe<&2,U32>) -> Result<&2,&2,B.Error,U32>:
  match value:
    case Some{v}: Done{v}
    case None{}: Fail{B.Error{"ExpectedU32","fixture"}}
def uint(v:J.Value) -> Result<&2,&2,B.Error,U32>: uint_maybe(J.as_u32(v))
def array(v:J.Value) -> Result<&2,&2,B.Error,List<&2,J.Value>>:
  match v:
    case J.JArray{values}: Done{values}
    case _: Fail{B.Error{"ExpectedArray","fixture"}}
def ufield(+v:J.Value,k:String) -> Result<&2,&2,B.Error,U32>:
  do Result<&2,&2,B.Error,U32>:
    v : J.Value <- field(v,k)
    uint(v)
def bfield(v:J.Value,+k:String) -> Result<&2,&2,B.Error,Bool>:
  do Result<&2,&2,B.Error,Bool>:
    v : J.Value <- field(v,k)
    B.strict_boolean(v,k)
def direction(v:J.Value) -> Result<&2,&2,B.Error,B.Direction>:
  do Result<&2,&2,B.Error,B.Direction>:
    v : String <- B.strict_string(v,"direction")
    B.direction(v,"direction")
def override(v:J.Value) -> Result<&2,&2,B.Error,Maybe<&2,B.Direction>>:
  match v:
    case J.JNull{}: Done{None{}}
    case value:
      do Result<&2,&2,B.Error,Maybe<&2,B.Direction>>:
        d : B.Direction <- direction(value)
        return Some{d}
def vec3(v:J.Value) -> Result<&2,&2,B.Error,B.Vec3>:
  match v:
    case J.JArray{a <> b <> c <> Nil{}}:
      do Result<&2,&2,B.Error,B.Vec3>:
        a : U32 <- uint(a)
        b : U32 <- uint(b)
        c : U32 <- uint(c)
        return B.Vec3{F.word(a),F.word(b),F.word(c)}
    case _: Fail{B.Error{"Vec3","fixture"}}
def position(v:J.Value) -> Result<&2,&2,B.Error,M.Position>:
  match v:
    case J.JArray{a <> b <> c <> Nil{}}:
      do Result<&2,&2,B.Error,M.Position>:
        a : U32 <- uint(a)
        b : U32 <- uint(b)
        c : U32 <- uint(c)
        return M.Position{a,b,c}
    case _: Fail{B.Error{"Position","fixture"}}
def state(+v:J.Value) -> Result<&2,&2,B.Error,M.StateInfo>:
  do Result<&2,&2,B.Error,M.StateInfo>:
    id : U32 <- ufield(v,"state")
    e : U32 <- ufield(v,"emission")
    r : Bool <- bfield(v,"emissive")
    s : Bool <- bfield(v,"solid")
    f : Bool <- bfield(v,"full")
    p : Bool <- bfield(v,"permeable")
    h : U32 <- ufield(v,"shade")
    return M.StateInfo{id,e,r,s,f,p,F.word(h)}
def optional_state(v:J.Value) -> Result<&2,&2,B.Error,Maybe<&2,M.StateInfo>>:
  match v:
    case J.JNull{}: Done{None{}}
    case other:
      do Result<&2,&2,B.Error,Maybe<&2,M.StateInfo>>:
        value : M.StateInfo <- state(other)
        return Some{value}
def optional_u32(v:J.Value) -> Result<&2,&2,B.Error,Maybe<&2,U32>>:
  match v:
    case J.JNull{}: Done{None{}}
    case other:
      do Result<&2,&2,B.Error,Maybe<&2,U32>>:
        value : U32 <- uint(other)
        return Some{value}
def cell(+v:J.Value) -> Result<&2,&2,B.Error,M.Cell>:
  do Result<&2,&2,B.Error,M.Cell>:
    raw : J.Value <- field(v,"position")
    p : M.Position <- position(raw)
    raw : J.Value <- field(v,"info")
    i : Maybe<&2,M.StateInfo> <- optional_state(raw)
    raw : J.Value <- field(v,"block")
    b : Maybe<&2,U32> <- optional_u32(raw)
    raw : J.Value <- field(v,"sky")
    s : Maybe<&2,U32> <- optional_u32(raw)
    return M.Cell{p,i,b,s}
def cells(values:List<&2,J.Value>) -> Result<&2,&2,B.Error,List<&2,M.Cell>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,B.Error,List<&2,M.Cell>>:
        head : M.Cell <- cell(value)
        tail : List<&2,M.Cell> <- cells(rest)
        return head <> tail
def cardinal(v:J.Value) -> Result<&2,&2,B.Error,Maybe<&2,M.Cardinal>>:
  match v:
    case J.JNull{}: Done{None{}}
    case J.JArray{a <> b <> c <> d <> e <> f <> Nil{}}:
      do Result<&2,&2,B.Error,Maybe<&2,M.Cardinal>>:
        a : U32 <- uint(a)
        b : U32 <- uint(b)
        c : U32 <- uint(c)
        d : U32 <- uint(d)
        e : U32 <- uint(e)
        f : U32 <- uint(f)
        return Some{M.Cardinal{F.word(a),F.word(b),F.word(c),F.word(d),F.word(e),F.word(f)}}
    case _: Fail{B.Error{"Cardinal","fixture"}}
def quad_vertices(values:J.Value,direction:B.Direction,override:Maybe<&2,B.Direction>,emission:U32) -> Result<&2,&2,B.Error,M.Quad>:
  match values:
    case J.JArray{a <> b <> c <> d <> Nil{}}:
      do Result<&2,&2,B.Error,M.Quad>:
        a : B.Vec3 <- vec3(a)
        b : B.Vec3 <- vec3(b)
        c : B.Vec3 <- vec3(c)
        d : B.Vec3 <- vec3(d)
        return M.Quad{a,b,c,d,direction,override,emission}
    case _: Fail{B.Error{"Quad","fixture"}}
def quad(+raw:J.Value) -> Result<&2,&2,B.Error,M.Quad>:
  do Result<&2,&2,B.Error,M.Quad>:
    v : J.Value <- field(raw,"direction")
    d : B.Direction <- direction(v)
    v : J.Value <- field(raw,"override")
    o : Maybe<&2,B.Direction> <- override(v)
    e : U32 <- ufield(raw,"emission")
    v : J.Value <- field(raw,"vertices")
    quad_vertices(v,d,o,e)
def mode(smooth:Bool,known:Maybe<&2,U32>) -> M.Mode:
  match smooth:
    case True{}: M.Smooth{}
    case False{}: M.Flat{known}
def num(n:U32) -> J.Value: J.JNumber{Decimal.show(n)}
def vertex(v:M.Vertex) -> J.Value:
  M.Vertex{raw,light,color}=v
  J.JObject{[J.JMember{"raw_light",num(raw)},J.JMember{"light",num(light)},J.JMember{"color",num(color)}]}
def appearance(result:Result<&2,&2,M.Error,M.Appearance>) -> J.Value:
  match result:
    case Fail{M.Refused{message}}: J.JObject{[J.JMember{"error",J.JString{message}}]}
    case Done{M.Appearance{a,b,c,d}}: J.JArray{[vertex(a),vertex(b),vertex(c),vertex(d)]}
def positions(values:List<&2,M.Position>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case M.Position{x,y,z} <> rest: J.JArray{[num(x),num(y),num(z)]} <> positions(rest)
def shape_value(bounds:M.Bounds) -> List<&2,J.Member>:
  M.Bounds{low,high,cubic,partial}=bounds
  [J.JMember{"cubic",J.JBool{cubic}},J.JMember{"partial",J.JBool{partial}}]
def result(id:String,+request:M.Request,context:M.Context) -> J.Value:
  M.Request{stamp,origin,M.StateInfo{s,e,r,b,+full,p,h},+quad,mode}=request
  J.JObject{List.append(&2,J.Member,[J.JMember{"id",J.JString{id}},J.JMember{"vertices",appearance(L.resolve(request,context))},J.JMember{"stencil",J.JArray{positions(L.stencil(request))}}],shape_value(G.shape(quad,full)))}
def execute(+raw:J.Value) -> Result<&2,&2,B.Error,J.Value>:
  do Result<&2,&2,B.Error,J.Value>:
    id : J.Value <- field(raw,"id")
    id : String <- B.strict_string(id,"id")
    q : M.Quad <- quad(raw)
    source : J.Value <- field(raw,"source")
    source : M.StateInfo <- state(source)
    values : J.Value <- field(raw,"cells")
    values : List<&2,J.Value> <- array(values)
    cells : List<&2,M.Cell> <- cells(values)
    cr : J.Value <- field(raw,"cardinal")
    cardinal : Maybe<&2,M.Cardinal> <- cardinal(cr)
    smooth : Bool <- bfield(raw,"smooth")
    known : J.Value <- field(raw,"flat")
    known : Maybe<&2,U32> <- optional_u32(known)
    revision : U32 <- ufield(raw,"revision")
    return result(id,M.Request{M.Stamp{"actual26.3","minecraft:overworld",11n,19n},M.Position{0,0,0},source,q,mode(smooth,known)},M.Context{M.Stamp{"actual26.3","minecraft:overworld",11n,U32.to_nat(revision)},cells,cardinal})
def executed(value:Result<&2,&2,B.Error,J.Value>) -> J.Value:
  match value:
    case Done{v}: v
    case Fail{B.Error{code,path}}: J.JObject{[J.JMember{"fixture_error",J.JString{code}},J.JMember{"path",J.JString{path}}]}
def fixtures(values:List<&2,J.Value>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: executed(execute(head)) <> fixtures(rest)
def parsed(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{reason}: IO.die(Unit,2,reason)
    case Done{J.JArray{values}}: IO.print(J.encode(J.JArray{fixtures(values)}))
    case _: IO.die(Unit,2,"expected observations array")
def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status)=value
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,8388608n,64))
def args(values:List<String>) -> IO(Unit):
  match values:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        read_done(result)
    case _: IO.die(Unit,2,"expected observations path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),args)
