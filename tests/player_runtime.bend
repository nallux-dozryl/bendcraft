import Base
import ../src/player_runtime.bend as RT
import ../src/player_tick.bend as P
import ../src/player_record.bend as PR
import ../src/player_codec.bend as PS
import ../src/player_controls.bend as PC
import ../src/player_input.bend as I
import ../src/player_look.bend as PL
import ../src/mouse_input.bend as MI
import ../src/client_controls.bend as CC
import ../src/support.bend as SP
import ../src/support_world.bend as SW
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/locomotion.bend as L
import ../src/travel.bend as T
import ../src/travel_world.bend as TW
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/core.bend as C
import ../src/schedule.bend as Q
import ../src/world_codec.bend as WC

# Standalone production-module harness. Settings only inject declared failure
# phases or the measured step-height attribute; gameplay remains in RT/P/SW.
type Settings is Data:
  Settings{mode:U32,maximum:F32,tail:List<&2,Settings>}
type Harness is Type:
  Harness{state:RT.State,settings:Settings,saved:Maybe<&2,PR.Record>,tail:List<&1,Harness>}
type Header is Data:
  Header{view:W.View,metadata:RT.Metadata,support:SP.State,controls:PC.Controller,
    error:Maybe<&2,String>,tail:List<&2,Header>}

def flag(value:Bool) -> String:
  U32.show(Bool.to_u32(value))
def scalar(value:F.F64) -> String:
  F.F64{high,low} = value
  U32.show(high) ++ "," ++ U32.show(low)
def vector(value:M.Vec3) -> String:
  M.Vec3{x,y,z} = value
  scalar(x) ++ "," ++ scalar(y) ++ "," ++ scalar(z)
def box(value:A.AABB) -> String:
  A.AABB{a,b,c,d,e,f} = value
  scalar(a) ++ "," ++ scalar(b) ++ "," ++ scalar(c) ++ "," ++ scalar(d) ++ "," ++ scalar(e) ++ "," ++ scalar(f)
def body_show(value:M.Body) -> String:
  M.Body{position,bounds,velocity,width,height,ground,horizontal,vertical,below} = value
  vector(position) ++ "," ++ box(bounds) ++ "," ++ vector(velocity) ++ "," ++ U32.show(F32.bits(width)) ++ "," ++ U32.show(F32.bits(height)) ++ "," ++ flag(ground) ++ "," ++ flag(horizontal) ++ "," ++ flag(vertical) ++ "," ++ flag(below)
def metadata_show(value:RT.Metadata) -> String:
  RT.Metadata{P.Input{x,y,z},jumping,delay,trigger,sync,speed,head} = value
  U32.show(F32.bits(x)) ++ "," ++ U32.show(F32.bits(y)) ++ "," ++ U32.show(F32.bits(z)) ++ "," ++ flag(jumping) ++ "," ++ U32.show(delay) ++ "," ++ U32.show(trigger) ++ "," ++ flag(sync) ++ "," ++ U32.show(F32.bits(speed)) ++ "," ++ U32.show(F32.bits(head))
def support_show(value:SP.State) -> String:
  match value:
    case SP.State{None{},empty}: "0,0,0,0," ++ flag(empty)
    case SP.State{Some{T.BlockPos{x,y,z}},empty}: "1," ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ flag(empty)
def look(value:PL.State) -> String:
  PL.State{yaw,pitch,old_yaw,old_pitch} = value
  U32.show(F32.bits(yaw)) ++ "," ++ U32.show(F32.bits(pitch)) ++ "," ++ U32.show(F32.bits(old_yaw)) ++ "," ++ U32.show(F32.bits(old_pitch))
def controls_show(value:PC.Controller) -> String:
  PC.Controller{buttons,rotation,MI.State{x,y,ax,ay,first},MI.Options{sensitivity,ix,iy,smooth,scoping}} = value
  U32.show(I.mask(buttons)) ++ "," ++ look(rotation) ++ "," ++ scalar(x) ++ "," ++ scalar(y) ++ "," ++ scalar(ax) ++ "," ++ scalar(ay) ++ "," ++ flag(first) ++ "," ++ scalar(sensitivity) ++ "," ++ flag(ix) ++ "," ++ flag(iy) ++ "," ++ flag(smooth) ++ "," ++ flag(scoping)
def bounds(value:W.Bounds) -> String:
  W.Bounds{x,y,z,width,height,depth} = value
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(width) ++ "," ++ U32.show(height) ++ "," ++ U32.show(depth)
def palette(value:Maybe<&2,W.Palette>) -> String:
  match value:
    case None{}: "none"
    case Some{W.Palette{a,b,c,d}}: U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)
def blocks(values:List<&2,W.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case W.RawBlock{W.Cell{x,y,z,edge},state,material} <> rest:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(edge) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ blocks(rest)
def cache(value:Maybe<&2,W.SnapshotCache>) -> String:
  match value:
    case None{}: "none"
    case Some{W.SnapshotCache{revision,region,colors,items}}: Nat.show(revision) ++ "/" ++ bounds(region) ++ "/" ++ palette(Some{colors}) ++ "/" ++ blocks(items)
def error(value:Maybe<&2,String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: text
def nibble(value:U32) -> String:
  match value:
    case 0: "0"
    case 1: "1"
    case 2: "2"
    case 3: "3"
    case 4: "4"
    case 5: "5"
    case 6: "6"
    case 7: "7"
    case 8: "8"
    case 9: "9"
    case 10: "a"
    case 11: "b"
    case 12: "c"
    case 13: "d"
    case 14: "e"
    case _: "f"
def hex(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case +value <> rest: nibble(U32.shrn(value,4n)) ++ nibble(U32.and(value,15)) ++ hex(rest)

def sample_context(settings:Settings,yaw:F32,buttons:I.Buttons,sample:SW.Sample) -> P.Context:
  Settings{mode,maximum,tail} = settings
  I.Buttons{forward,backward,left,right,jumping,shift,sprint} = buttons
  SW.Sample{ground,factor} = sample
  P.Context{T.Context{ground,T.Attributes{F.F64{1069128089,2576980378},F.F64{1068792545,1202590843},F.from_u32(1),F.from_u32(1)},yaw,maximum,sprint,False{},False{},T.NeutralDryAir{}},F.F64{1071309127,2920577761},factor,True{},P.Neutral{}}
def selected_context(settings:Settings,context:P.Context) -> P.Context:
  Settings{mode,maximum,tail} = settings
  match mode:
    case 2:
      P.Context{travel,strength,factor,affected,old} = context
      P.Context{travel,strength,factor,affected,P.NearbyActors{}}
    case _: context
def sampled(+settings:Settings,yaw:F32,buttons:I.Buttons,result:W.State & Result<&2,&2,SW.Error,SW.Sample>) -> W.State & Result<&2,&2,String,P.Context>:
  (world,status) = result
  match status:
    case Fail{cause}: (world,Fail{SW.error_text(cause)})
    case Done{sample}: (world,Done{selected_context(settings,sample_context(settings,yaw,buttons,sample))})
def context(+settings:Settings,world:W.State,support:SP.State,buttons:I.Buttons,yaw:F32) -> W.State & Result<&2,&2,String,P.Context>:
  Settings{mode,maximum,tail} = settings
  match mode:
    case 1: (world,Fail{"injected-context"})
    case _: sampled(settings,yaw,buttons,SW.sample_checked(world,support))
def supported(result:W.State & Result<&2,&2,SW.Error,SP.State>) -> W.State & Result<&2,&2,String,SP.State>:
  (world,status) = result
  match status:
    case Fail{cause}: (world,Fail{SW.error_text(cause)})
    case Done{next}: (world,Done{next})
def after(+settings:Settings,world:W.State,support:SP.State,movement:M.Transition) -> W.State & Result<&2,&2,String,SP.State>:
  Settings{mode,maximum,tail} = settings
  match mode:
    case 3: (world,Fail{"injected-support"})
    case _: supported(SW.update_checked(world,support,movement))
def driver(+settings:Settings) -> RT.Driver:
  RT.Driver{world => support => buttons => yaw => context(settings,world,support,buttons,yaw),world => support => movement => after(settings,world,support,movement)}
def bindings() -> I.Bindings:
  I.Bindings{119,115,97,100,32,340,341}

def record_text(result:Result<&2,&2,PR.Error,List<&2,U32>>) -> String:
  match result:
    case Fail{cause}: "invalid"
    case Done{bytes}: hex(bytes)
def emitted(id:String,tables:L.Tables,header:Header,registry:B.Registry,result:C.World & Result<&2,&2,String,List<&2,U32>>) -> IO(RT.State):
  Header{view,metadata,support,controls,last_error,tail} = header
  (world,status) = result
  match status:
    case Fail{cause}: IO.die(RT.State,3,"world encode: " ++ cause)
    case Done{bytes}:
      do IO<RT.State>:
        IO.print(id ++ "|world|" ++ hex(bytes))
        return RT.State{W.attach(G.Engine{world,registry},view),tables,metadata,support,controls,last_error}
def report_header(+id:String,tables:L.Tables,+header:Header,engine:G.Engine) -> IO(RT.State):
  Header{+view,+metadata,+support,+controls,last_error,tail} = header
  W.View{body,yaw,pitch,colors,region,old_cache} = view
  G.Engine{world,registry} = engine
  do IO<RT.State>:
    IO.print(id ++ "|body|" ++ body_show(body))
    IO.print(id ++ "|metadata|" ++ metadata_show(metadata))
    IO.print(id ++ "|support|" ++ support_show(support))
    IO.print(id ++ "|controls|" ++ controls_show(controls))
    IO.print(id ++ "|view|" ++ U32.show(F32.bits(yaw)) ++ "," ++ U32.show(F32.bits(pitch)) ++ "|" ++ palette(colors) ++ "|" ++ bounds(region) ++ "|" ++ cache(old_cache))
    IO.print(id ++ "|error|" ++ error(last_error))
    IO.print(id ++ "|record|" ++ record_text(PR.encode(PR.Record{PS.Snapshot{RT.compose(body,metadata),support,yaw,pitch,"minecraft:overworld"},RT.look(controls)})))
    emitted(id,tables,header,registry,WC.encode(world,"runtime-fixture"))
def report_extracted(id:String,tables:L.Tables,metadata:RT.Metadata,support:SP.State,controls:PC.Controller,error:Maybe<&2,String>,result:G.Engine & W.View) -> IO(RT.State):
  (engine,view) = result
  report_header(id,tables,Header{view,metadata,support,controls,error,[]},engine)
def report(id:String,state:RT.State) -> IO(RT.State):
  RT.State{world,tables,metadata,support,controls,error} = state
  report_extracted(id,tables,metadata,support,controls,error,W.take(world))
def reported(+id:String,settings:Settings,saved:Maybe<&2,PR.Record>,state:RT.State) -> IO(Harness):
  do IO<Harness>:
    kept : RT.State <- report(id,state)
    return Harness{kept,settings,saved,[]}
def status_text(status:Result<&2,&2,String,Unit>) -> String:
  match status:
    case Fail{cause}: cause
    case Done{unit}: "none"
def status_report(+id:String,settings:Settings,saved:Maybe<&2,PR.Record>,result:RT.State & Result<&2,&2,String,Unit>) -> IO(Harness):
  (state,status) = result
  do IO<Harness>:
    IO.print(id ++ "|status|" ++ status_text(status))
    reported(id,settings,saved,state)

def set_body(state:RT.State,body:M.Body) -> RT.State:
  RT.State{world,tables,metadata,support,controls,error} = state
  W.paired(G.Engine,W.View,RT.State,W.take(world),engine => view => RT.State{W.attach(engine,TW.with_body(view,body)),tables,metadata,support,controls,error})
def set_metadata(state:RT.State,metadata:RT.Metadata) -> RT.State:
  RT.State{world,tables,old,support,controls,error} = state
  RT.State{world,tables,metadata,support,controls,error}
def set_support(state:RT.State,support:SP.State) -> RT.State:
  RT.State{world,tables,metadata,old,controls,error} = state
  RT.State{world,tables,metadata,support,controls,error}
def set_controls(state:RT.State,controls:PC.Controller) -> RT.State:
  RT.State{world,tables,metadata,support,old,error} = state
  RT.State{world,tables,metadata,support,controls,error}
def set_look(state:RT.State,look:PL.State) -> RT.State:
  RT.State{world,tables,metadata,support,PC.Controller{buttons,old,mouse,options},error} = state
  RT.State{world,tables,metadata,support,PC.Controller{buttons,look,mouse,options},error}
def set_devices(state:RT.State,buttons:I.Buttons,mouse:MI.State,options:MI.Options) -> RT.State:
  RT.State{world,tables,metadata,support,PC.Controller{old_buttons,look,old_mouse,old_options},error} = state
  RT.State{world,tables,metadata,support,PC.Controller{buttons,look,mouse,options},error}
def set_error(state:RT.State,text:String) -> RT.State:
  RT.State{world,tables,metadata,support,controls,error} = state
  RT.State{world,tables,metadata,support,controls,Some{text}}
def pause_extracted(paused:Bool,result:G.Engine & W.View) -> W.State:
  (G.Engine{core,registry},view) = result
  W.attach(G.Engine{C.set_paused(core,paused),registry},view)
def pause_world(world:W.State,paused:Bool) -> W.State:
  pause_extracted(paused,W.take(world))
def pause(state:RT.State,paused:Bool) -> RT.State:
  RT.State{world,tables,metadata,support,controls,error} = state
  RT.State{pause_world(world,paused),tables,metadata,support,controls,error}

def material(colors:W.Palette,index:U32) -> U32:
  W.Palette{air,stone,dirt,planks} = colors
  match index:
    case 0: air
    case 1: stone
    case 2: dirt
    case _: planks
def edited_core(registry:B.Registry,view:W.View,result:C.World & Result<&2,&2,C.Error,Unit>) -> W.State:
  (world,status) = result
  W.attach(G.Engine{world,registry},view)
def edit_view(tick:U32,sequence:U32,x:U32,y:U32,z:U32,index:U32,+view:W.View,engine:G.Engine) -> W.State:
  W.View{body,yaw,pitch,colors,region,cache} = view
  match colors:
    case None{}: W.attach(engine,view)
    case Some{palette}:
      G.Engine{core,registry} = engine
      edited_core(registry,view,C.admit(core,C.Developer{},Q.Stamp{U32.to_nat(tick),77,U32.to_nat(sequence)},C.BlockSet{C.Position{"minecraft:overworld",x,y,z},material(palette,index)}))
def edit_extracted(tick:U32,sequence:U32,x:U32,y:U32,z:U32,index:U32,result:G.Engine & W.View) -> W.State:
  (engine,view) = result
  edit_view(tick,sequence,x,y,z,index,view,engine)
def edit_world(world:W.State,tick:U32,sequence:U32,x:U32,y:U32,z:U32,index:U32) -> W.State:
  edit_extracted(tick,sequence,x,y,z,index,W.take(world))
def edit(state:RT.State,tick:U32,sequence:U32,x:U32,y:U32,z:U32,index:U32) -> RT.State:
  RT.State{world,tables,metadata,support,controls,error} = state
  RT.State{edit_world(world,tick,sequence,x,y,z,index),tables,metadata,support,controls,error}

def actions(fields:List<&2,U32>) -> List<&2,CC.Action>:
  match fields:
    case Nil{}: []
    case 0 <> a <> b <> rest: CC.PlatformEvent{Key{a,U32.is_ne(b,0)},True{}} <> actions(rest)
    case 1 <> a <> b <> rest: CC.PlatformEvent{Look{PL.float_bits(a),PL.float_bits(b)},True{}} <> actions(rest)
    case kind <> a <> b <> rest: CC.Release{} <> actions(rest)
    case _: []
def snapshot_result(+id:String,settings:Settings,saved:Maybe<&2,PR.Record>,result:RT.State & Result<&2,&2,String,R.Snapshot>) -> IO(Harness):
  (state,status) = result
  match status:
    case Fail{cause}: status_report(id,settings,saved,(state,Fail{cause}))
    case Done{value}: status_report(id,settings,saved,(state,Done{Unit{}}))
def saved_record(+id:String,settings:Settings,result:RT.State & PR.Record) -> IO(Harness):
  (state,record) = result
  reported(id,settings,Some{record},state)
def bad_record(record:PR.Record,mode:U32) -> PR.Record:
  PR.Record{PS.Snapshot{player,support,yaw,pitch,dimension},look} = record
  match mode:
    case 1: PR.Record{PS.Snapshot{player,support,PL.float_bits(U32.xor(F32.bits(yaw),1)),pitch,dimension},look}
    case 2: PR.Record{PS.Snapshot{player,support,yaw,pitch,"minecraft:the_end"},look}
    case _: PR.Record{PS.Snapshot{player,support,yaw,pitch,dimension},look}
def restore_record(+id:String,settings:Settings,+saved:Maybe<&2,PR.Record>,state:RT.State,mode:U32) -> IO(Harness):
  match saved:
    case None{}: IO.die(Harness,2,"no saved record")
    case Some{record}: status_report(id,settings,saved,RT.restore(state,bad_record(record,mode)))

def parsed_numbers(head:Maybe<&2,U32>,tail:Maybe<&2,List<&2,U32>>) -> Maybe<&2,List<&2,U32>>:
  match head tail:
    case Some{word} Some{words}: Some{word <> words}
    case _ _: None{}
def numbers(fields:List<&2,String>) -> Maybe<&2,List<&2,U32>>:
  match fields:
    case Nil{}: Some{[]}
    case text <> rest: parsed_numbers(U32.read(text),numbers(rest))
def numeric(+id:String,harness:Harness,op:String,fields:List<&2,U32>) -> IO(Harness):
  Harness{state,+settings,+saved,tail} = harness
  match op fields:
    case "body" pxh <> pxl <> pyh <> pyl <> pzh <> pzl <> axh <> axl <> ayh <> ayl <> azh <> azl <> bxh <> bxl <> byh <> byl <> bzh <> bzl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> Nil{}:
      reported(id,settings,saved,set_body(state,M.Body{M.Vec3{F.F64{pxh,pxl},F.F64{pyh,pyl},F.F64{pzh,pzl}},A.AABB{F.F64{axh,axl},F.F64{ayh,ayl},F.F64{azh,azl},F.F64{bxh,bxl},F.F64{byh,byl},F.F64{bzh,bzl}},M.Vec3{F.F64{vxh,vxl},F.F64{vyh,vyl},F.F64{vzh,vzl}},PL.float_bits(width),PL.float_bits(height),U32.is_ne(ground,0),U32.is_ne(horizontal,0),U32.is_ne(vertical,0),U32.is_ne(below,0)}))
    case "metadata" x <> y <> z <> jumping <> delay <> trigger <> sync <> speed <> head <> Nil{}:
      reported(id,settings,saved,set_metadata(state,RT.Metadata{P.Input{PL.float_bits(x),PL.float_bits(y),PL.float_bits(z)},U32.is_ne(jumping,0),delay,trigger,U32.is_ne(sync,0),PL.float_bits(speed),PL.float_bits(head)}))
    case "support" present <> x <> y <> z <> empty <> Nil{}:
      reported(id,settings,saved,set_support(state,SP.State{W.choose(Maybe<&2,T.BlockPos>,Some{T.BlockPos{x,y,z}},None{},U32.is_ne(present,0)),U32.is_ne(empty,0)}))
    case "look" yaw <> pitch <> old_yaw <> old_pitch <> Nil{}:
      reported(id,settings,saved,set_look(state,PL.State{PL.float_bits(yaw),PL.float_bits(pitch),PL.float_bits(old_yaw),PL.float_bits(old_pitch)}))
    case "controls" mask <> xh <> xl <> yh <> yl <> axh <> axl <> ayh <> ayl <> first <> sh <> sl <> ix <> iy <> smooth <> scoping <> Nil{}:
      reported(id,settings,saved,set_devices(state,I.from_mask(mask),MI.State{F.F64{xh,xl},F.F64{yh,yl},F.F64{axh,axl},F.F64{ayh,ayl},U32.is_ne(first,0)},MI.Options{F.F64{sh,sl},U32.is_ne(ix,0),U32.is_ne(iy,0),U32.is_ne(smooth,0),U32.is_ne(scoping,0)}))
    case "settings" mode <> maximum <> Nil{}: reported(id,Settings{mode,PL.float_bits(maximum),[]},saved,state)
    case "key" code <> down <> Nil{}: reported(id,settings,saved,RT.key(state,bindings(),code,U32.is_ne(down,0)))
    case "packet" focused <> captured <> rest: status_report(id,settings,saved,RT.input(state,bindings(),CC.Packet{actions(rest),U32.is_ne(focused,0),U32.is_ne(captured,0)}))
    case "advance" count <> Nil{}: reported(id,settings,saved,RT.advance(~driver(Settings{0,0.6,[]}),U32.to_nat(U32.min(count,64)),state))
    case "pause" paused <> Nil{}: reported(id,settings,saved,pause(state,U32.is_ne(paused,0)))
    case "edit" tick <> sequence <> x <> y <> z <> index <> Nil{}: reported(id,settings,saved,edit(state,tick,sequence,x,y,z,index))
    case "restore" mode <> Nil{}: restore_record(id,settings,saved,state,mode)
    case _ _: IO.die(Harness,2,"invalid numeric command")
def parsed(id:String,op:String,harness:Harness,fields:Maybe<&2,List<&2,U32>>) -> IO(Harness):
  match fields:
    case None{}: IO.die(Harness,2,"invalid numeric field")
    case Some{words}: numeric(id,harness,op,words)
def queried_body(id:String,settings:Settings,saved:Maybe<&2,PR.Record>,result:RT.State & M.Body) -> IO(Harness):
  (state,body) = result
  reported(id,settings,saved,state)
def simple(+id:String,harness:Harness,op:String) -> IO(Harness):
  Harness{state,+settings,saved,tail} = harness
  match op:
    case "step": reported(id,settings,saved,RT.step(driver(settings),state))
    case "realtime": reported(id,settings,saved,RT.realtime_step(driver(settings),state))
    case "release": reported(id,settings,saved,RT.release(state))
    case "snapshot": snapshot_result(id,settings,saved,RT.snapshot(state,64,48))
    case "save-record": saved_record(id,settings,RT.record(state))
    case "query": queried_body(id,settings,saved,RT.query(M.Body,state,world => W.body(world)))
    case _: reported(id,settings,saved,state)
def dispatch(fields:List<&2,String>,harness:Harness) -> IO(Harness):
  match fields:
    case +id <> "error" <> text <> Nil{}:
      Harness{state,settings,saved,tail} = harness
      reported(id,settings,saved,set_error(state,text))
    case id <> op <> Nil{}: simple(id,harness,op)
    case id <> op <> rest: parsed(id,op,harness,numbers(rest))
    case _: IO.die(Harness,2,"invalid command")
def loop(args:List<String>,harness:Harness) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case command <> rest:
      do IO<Unit>:
        next : Harness <- dispatch(String.split(command,'|'),harness)
        loop(rest,next)
def loaded_world(args:List<String>,tables:L.Tables,result:W.State & Result<&2,&2,String,Unit>) -> IO(Unit):
  (world,status) = result
  match status:
    case Fail{cause}: IO.die(Unit,3,"fixture: " ++ cause)
    case Done{unit}: loop(args,Harness{RT.new(world,tables),Settings{0,0.6,[]},None{},[]})
def loaded_tables(args:List<String>,result:Result<&2,&1,L.Error,L.Tables>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,3,"table load failed")
    case Done{tables}:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        loaded_world(args,tables,W.fixture(engine))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> rest:
      do IO<Unit>:
        tables : Result<&2,&1,L.Error,L.Tables> <- L.Tables.load(path)
        loaded_tables(rest,tables)
    case _: IO.die(Unit,2,"table path required")
def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
