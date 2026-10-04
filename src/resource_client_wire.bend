import Base
import ./json.bend as J
import ./client_controls.bend as CC
import ./client_world.bend as W
import ./client_render.bend as R
import ./world_visibility.bend as V
import ./world_mesh.bend as WM
import ./movement.bend as M
import ./f64.bend as F
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./generic_resource_world_sample.bend as GS
import ./mesh_render.bend as Mesh

# Pure, monomorphic renderer wire DTOs. Authentication, matching lease cleanup,
# strict expected-sequence transition and expiry belong to the backend actor.
type Command is Data:
  Frame{width:U32,height:U32}
  Input{packet:CC.Packet}
  Release{}
  Action{button:U32}
  Hotbar{index:U32}
  Inventory{}
  Transfer{source:U32,destination:U32,count:U32,mode:Inv.TransferMode}
  Acquire{index:U32,key:Inv.ItemKey,count:U32}
  MenuInspect{}
  MenuOpen{}
  MenuClose{}
  MenuClick{index:U32,click:I.Click}
  Select{index:U32}
  FrameCatalog{width:U32,height:U32}
type Request is Data:
  Hello{capability:String}
  Call{epoch:String,sequence:Nat,command:Command}
type Reply is Data:
  HelloAck{epoch:String,sequence:Nat}
  FrameReply{epoch:String,sequence:Nat,sample:V.Sample}
  Ack{epoch:String,sequence:Nat}
  Fault{epoch:String,sequence:Nat,message:String}
  InventoryReply{epoch:String,sequence:Nat,snapshot:I.Snapshot}
  ActionReply{epoch:String,sequence:Nat,changed:Bool,message:String}
  MenuReply{epoch:String,sequence:Nat,accepted:Bool,message:String,snapshot:I.MenuSnapshot}
  CatalogFrameReply{epoch:String,sequence:Nat,sample:GS.Sample}
type Row is Data:
  Row{raw:W.RawBlock,block:R.Block,visibility:V.Visibility}
type Rows is Data:
  Rows{raw:List<&2,W.RawBlock>,blocks:List<&2,R.Block>,masks:List<&2,V.Visibility>}

def version() -> U32: 1

def transport_bytes() -> U32: 65536

def parser_scalars() -> Nat: 65536n

def parser_depth() -> U32: 8

def sample_blocks() -> U32: 4096

def mesh_limits() -> WM.Limits: WM.defaults()

def nat_max() -> Nat: Nat.add(Nat.mul(U32.to_nat(65535),Nat.add(U32.to_nat(4294967295),1n)),U32.to_nat(4294967295))

# Nat48 max = 65536 * 2^32 - 1. Compute without overflowing the native lane.
def sequence_valid(+sequence:Nat) -> Bool:
  Nat.is_gt(sequence,0n) && Nat.is_le(sequence,nat_max())

def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}

def printable_ascii(text:String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+c},tail}: U32.is_ge(c,33) && U32.is_le(c,126) && printable_ascii(tail)

def nonempty_ascii_admitted(+text:String,valid:Bool) -> Bool:
  match valid:
    case False{}: False{}
    case True{}: Nat.is_gt(String.length(text),0n) && printable_ascii(text)

def nonempty_ascii(+text:String,maximum:Nat) -> Bool:
  nonempty_ascii_admitted(text,J.within(maximum,text))

def epoch_valid(epoch:String) -> Bool:
  nonempty_ascii(epoch,64n)

def ascii(text:String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{c,tail}: U32.is_lt(Char.to_u32(c),128) && ascii(tail)

def scalar_text(text:String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{c,tail}: J.scalar(Char.to_u32(c)) && scalar_text(tail)

def diagnostic_valid(+message:String) -> Bool:
  J.within(2048n,message) && scalar_text(message)

# Count containers as well as scalar values. This independent AST budget is
# smaller than the transport character bound. Fuel precedes traversal state.
def values_fit(fuel:Nat,values:List<&2,J.Value>) -> Bool:
  match fuel values:
    case _ Nil{}: True{}
    case 0n head <> tail: False{}
    case 1n+rest J.JArray{children} <> tail: values_fit(rest,List.append(&2,J.Value,children,tail))
    case 1n+rest J.JObject{members} <> tail: False{}
    case 1n+rest head <> tail: values_fit(rest,tail)

def parse_admitted(+text:String,valid:Bool) -> Result<&2,&2,String,J.Value>:
  match valid:
    case False{}: Fail{"wire:ASCII-or-transport-parser-budget"}
    case True{}: J.parse_with(text,J.Limits{65536n,8})

def parse(+text:String) -> Result<&2,&2,String,J.Value>:
  parse_admitted(text,J.within(65536n,text) && ascii(text))

def float_bits(value:U32) -> F32:
  U32{word} = value
  F32{word}

def uint_optional(value:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match value:
    case Some{word}: Done{word}
    case None{}: Fail{"wire:U32"}

def uint(value:J.Value) -> Result<&2,&2,String,U32>:
  match value:
    case J.JNumber{+raw}:
      do Result<&2,&2,String,U32>:
        guard(J.within(10n,raw),"wire:U32-lexeme-budget")
        uint_optional(J.u32_lexeme(raw))
    case _: Fail{"wire:expected-U32"}

def natural_read(+raw:String,result:Maybe<&2,Nat>) -> Result<&2,&2,String,Nat>:
  match result:
    case None{}: Fail{"wire:Nat48"}
    case Some{+value}:
      do Result<&2,&2,String,Nat>:
        guard(String.eq(raw,Nat.show(value)),"wire:noncanonical-Nat48")
        Done{value}

def natural(value:J.Value) -> Result<&2,&2,String,Nat>:
  match value:
    case J.JNumber{+raw}: natural_read(raw,Nat.read(raw))
    case _: Fail{"wire:expected-Nat48"}

def boolean(value:J.Value) -> Result<&2,&2,String,Bool>:
  match value:
    case J.JBool{value}: Done{value}
    case _: Fail{"wire:expected-Bool"}

def text(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{value}: Done{value}
    case _: Fail{"wire:expected-String"}

def floats3(value:J.Value) -> Result<&2,&2,String,R.Camera>:
  match value:
    case J.JArray{[x,y,z,yaw,pitch]}:
      do Result<&2,&2,String,R.Camera>:
        +xx:U32 <- uint(x)
        +yy:U32 <- uint(y)
        +zz:U32 <- uint(z)
        +ya:U32 <- uint(yaw)
        +pi:U32 <- uint(pitch)
        Done{R.Camera{float_bits(xx),float_bits(yy),float_bits(zz),float_bits(ya),float_bits(pi)}}
    case _: Fail{"wire:camera-cardinality"}

def origin(value:J.Value) -> Result<&2,&2,String,M.Vec3>:
  match value:
    case J.JArray{[xh,xl,yh,yl,zh,zl]}:
      do Result<&2,&2,String,M.Vec3>:
        +a:U32 <- uint(xh)
        +b:U32 <- uint(xl)
        +c:U32 <- uint(yh)
        +d:U32 <- uint(yl)
        +e:U32 <- uint(zh)
        +f:U32 <- uint(zl)
        Done{M.Vec3{F.F64{a,b},F.F64{c,d},F.F64{e,f}}}
    case _: Fail{"wire:origin-cardinality"}

def palette(value:J.Value) -> Result<&2,&2,String,W.Palette>:
  match value:
    case J.JArray{[a,b,c,d]}:
      do Result<&2,&2,String,W.Palette>:
        +air:U32 <- uint(a)
        +stone:U32 <- uint(b)
        +dirt:U32 <- uint(c)
        +planks:U32 <- uint(d)
        Done{W.Palette{air,stone,dirt,planks}}
    case _: Fail{"wire:palette-cardinality"}

def row(value:J.Value) -> Result<&2,&2,String,Row>:
  match value:
    case J.JArray{[x,y,z,boundary,state,material,visible,bx,by,bz]}:
      do Result<&2,&2,String,Row>:
        +xx:U32 <- uint(x)
        +yy:U32 <- uint(y)
        +zz:U32 <- uint(z)
        +bound:U32 <- uint(boundary)
        +st:U32 <- uint(state)
        +mat:U32 <- uint(material)
        +mask:U32 <- uint(visible)
        +rx:U32 <- uint(bx)
        +ry:U32 <- uint(by)
        +rz:U32 <- uint(bz)
        Done{Row{W.RawBlock{W.Cell{xx,yy,zz,bound},st,mat},
          R.Block{float_bits(rx),float_bits(ry),float_bits(rz),st,mat},
          V.Visibility{W.Cell{xx,yy,zz,bound},st,mask}}}
    case _: Fail{"wire:cell-cardinality"}

def row_cons(own:Row,remaining:Rows) -> Rows:
  Row{raw,block,mask} = own
  Rows{other,blocks,masks} = remaining
  Rows{raw <> other,block <> blocks,mask <> masks}

def rows(values:List<&2,J.Value>,fuel:Nat) -> Result<&2,&2,String,Rows>:
  match values fuel:
    case Nil{} _: Done{Rows{[],[],[]}}
    case head <> tail 0n: Fail{"wire:sample-budget"}
    case head <> tail 1n+rest:
      do Result<&2,&2,String,Rows>:
        +own:Row <- row(head)
        +remaining:Rows <- rows(tail,rest)
        Done{row_cons(own,remaining)}

def row_array(value:J.Value) -> Result<&2,&2,String,Rows>:
  match value:
    case J.JArray{values}: rows(values,4096n)
    case _: Fail{"wire:expected-cells-array"}

def mask_boundaries(raw:List<&2,W.RawBlock>,masks:List<&2,V.Visibility>) -> Bool:
  match raw masks:
    case Nil{} Nil{}: True{}
    case W.RawBlock{W.Cell{x,y,z,boundary},state,material} <> tail
         V.Visibility{W.Cell{vx,vy,vz,other},vs,visible} <> remaining:
      U32.is_eq(boundary,other) && mask_boundaries(tail,remaining)
    case _ _: False{}

def sample_valid(+sample:V.Sample) -> Bool:
  V.Sample{R.Snapshot{tick,revision,blocks,+camera},raw,masks,origin,palette,reads} = sample
  Nat.is_le(tick,nat_max()) && Nat.is_le(revision,nat_max()) &&
    U32.is_le(reads,24576) && WM.relative_camera(camera) && mask_boundaries(raw,masks) && V.sample_valid(sample,4096)

def checked_sample(+sample:V.Sample) -> Result<&2,&2,String,V.Sample>:
  do Result<&2,&2,String,V.Sample>:
    guard(sample_valid(sample),"wire:sample-alignment-palette-camera-budget")
    Done{sample}

def sample_rows(tick:Nat,revision:Nat,origin:M.Vec3,camera:R.Camera,palette:W.Palette,reads:U32,rows:Rows) -> Result<&2,&2,String,V.Sample>:
  Rows{raw,blocks,masks} = rows
  checked_sample(V.Sample{R.Snapshot{tick,revision,blocks,camera},raw,masks,origin,palette,reads})

def sample(value:J.Value) -> Result<&2,&2,String,V.Sample>:
  match value:
    case J.JArray{[tick,revision,eye,camera,colors,reads,cells]}:
      do Result<&2,&2,String,V.Sample>:
        +t:Nat <- natural(tick)
        +r:Nat <- natural(revision)
        +o:M.Vec3 <- origin(eye)
        +c:R.Camera <- floats3(camera)
        +p:W.Palette <- palette(colors)
        +n:U32 <- uint(reads)
        +decoded:Rows <- row_array(cells)
        sample_rows(t,r,o,c,p,n,decoded)
    case _: Fail{"wire:sample-cardinality"}

def event(value:J.Value) -> Result<&2,&2,String,Event>:
  match value:
    case J.JArray{[J.JNumber{"0"},code,down]}:
      do Result<&2,&2,String,Event>:
        +c:U32 <- uint(code)
        +d:Bool <- boolean(down)
        Done{Key{c,d}}
    case J.JArray{[J.JNumber{"1"},x,y,button,down]}:
      do Result<&2,&2,String,Event>:
        +a:U32 <- uint(x)
        +b:U32 <- uint(y)
        +c:U32 <- uint(button)
        +d:Bool <- boolean(down)
        Done{Mouse{a,b,c,d}}
    case J.JArray{[J.JNumber{"2"},x,y]}:
      do Result<&2,&2,String,Event>:
        +a:U32 <- uint(x)
        +b:U32 <- uint(y)
        Done{Move{a,b}}
    case J.JArray{[J.JNumber{"3"},x,y]}:
      do Result<&2,&2,String,Event>:
        +a:U32 <- uint(x)
        +b:U32 <- uint(y)
        Done{Look{float_bits(a),float_bits(b)}}
    case J.JArray{[J.JNumber{"4"},x,y,dx,dy]}:
      do Result<&2,&2,String,Event>:
        +a:U32 <- uint(x)
        +b:U32 <- uint(y)
        +c:U32 <- uint(dx)
        +d:U32 <- uint(dy)
        Done{Scroll{a,b,float_bits(c),float_bits(d)}}
    case J.JArray{[J.JNumber{"5"}]}: Done{Close{}}
    case _: Fail{"wire:event-tag-or-cardinality"}

def action(value:J.Value) -> Result<&2,&2,String,CC.Action>:
  match value:
    case J.JArray{[J.JNumber{"0"}]}: Done{CC.Release{}}
    case J.JArray{[J.JNumber{"1"},captured,raw]}:
      do Result<&2,&2,String,CC.Action>:
        +c:Bool <- boolean(captured)
        +e:Event <- event(raw)
        Done{CC.PlatformEvent{e,c}}
    case _: Fail{"wire:action-tag-or-cardinality"}

def actions(values:List<&2,J.Value>,fuel:Nat) -> Result<&2,&2,String,List<&2,CC.Action>>:
  match values fuel:
    case Nil{} _: Done{[]}
    case head <> tail 0n: Fail{"wire:input-action-budget"}
    case head <> tail 1n+rest:
      do Result<&2,&2,String,List<&2,CC.Action>>:
        +own:CC.Action <- action(head)
        +remaining:List<&2,CC.Action> <- actions(tail,rest)
        Done{own <> remaining}

def action_array(value:J.Value) -> Result<&2,&2,String,List<&2,CC.Action>>:
  match value:
    case J.JArray{values}: actions(values,1024n)
    case _: Fail{"wire:expected-actions-array"}

def packet(value:J.Value) -> Result<&2,&2,String,CC.Packet>:
  match value:
    case J.JArray{[focused,captured,values]}:
      do Result<&2,&2,String,CC.Packet>:
        +f:Bool <- boolean(focused)
        +c:Bool <- boolean(captured)
        +a:List<&2,CC.Action> <- action_array(values)
        Done{CC.Packet{a,f,c}}
    case _: Fail{"wire:packet-cardinality"}

def transfer_mode(value:J.Value) -> Result<&2,&2,String,Inv.TransferMode>:
  match value:
    case J.JNumber{"0"}: Done{Inv.TransferAny{}}
    case J.JNumber{"1"}: Done{Inv.TransferSplit{}}
    case J.JNumber{"2"}: Done{Inv.TransferMerge{}}
    case _: Fail{"wire:transfer-mode"}

def click_valid(value:I.Click) -> Bool:
  match value:
    case I.Pickup{button}: U32.is_lt(button,2)
    case _: True{}

def menu_click(value:J.Value) -> Result<&2,&2,String,I.Click>:
  match value:
    case J.JArray{[J.JNumber{"0"},button]}:
      do Result<&2,&2,String,I.Click>:
        +b:U32 <- uint(button)
        guard(U32.is_lt(b,2),"wire:pickup-button")
        Done{I.Pickup{b}}
    case J.JArray{[J.JNumber{"1"}]}: Done{I.QuickMove{}}
    case J.JArray{[J.JNumber{"2"},hotbar]}:
      do Result<&2,&2,String,I.Click>:
        index:U32 <- uint(hotbar)
        Done{I.Swap{index}}
    case J.JArray{[J.JNumber{"3"}]}: Done{I.Clone{}}
    case J.JArray{[J.JNumber{"4"},all]}:
      do Result<&2,&2,String,I.Click>:
        value:Bool <- boolean(all)
        Done{I.Throw{value}}
    case J.JArray{[J.JNumber{"5"},phase,button]}:
      do Result<&2,&2,String,I.Click>:
        p:U32 <- uint(phase)
        b:U32 <- uint(button)
        Done{I.QuickCraft{p,b}}
    case J.JArray{[J.JNumber{"6"}]}: Done{I.PickupAll{}}
    case _: Fail{"wire:menu-click-tag-or-cardinality"}

def acquire_component_count(key:Inv.ItemKey,count:U32) -> Bool:
  Inv.ItemKey{id,components} = key
  String.is_empty(components) || U32.is_le(count,1)

def acquire_valid(index:U32,+key:Inv.ItemKey,+count:U32) -> Bool:
  U32.is_lt(index,36) && I.structural_slot(Inv.InvStack{key,1}) && U32.is_le(count,99) && acquire_component_count(key,count)

def admitted_item_key(+key:Inv.ItemKey) -> Result<&2,&2,String,Inv.ItemKey>:
  do Result<&2,&2,String,Inv.ItemKey>:
    guard(I.structural_slot(Inv.InvStack{key,1}),"wire:item-key-components")
    Done{key}

def item_key(value:J.Value) -> Result<&2,&2,String,Inv.ItemKey>:
  match value:
    case J.JArray{[name,components]}:
      do Result<&2,&2,String,Inv.ItemKey>:
        id:String <- text(name)
        patch:String <- text(components)
        admitted_item_key(Inv.ItemKey{id,patch})
    case _: Fail{"wire:item-key-cardinality"}

def command_valid(command:Command) -> Bool:
  match command:
    case Frame{width,height}: WM.frame_valid(WM.frame(width,height))
    case FrameCatalog{width,height}: WM.frame_valid(WM.frame(width,height))
    case Input{CC.Packet{actions,focused,captured}}: WM.fits(CC.Action,actions,1024)
    case Release{}: True{}
    case Action{button}: U32.is_le(button,1)
    case Hotbar{index}: U32.is_lt(index,9)
    case Inventory{}: True{}
    case Transfer{source,destination,count,mode}: U32.is_lt(source,36) && U32.is_lt(destination,36)
    case Acquire{index,key,count}: acquire_valid(index,key,count)
    case MenuInspect{}: True{}
    case MenuOpen{}: True{}
    case MenuClose{}: True{}
    case MenuClick{index,click}: click_valid(click)
    case Select{index}: U32.is_lt(index,9)

def command(value:J.Value) -> Result<&2,&2,String,Command>:
  match value:
    case J.JArray{[J.JNumber{"0"},width,height]}:
      do Result<&2,&2,String,Command>:
        +w:U32 <- uint(width)
        +h:U32 <- uint(height)
        guard(WM.frame_valid(WM.frame(w,h)),"wire:frame-dimensions")
        Done{Frame{w,h}}
    case J.JArray{[J.JNumber{"1"},value]}:
      do Result<&2,&2,String,Command>:
        +p:CC.Packet <- packet(value)
        Done{Input{p}}
    case J.JArray{[J.JNumber{"2"}]}: Done{Release{}}
    case J.JArray{[J.JNumber{"3"},button]}:
      do Result<&2,&2,String,Command>:
        +value:U32 <- uint(button)
        guard(U32.is_le(value,1),"wire:interaction-button")
        Done{Action{value}}
    case J.JArray{[J.JNumber{"4"},index]}:
      do Result<&2,&2,String,Command>:
        +value:U32 <- uint(index)
        guard(U32.is_lt(value,9),"wire:hotbar-index")
        Done{Hotbar{value}}
    case J.JArray{[J.JNumber{"5"}]}: Done{Inventory{}}
    case J.JArray{[J.JNumber{"6"},source,destination,count,mode]}:
      do Result<&2,&2,String,Command>:
        +a:U32 <- uint(source)
        +b:U32 <- uint(destination)
        c:U32 <- uint(count)
        m:Inv.TransferMode <- transfer_mode(mode)
        guard(U32.is_lt(a,36) && U32.is_lt(b,36),"wire:transfer-main-slot")
        Done{Transfer{a,b,c,m}}
    case J.JArray{[J.JNumber{"7"},index,key,count]}:
      do Result<&2,&2,String,Command>:
        +i:U32 <- uint(index)
        +k:Inv.ItemKey <- item_key(key)
        +c:U32 <- uint(count)
        guard(acquire_valid(i,k,c),"wire:acquire-shape")
        Done{Acquire{i,k,c}}
    case J.JArray{[J.JNumber{"8"}]}: Done{MenuInspect{}}
    case J.JArray{[J.JNumber{"9"}]}: Done{MenuOpen{}}
    case J.JArray{[J.JNumber{"10"}]}: Done{MenuClose{}}
    case J.JArray{[J.JNumber{"11"},index,click]}:
      do Result<&2,&2,String,Command>:
        i:U32 <- uint(index)
        value:I.Click <- menu_click(click)
        Done{MenuClick{i,value}}
    case J.JArray{[J.JNumber{"12"},index]}:
      do Result<&2,&2,String,Command>:
        +i:U32 <- uint(index)
        guard(U32.is_lt(i,9),"wire:select-hotbar-index")
        Done{Select{i}}
    case J.JArray{[J.JNumber{"13"},width,height]}:
      do Result<&2,&2,String,Command>:
        +w:U32 <- uint(width)
        +h:U32 <- uint(height)
        guard(WM.frame_valid(WM.frame(w,h)),"wire:catalog-frame-dimensions")
        Done{FrameCatalog{w,h}}
    case _: Fail{"wire:command-tag-or-cardinality"}

def request_value(value:J.Value) -> Result<&2,&2,String,Request>:
  match value:
    case J.JArray{[J.JNumber{"1"},J.JNumber{"0"},capability]}:
      do Result<&2,&2,String,Request>:
        +cap:String <- text(capability)
        guard(nonempty_ascii(cap,256n),"wire:capability-shape")
        Done{Hello{cap}}
    case J.JArray{[J.JNumber{"1"},J.JNumber{"1"},epoch,sequence,body]}:
      do Result<&2,&2,String,Request>:
        +e:String <- text(epoch)
        +s:Nat <- natural(sequence)
        +c:Command <- command(body)
        guard(epoch_valid(e) && sequence_valid(s),"wire:epoch-sequence")
        Done{Call{e,s,c}}
    case _: Fail{"wire:request-version-tag-or-cardinality"}

def fault_valid(+epoch:String,+sequence:Nat,message:String) -> Bool:
  ((String.eq(epoch,"") && Nat.is_eq(sequence,0n)) || (epoch_valid(epoch) && sequence_valid(sequence))) && diagnostic_valid(message)

def admitted_inventory_slot(+slot:Inv.Slot) -> Result<&2,&2,String,Inv.Slot>:
  do Result<&2,&2,String,Inv.Slot>:
    guard(I.structural_slot(slot),"wire:inventory-slot-components-count")
    Done{slot}

def inventory_slot(value:J.Value) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case J.JArray{[J.JNumber{"0"}]}: Done{Inv.InvEmpty{}}
    case J.JArray{[J.JNumber{"1"},name,components,count]}:
      do Result<&2,&2,String,Inv.Slot>:
        id:String <- text(name)
        payload:String <- text(components)
        amount:U32 <- uint(count)
        admitted_inventory_slot(Inv.InvStack{Inv.ItemKey{id,payload},amount})
    case _: Fail{"wire:inventory-slot-tag-or-cardinality"}

def inventory_slots(left:Nat,values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match left values:
    case 0n Nil{}: Done{[]}
    case 1n+rest head <> tail:
      do Result<&2,&2,String,List<&2,Inv.Slot>>:
        own:Inv.Slot <- inventory_slot(head)
        remaining:List<&2,Inv.Slot> <- inventory_slots(rest,tail)
        Done{own <> remaining}
    case _ _: Fail{"wire:inventory-slots-cardinality"}

def inventory_array(value:J.Value) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match value:
    case J.JArray{slots}: inventory_slots(36n,slots)
    case _: Fail{"wire:expected-inventory-slots-array"}

def main_snapshot_valid(snapshot:I.Snapshot) -> Bool:
  I.Snapshot{selected,slots,abilities} = snapshot
  U32.is_lt(selected,9) && I.structural_slots(36n,slots)

def inventory_snapshot(value:J.Value) -> Result<&2,&2,String,I.Snapshot>:
  match value:
    case J.JArray{[selected,instabuild,maybuild,slots]}:
      do Result<&2,&2,String,I.Snapshot>:
        +index:U32 <- uint(selected)
        +creative:Bool <- boolean(instabuild)
        +build:Bool <- boolean(maybuild)
        +items:List<&2,Inv.Slot> <- inventory_array(slots)
        +snapshot:I.Snapshot = I.Snapshot{index,items,I.Abilities{creative,build}}
        guard(main_snapshot_valid(snapshot),"wire:inventory-snapshot")
        Done{snapshot}
    case _: Fail{"wire:inventory-snapshot-cardinality"}

def counted_slots(left:Nat,value:J.Value) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match value:
    case J.JArray{slots}: inventory_slots(left,slots)
    case _: Fail{"wire:expected-menu-slots-array"}

def menu_status(value:J.Value) -> Result<&2,&2,String,I.Status>:
  match value:
    case J.JArray{[invulnerable,mayfly,flying,walking_speed,flying_speed]}:
      do Result<&2,&2,String,I.Status>:
        a:Bool <- boolean(invulnerable)
        b:Bool <- boolean(mayfly)
        c:Bool <- boolean(flying)
        walk:U32 <- uint(walking_speed)
        fly:U32 <- uint(flying_speed)
        Done{I.Status{a,b,c,walk,fly}}
    case _: Fail{"wire:menu-status-cardinality"}

def menu_result(value:J.Value) -> Result<&2,&2,String,Maybe<&2,Inv.Slot>>:
  match value:
    case J.JArray{[J.JNumber{"0"}]}: Done{None{}}
    case J.JArray{[J.JNumber{"1"},slot]}:
      do Result<&2,&2,String,Maybe<&2,Inv.Slot>>:
        item:Inv.Slot <- inventory_slot(slot)
        Done{Some{item}}
    case _: Fail{"wire:menu-result-tag-or-cardinality"}

def menu_revision_valid(snapshot:I.MenuSnapshot) -> Bool:
  I.MenuSnapshot{saved,craft,carried,result,opened,revision} = snapshot
  Nat.is_le(revision,nat_max())

def menu_snapshot_valid(+snapshot:I.MenuSnapshot) -> Bool:
  I.menu_snapshot_valid(snapshot) && menu_revision_valid(snapshot)

def menu_snapshot(value:J.Value) -> Result<&2,&2,String,I.MenuSnapshot>:
  match value:
    case J.JArray{[main,equipment,status,craft,carried,result,opened,revision]}:
      do Result<&2,&2,String,I.MenuSnapshot>:
        saved:I.Snapshot <- inventory_snapshot(main)
        equipped:List<&2,Inv.Slot> <- counted_slots(7n,equipment)
        abilities:I.Status <- menu_status(status)
        temporary:List<&2,Inv.Slot> <- counted_slots(4n,craft)
        cursor:Inv.Slot <- inventory_slot(carried)
        output:Maybe<&2,Inv.Slot> <- menu_result(result)
        open:Bool <- boolean(opened)
        rev:Nat <- natural(revision)
        +snapshot:I.MenuSnapshot = I.MenuSnapshot{I.Persisted{saved,equipped,abilities},temporary,cursor,output,open,rev}
        guard(menu_snapshot_valid(snapshot),"wire:menu-snapshot")
        Done{snapshot}
    case _: Fail{"wire:menu-snapshot-cardinality"}

def catalog_address(value:J.Value) -> Result<&2,&2,String,Mesh.Address>:
  match value:
    case J.JNumber{"0"}: Done{Mesh.Clamp{}}
    case J.JNumber{"1"}: Done{Mesh.Repeat{}}
    case _: Fail{"wire:catalog-address"}

def catalog_cull(value:J.Value) -> Result<&2,&2,String,Mesh.Cull>:
  match value:
    case J.JNumber{"0"}: Done{Mesh.Back{}}
    case J.JNumber{"1"}: Done{Mesh.NoCull{}}
    case _: Fail{"wire:catalog-cull"}

def catalog_tints(values:List<&2,J.Value>,fuel:Nat) -> Result<&2,&2,String,List<&2,WM.Tint>>:
  match values fuel:
    case Nil{} _: Done{[]}
    case J.JArray{[index,color]} <> tail 1n+rest:
      do Result<&2,&2,String,List<&2,WM.Tint>>:
        i:U32 <- uint(index)
        c:U32 <- uint(color)
        remaining:List<&2,WM.Tint> <- catalog_tints(tail,rest)
        Done{WM.Tint{i,c} <> remaining}
    case _ _: Fail{"wire:catalog-tint-cardinality-or-budget"}

def catalog_appearance(value:J.Value) -> Result<&2,&2,String,WM.Appearance>:
  match value:
    case J.JArray{[J.JArray{tints},light,address,cull,nether,threshold]}:
      do Result<&2,&2,String,WM.Appearance>:
        colors:List<&2,WM.Tint> <- catalog_tints(tints,256n)
        l:U32 <- uint(light)
        a:Mesh.Address <- catalog_address(address)
        c:Mesh.Cull <- catalog_cull(cull)
        n:Bool <- boolean(nether)
        t:U32 <- uint(threshold)
        +appearance:WM.Appearance = WM.Appearance{colors,l,a,c,n,t}
        guard(WM.appearance_valid(appearance,256),"wire:catalog-appearance")
        Done{appearance}
    case _: Fail{"wire:catalog-appearance-cardinality"}

def catalog_cells(values:List<&2,J.Value>,fuel:Nat) -> Result<&2,&2,String,List<&2,GS.Cell>>:
  match values fuel:
    case Nil{} _: Done{[]}
    case J.JArray{[x,y,z,boundary,state,seed,appearance]} <> tail 1n+rest:
      do Result<&2,&2,String,List<&2,GS.Cell>>:
        a:U32 <- uint(x)
        b:U32 <- uint(y)
        c:U32 <- uint(z)
        edge:U32 <- uint(boundary)
        id:U32 <- uint(state)
        ticket:U32 <- uint(seed)
        surface:WM.Appearance <- catalog_appearance(appearance)
        remaining:List<&2,GS.Cell> <- catalog_cells(tail,rest)
        Done{GS.Cell{W.Cell{a,b,c,edge},id,ticket,surface} <> remaining}
    case _ _: Fail{"wire:catalog-cell-cardinality-or-budget"}

def catalog_sample_valid(+sample:GS.Sample) -> Bool:
  GS.Sample{registry,tick,revision,origin,camera,cells} = sample
  nonempty_ascii(registry,128n) && Nat.is_le(tick,nat_max()) &&
    Nat.is_le(revision,nat_max()) && GS.sample_valid(sample)

def catalog_sample(value:J.Value) -> Result<&2,&2,String,GS.Sample>:
  match value:
    case J.JArray{[identity,tick,revision,origin_value,camera_value,J.JArray{cells}]}:
      do Result<&2,&2,String,GS.Sample>:
        registry:String <- text(identity)
        t:Nat <- natural(tick)
        r:Nat <- natural(revision)
        o:M.Vec3 <- origin(origin_value)
        c:R.Camera <- floats3(camera_value)
        values:List<&2,GS.Cell> <- catalog_cells(cells,4096n)
        +sample:GS.Sample = GS.Sample{registry,t,r,o,c,values}
        guard(catalog_sample_valid(sample),"wire:catalog-sample")
        Done{sample}
    case _: Fail{"wire:catalog-sample-cardinality"}

def reply_value(value:J.Value) -> Result<&2,&2,String,Reply>:
  match value:
    case J.JArray{[J.JNumber{"1"},J.JNumber{"0"},epoch,sequence]}:
      do Result<&2,&2,String,Reply>:
        +e:String <- text(epoch)
        +s:Nat <- natural(sequence)
        guard(epoch_valid(e) && Nat.is_eq(s,0n),"wire:hello-correlation")
        Done{HelloAck{e,s}}
    case J.JArray{[J.JNumber{"1"},J.JNumber{"1"},epoch,sequence,body]}:
      do Result<&2,&2,String,Reply>:
        +e:String <- text(epoch)
        +s:Nat <- natural(sequence)
        +v:V.Sample <- sample(body)
        guard(epoch_valid(e) && sequence_valid(s),"wire:frame-correlation")
        Done{FrameReply{e,s,v}}
    case J.JArray{[J.JNumber{"1"},J.JNumber{"2"},epoch,sequence]}:
      do Result<&2,&2,String,Reply>:
        +e:String <- text(epoch)
        +s:Nat <- natural(sequence)
        guard(epoch_valid(e) && sequence_valid(s),"wire:ack-correlation")
        Done{Ack{e,s}}
    case J.JArray{[J.JNumber{"1"},J.JNumber{"3"},epoch,sequence,message]}:
      do Result<&2,&2,String,Reply>:
        +e:String <- text(epoch)
        +s:Nat <- natural(sequence)
        +m:String <- text(message)
        guard(fault_valid(e,s,m),"wire:fault-correlation-or-message")
        Done{Fault{e,s,m}}
    case J.JArray{[J.JNumber{"1"},J.JNumber{"4"},epoch,sequence,body]}:
      do Result<&2,&2,String,Reply>:
        +e:String <- text(epoch)
        +s:Nat <- natural(sequence)
        value:I.Snapshot <- inventory_snapshot(body)
        guard(epoch_valid(e) && sequence_valid(s),"wire:inventory-correlation")
        Done{InventoryReply{e,s,value}}
    case J.JArray{[J.JNumber{"1"},J.JNumber{"5"},epoch,sequence,changed,message]}:
      do Result<&2,&2,String,Reply>:
        +e:String <- text(epoch)
        +s:Nat <- natural(sequence)
        value:Bool <- boolean(changed)
        +m:String <- text(message)
        guard(epoch_valid(e) && sequence_valid(s) && diagnostic_valid(m),"wire:interaction-correlation-or-message")
        Done{ActionReply{e,s,value,m}}
    case J.JArray{[J.JNumber{"1"},J.JNumber{"6"},epoch,sequence,accepted,message,body]}:
      do Result<&2,&2,String,Reply>:
        +e:String <- text(epoch)
        +s:Nat <- natural(sequence)
        value:Bool <- boolean(accepted)
        +m:String <- text(message)
        snapshot:I.MenuSnapshot <- menu_snapshot(body)
        guard(epoch_valid(e) && sequence_valid(s) && diagnostic_valid(m),"wire:menu-correlation-or-message")
        Done{MenuReply{e,s,value,m,snapshot}}
    case J.JArray{[J.JNumber{"1"},J.JNumber{"7"},epoch,sequence,body]}:
      do Result<&2,&2,String,Reply>:
        +e:String <- text(epoch)
        +s:Nat <- natural(sequence)
        value:GS.Sample <- catalog_sample(body)
        guard(epoch_valid(e) && sequence_valid(s),"wire:catalog-frame-correlation")
        Done{CatalogFrameReply{e,s,value}}
    case _: Fail{"wire:reply-version-tag-or-cardinality"}

def decode_request(input:String) -> Result<&2,&2,String,Request>:
  do Result<&2,&2,String,Request>:
    +value:J.Value <- parse(input)
    guard(values_fit(16384n,[value]),"wire:value-budget")
    request_value(value)

def decode_reply(input:String) -> Result<&2,&2,String,Reply>:
  do Result<&2,&2,String,Reply>:
    +value:J.Value <- parse(input)
    guard(values_fit(16384n,[value]),"wire:value-budget")
    reply_value(value)

# All numeric fields encode exact integers. F32/F64 values are raw words.
def u(value:U32) -> J.Value: J.JNumber{U32.show(value)}
def n(value:Nat) -> J.Value: J.JNumber{Nat.show(value)}
def b(value:Bool) -> J.Value: J.JBool{value}
def s(value:String) -> J.Value: J.JString{value}

def origin_value(value:M.Vec3) -> J.Value:
  M.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}} = value
  J.JArray{[u(xh),u(xl),u(yh),u(yl),u(zh),u(zl)]}

def camera_value(value:R.Camera) -> J.Value:
  R.Camera{x,y,z,yaw,pitch} = value
  J.JArray{[u(F32.bits(x)),u(F32.bits(y)),u(F32.bits(z)),u(F32.bits(yaw)),u(F32.bits(pitch))]}

def palette_value(value:W.Palette) -> J.Value:
  W.Palette{air,stone,dirt,planks} = value
  J.JArray{[u(air),u(stone),u(dirt),u(planks)]}

def encode_rows(raw:List<&2,W.RawBlock>,blocks:List<&2,R.Block>,masks:List<&2,V.Visibility>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match raw blocks masks:
    case Nil{} Nil{} Nil{}: Done{[]}
    case W.RawBlock{W.Cell{x,y,z,boundary},state,material} <> tail
         R.Block{bx,by,bz,bs,bm} <> rest V.Visibility{cell,ms,visible} <> remaining:
      do Result<&2,&2,String,List<&2,J.Value>>:
        remaining:List<&2,J.Value> <- encode_rows(tail,rest,remaining)
        Done{J.JArray{[u(x),u(y),u(z),u(boundary),u(state),u(material),u(visible),u(F32.bits(bx)),u(F32.bits(by)),u(F32.bits(bz))]} <> remaining}
    case _ _ _: Fail{"wire:encode-cell-alignment"}

def sample_value(value:V.Sample) -> Result<&2,&2,String,J.Value>:
  V.Sample{R.Snapshot{tick,revision,blocks,camera},raw,masks,origin,palette,reads} = value
  do Result<&2,&2,String,J.Value>:
    cells:List<&2,J.Value> <- encode_rows(raw,blocks,masks)
    Done{J.JArray{[n(tick),n(revision),origin_value(origin),camera_value(camera),palette_value(palette),u(reads),J.JArray{cells}]}}

def catalog_address_value(value:Mesh.Address) -> J.Value:
  match value:
    case Mesh.Clamp{}: u(0)
    case Mesh.Repeat{}: u(1)

def catalog_cull_value(value:Mesh.Cull) -> J.Value:
  match value:
    case Mesh.Back{}: u(0)
    case Mesh.NoCull{}: u(1)

def catalog_tint_values(values:List<&2,WM.Tint>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case WM.Tint{index,color} <> tail:
      J.JArray{[u(index),u(color)]} <> catalog_tint_values(tail)

def catalog_appearance_value(value:WM.Appearance) -> J.Value:
  WM.Appearance{tints,light,address,cull,nether,threshold} = value
  J.JArray{[J.JArray{catalog_tint_values(tints)},u(light),catalog_address_value(address),
    catalog_cull_value(cull),b(nether),u(threshold)]}

def catalog_cell_values(values:List<&2,GS.Cell>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case GS.Cell{W.Cell{x,y,z,boundary},state,seed,appearance} <> tail:
      J.JArray{[u(x),u(y),u(z),u(boundary),u(state),u(seed),catalog_appearance_value(appearance)]} <>
        catalog_cell_values(tail)

def catalog_sample_value(value:GS.Sample) -> J.Value:
  GS.Sample{identity,tick,revision,origin,camera,cells} = value
  J.JArray{[s(identity),n(tick),n(revision),origin_value(origin),camera_value(camera),
    J.JArray{catalog_cell_values(cells)}]}

def event_value(value:Event) -> J.Value:
  match value:
    case Key{code,down}: J.JArray{[u(0),u(code),b(down)]}
    case Mouse{x,y,button,down}: J.JArray{[u(1),u(x),u(y),u(button),b(down)]}
    case Move{x,y}: J.JArray{[u(2),u(x),u(y)]}
    case Look{dx,dy}: J.JArray{[u(3),u(F32.bits(dx)),u(F32.bits(dy))]}
    case Scroll{x,y,dx,dy}: J.JArray{[u(4),u(x),u(y),u(F32.bits(dx)),u(F32.bits(dy))]}
    case Close{}: J.JArray{[u(5)]}

def action_value(value:CC.Action) -> J.Value:
  match value:
    case CC.Release{}: J.JArray{[u(0)]}
    case CC.PlatformEvent{event,captured}: J.JArray{[u(1),b(captured),event_value(event)]}

def action_values(values:List<&2,CC.Action>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> tail: action_value(head) <> action_values(tail)

def packet_value(value:CC.Packet) -> J.Value:
  CC.Packet{actions,focused,captured} = value
  J.JArray{[b(focused),b(captured),J.JArray{action_values(actions)}]}

def transfer_mode_value(mode:Inv.TransferMode) -> J.Value:
  match mode:
    case Inv.TransferAny{}: u(0)
    case Inv.TransferSplit{}: u(1)
    case Inv.TransferMerge{}: u(2)

def click_value(click:I.Click) -> J.Value:
  match click:
    case I.Pickup{button}: J.JArray{[u(0),u(button)]}
    case I.QuickMove{}: J.JArray{[u(1)]}
    case I.Swap{hotbar}: J.JArray{[u(2),u(hotbar)]}
    case I.Clone{}: J.JArray{[u(3)]}
    case I.Throw{all}: J.JArray{[u(4),b(all)]}
    case I.QuickCraft{phase,button}: J.JArray{[u(5),u(phase),u(button)]}
    case I.PickupAll{}: J.JArray{[u(6)]}

def command_value(value:Command) -> J.Value:
  match value:
    case Frame{width,height}: J.JArray{[u(0),u(width),u(height)]}
    case FrameCatalog{width,height}: J.JArray{[u(13),u(width),u(height)]}
    case Input{packet}: J.JArray{[u(1),packet_value(packet)]}
    case Release{}: J.JArray{[u(2)]}
    case Action{button}: J.JArray{[u(3),u(button)]}
    case Hotbar{index}: J.JArray{[u(4),u(index)]}
    case Inventory{}: J.JArray{[u(5)]}
    case Transfer{source,destination,count,mode}: J.JArray{[u(6),u(source),u(destination),u(count),transfer_mode_value(mode)]}
    case Acquire{index,Inv.ItemKey{name,components},count}: J.JArray{[u(7),u(index),J.JArray{[s(name),s(components)]},u(count)]}
    case MenuInspect{}: J.JArray{[u(8)]}
    case MenuOpen{}: J.JArray{[u(9)]}
    case MenuClose{}: J.JArray{[u(10)]}
    case MenuClick{index,click}: J.JArray{[u(11),u(index),click_value(click)]}
    case Select{index}: J.JArray{[u(12),u(index)]}

def request_valid(request:Request) -> Bool:
  match request:
    case Hello{capability}: nonempty_ascii(capability,256n)
    case Call{epoch,sequence,command}: epoch_valid(epoch) && sequence_valid(sequence) && command_valid(command)

def request_json(request:Request) -> J.Value:
  match request:
    case Hello{capability}: J.JArray{[u(1),u(0),s(capability)]}
    case Call{epoch,sequence,command}: J.JArray{[u(1),u(1),s(epoch),n(sequence),command_value(command)]}

def reply_valid(reply:Reply) -> Bool:
  match reply:
    case HelloAck{epoch,sequence}: epoch_valid(epoch) && Nat.is_eq(sequence,0n)
    case FrameReply{epoch,sequence,sample}: epoch_valid(epoch) && sequence_valid(sequence) && sample_valid(sample)
    case CatalogFrameReply{epoch,sequence,sample}: epoch_valid(epoch) && sequence_valid(sequence) && catalog_sample_valid(sample)
    case Ack{epoch,sequence}: epoch_valid(epoch) && sequence_valid(sequence)
    case Fault{epoch,sequence,message}: fault_valid(epoch,sequence,message)
    case InventoryReply{epoch,sequence,snapshot}: epoch_valid(epoch) && sequence_valid(sequence) && main_snapshot_valid(snapshot)
    case ActionReply{epoch,sequence,changed,message}: epoch_valid(epoch) && sequence_valid(sequence) && diagnostic_valid(message)
    case MenuReply{epoch,sequence,accepted,message,snapshot}: epoch_valid(epoch) && sequence_valid(sequence) && diagnostic_valid(message) && menu_snapshot_valid(snapshot)

def inventory_slot_value(value:Inv.Slot) -> J.Value:
  match value:
    case Inv.InvEmpty{}: J.JArray{[u(0)]}
    case Inv.InvStack{Inv.ItemKey{name,components},count}: J.JArray{[u(1),s(name),s(components),u(count)]}

def inventory_slot_values(values:List<&2,Inv.Slot>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> tail: inventory_slot_value(head) <> inventory_slot_values(tail)

def inventory_snapshot_value(value:I.Snapshot) -> J.Value:
  I.Snapshot{selected,slots,I.Abilities{instabuild,maybuild}} = value
  J.JArray{[u(selected),b(instabuild),b(maybuild),J.JArray{inventory_slot_values(slots)}]}

def menu_result_value(result:Maybe<&2,Inv.Slot>) -> J.Value:
  match result:
    case None{}: J.JArray{[u(0)]}
    case Some{slot}: J.JArray{[u(1),inventory_slot_value(slot)]}

def menu_status_value(status:I.Status) -> J.Value:
  I.Status{invulnerable,mayfly,flying,walk,fly} = status
  J.JArray{[b(invulnerable),b(mayfly),b(flying),u(walk),u(fly)]}

def menu_snapshot_value(snapshot:I.MenuSnapshot) -> J.Value:
  I.MenuSnapshot{I.Persisted{main,equipment,status},craft,carried,result,opened,revision} = snapshot
  J.JArray{[inventory_snapshot_value(main),J.JArray{inventory_slot_values(equipment)},menu_status_value(status),
    J.JArray{inventory_slot_values(craft)},inventory_slot_value(carried),menu_result_value(result),b(opened),n(revision)]}

def reply_json(reply:Reply) -> Result<&2,&2,String,J.Value>:
  match reply:
    case HelloAck{epoch,sequence}: Done{J.JArray{[u(1),u(0),s(epoch),n(sequence)]}}
    case FrameReply{epoch,sequence,sample}:
      do Result<&2,&2,String,J.Value>:
        value:J.Value <- sample_value(sample)
        Done{J.JArray{[u(1),u(1),s(epoch),n(sequence),value]}}
    case CatalogFrameReply{epoch,sequence,sample}:
      Done{J.JArray{[u(1),u(7),s(epoch),n(sequence),catalog_sample_value(sample)]}}
    case Ack{epoch,sequence}: Done{J.JArray{[u(1),u(2),s(epoch),n(sequence)]}}
    case Fault{epoch,sequence,message}: Done{J.JArray{[u(1),u(3),s(epoch),n(sequence),s(message)]}}
    case InventoryReply{epoch,sequence,snapshot}: Done{J.JArray{[u(1),u(4),s(epoch),n(sequence),inventory_snapshot_value(snapshot)]}}
    case ActionReply{epoch,sequence,changed,message}: Done{J.JArray{[u(1),u(5),s(epoch),n(sequence),b(changed),s(message)]}}
    case MenuReply{epoch,sequence,accepted,message,snapshot}: Done{J.JArray{[u(1),u(6),s(epoch),n(sequence),b(accepted),s(message),menu_snapshot_value(snapshot)]}}

def hex4(+word:U32) -> String:
  Char.show(J.hex_char(U32.and(U32.shrn(word,12n),15))) ++
    Char.show(J.hex_char(U32.and(U32.shrn(word,8n),15))) ++
    Char.show(J.hex_char(U32.and(U32.shrn(word,4n),15))) ++ Char.show(J.hex_char(U32.and(word,15)))

def escape_scalar_checked(+code:U32,small:Bool) -> String:
  match small:
    case True{}: J.escape_char(code)
    case False{}:
      J.choose(String,"\\u" ++ hex4(code),"\\u" ++ hex4(U32.add(55296,U32.div(U32.sub(code,65536),1024))) ++
        "\\u" ++ hex4(U32.add(56320,U32.mod(U32.sub(code,65536),1024))),U32.is_le(code,65535))

def escape_scalar(+code:U32) -> String:
  escape_scalar_checked(code,U32.is_lt(code,128))

def quote_ascii(text:String) -> String:
  match text:
    case SNil{}: "\""
    case SCon{c,tail}: escape_scalar(Char.to_u32(c)) ++ quote_ascii(tail)

# DTO output has no objects. This encoder emits only ASCII strings/numbers.
def json_ascii(value:J.Value,continuation:Bool) -> String:
  match value:
    case J.JString{text}: "\"" ++ quote_ascii(text)
    case J.JArray{Nil{}}: J.choose(String,"]","[]",continuation)
    case J.JArray{head <> tail}:
      J.choose(String,",","[",continuation) ++ json_ascii(head,False{}) ++ json_ascii(J.JArray{tail},True{})
    case J.JObject{members}: "invalid-wire-object"
    case _: J.encode(value)

def encoded_text(+output:String) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    guard(J.within(65536n,output) && ascii(output),"wire:encoded-transport-parser-budget")
    Done{output}

def encode_value(+value:J.Value) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    guard(values_fit(16384n,[value]),"wire:encoded-value-budget")
    encoded_text(json_ascii(value,False{}))

def request_encode(valid:Bool,request:Request) -> Result<&2,&2,String,String>:
  match valid:
    case False{}: Fail{"wire:invalid-request"}
    case True{}: encode_value(request_json(request))

def reply_encode(valid:Bool,reply:Reply) -> Result<&2,&2,String,String>:
  match valid:
    case False{}: Fail{"wire:invalid-reply"}
    case True{}:
      do Result<&2,&2,String,String>:
        value:J.Value <- reply_json(reply)
        encode_value(value)

def encode_request(+request:Request) -> Result<&2,&2,String,String>:
  request_encode(request_valid(request),request)

def encode_reply(+reply:Reply) -> Result<&2,&2,String,String>:
  reply_encode(reply_valid(reply),reply)

# These checks match an actor-owned/client-owned expectation; they do not
# authorize a lease or advance its expected sequence on their own.
def correlation(+epoch:String,+sequence:Nat,reply:Reply) -> Bool:
  match reply:
    case HelloAck{other,number}: String.eq(epoch,other) && Nat.is_eq(sequence,number)
    case FrameReply{other,number,sample}: String.eq(epoch,other) && Nat.is_eq(sequence,number)
    case CatalogFrameReply{other,number,sample}: String.eq(epoch,other) && Nat.is_eq(sequence,number)
    case Ack{other,number}: String.eq(epoch,other) && Nat.is_eq(sequence,number)
    case Fault{other,number,message}: String.eq(epoch,other) && Nat.is_eq(sequence,number)
    case InventoryReply{other,number,snapshot}: String.eq(epoch,other) && Nat.is_eq(sequence,number)
    case ActionReply{other,number,changed,message}: String.eq(epoch,other) && Nat.is_eq(sequence,number)
    case MenuReply{other,number,accepted,message,snapshot}: String.eq(epoch,other) && Nat.is_eq(sequence,number)

law raw_look_preserves_signed_zero_and_nan_payload:
  {event(J.JArray{[u(3),u(2147483648),u(2143289345)]}) ==
    Done{Look{float_bits(2147483648),float_bits(2143289345)}} : Result<&2,&2,String,Event>}

def raw_look_preserves_signed_zero_and_nan_payload():
  {==}

law version_mismatch_refuses_request:
  {request_value(J.JArray{[u(2),u(0),s("token")]}) ==
    Fail{"wire:request-version-tag-or-cardinality"} : Result<&2,&2,String,Request>}

def version_mismatch_refuses_request():
  {==}

law extra_release_fields_are_refused:
  {command(J.JArray{[u(2),u(0)]}) == Fail{"wire:command-tag-or-cardinality"} : Result<&2,&2,String,Command>}

def extra_release_fields_are_refused():
  {==}

law sequence_above_native_word_is_refused:
  {natural(J.JNumber{"281474976710656"}) == Fail{"wire:Nat48"} : Result<&2,&2,String,Nat>}

def sequence_above_native_word_is_refused():
  {==}

law packet_roundtrip_keeps_order_capture_and_raw_words:
  {packet(packet_value(CC.Packet{[CC.Release{},CC.PlatformEvent{Key{87,True{}},True{}},
      CC.PlatformEvent{Move{4294967295,2147483648},False{}}],True{},False{}})) ==
    Done{CC.Packet{[CC.Release{},CC.PlatformEvent{Key{87,True{}},True{}},
      CC.PlatformEvent{Move{4294967295,2147483648},False{}}],True{},False{}}} : Result<&2,&2,String,CC.Packet>}

def packet_roundtrip_keeps_order_capture_and_raw_words():
  {==}
