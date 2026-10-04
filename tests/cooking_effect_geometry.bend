import Base
import ../src/json.bend as J
import ../src/f64.bend as F
import ../src/geometry.bend as A
import ../src/vanilla_entity_fields.bend as V
import ../src/cooking_effect_geometry_voxel.bend as S
import ../src/cooking_effect_geometry.bend as P

def field_result(name:String,value:Maybe<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  match value:
    case None{}: Fail{"missing:" ++ name}
    case Some{value}: Done{value}
def field(raw:J.Value,+name:String) -> Result<&2,&2,String,J.Value>: field_result(name,J.member(raw,name))
def array(raw:J.Value) -> Result<&2,&2,String,List<&2,J.Value>>:
  match raw:
    case J.JArray{values}: Done{values}
    case _: Fail{"array expected"}
def number_result(value:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match value:
    case Some{value}: Done{value}
    case None{}: Fail{"U32 expected"}
def number(raw:J.Value) -> Result<&2,&2,String,U32>:
  match raw:
    case J.JNumber{lexeme}: number_result(J.u32_lexeme(lexeme))
    case _: Fail{"number expected"}
def boolean(raw:J.Value) -> Result<&2,&2,String,Bool>:
  match raw:
    case J.JBool{value}: Done{value}
    case _: Fail{"Bool expected"}
def double(raw:J.Value) -> Result<&2,&2,String,F.F64>:
  match raw:
    case J.JArray{a <> b <> Nil{}}:
      do Result<&2,&2,String,F.F64>:
        hi : U32 <- number(a)
        lo : U32 <- number(b)
        return F.F64{hi,lo}
    case _: Fail{"double bits expected"}
def doubles(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,F.F64>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,F.F64>>:
        a : F.F64 <- double(head)
        b : List<&2,F.F64> <- doubles(rest)
        return a <> b
def point(raw:J.Value) -> Result<&2,&2,String,V.Vec3>:
  match raw:
    case J.JArray{a <> b <> c <> Nil{}}:
      do Result<&2,&2,String,V.Vec3>:
        x : F.F64 <- double(a)
        y : F.F64 <- double(b)
        z : F.F64 <- double(c)
        return V.Vec3{x,y,z}
    case _: Fail{"point expected"}
def box(raw:J.Value) -> Result<&2,&2,String,A.AABB>:
  match raw:
    case J.JArray{a <> b <> c <> d <> e <> f <> Nil{}}:
      do Result<&2,&2,String,A.AABB>:
        x : F.F64 <- double(a)
        y : F.F64 <- double(b)
        z : F.F64 <- double(c)
        u : F.F64 <- double(d)
        v : F.F64 <- double(e)
        w : F.F64 <- double(f)
        return A.AABB{x,y,z,u,v,w}
    case _: Fail{"box expected"}
def cell(raw:J.Value) -> Result<&2,&2,String,S.Cell>:
  match raw:
    case J.JArray{a <> b <> c <> Nil{}}:
      do Result<&2,&2,String,S.Cell>:
        x : U32 <- number(a)
        y : U32 <- number(b)
        z : U32 <- number(c)
        return S.Cell{x,y,z}
    case _: Fail{"cell expected"}
def cells(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,S.Cell>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,S.Cell>>:
        a : S.Cell <- cell(head)
        b : List<&2,S.Cell> <- cells(rest)
        return a <> b
def axis(+raw:J.Value) -> Result<&2,&2,String,S.Axis>:
  do Result<&2,&2,String,S.Axis>:
    coords : J.Value <- field(raw,"coords")
    values : List<&2,J.Value> <- array(coords)
    coords : List<&2,F.F64> <- doubles(values)
    flag : J.Value <- field(raw,"cube")
    cube : Bool <- boolean(flag)
    return S.Axis{coords,cube}
def shape_axes(raw:J.Value,values:List<&2,J.Value>) -> Result<&2,&2,String,S.Shape>:
  match values:
    case a <> b <> c <> Nil{}:
      do Result<&2,&2,String,S.Shape>:
        x : S.Axis <- axis(a)
        y : S.Axis <- axis(b)
        z : S.Axis <- axis(c)
        raw : J.Value <- field(raw,"cells")
        values : List<&2,J.Value> <- array(raw)
        filled : List<&2,S.Cell> <- cells(values)
        return S.Shape{x,y,z,filled}
    case _: Fail{"three shape axes expected"}
def shape(+raw:J.Value) -> Result<&2,&2,String,S.Shape>:
  do Result<&2,&2,String,S.Shape>:
    axes : J.Value <- field(raw,"axes")
    values : List<&2,J.Value> <- array(axes)
    shape_axes(raw,values)
def obstacle(+raw:J.Value) -> Result<&2,&2,String,P.Obstacle>:
  do Result<&2,&2,String,P.Obstacle>:
    b : J.Value <- field(raw,"box")
    b : A.AABB <- box(b)
    s : J.Value <- field(raw,"shape")
    s : S.Shape <- shape(s)
    f : J.Value <- field(raw,"full")
    f : Bool <- boolean(f)
    return P.Obstacle{b,s,f}
def obstacles(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,P.Obstacle>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,P.Obstacle>>:
        a : P.Obstacle <- obstacle(head)
        b : List<&2,P.Obstacle> <- obstacles(rest)
        return a <> b
def boxes(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,A.AABB>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,A.AABB>>:
        a : A.AABB <- box(head)
        b : List<&2,A.AABB> <- boxes(rest)
        return a <> b

def num(n:U32) -> J.Value: J.JNumber{U32.show(n)}
def double_value(value:F.F64) -> J.Value:
  F.F64{hi,lo} = value
  J.JArray{[num(hi),num(lo)]}
def point_value(value:V.Vec3) -> J.Value:
  V.Vec3{x,y,z} = value
  J.JArray{[double_value(x),double_value(y),double_value(z)]}
def box_value(value:A.AABB) -> J.Value:
  A.AABB{a,b,c,d,e,f} = value
  J.JArray{[double_value(a),double_value(b),double_value(c),double_value(d),double_value(e),double_value(f)]}
def boxes_values(values:List<&2,A.AABB>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: box_value(head) <> boxes_values(rest)
def boxes_value(values:List<&2,A.AABB>) -> J.Value:
  J.JArray{boxes_values(values)}
def maybe_value(value:Maybe<&2,V.Vec3>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{point}: point_value(point)
def observation_prepared(+context:P.Context,prepared:P.Prepared) -> Result<&2,&2,String,J.Value>:
  P.Context{dimension,coverage,+blocks,entities,+budget} = context
  P.Prepared{+point,+body,+center,+search,+outer} = prepared
  do Result<&2,&2,String,J.Value>:
    clear : Bool <- P.no_collision(context,body)
    +free : Maybe<&2,V.Vec3> <- P.free_position(context,search,center,outer)
    +query : S.Shape <- S.create(outer)
    +union : S.Shape <- P.union_blocks(blocks,outer,query,budget,S.empty())
    available : S.Shape <- S.join_limited(search,union,2,budget)
    final : V.Vec3 <- P.place_query(context,"minecraft:overworld",point)
    return J.JObject{[J.JMember{"clear",J.JBool{clear}},J.JMember{"free",maybe_value(free)},J.JMember{"position",point_value(final)},J.JMember{"body",box_value(body)},J.JMember{"outer",box_value(outer)},J.JMember{"search",boxes_value(S.boxes(search))},J.JMember{"union",boxes_value(S.boxes(union))},J.JMember{"available",boxes_value(S.boxes(available))}]}
def observation(context:P.Context,point:V.Vec3) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    prepared : P.Prepared <- P.prepare(point)
    observation_prepared(context,prepared)
def fixture(+raw:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    v : J.Value <- field(raw,"point")
    point : V.Vec3 <- point(v)
    v : J.Value <- field(raw,"coverage")
    coverage : A.AABB <- box(v)
    v : J.Value <- field(raw,"blocks")
    values : List<&2,J.Value> <- array(v)
    blocks : List<&2,P.Obstacle> <- obstacles(values)
    v : J.Value <- field(raw,"entities")
    values : List<&2,J.Value> <- array(v)
    entities : List<&2,A.AABB> <- boxes(values)
    observation(P.Context{"minecraft:overworld",coverage,blocks,entities,32768},point)
def fixtures(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        a : J.Value <- fixture(head)
        b : List<&2,J.Value> <- fixtures(rest)
        return a <> b
def execute(raw:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    values : List<&2,J.Value> <- array(raw)
    answers : List<&2,J.Value> <- fixtures(values)
    return J.JArray{answers}
def respond(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: IO.print(J.encode(value))
def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: respond(execute(value))
def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = value
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,1048576n,64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,1048576)
        read_done(result)
    case _: IO.die(Unit,2,"expected geometry fixture path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
