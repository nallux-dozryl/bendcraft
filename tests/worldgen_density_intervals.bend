import Base
import ../src/worldgen_density_interval.bend as I
import ../src/worldgen_density_coordinates.bend as Coordinates
import ../src/worldgen_density_ast.bend as A
import ../src/f64.bend as F
import ./worldgen_density.bend as H
import ./worldgen_density_spline.bend as Spline
import ../src/worldgen_density_column.bend as Column
import ../src/worldgen_density_loader.bend as L
import ../src/worldgen_density_compile.bend as C
import ../src/worldgen_density_state.bend as S
import ../src/worldgen_overworld.bend as O
import ../src/worldgen_noise_settings.bend as NS
import ../src/worldgen_noise_settings_codec.bend as NC
import ../src/world_generation_settings.bend as WG
import ../src/json.bend as J
import ../src/nbt.bend as N

def interval(kind:String,low:String,high:String) -> I.Interval:
  match kind:
    case "N": I.NaI{}
    case _: I.Range{I.bits(H.number(low)),I.bits(H.number(high))}

def operation(kind:String,+a:I.Interval,+b:I.Interval,c:I.Interval) -> Result<&2,&2,String,I.Interval>:
  match kind:
    case "add": I.add(a,b)
    case "sub": I.sub(a,b)
    case "mul": I.mul(a,b)
    case "div": I.div(a,b)
    case "min": I.min(a,b)
    case "max": I.max(a,b)
    case "lerp": I.lerp(a,b,c)
    case "absolute": I.absolute(a)
    case "square": I.square(a)
    case "reciprocal": I.reciprocal(a)
    case "clamp": I.clamp(a,I.low(b),I.high(b))
    case _: Fail{"unknown actual interval operator"}

def result(status:Result<&2,&2,String,I.Interval>) -> String:
  match status:
    case Fail{message}: "fail|" ++ message
    case Done{+range}: "range|" ++ Bool.show(I.is_nai(range)) ++ "|" ++ U32.show(F32.bits(I.low(range))) ++ "," ++ U32.show(F32.bits(I.high(range)))

def intervals(+kind:String,+a:I.Interval,+b:I.Interval,c:I.Interval) -> String:
  match kind:
    case "float-min": "float|" ++ U32.show(F32.bits(I.float_min(I.low(a),I.low(b))))
    case "float-max": "float|" ++ U32.show(F32.bits(I.float_max(I.low(a),I.low(b))))
    case _: result(operation(kind,a,b,c))

def words(value:F.F64) -> String:
  match value:
    case F.F64{hi,lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def coordinates(value:Coordinates.Coordinates) -> String:
  match value:
    case Coordinates.Coordinates{x,y,z}: "coords|" ++ words(x) ++ ";" ++ words(y) ++ ";" ++ words(z)

def mode(kind:String) -> A.NoiseMode:
  match kind:
    case "plain": A.Plain{}
    case "xz": A.ShiftedXZ{}
    case _: A.ShiftedXYZ{}

def affine(-T:Data,status:Result<&2,&2,String,T>) -> Result<&2,&1,String,T>:
  match status:
    case Fail{message}: Fail{message}
    case Done{value}: Done{value}

def column_initialize(seed:N.Word64,metadata:String,loaded:String,expression:String,limits:C.Limits,fuel:Nat) -> Result<&2,&1,String,S.State>:
  do Result<&2,&1,String,S.State>:
    raw:J.Value <- affine(J.Value,J.parse(metadata))
    settings:NS.Settings <- affine(NS.Settings,NC.read("minecraft:overworld",raw))
    plan:O.Plan <- affine(O.Plan,O.prepare(WG.normal(seed),settings))
    resources:J.Value <- affine(J.Value,J.parse_with(loaded,J.Limits{262144n,128}))
    expression:J.Value <- affine(J.Value,J.parse(expression))
    L.initialize_unblended(plan,resources,expression,limits,fuel)

def float_values(values:List<&2,F32>) -> String:
  match values:
    case Nil{}: ""
    case value <> rest: U32.show(F32.bits(value)) ++ ";" ++ float_values(rest)

def column_result(result:S.State & Result<&2,&2,String,Column.Column>) -> String:
  match result:
    case Tuple{state,Fail{message}}: "fail|" ++ message
    case Tuple{state,Done{Column.Column{expression,x,z,bottom,step,values}}}:
      "column|" ++ J.encode(expression) ++ "|" ++ U32.show(x) ++ "," ++ U32.show(z) ++ "," ++ U32.show(bottom) ++ "," ++ U32.show(step) ++ "|" ++ float_values(values)

def column(request:O.ColumnRequest,depth:Nat,result:Result<&2,&1,String,S.State>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{state}: column_result(Column.sample(state,request,4096,depth))

def run(+fields:List<&2,String>) -> String:
  match fields:
    case "interval" <> kind <> ak <> al <> ah <> bk <> bl <> bh <> ck <> cl <> ch <> Nil{}:
      intervals(kind,interval(ak,al,ah),interval(bk,bl,bh),interval(ck,cl,ch))
    case "coords" <> kind <> x <> y <> z <> xh <> xl <> yh <> yl <> sx <> sy <> sz <> Nil{}:
      coordinates(Coordinates.shifted(H.number(x),H.number(y),H.number(z),F.F64{H.number(xh),H.number(xl)},F.F64{H.number(yh),H.number(yl)},I.bits(H.number(sx)),I.bits(H.number(sy)),I.bits(H.number(sz)),mode(kind)))
    case "column" <> hi <> lo <> metadata <> loaded <> expression <> x <> z <> bottom <> step <> count <> compile_depth <> nodes <> entries <> fuel <> depth <> Nil{}:
      column(O.ColumnRequest{H.number(x),H.number(z),H.number(bottom),H.number(step),H.number(count)},U32.to_nat(H.number(depth)),
        column_initialize(N.Word64{H.number(hi),H.number(lo)},metadata,loaded,expression,C.Limits{U32.to_nat(H.number(compile_depth)),H.number(nodes),U32.to_nat(H.number(entries))},U32.to_nat(H.number(fuel))))
    case _: Spline.run(fields)

def arguments(args:List<&1,String>) -> IO(Unit):
  match args:
    case executable <> fixture <> Nil{}: IO.print(run(String.split(fixture,'|')))
    case _: IO.print("fail|one fixture argument required")

def main() -> IO(Unit):
  do IO<Unit>:
    args:List<&1,String> <- IO.args()
    arguments(args)
