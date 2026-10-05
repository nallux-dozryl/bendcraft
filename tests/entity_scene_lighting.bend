import Base
import ../src/entity_scene_lighting_model.bend as M
import ../src/entity_scene_lighting.bend as L
import ../src/entity_scene_lighting_sample.bend as S
import ../src/entity_scene_lighting_proof.bend as Proof
import ../src/block_light.bend as B
import ../src/block_light_world.bend as BW
import ../src/block_light_registry.bend as BR
import ../src/sky_light.bend as Sky
import ../src/sky_light_world.bend as SW
import ../src/sky_light_flat_authority.bend as F
import ../src/world_generation_settings.bend as G
import ../src/core.bend as C
import ../src/remote_entity_snapshot_wire.bend as W
import ../src/f64.bend as Float
import ../src/movement.bend as V
import ../src/client_render.bend as R
import ../src/nbt.bend as N

# An explicitly labelled fixture catalog, not an official registry substitute.
def context() -> F.Context:
  F.Context{BR.Catalog{"fixture:air",1,1,
    Map.set(&2,Maybe<&2,BR.Entry>,MTip{},"0",Some{BR.Entry{0,0,BR.Faces{0,0,0,0,0,0}}}),
    Map.set(&2,Maybe<&2,List<&2,U32>>,MTip{},"0",Some{[0]})},
    G.Settings{"minecraft:overworld",0,16,N.Word64{0,0},
      G.Flat{"fixture:air","minecraft:plains",[],False{},False{},Some{[]}}},0,True{},True{}}
def stamp(tick:Nat,revision:Nat,camera:R.Camera,partial:F32) -> W.Stamp:
  W.Stamp{"fixture:air",tick,revision,"minecraft:overworld",
    V.Vec3{Float.F64{0,0},Float.F64{0,0},Float.F64{0,0}},camera,partial}
def camera() -> R.Camera: R.Camera{0.0,0.0,0.0,0.0,0.0}
def capture() -> M.Capture: M.Capture{"fixture:epoch",stamp(0n,0n,camera(),0.0),None{}}
def state() -> M.State:
  M.State{BW.State{C.new(1),B.new(),None{}},SW.empty(),context(),"fixture:epoch"}
def ready() -> M.State:
  M.State{BW.State{C.new(1),B.new(),None{}},
    SW.State{Sky.new(),SW.Ready{},[],[],[],Some{0n}},context(),"fixture:epoch"}
def request(epoch:String,stamp:W.Stamp,sites:List<&2,M.Site>) -> M.Request:
  M.Request{epoch,stamp,sites}
def error(result:M.State & Result<&2,&2,M.Error,M.Publication>) -> String:
  (state,status) = result
  match status:
    case Done{publication}: "done"
    case Fail{M.EpochMismatch{}}: "epoch"
    case Fail{M.StampMismatch{}}: "stamp"
    case Fail{M.InvalidPartial{}}: "partial"
    case Fail{M.DimensionMismatch{position}}: "dimension"
    case Fail{M.BlockFailure{BW.LoadingInProgress{}}}: "block-loading"
    case Fail{M.SkyFailure{SW.StaleRevision{}}}: "sky-stale"
    case Fail{other}: "other"
def missing(result:Result<&2,&2,M.Error,M.Sample>) -> Bool:
  match result:
    case Fail{M.MissingResident{position}}: True{}
    case _: False{}
def mismatch(result:Result<&2,&2,M.Error,M.Sample>) -> Bool:
  match result:
    case Fail{M.InconsistentSample{position}}: True{}
    case _: False{}
def environment_absent(result:M.State & Result<&2,&2,M.Error,M.Publication>) -> Bool:
  (state,status) = result
  match status:
    case Done{M.Publication{M.Capture{epoch,stamp,None{}},clock,Nil{}}}: True{}
    case _: False{}
def retained_rows(result:Result<&2,&2,M.Error,List<&2,M.Sample>>) -> Bool:
  match result:
    case Done{[M.Sample{M.Site{M.Entity{7,1},position},0,3,4},
      M.Sample{M.Site{M.Face{2,3,9},second},0,3,4}]}: True{}
    case _: False{}
def rows() -> Bool:
  +p:C.Position = C.Position{"minecraft:overworld",0,0,0}
  retained_rows(S.zip([M.Site{M.Entity{7,1},p},M.Site{M.Face{2,3,9},p}],
    [BW.Observation{p,Some{0},Some{3}},BW.Observation{p,Some{0},Some{3}}],
    [SW.Observation{p,Some{0},Some{4}},SW.Observation{p,Some{0},Some{4}}]))
def check(label:String,valid:Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("ok " ++ label)
    case False{}: IO.print("FAIL " ++ label)
def main() -> IO(Unit):
  +p:C.Position = C.Position{"minecraft:overworld",0,0,0}
  +ordinary:W.Stamp = stamp(0n,0n,camera(),0.0)
  +negative_zero:F32 = W.float_bits(2147483648)
  +nan:F32 = W.float_bits(2143294004)
  do IO<Unit>:
    check("epoch mismatch refuses before sampling",String.eq(error(S.sample(capture(),request("other",ordinary,[]),state())),"epoch"))
    check("raw camera signed zero mismatch refuses",String.eq(error(S.sample(capture(),
      request("fixture:epoch",stamp(0n,0n,R.Camera{negative_zero,0.0,0.0,0.0,0.0},0.0),[]),state())),"stamp"))
    check("current Core tick guards capture",String.eq(error(S.sample(
      M.Capture{"fixture:epoch",stamp(1n,0n,camera(),0.0),None{}},
      request("fixture:epoch",stamp(1n,0n,camera(),0.0),[]),state())),"stamp"))
    check("nonfinite partial cannot publish",String.eq(error(S.sample(
      M.Capture{"fixture:epoch",stamp(0n,0n,camera(),nan),None{}},
      request("fixture:epoch",stamp(0n,0n,camera(),nan),[]),state())),"partial"))
    check("stencil dimension mismatch refuses",String.eq(error(S.sample(capture(),
      request("fixture:epoch",ordinary,[M.Site{M.Entity{1,0},C.Position{"minecraft:the_nether",0,0,0}}]),state())),"dimension"))
    check("block acquisition forbids stamped samples",String.eq(error(S.sample(capture(),
      request("fixture:epoch",ordinary,[]),M.State{BW.begin(C.new(1)),SW.empty(),context(),"fixture:epoch"})),"block-loading"))
    check("unavailable sky revision remains unavailable",String.eq(error(S.sample(capture(),request("fixture:epoch",ordinary,[]),state())),"sky-stale"))
    check("missing resident cell is not fullbright",missing(S.merged(M.Site{M.Entity{1,0},p},
      BW.Observation{p,None{},None{}},SW.Observation{p,None{},None{}})))
    check("different actual state IDs refuse",mismatch(S.merged(M.Site{M.Entity{1,0},p},
      BW.Observation{p,Some{0},Some{0}},SW.Observation{p,Some{1},Some{15}})))
    check("duplicate ordered stencil roles retained",rows())
    check("absent environment stays absent",environment_absent(S.sample(capture(),request("fixture:epoch",ordinary,[]),ready())))
