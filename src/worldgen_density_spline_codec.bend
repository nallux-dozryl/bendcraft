import Base
import ./worldgen_density_spline.bend as S
import ./worldgen_noise_settings.bend as NS
import ./json.bend as J

# The bound is derived from the complete JSON tree rather than a point-count
# limit; rebuilding the same JSON list constructor preserves structural descent.
def size(value:J.Value) -> Nat:
  match value:
    case J.JArray{Nil{}}: 1n
    case J.JArray{value <> rest}: 1n+Nat.add(size(value),size(J.JArray{rest}))
    case J.JObject{Nil{}}: 1n
    case J.JObject{J.JMember{name,value} <> rest}: 1n+Nat.add(size(value),size(J.JObject{rest}))
    case _: 1n

type Work is Data:
  TreeWork{depth:Nat,value:J.Value}
  PointsWork{depth:Nat,values:List<&2,J.Value>}

type Output is Data:
  TreeOutput{tree:S.Tree<J.Value>}
  PointsOutput{points:List<&2,S.Point<J.Value>>}

type RawMulti is Data:
  RawMulti{coordinate:J.Value,points:List<&2,J.Value>}

type RawPoint is Data:
  RawPoint{location:F32,value:J.Value,derivative:F32}

def field_result(name:String,value:Maybe<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  match value:
    case None{}: Fail{"missing density spline field: " ++ name}
    case Some{value}: Done{value}

def field(value:J.Value,+name:String) -> Result<&2,&2,String,J.Value>:
  field_result(name,J.member(value,name))

def float_read(value:Maybe<&2,F32>) -> Result<&2,&2,String,F32>:
  match value:
    case None{}: Fail{"density spline float token could not be decoded"}
    case Some{value}: Done{value}

def float_checked(raw:String,valid:Bool) -> Result<&2,&2,String,F32>:
  match valid:
    case False{}: Fail{"density spline float is not a JSON number token"}
    case True{}: float_read(F32.read(raw))

# CubicSpline's Codec.FLOAT is unconstrained. In particular the density
# constant codec's +/-1,000,000 bound does not apply to spline numbers.
def float(value:J.Value) -> Result<&2,&2,String,F32>:
  match value:
    case J.JNumber{+raw}: float_checked(raw,NS.number_body(raw))
    case _: Fail{"density spline float number required"}

def points_value(value:J.Value) -> Result<&2,&2,String,List<&2,J.Value>>:
  match value:
    case J.JArray{Nil{}}: Fail{"density spline has no points"}
    case J.JArray{values}: Done{values}
    case _: Fail{"density spline points array required"}

def point_fields(+value:J.Value) -> Result<&2,&2,String,RawPoint>:
  do Result<&2,&2,String,RawPoint>:
    location_value:J.Value <- field(value,"location")
    location:F32 <- float(location_value)
    child:J.Value <- field(value,"value")
    derivative_value:J.Value <- field(value,"derivative")
    derivative:F32 <- float(derivative_value)
    return RawPoint{location,child,derivative}

def multi_fields(+value:J.Value) -> Result<&2,&2,String,RawMulti>:
  do Result<&2,&2,String,RawMulti>:
    coordinate:J.Value <- field(value,"coordinate")
    point_value:J.Value <- field(value,"points")
    raw:List<&2,J.Value> <- points_value(point_value)
    return RawMulti{coordinate,raw}

def constant(result:Result<&2,&2,String,F32>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: Done{TreeOutput{S.Constant{value}}}

def multi_output(coordinate:J.Value,result:Result<&2,&2,String,Output>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{PointsOutput{points}}: Done{TreeOutput{S.Multi{coordinate,points}}}
    case _: Fail{"density spline internal point result mismatch"}

def points_output(point:S.Point<J.Value>,result:Result<&2,&2,String,Output>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{PointsOutput{points}}: Done{PointsOutput{point <> points}}
    case _: Fail{"density spline internal point result mismatch"}

def tree_result(result:Result<&2,&2,String,Output>,next:S.Tree<J.Value> -> Result<&2,&2,String,Output>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{TreeOutput{tree}}: next(tree)
    case _: Fail{"density spline internal tree result mismatch"}

def multi_result(result:Result<&2,&2,String,RawMulti>,
    next:J.Value -> List<&2,J.Value> -> Result<&2,&2,String,Output>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{RawMulti{coordinate,points}}: next(coordinate,points)

def point_result(result:Result<&2,&2,String,RawPoint>,
    next:F32 -> J.Value -> F32 -> Result<&2,&2,String,Output>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{RawPoint{location,value,derivative}}: next(location,value,derivative)

def load(steps:Nat,work:Work) -> Result<&2,&2,String,Output>:
  match steps work:
    case 0n _: Fail{"density spline decoder work budget exhausted"}
    case 1n+ +remaining TreeWork{0n,value}: Fail{"density spline exceeds caller depth budget"}
    case 1n+ +remaining TreeWork{1n+depth,J.JNumber{raw}}: constant(float(J.JNumber{raw}))
    case 1n+ +remaining TreeWork{1n+depth,J.JObject{fields}}:
      multi_result(multi_fields(J.JObject{fields}),coordinate => points =>
        multi_output(coordinate,load(remaining,PointsWork{depth,points})))
    case 1n+ +remaining TreeWork{depth,value}: Fail{"density spline must be a float or coordinate/points object"}
    case 1n+ +remaining PointsWork{depth,Nil{}}: Done{PointsOutput{[]}}
    case 1n+ +remaining PointsWork{+depth,value <> rest}:
      point_result(point_fields(value),location => value => derivative =>
        tree_result(load(remaining,TreeWork{depth,value}),tree =>
          points_output(S.Point{location,tree,derivative},load(remaining,PointsWork{depth,rest}))))

def as_tree(result:Result<&2,&2,String,Output>) -> Result<&2,&2,String,S.Tree<J.Value>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{TreeOutput{tree}}: Done{tree}
    case _: Fail{"density spline internal tree result mismatch"}

def read(fuel:Nat,+value:J.Value) -> Result<&2,&2,String,S.Tree<J.Value>>:
  as_tree(load(size(value),TreeWork{fuel,value}))

def density(fuel:Nat,value:J.Value) -> Result<&2,&2,String,S.Tree<J.Value>>:
  do Result<&2,&2,String,S.Tree<J.Value>>:
    tree:J.Value <- field(value,"spline")
    read(fuel,tree)
