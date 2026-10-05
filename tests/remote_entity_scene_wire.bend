import Base
import ./item_component.bend as Fixture
import ./player_cooking_wire.bend as Legacy
import ../src/resource_client_wire.bend as W
import ../src/remote_entity_snapshot_wire.bend as EW
import ../src/remote_entity_frame.bend as EF
import ../src/item_entity_render_model.bend as D
import ../src/generic_resource_world_sample.bend as GS
import ../src/vanilla_entity_fields.bend as V
import ../src/movement.bend as M
import ../src/client_render.bend as R
import ../src/client_world.bend as World
import ../src/world_visibility.bend as Visibility
import ../src/world_mesh.bend as WM
import ../src/mesh_render.bend as Mesh
import ../src/inventory.bend as Inv
import ../src/f64.bend as F
import ../src/u32_decimal.bend as Decimal
import ../src/json.bend as J

# Expose actual typed fields without the production entity/sample JSON encoders.
# The Python caller supplies independent literal packets and expected fields.
def number(value:U32) -> J.Value: J.JNumber{Decimal.show(value)}
def natural(value:Nat) -> J.Value: J.JNumber{Nat.show(value)}
def strings(+value:J.Value,+name:String) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    raw:J.Value <- Fixture.required(J.member(value,name),name)
    Fixture.text_value(raw)

def position(value:V.Vec3) -> J.Value:
  V.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}} = value
  J.JArray{[number(xh),number(xl),number(yh),number(yl),number(zh),number(zl)]}
def origin(value:M.Vec3) -> J.Value:
  M.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}} = value
  J.JArray{[number(xh),number(xl),number(yh),number(yl),number(zh),number(zl)]}
def camera(value:R.Camera) -> J.Value:
  R.Camera{x,y,z,yaw,pitch} = value
  J.JArray{[number(F32.bits(x)),number(F32.bits(y)),number(F32.bits(z)),number(F32.bits(yaw)),number(F32.bits(pitch))]}
def common(value:D.Common) -> J.Value:
  D.Common{dimension,id,current,old,tick,removed,accessible,order} = value
  Fixture.object([J.JMember{"dimension",Fixture.text(dimension)},J.JMember{"id",number(id)},
    J.JMember{"current",position(current)},J.JMember{"old",position(old)},J.JMember{"tick_count",number(tick)},
    J.JMember{"removed",Fixture.boolean(removed)},J.JMember{"accessible",Fixture.boolean(accessible)},
    J.JMember{"source_order",natural(order)}])
def record(value:D.Record) -> J.Value:
  match value:
    case D.Item{base,item,bob}:
      Fixture.object([J.JMember{"kind",number(0)},J.JMember{"common",common(base)},
        J.JMember{"item",Fixture.slot(item)},J.JMember{"bob",number(F32.bits(bob))}])
    case D.Orb{base,value}:
      Fixture.object([J.JMember{"kind",number(1)},J.JMember{"common",common(base)},J.JMember{"value",number(value)}])
def records(values:List<&2,D.Record>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: record(head) <> records(rest)
def entities(value:D.Snapshot) -> J.Value:
  match value:
    case D.Unbound{}: Fixture.object([J.JMember{"bound",Fixture.boolean(False{})}])
    case D.Bound{values}: Fixture.object([J.JMember{"bound",Fixture.boolean(True{})},J.JMember{"records",J.JArray{records(values)}}])

def address(value:Mesh.Address) -> J.Value:
  match value:
    case Mesh.Clamp{}: number(0)
    case Mesh.Repeat{}: number(1)
def cull(value:Mesh.Cull) -> J.Value:
  match value:
    case Mesh.Back{}: number(0)
    case Mesh.NoCull{}: number(1)
def tints(values:List<&2,WM.Tint>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case WM.Tint{index,color} <> rest: J.JArray{[number(index),number(color)]} <> tints(rest)
def appearance(value:WM.Appearance) -> J.Value:
  WM.Appearance{colors,light,uv,face,nether,threshold} = value
  J.JArray{[J.JArray{tints(colors)},number(light),address(uv),cull(face),Fixture.boolean(nether),number(threshold)]}
def cells(values:List<&2,GS.Cell>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case GS.Cell{World.Cell{x,y,z,boundary},state,seed,surface} <> rest:
      J.JArray{[number(x),number(y),number(z),number(boundary),number(state),number(seed),appearance(surface)]} <> cells(rest)
def sample(value:GS.Sample) -> J.Value:
  GS.Sample{registry,tick,revision,o,c,values} = value
  Fixture.object([J.JMember{"registry",Fixture.text(registry)},J.JMember{"tick",natural(tick)},
    J.JMember{"revision",natural(revision)},J.JMember{"origin",origin(o)},J.JMember{"camera",camera(c)},
    J.JMember{"cells",J.JArray{cells(values)}}])
def frame(value:EF.Frame) -> J.Value:
  EF.Frame{blocks,values,dimension,partial} = value
  Fixture.object([J.JMember{"sample",sample(blocks)},J.JMember{"entities",entities(values)},
    J.JMember{"dimension",Fixture.text(dimension)},J.JMember{"partial",number(F32.bits(partial))}])
def stamp(value:EW.Stamp) -> J.Value:
  EW.Stamp{registry,tick,revision,dimension,o,c,partial} = value
  Fixture.object([J.JMember{"registry",Fixture.text(registry)},J.JMember{"tick",natural(tick)},
    J.JMember{"revision",natural(revision)},J.JMember{"dimension",Fixture.text(dimension)},
    J.JMember{"origin",origin(o)},J.JMember{"camera",camera(c)},J.JMember{"partial",number(F32.bits(partial))}])
def old_sample(value:Visibility.Sample) -> J.Value:
  Visibility.Sample{R.Snapshot{tick,revision,blocks,c},raw,masks,o,World.Palette{a,b,d,e},reads} = value
  Fixture.object([J.JMember{"tick",natural(tick)},J.JMember{"revision",natural(revision)},
    J.JMember{"origin",origin(o)},J.JMember{"camera",camera(c)},
    J.JMember{"palette",J.JArray{[number(a),number(b),number(d),number(e)]}},J.JMember{"reads",number(reads)},
    J.JMember{"raw_count",natural(List.length(&2,World.RawBlock,raw))},
    J.JMember{"blocks_count",natural(List.length(&2,R.Block,blocks))},
    J.JMember{"masks_count",natural(List.length(&2,Visibility.Visibility,masks))}])
def request(value:W.Request) -> J.Value:
  match value:
    case W.Call{epoch,sequence,W.SceneFrame{width,height,partial}}:
      Fixture.object([J.JMember{"epoch",Fixture.text(epoch)},J.JMember{"sequence",natural(sequence)},
        J.JMember{"command",J.JArray{[number(20),number(width),number(height),number(F32.bits(partial))]}}])
    case other: Legacy.request(other)
def reply(value:W.Reply) -> J.Value:
  match value:
    case W.SceneFrameReply{epoch,sequence,publication}:
      Fixture.object([J.JMember{"tag",number(9)},J.JMember{"epoch",Fixture.text(epoch)},
        J.JMember{"sequence",natural(sequence)},J.JMember{"frame",frame(publication)}])
    case W.CatalogFrameReply{epoch,sequence,blocks}:
      Fixture.object([J.JMember{"tag",number(7)},J.JMember{"epoch",Fixture.text(epoch)},
        J.JMember{"sequence",natural(sequence)},J.JMember{"sample",sample(blocks)}])
    case W.FrameReply{epoch,sequence,blocks}:
      Fixture.object([J.JMember{"tag",number(1)},J.JMember{"epoch",Fixture.text(epoch)},
        J.JMember{"sequence",natural(sequence)},J.JMember{"sample",old_sample(blocks)}])
    case other: Legacy.reply(other)

def encoded(value:Result<&2,&2,String,String>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{text}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})},J.JMember{"text",Fixture.text(text)}])
def decoded_request(value:Result<&2,&2,String,W.Request>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{+answer}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})},
      J.JMember{"observed",request(answer)},J.JMember{"encoded",encoded(W.encode_request(answer))}])
def decoded_reply(value:Result<&2,&2,String,W.Reply>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{+answer}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})},
      J.JMember{"observed",reply(answer)},J.JMember{"encoded",encoded(W.encode_reply(answer))}])
def encoded_request(+value:Result<&2,&2,String,String>) -> J.Value:
  match value:
    case Fail{message}: Fixture.object([J.JMember{"encoded",encoded(value)}])
    case Done{text}: Fixture.object([J.JMember{"encoded",encoded(value)},J.JMember{"decoded",decoded_request(W.decode_request(text))}])
def encoded_reply(+value:Result<&2,&2,String,String>) -> J.Value:
  match value:
    case Fail{message}: Fixture.object([J.JMember{"encoded",encoded(value)}])
    case Done{text}: Fixture.object([J.JMember{"encoded",encoded(value)},J.JMember{"decoded",decoded_reply(W.decode_reply(text))}])

def fixture_origin() -> M.Vec3:
  M.Vec3{F.F64{2147483648,0},F.F64{1078984704,0},F.F64{3220176896,0}}
def fixture_camera() -> R.Camera:
  R.Camera{EW.float_bits(2147483648),0.0,EW.float_bits(2147483648),EW.float_bits(1119092736),EW.float_bits(3258187776)}
def fixture_sample() -> GS.Sample:
  GS.Sample{"entity-fixture:26.3",W.nat_max(),Nat.sub(W.nat_max(),1n),fixture_origin(),fixture_camera(),
    [GS.Cell{World.Cell{4294967295,2147483648,0,3},321,4294967295,
      WM.Appearance{[WM.Tint{2,4294967295},WM.Tint{0,4278190080}],4294967295,Mesh.Repeat{},Mesh.NoCull{},True{},127}}]}
def fixture_current(variant:String) -> V.Vec3:
  match variant:
    case "current_infinity": V.Vec3{F.F64{2146435072,0},F.F64{1072693248,1},F.F64{3220176896,0}}
    case _: V.Vec3{F.F64{2147483648,0},F.F64{1072693248,1},F.F64{3220176896,0}}
def fixture_old(variant:String) -> V.Vec3:
  match variant:
    case "old_nan": V.Vec3{F.F64{0,1},F.F64{1073741824,0},F.F64{2146959360,123}}
    case _: V.Vec3{F.F64{0,1},F.F64{1073741824,0},F.F64{3221225472,0}}
def fixture_first_id(variant:String) -> U32:
  match variant:
    case "id_zero": 0
    case _: 23
def fixture_orb_id(variant:String) -> U32:
  match variant:
    case "duplicate_id": 23
    case _: 7
def fixture_common(+variant:String) -> D.Common:
  D.Common{"minecraft:the_end",fixture_first_id(variant),fixture_current(variant),fixture_old(variant),4294967295,False{},True{},W.nat_max()}
def fixture_orb_common(variant:String) -> D.Common:
  D.Common{"minecraft:overworld",fixture_orb_id(variant),fixture_current("bound"),fixture_old("bound"),4294967295,True{},False{},0n}
def fixture_last_common() -> D.Common:
  D.Common{"minecraft:the_end",4294967295,fixture_current("bound"),fixture_old("bound"),4294967295,False{},True{},0n}
def fixture_item(variant:String,components:String,count:U32) -> Inv.Slot:
  match variant:
    case "item_empty": Inv.InvEmpty{}
    case _: Inv.InvStack{Inv.ItemKey{"minecraft:suspicious_stew",components},count}
def fixture_last_item(variant:String,components:String) -> Inv.Slot:
  match variant:
    case "multi_large": Inv.InvStack{Inv.ItemKey{"minecraft:suspicious_stew",components},1}
    case _: Inv.InvStack{Inv.ItemKey{"minecraft:stone",""},99}
def fixture_bob(variant:String,bits:U32) -> F32:
  match variant:
    case "bob_nan": EW.float_bits(2143289345)
    case "bob_infinity": EW.float_bits(2139095040)
    case _: EW.float_bits(bits)
def fixture_orb_value(variant:String) -> U32:
  match variant:
    case "orb_zero": 0
    case _: 4294967295
def fixture_entities(+variant:String,+components:String,count:U32,bob:U32) -> D.Snapshot:
  match variant:
    case "unbound": D.Unbound{}
    case "empty": D.Bound{[]}
    case _: D.Bound{[
      D.Item{fixture_common(variant),fixture_item(variant,components,count),fixture_bob(variant,bob)},
      D.Orb{fixture_orb_common(variant),fixture_orb_value(variant)},
      D.Item{fixture_last_common(),fixture_last_item(variant,components),EW.float_bits(2147483648)}]}
def fixture_dimension(variant:String) -> String:
  match variant:
    case "unknown_dimension": "fixture:other_dimension"
    case _: "minecraft:the_end"
def fixture_frame(+variant:String,components:String,count:U32,bob:U32) -> EF.Frame:
  EF.Frame{fixture_sample(),fixture_entities(variant,components,count,bob),fixture_dimension(variant),EW.float_bits(1056964608)}

# Each expectation changes exactly one field. The zero-word changes deliberately
# preserve numeric equality while requiring distinct capture identity.
def expected_origin(variant:String) -> M.Vec3:
  match variant:
    case "origin_x_hi": M.Vec3{F.F64{0,0},F.F64{1078984704,0},F.F64{3220176896,0}}
    case "origin_x_lo": M.Vec3{F.F64{2147483648,1},F.F64{1078984704,0},F.F64{3220176896,0}}
    case "origin_y_hi": M.Vec3{F.F64{2147483648,0},F.F64{1078984705,0},F.F64{3220176896,0}}
    case "origin_y_lo": M.Vec3{F.F64{2147483648,0},F.F64{1078984704,1},F.F64{3220176896,0}}
    case "origin_z_hi": M.Vec3{F.F64{2147483648,0},F.F64{1078984704,0},F.F64{3220176897,0}}
    case "origin_z_lo": M.Vec3{F.F64{2147483648,0},F.F64{1078984704,0},F.F64{3220176896,1}}
    case _: fixture_origin()
def expected_camera(variant:String) -> R.Camera:
  match variant:
    case "camera_x": R.Camera{0.0,0.0,EW.float_bits(2147483648),EW.float_bits(1119092736),EW.float_bits(3258187776)}
    case "camera_y": R.Camera{EW.float_bits(2147483648),EW.float_bits(2147483648),EW.float_bits(2147483648),EW.float_bits(1119092736),EW.float_bits(3258187776)}
    case "camera_z": R.Camera{EW.float_bits(2147483648),0.0,0.0,EW.float_bits(1119092736),EW.float_bits(3258187776)}
    case "camera_yaw": R.Camera{EW.float_bits(2147483648),0.0,EW.float_bits(2147483648),EW.float_bits(1119092737),EW.float_bits(3258187776)}
    case "camera_pitch": R.Camera{EW.float_bits(2147483648),0.0,EW.float_bits(2147483648),EW.float_bits(1119092736),EW.float_bits(3258187777)}
    case _: fixture_camera()
def expected_registry(variant:String) -> String:
  match variant:
    case "registry": "entity-fixture:26.4"
    case _: "entity-fixture:26.3"
def expected_tick(variant:String) -> Nat:
  match variant:
    case "tick": Nat.sub(W.nat_max(),1n)
    case _: W.nat_max()
def expected_revision(variant:String) -> Nat:
  match variant:
    case "revision": W.nat_max()
    case _: Nat.sub(W.nat_max(),1n)
def expected_dimension(variant:String) -> String:
  match variant:
    case "dimension": "minecraft:overworld"
    case _: "minecraft:the_end"
def expected_partial(variant:String) -> F32:
  match variant:
    case "same_zero_partial": EW.float_bits(2147483648)
    case "partial_zero_sign": 0.0
    case "partial": EW.float_bits(1056964609)
    case _: EW.float_bits(1056964608)
def expected_stamp(+variant:String) -> EW.Stamp:
  EW.Stamp{expected_registry(variant),expected_tick(variant),expected_revision(variant),expected_dimension(variant),
    expected_origin(variant),expected_camera(variant),expected_partial(variant)}
def stamp_checked(value:Result<&2,&2,String,EF.Frame>) -> J.Value:
  match value:
    case Fail{message}: Fixture.error(message)
    case Done{frame}: Fixture.object([J.JMember{"accepted",Fixture.boolean(True{})}])
def stamp_probe(+variant:String,+value:EF.Frame) -> J.Value:
  Fixture.object([J.JMember{"stamp",stamp(EW.stamp(value))},
    J.JMember{"matches",Fixture.boolean(EW.matches(expected_stamp(variant),value))},
    J.JMember{"checked",stamp_checked(EW.checked_stamp(expected_stamp(variant),value))}])
def fixture_stamp_frame(variant:String,components:String,count:U32,bob:U32) -> EF.Frame:
  match variant:
    case "same_zero_partial": EF.Frame{fixture_sample(),fixture_entities("bound",components,count,bob),"minecraft:the_end",EW.float_bits(2147483648)}
    case "partial_zero_sign": EF.Frame{fixture_sample(),fixture_entities("bound",components,count,bob),"minecraft:the_end",EW.float_bits(2147483648)}
    case _: fixture_frame("bound",components,count,bob)
def correlation_reply(variant:String,components:String,count:U32,bob:U32) -> W.Reply:
  match variant:
    case "wrong_epoch": W.SceneFrameReply{"other-entity-scene-wire",W.nat_max(),fixture_frame("bound",components,count,bob)}
    case "wrong_sequence": W.SceneFrameReply{"entity-scene-wire",Nat.sub(W.nat_max(),1n),fixture_frame("bound",components,count,bob)}
    case "legacy": W.Ack{"entity-scene-wire",W.nat_max()}
    case "same_zero_partial": W.SceneFrameReply{"entity-scene-wire",W.nat_max(),fixture_stamp_frame("same_zero_partial",components,count,bob)}
    case "partial_zero_sign": W.SceneFrameReply{"entity-scene-wire",W.nat_max(),fixture_stamp_frame("partial_zero_sign",components,count,bob)}
    case _: W.SceneFrameReply{"entity-scene-wire",W.nat_max(),fixture_frame("bound",components,count,bob)}
def correlation_fraction(variant:String) -> F32:
  match variant:
    case "wrong_partial": EW.float_bits(1056964609)
    case "same_zero_partial": EW.float_bits(2147483648)
    case "partial_zero_sign": 0.0
    case _: EW.float_bits(1056964608)
def correlation_stamp(variant:String) -> EW.Stamp:
  match variant:
    case "wrong_stamp": expected_stamp("tick")
    case "same_zero_partial": expected_stamp("same_zero_partial")
    case "partial_zero_sign": expected_stamp("partial_zero_sign")
    case _: expected_stamp("same")
def correlation_probe(+variant:String,+value:W.Reply) -> J.Value:
  Fixture.object([J.JMember{"correlation",Fixture.boolean(W.correlation("entity-scene-wire",W.nat_max(),value))},
    J.JMember{"fraction_valid",Fixture.boolean(W.scene_fraction_valid(correlation_fraction(variant),value))},
    J.JMember{"fraction_matches",Fixture.boolean(W.scene_fraction_matches("entity-scene-wire",W.nat_max(),correlation_fraction(variant),value))},
    J.JMember{"stamp_matches",Fixture.boolean(W.scene_stamp_matches("entity-scene-wire",W.nat_max(),correlation_stamp(variant),value))}])

def run(+value:J.Value,mode:String) -> Result<&2,&2,String,J.Value>:
  match mode:
    case "decode_request":
      do Result<&2,&2,String,J.Value>:
        raw:String <- strings(value,"text")
        return decoded_request(W.decode_request(raw))
    case "decode_reply":
      do Result<&2,&2,String,J.Value>:
        raw:String <- strings(value,"text")
        return decoded_reply(W.decode_reply(raw))
    case "encode_request":
      do Result<&2,&2,String,J.Value>:
        width:U32 <- Fixture.fixture_number(value,"width")
        height:U32 <- Fixture.fixture_number(value,"height")
        partial:U32 <- Fixture.fixture_number(value,"partial")
        return encoded_request(W.encode_request(W.Call{"entity-scene-wire",W.nat_max(),W.SceneFrame{width,height,EW.float_bits(partial)}}))
    case "encode_reply":
      do Result<&2,&2,String,J.Value>:
        variant:String <- strings(value,"variant")
        components:String <- strings(value,"components")
        count:U32 <- Fixture.fixture_number(value,"count")
        bob:U32 <- Fixture.fixture_number(value,"bob")
        return encoded_reply(W.encode_reply(W.SceneFrameReply{"entity-scene-wire",W.nat_max(),fixture_frame(variant,components,count,bob)}))
    case "stamp":
      do Result<&2,&2,String,J.Value>:
        +variant:String <- strings(value,"variant")
        components:String <- strings(value,"components")
        count:U32 <- Fixture.fixture_number(value,"count")
        bob:U32 <- Fixture.fixture_number(value,"bob")
        return stamp_probe(variant,fixture_stamp_frame(variant,components,count,bob))
    case "correlation":
      do Result<&2,&2,String,J.Value>:
        +variant:String <- strings(value,"variant")
        components:String <- strings(value,"components")
        count:U32 <- Fixture.fixture_number(value,"count")
        bob:U32 <- Fixture.fixture_number(value,"bob")
        return correlation_probe(variant,correlation_reply(variant,components,count,bob))
    case _: Fail{"unknown entity-scene wire fixture mode"}
def fixture(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id:String <- strings(value,"id")
    mode:String <- strings(value,"mode")
    result:J.Value <- run(value,mode)
    return Fixture.object([J.JMember{"id",Fixture.text(id)},J.JMember{"result",result}])
def fixtures(values:List<&2,J.Value>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        Fixture.print(fixture(value))
        fixtures(rest)
def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: Fixture.print(Fail{message})
    case Done{J.JArray{values}}: fixtures(values)
    case _: IO.die(Unit,2,"entity-scene wire fixture array required")
def read_done(result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    input:String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,8388608n,32))
def arguments(values:List<String>) -> IO(Unit):
  match values:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file:File <- IO.try(File,File.open(path,"r"))
        result:File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        read_done(result)
    case _: IO.die(Unit,2,"expected entity-scene wire fixture file")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
