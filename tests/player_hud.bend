import Base
import ../src/player_hud.bend as H
import ../src/client_controls.bend as C
import ../src/resource_client_wire.bend as W
import ../src/client_render.bend as R
import ../src/png.bend as P
import ../src/inventory.bend as I
import ../src/block_resources.bend as Resources
import ../src/block_bake.bend as Bake

# These checks use synthetic inputs and no Window, socket or saved-world owner.
# OS-input and pinned-vanilla HUD acceptance remain separate evidence.
def require(ok:Bool,message:String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,"HUD: " ++ message)

def words_equal(a:List<&2,U32>,b:List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case head <> rest wanted <> tail: U32.is_eq(head,wanted) && words_equal(rest,tail)
    case _ _: False{}

def command_words(commands:List<&2,W.Command>) -> List<&2,U32>:
  match commands:
    case Nil{}: []
    case W.Hotbar{index} <> rest: index <> command_words(rest)
    case W.Action{button} <> rest: U32.add(100,button) <> command_words(rest)
    case other <> rest: 999 <> command_words(rest)

def key(code:U32,down:Bool,captured:Bool) -> C.Action:
  C.PlatformEvent{Key{code,down},captured}

def mouse(button:U32,captured:Bool) -> C.Action:
  C.PlatformEvent{Mouse{0,0,button,True{}},captured}

def packet_words(actions:List<&2,C.Action>,focused:Bool,captured:Bool,previous:Bool) -> List<&2,U32>:
  command_words(H.packet_commands(C.Packet{actions,focused,captured},previous))

def layout_matches(value:H.Layout,left:U32,top:U32,slot:U32,width:U32,height:U32,visible:Bool) -> Bool:
  H.Layout{fw,fh,actual_left,actual_top,actual_slot,actual_width,actual_height,actual_visible} = value
  U32.is_eq(actual_left,left) && U32.is_eq(actual_top,top) && U32.is_eq(actual_slot,slot) &&
    U32.is_eq(actual_width,width) && U32.is_eq(actual_height,height) && Bool.not(Bool.xor(actual_visible,visible))

def color_texture(color:U32) -> R.Texture:
  R.Texture{1,1,1,Pix{color}}

def sprite(id:String,index:U32) -> Resources.SpriteInfo:
  Resources.SpriteInfo{id,index,1,1,Bake.Solid{},None{}}

def icon_color(icon:Maybe<&2,R.Texture>) -> U32:
  match icon:
    case None{}: 0
    case Some{R.Texture{width,height,side,Pix{color}}}: color
    case _: 1

def stack_count(slot:H.DrawSlot) -> U32:
  match slot:
    case H.Empty{}: 0
    case H.Stack{count,icon}: count

def view_matches(view:H.View) -> Bool:
  H.View{selected,+slots} = view
  U32.is_eq(selected,8) && Nat.is_eq(List.length(&2,H.DrawSlot,slots),9n) &&
    U32.is_eq(stack_count(H.at_slot(slots,0n)),64) && U32.is_eq(stack_count(H.at_slot(slots,8n)),2)

def leaves(image:Image) -> U32:
  match image:
    case Pix{color}: 1
    case Qua{tl,tr,bl,br}: U32.add(U32.add(leaves(tl),leaves(tr)),U32.add(leaves(bl),leaves(br)))

def pixel(+image:Image,+width:U32,+height:U32,x:U32,y:U32) -> U32:
  +depth = P.array_depth(13n,U32.max(width,height),1)
  R.pixel_at(depth,image,x,y,U32.shln(1,depth))

def result_good(value:Result<&2,&2,String,Unit>) -> Bool:
  match value:
    case Done{unit}: True{}
    case Fail{message}: False{}

# Expected rows are literal binary raster fixtures, independent of H.glyph.
def raster_row(fuel:Nat,+value:U32,+width:U32,+x:U32,+y:U32,+bits:U32) -> Bool:
  match fuel:
    case 0n: True{}
    case 1n+rest:
      Bool.not(Bool.xor(H.number_pixel(value,x,y),U32.is_ne(
        U32.and(U32.shrn(bits,U32.to_nat(U32.sub(U32.sub(width,1),x))),1),0))) &&
        raster_row(rest,value,width,U32.add(x,1),y,bits)

def raster_rows(rows:List<&2,U32>,+value:U32,+width:U32,+y:U32) -> Bool:
  match rows:
    case Nil{}: True{}
    case row <> rest: raster_row(U32.to_nat(width),value,width,0,y,row) &&
      Bool.not(H.number_pixel(value,width,y)) && raster_rows(rest,value,width,U32.add(y,1))

def checks_input() -> IO(Unit):
  do IO<Unit>:
    require(words_equal(packet_words([key(48,True{},True{}),key(49,True{},True{}),key(57,True{},True{}),
      key(58,True{},True{}),key(50,False{},True{}),mouse(2,True{}),mouse(0,True{}),mouse(1,True{})],
      True{},True{},True{}),[0,8,100,101]),"digit range, button range, key-up or event order")
    require(words_equal(packet_words([mouse(0,True{}),mouse(1,True{}),key(53,True{},True{})],
      True{},True{},False{}),[101,4]),"first capture click was not consumed")
    require(words_equal(packet_words([mouse(0,True{}),key(49,True{},True{})],
      False{},True{},True{}),[]),"final focus loss admitted commands")
    require(words_equal(packet_words([mouse(0,True{}),C.Release{}],
      True{},False{},True{}),[]),"final capture loss admitted earlier commands")
    require(words_equal(packet_words([C.Release{},mouse(0,True{}),mouse(0,True{})],
      True{},True{},True{}),[100]),"release and recapture admitted the capture click")
    require(words_equal(packet_words([mouse(1,False{}),key(49,True{},False{})],
      True{},True{},False{}),[]),"uncaptured events admitted commands")

def checks_replies() -> IO(Unit):
  +ack = {W.Ack{"hud-test",1n}:W.Reply}
  +action = {W.ActionReply{"hud-test",1n,False{},"no eligible target"}:W.Reply}
  do IO<Unit>:
    require(result_good(H.command_result(W.Action{0},Done{action})),"unchanged action is a successful reply")
    require(Bool.not(result_good(H.command_result(W.Action{0},Done{ack}))),"Action accepted Ack")
    require(result_good(H.command_result(W.Hotbar{8},Done{ack})),"Hotbar rejected Ack")
    require(Bool.not(result_good(H.command_result(W.Hotbar{8},Done{action}))),"Hotbar accepted ActionReply")
    require(Bool.not(result_good(H.command_result(W.Action{1},Fail{"transport failure"}))),"transport failure admitted")

def checks_pixels() -> IO(Unit):
  +texture = color_texture(4281558732)
  +view = {H.View{4,[H.Stack{64,Some{texture}},H.Empty{},H.Empty{},H.Empty{},H.Stack{2,Some{texture}},
    H.Empty{},H.Empty{},H.Empty{},H.Empty{}]}:H.View}
  +image = H.draw(Pix{4279383126},view,128,128)
  do IO<Unit>:
    require(U32.is_eq(pixel(image,128,128,0,0),4279383126),"overlay changed an untouched world pixel")
    require(U32.is_eq(pixel(image,128,128,64,64),4293774249),"crosshair did not invert RGB")
    require(U32.is_eq(pixel(image,128,128,67,64),4293774249) &&
      U32.is_eq(pixel(image,128,128,68,64),4279383126),"crosshair extent")
    require(U32.is_eq(pixel(image,128,128,57,112),4294967295),"selected fifth hotbar boundary")
    require(U32.is_eq(pixel(image,128,128,7,114),4281558732),"resource icon did not draw")
    require(U32.is_lt(leaves(image),4096),"sparse overlay expanded the whole 128 square")
    require(U32.is_eq(H.stack_pixel(H.Stack{2,None{}},16,16,20,4278190080),4278190080),
      "digit2 interior zero was changed")
    require(U32.is_eq(H.stack_pixel(H.Stack{2,None{}},17,17,20,4278190080),4294967295),
      "digit2 bottom row was clipped")
    require(U32.is_eq(pixel(image,128,128,67,122),4294967295) &&
      U32.is_eq(pixel(image,128,128,67,121),4278190080),"selected border clipped count glyph or shadow")
    require(U32.is_eq(H.icon_pixel(Some{color_texture(16711680)},0,0,1,4279383126),4279383126),
      "transparent icon erased slot background")
    require(U32.is_eq(H.icon_pixel(Some{color_texture(2164195328)},0,0,1,4278190335),4286578815),
      "half-alpha icon did not composite")

def checks_icons(+icons:H.Icons) -> IO(Unit):
  H.Icons{+stone,+dirt,+planks} = icons
  +slot = {I.InvStack{I.ItemKey{"minecraft:stone",""},64}:I.Slot}
  +last = {I.InvStack{I.ItemKey{"minecraft:dirt",""},2}:I.Slot}
  do IO<Unit>:
    require(layout_matches(H.layout(128,128),4,111,13,119,15,True{}),"128 HUD layout")
    require(layout_matches(H.layout(320,180),69,156,20,182,22,True{}),"320x180 HUD layout")
    require(layout_matches(H.layout(40,24),5,17,3,29,5,True{}),"narrow HUD layout")
    require(layout_matches(H.layout(0,0),0,0,1,11,3,False{}),"tiny HUD layout underflow")
    require(U32.is_eq(icon_color(stone),4294901760) && U32.is_eq(icon_color(dirt),4278255360) &&
      U32.is_eq(icon_color(planks),4278190335),"icons ignored resource identifiers")
    require(view_matches(H.prepare(8,[slot,I.InvEmpty{},I.InvEmpty{},I.InvEmpty{},I.InvEmpty{},I.InvEmpty{},
      I.InvEmpty{},I.InvEmpty{},last,slot],icons)),"saved selection/count or nine-slot limit")
    require(U32.is_eq(H.stack_pixel(H.Stack{64,None{}},2,2,3,4279383126),4279383126),"narrow icon subtraction wrapped")
    require(raster_rows([39,33,39,36,39],12,7,0) && raster_rows([117,69,119,81,113],64,7,0),
      "literal decimal raster fixture or separator mismatch")
    require(U32.is_eq(H.number_width(4294967295),39) && Bool.not(H.number_pixel(64,0,5)),
      "decimal extent mismatch")

def checks_data() -> IO(Unit):
  checks_icons(H.icons([color_texture(4278255360),color_texture(4294901760),color_texture(4278190335)],
    [sprite("minecraft:block/dirt",0),sprite("minecraft:block/stone",1),sprite("minecraft:block/oak_planks",2)]))

def checks_presentation() -> IO(Unit):
  +texture = color_texture(4281558732)
  +logical = H.draw(Pix{4279383126},H.View{4,[H.Stack{64,Some{texture}},H.Empty{},H.Empty{},H.Empty{},
    H.Stack{2,Some{texture}},H.Empty{},H.Empty{},H.Empty{},H.Empty{}]},320,180)
  +image = H.presentation(logical,True{},320,180)
  +tiny = H.project(Qua{Pix{4294901760},Pix{4278255360},Pix{4278190335},Pix{4294967295}},4,2,8,4)
  do IO<Unit>:
    require(U32.is_eq(pixel(image,960,540,0,0),4279383126) &&
      U32.is_eq(pixel(image,960,540,959,539),4279383126),"human drawable edge mapping left black padding")
    require(U32.is_eq(pixel(image,960,540,480,270),4293774249) &&
      U32.is_eq(pixel(image,960,540,491,270),4293774249) &&
      U32.is_eq(pixel(image,960,540,492,270),4279383126),"threefold human crosshair mapping")
    require(U32.is_eq(pixel(image,960,540,450,471),4294967295) &&
      U32.is_eq(pixel(image,960,540,216,477),4281558732),"human hotbar and resource icon mapping")
    require(U32.is_eq(pixel(image,960,540,750,530),4283782485) &&
      U32.is_eq(pixel(image,960,540,753,530),4279383126),"human hotbar edge mapping")
    require(U32.is_eq(pixel(image,960,540,960,0),0) && U32.is_eq(pixel(image,960,540,0,540),0),
      "projection wrote outside drawable extent")
    require(U32.is_eq(pixel(tiny,8,4,3,3),4294901760) &&
      U32.is_eq(pixel(tiny,8,4,4,3),4278255360) && U32.is_eq(pixel(tiny,8,4,7,3),4278255360) &&
      U32.is_eq(pixel(tiny,8,4,0,4),0),"rectangular projection source or padding extent")
    require(U32.is_eq(leaves(H.project(Pix{4279383126},4,2,8,4)),4),"projection failed to retain constant regions")
    require(U32.is_eq(pixel(H.presentation(logical,False{},320,180),320,180,160,90),4293774249),
      "hidden path changed logical pixels")

def run() -> IO(Unit):
  do IO<Unit>:
    checks_input()
    checks_replies()
    checks_data()
    checks_pixels()
    checks_presentation()
    IO.print("PASS player HUD: saved values, resource identifiers, responsive sparse pixels, capture transitions, strict reply types")

def main() -> IO(Unit):
  run()
