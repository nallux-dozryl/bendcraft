import Base
import ./client_render.bend as R
import ./mesh_render.bend as Mesh
import ./png.bend as P
import ./block_resources.bend as BR
import ./inventory.bend as Inv
import ./client_controls.bend as CC
import ./resource_client_wire.bend as Wire
import ./player_presentation.bend as Presentation

# Presentation-only values. The caller supplies a snapshot from the same saved
# player authority as the world frame. No stack or selection is synthesized.
type Icons is Data:
  Icons{stone:Maybe<&2,R.Texture>,dirt:Maybe<&2,R.Texture>,planks:Maybe<&2,R.Texture>}
type DrawSlot is Data:
  Empty{}
  Stack{count:U32,icon:Maybe<&2,R.Texture>}
type View is Data:
  View{selected:U32,slots:List<&2,DrawSlot>}
type Layout is Data:
  Layout{width:U32,height:U32,left:U32,top:U32,slot:U32,bar_width:U32,bar_height:U32,visible:Bool}

def sprite(textures:List<&2,R.Texture>,sprites:List<&2,BR.SpriteInfo>,+wanted:String) -> Maybe<&2,R.Texture>:
  match textures sprites:
    case head <> tail BR.SpriteInfo{id,slot,width,height,layer,metadata} <> remaining:
      P.choose(Maybe<&2,R.Texture>,Some{head},sprite(tail,remaining,wanted),String.eq(id,wanted))
    case _ _: None{}

def icons(+textures:List<&2,R.Texture>,+sprites:List<&2,BR.SpriteInfo>) -> Icons:
  Icons{sprite(textures,sprites,"minecraft:block/stone"),
    sprite(textures,sprites,"minecraft:block/dirt"),
    sprite(textures,sprites,"minecraft:block/oak_planks")}

def item_icon(id:String,icons:Icons) -> Maybe<&2,R.Texture>:
  match id icons:
    case "minecraft:stone" Icons{stone,dirt,planks}: stone
    case "minecraft:dirt" Icons{stone,dirt,planks}: dirt
    case "minecraft:oak_planks" Icons{stone,dirt,planks}: planks
    case _ _: None{}

def draw_slot(slot:Inv.Slot,icons:Icons) -> DrawSlot:
  match slot:
    case Inv.InvEmpty{}: Empty{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}: Stack{count,item_icon(id,icons)}

def prepare_slots(fuel:Nat,slots:List<&2,Inv.Slot>,+icons:Icons) -> List<&2,DrawSlot>:
  match fuel slots:
    case 0n _: []
    case _ Nil{}: []
    case 1n+rest head <> tail: draw_slot(head,icons) <> prepare_slots(rest,tail,icons)

def prepare(selected:U32,slots:List<&2,Inv.Slot>,icons:Icons) -> View:
  View{selected,prepare_slots(9n,slots,icons)}

def layout(+width:U32,+height:U32) -> Layout:
  +slot = U32.max(1,U32.min(20,U32.div(U32.sub(U32.max(width,10),10),9)))
  +bar_width = U32.add(U32.mul(slot,9),2)
  +bar_height = U32.add(slot,2)
  Layout{width,height,U32.div(U32.sub(U32.max(width,bar_width),bar_width),2),
    U32.sub(U32.max(height,U32.add(bar_height,2)),U32.add(bar_height,2)),
    slot,bar_width,bar_height,U32.is_ge(width,40) && U32.is_ge(height,24)}

def inside(+x:U32,+y:U32,+left:U32,+top:U32,width:U32,height:U32) -> Bool:
  U32.is_ge(x,left) && U32.is_ge(y,top) &&
    U32.is_lt(x,U32.add(left,width)) && U32.is_lt(y,U32.add(top,height))

def overlaps(+x:U32,+y:U32,+side:U32,+left:U32,+top:U32,width:U32,height:U32) -> Bool:
  U32.is_lt(x,U32.add(left,width)) && U32.is_lt(y,U32.add(top,height)) &&
    U32.is_gt(U32.add(x,side),left) && U32.is_gt(U32.add(y,side),top)

def distance(+a:U32,+b:U32) -> U32:
  U32.sub(U32.max(a,b),U32.min(a,b))

def crosshair(+x:U32,+y:U32,+width:U32,+height:U32) -> Bool:
  +cx = U32.div(width,2)
  +cy = U32.div(height,2)
  (U32.is_eq(x,cx) && U32.is_le(distance(y,cy),3)) ||
    (U32.is_eq(y,cy) && U32.is_le(distance(x,cx),3))

# Three-by-five decimal glyphs, packed as five 3-bit rows. Counts remain exact;
# zero/one are omitted in the same way as an ordinary Minecraft stack overlay.
def glyph(digit:U32) -> U32:
  match digit:
    case 0: 31599
    case 1: 9362
    case 2: 29671
    case 3: 29647
    case 4: 23497
    case 5: 31183
    case 6: 31215
    case 7: 29257
    case 8: 31727
    case 9: 31695
    case _: 29314

def glyph_pixel(digit:U32,+x:U32,+y:U32) -> Bool:
  U32.is_lt(x,3) && U32.is_lt(y,5) &&
    U32.is_ne(U32.and(U32.shrn(glyph(digit),U32.to_nat(U32.add(U32.mul(U32.sub(4,y),3),U32.sub(2,x)))),1),0)

def number_width_go(fuel:Nat,+value:U32) -> U32:
  match fuel:
    case 0n: 3
    case 1n+rest: P.choose(U32,3,U32.add(4,number_width_go(rest,U32.div(value,10))),U32.is_lt(value,10))

def number_width(value:U32) -> U32:
  number_width_go(9n,value)

def number_pixel(+value:U32,+x:U32,+y:U32) -> Bool:
  +width = number_width(value)
  +from_right = U32.sub(U32.sub(width,1),U32.min(x,U32.sub(width,1)))
  +digit_index = U32.div(from_right,4)
  +divisor = U32.pow(10,U32.to_nat(digit_index))
  U32.is_lt(x,width) && U32.is_lt(y,5) && Bool.not(U32.is_eq(U32.mod(from_right,4),3)) &&
    glyph_pixel(U32.mod(U32.div(value,divisor),10),U32.sub(2,U32.mod(from_right,4)),y)

def at_slot(slots:List<&2,DrawSlot>,index:Nat) -> DrawSlot:
  match slots index:
    case head <> tail 0n: head
    case head <> tail 1n+rest: at_slot(tail,rest)
    case Nil{} _: Empty{}

def darken(+color:U32) -> U32:
  P.argb(255,U32.div(U32.and(U32.shrn(color,16n),255),3),
    U32.div(U32.and(U32.shrn(color,8n),255),3),U32.div(U32.and(color,255),3))

def icon_pixel(icon:Maybe<&2,R.Texture>,+x:U32,+y:U32,+size:U32,background:U32) -> U32:
  match icon:
    case None{}: P.choose(U32,4294967295,background,glyph_pixel(10,U32.div(x,U32.max(1,U32.div(size,4))),U32.div(y,U32.max(1,U32.div(size,6)))))
    case Some{texture}:
      Mesh.blend(R.texel(texture,F32.div(F32.from_nat(U32.to_nat(x)),F32.from_nat(U32.to_nat(size))),
        F32.div(F32.from_nat(U32.to_nat(y)),F32.from_nat(U32.to_nat(size)))),background)

def stack_pixel(slot:DrawSlot,+x:U32,+y:U32,+size:U32,+background:U32) -> U32:
  match slot:
    case Empty{}: background
    case Stack{+count,icon}:
      +icon_size = U32.max(1,U32.sub(U32.max(size,4),4))
      +count_left = U32.sub(U32.max(size,U32.add(number_width(count),2)),U32.add(number_width(count),2))
      +count_top = U32.sub(U32.max(size,7),7)
      +count_visible = U32.is_gt(count,1) && U32.is_ge(size,11)
      P.choose(U32,4294967295,
        P.choose(U32,4278190080,
          P.choose(U32,icon_pixel(icon,U32.sub(x,2),U32.sub(y,2),icon_size,background),background,
            U32.is_ge(size,5) && inside(x,y,2,2,icon_size,icon_size)),
          count_visible && inside(x,y,U32.add(count_left,1),U32.add(count_top,1),number_width(count),5) &&
            number_pixel(count,U32.sub(x,U32.add(count_left,1)),U32.sub(y,U32.add(count_top,1)))),
        count_visible && inside(x,y,count_left,count_top,number_width(count),5) &&
          number_pixel(count,U32.sub(x,count_left),U32.sub(y,count_top)))

def bar_pixel(+view:View,+layout:Layout,+x:U32,+y:U32,+world:U32) -> U32:
  View{selected,slots} = view
  Layout{width,height,left,top,+size,+bw,+bh,visible} = layout
  +local_x = U32.sub(x,left)
  +local_y = U32.sub(y,top)
  +index = U32.min(8,U32.div(U32.sub(local_x,1),size))
  +sx = U32.mod(U32.sub(local_x,1),size)
  +sy = U32.sub(local_y,1)
  +edge = U32.is_eq(local_x,0) || U32.is_eq(local_y,0) || U32.is_eq(local_x,U32.sub(bw,1)) || U32.is_eq(local_y,U32.sub(bh,1))
  +selected_edge = U32.is_eq(index,selected) && (U32.is_eq(sx,0) || U32.is_eq(sx,U32.sub(size,1)) || U32.is_eq(sy,0) || U32.is_eq(sy,U32.sub(size,1)))
  +divider = U32.is_eq(sx,0) || U32.is_eq(sy,0) || U32.is_eq(sy,U32.sub(size,1))
  P.choose(U32,4283782485,P.choose(U32,4294967295,
    P.choose(U32,4283782485,stack_pixel(at_slot(slots,U32.to_nat(index)),sx,sy,size,darken(world)),divider),selected_edge),edge)

def pixel(+view:View,+layout:Layout,+x:U32,+y:U32,+world:U32) -> U32:
  Layout{+width,+height,+left,+top,slot,+bw,+bh,+visible} = layout
  P.choose(U32,U32.or(4278190080,U32.xor(U32.and(world,16777215),16777215)),
    P.choose(U32,bar_pixel(view,layout,x,y,world),world,visible && inside(x,y,left,top,bw,bh)),
    crosshair(x,y,width,height))

def touched(+layout:Layout,+x:U32,+y:U32,+side:U32) -> Bool:
  Layout{+width,+height,left,top,slot,bw,bh,visible} = layout
  overlaps(x,y,side,U32.sub(U32.max(U32.div(width,2),3),3),U32.sub(U32.max(U32.div(height,2),3),3),7,7) ||
    (visible && overlaps(x,y,side,left,top,bw,bh))

# This descends only into branches intersecting the HUD. World pixels outside
# those rectangles return their original Image subtree without a full readback.
def overlay(fuel:Nat,image:Image,+view:View,+layout:Layout,+x:U32,+y:U32,+side:U32,active:Bool) -> Image:
  match fuel image active:
    case _ _ False{}: image
    case 0n Pix{color} True{}: Pix{pixel(view,layout,x,y,color)}
    case 0n Qua{tl,tr,bl,br} True{}: Pix{pixel(view,layout,x,y,R.pixel_at(0n,Qua{tl,tr,bl,br},0,0,1))}
    case 1n+ +rest Pix{+color} True{}:
      +half = U32.div(side,2)
      Qua{overlay(rest,Pix{color},view,layout,x,y,half,touched(layout,x,y,half)),
        overlay(rest,Pix{color},view,layout,U32.add(x,half),y,half,touched(layout,U32.add(x,half),y,half)),
        overlay(rest,Pix{color},view,layout,x,U32.add(y,half),half,touched(layout,x,U32.add(y,half),half)),
        overlay(rest,Pix{color},view,layout,U32.add(x,half),U32.add(y,half),half,touched(layout,U32.add(x,half),U32.add(y,half),half))}
    case 1n+ +rest Qua{tl,tr,bl,br} True{}:
      +half = U32.div(side,2)
      Qua{overlay(rest,tl,view,layout,x,y,half,touched(layout,x,y,half)),
        overlay(rest,tr,view,layout,U32.add(x,half),y,half,touched(layout,U32.add(x,half),y,half)),
        overlay(rest,bl,view,layout,x,U32.add(y,half),half,touched(layout,x,U32.add(y,half),half)),
        overlay(rest,br,view,layout,U32.add(x,half),U32.add(y,half),half,touched(layout,U32.add(x,half),U32.add(y,half),half))}

def draw(image:Image,view:View,+width:U32,+height:U32) -> Image:
  +depth = P.array_depth(13n,U32.max(width,height),1)
  overlay(depth,image,view,layout(width,height),0,0,U32.shln(1,depth),True{})

def native_pixel(view:View,layout:Layout,viewport:Presentation.Viewport,+x:U32,+y:U32,+world:U32) -> U32:
  Presentation.Viewport{+width,+height,+native_width,+native_height} = viewport
  P.choose(U32,pixel(view,layout,Presentation.coordinate(x,native_width,width),
    Presentation.coordinate(y,native_height,height),world),world,U32.is_lt(x,native_width) && U32.is_lt(y,native_height))

def native_touched(layout:Layout,viewport:Presentation.Viewport,+x:U32,+y:U32,+side:U32) -> Bool:
  Presentation.Viewport{+width,+height,+native_width,+native_height} = viewport
  +left = Presentation.coordinate(x,native_width,width)
  +top = Presentation.coordinate(y,native_height,height)
  +right = Presentation.coordinate(U32.sub(U32.add(x,side),1),native_width,width)
  +bottom = Presentation.coordinate(U32.sub(U32.add(y,side),1),native_height,height)
  U32.is_lt(x,native_width) && U32.is_lt(y,native_height) &&
    touched(layout,left,top,U32.add(1,U32.max(U32.sub(right,left),U32.sub(bottom,top))))

def native_uniform(view:View,layout:Layout,+viewport:Presentation.Viewport,+x:U32,+y:U32,+side:U32,color:U32) -> Maybe<&2,U32>:
  Presentation.Viewport{+width,+height,+native_width,+native_height} = viewport
  +right = U32.sub(U32.add(x,side),1)
  +bottom = U32.sub(U32.add(y,side),1)
  P.choose(Maybe<&2,U32>,Some{native_pixel(view,layout,viewport,x,y,color)},None{},
    U32.is_lt(right,native_width) && U32.is_lt(bottom,native_height) &&
    U32.is_eq(Presentation.coordinate(x,native_width,width),Presentation.coordinate(right,native_width,width)) &&
    U32.is_eq(Presentation.coordinate(y,native_height,height),Presentation.coordinate(bottom,native_height,height)))

def native_uniform_or(color:Maybe<&2,U32>,draw:Unit -> Image) -> Image:
  match color:
    case Some{value}: Pix{value}
    case None{}: draw(Unit{})

def native_overlay(fuel:Nat,image:Image,+view:View,+layout:Layout,+viewport:Presentation.Viewport,
    +x:U32,+y:U32,+side:U32,active:Bool) -> Image:
  match fuel image active:
    case _ _ False{}: image
    case 0n Pix{color} True{}: Pix{native_pixel(view,layout,viewport,x,y,color)}
    case 0n Qua{tl,tr,bl,br} True{}: Pix{native_pixel(view,layout,viewport,x,y,R.pixel_at(0n,Qua{tl,tr,bl,br},0,0,1))}
    case 1n+ +rest Pix{+color} True{}:
      +half = U32.div(side,2)
      native_uniform_or(native_uniform(view,layout,viewport,x,y,side,color),unused =>
        Qua{native_overlay(rest,Pix{color},view,layout,viewport,x,y,half,native_touched(layout,viewport,x,y,half)),
        native_overlay(rest,Pix{color},view,layout,viewport,U32.add(x,half),y,half,native_touched(layout,viewport,U32.add(x,half),y,half)),
        native_overlay(rest,Pix{color},view,layout,viewport,x,U32.add(y,half),half,native_touched(layout,viewport,x,U32.add(y,half),half)),
        native_overlay(rest,Pix{color},view,layout,viewport,U32.add(x,half),U32.add(y,half),half,native_touched(layout,viewport,U32.add(x,half),U32.add(y,half),half))})
    case 1n+ +rest Qua{tl,tr,bl,br} True{}:
      +half = U32.div(side,2)
      Qua{native_overlay(rest,tl,view,layout,viewport,x,y,half,native_touched(layout,viewport,x,y,half)),
        native_overlay(rest,tr,view,layout,viewport,U32.add(x,half),y,half,native_touched(layout,viewport,U32.add(x,half),y,half)),
        native_overlay(rest,bl,view,layout,viewport,x,U32.add(y,half),half,native_touched(layout,viewport,x,U32.add(y,half),half)),
        native_overlay(rest,br,view,layout,viewport,U32.add(x,half),U32.add(y,half),half,native_touched(layout,viewport,U32.add(x,half),U32.add(y,half),half))}

def draw_native(image:Image,view:View,+viewport:Presentation.Viewport) -> Image:
  Presentation.Viewport{width,height,+native_width,+native_height} = viewport
  +depth = Presentation.depth(native_width,native_height)
  native_overlay(depth,image,view,layout(width,height),viewport,0,0,U32.shln(1,depth),True{})

# Common.events preserves each event's observed capture. The first left click
# that establishes capture is consumed, so resuming control cannot break a
# block accidentally. A final focus/capture loss suppresses all game commands.
def command_admitted(admitted:Bool,event:Event) -> Maybe<&2,Wire.Command>:
  match admitted event:
    case False{} _: None{}
    case True{} Key{+code,True{}}:
      P.choose(Maybe<&2,Wire.Command>,Some{Wire.Hotbar{U32.sub(code,49)}},None{},U32.is_ge(code,49) && U32.is_le(code,57))
    case True{} Mouse{x,y,0,True{}}: Some{Wire.Action{0}}
    case True{} Mouse{x,y,1,True{}}: Some{Wire.Action{1}}
    case _ _: None{}

def command(event:Event,admitted:Bool) -> Maybe<&2,Wire.Command>:
  command_admitted(admitted,event)

def prepend(value:Maybe<&2,Wire.Command>,tail:List<&2,Wire.Command>) -> List<&2,Wire.Command>:
  match value:
    case None{}: tail
    case Some{head}: head <> tail

def commands(actions:List<&2,CC.Action>,active:Bool,+focused:Bool) -> List<&2,Wire.Command>:
  match actions:
    case Nil{}: []
    case CC.Release{} <> tail: commands(tail,False{},focused)
    case CC.PlatformEvent{event,+captured} <> tail:
      prepend(command(event,active && captured && focused),commands(tail,captured,focused))

def packet_commands(packet:CC.Packet,previous_capture:Bool) -> List<&2,Wire.Command>:
  CC.Packet{actions,focused,captured} = packet
  commands(actions,previous_capture,focused && captured)

type Projection is Data:
  Projection{source_width:U32,source_height:U32,source_depth:Nat,source_side:U32,
    width:U32,height:U32}

def presentation_width(human:Bool,logical:U32) -> U32:
  P.choose(U32,960,logical,human)

def presentation_height(human:Bool,logical:U32) -> U32:
  P.choose(U32,540,logical,human)

# Base's Window samples against the drawable's power-of-two backing side.
# A rectangular logical raster therefore needs a Bend-owned projection first.
# Constant source subtrees are returned as one Pix, without visiting each
# destination pixel. Production composition uses its measured output extent;
# presentation() below remains the historical fixed960 fixture compatibility.
def uniform(fuel:Nat,image:Image,+x:U32,+y:U32,+right:U32,+bottom:U32,+side:U32) -> Maybe<&2,U32>:
  match fuel image:
    case _ Pix{color}: Some{color}
    case 0n Qua{tl,tr,bl,br}: None{}
    case 1n+rest Qua{tl,tr,bl,br}:
      +half = U32.div(side,2)
      +east = U32.is_ge(x,half)
      +south = U32.is_ge(y,half)
      P.choose(Maybe<&2,U32>,uniform(rest,R.quadrant(tl,tr,bl,br,east,south),U32.mod(x,half),U32.mod(y,half),
        U32.mod(right,half),U32.mod(bottom,half),half),None{},
        Bool.not(Bool.xor(east,U32.is_ge(right,half))) && Bool.not(Bool.xor(south,U32.is_ge(bottom,half))))

def projection_uniform(complete:Bool,+image:Image,projection:Projection,+x:U32,+y:U32,+side:U32) -> Maybe<&2,U32>:
  match complete:
    case False{}: None{}
    case True{}:
      Projection{+sw,+sh,depth,source_side,+width,+height} = projection
      uniform(depth,image,
        U32.div(U32.mul(x,sw),width),U32.div(U32.mul(y,sh),height),
        U32.div(U32.mul(U32.sub(U32.min(U32.add(x,side),width),1),sw),width),
        U32.div(U32.mul(U32.sub(U32.min(U32.add(y,side),height),1),sh),height),source_side)

def projection_color(color:Maybe<&2,U32>,split:Unit -> Image) -> Image:
  match color:
    case Some{value}: Pix{value}
    case None{}: split(Unit{})

def projection_admit(visible:Bool,draw:Unit -> Image) -> Image:
  match visible:
    case False{}: Pix{0}
    case True{}: draw(Unit{})

def projected(fuel:Nat,+image:Image,+projection:Projection,+x:U32,+y:U32,+side:U32) -> Image:
  match fuel projection:
    case 0n Projection{+sw,+sh,depth,source_side,+width,+height}:
      P.choose(Image,Pix{R.pixel_at(depth,image,U32.div(U32.mul(x,sw),width),
        U32.div(U32.mul(y,sh),height),source_side)},Pix{0},U32.is_lt(x,width) && U32.is_lt(y,height))
    case 1n+ +rest Projection{+sw,+sh,+depth,+source_side,+width,+height}:
      +half = U32.div(side,2)
      projection_admit(U32.is_lt(x,width) && U32.is_lt(y,height),unit =>
        projection_color(projection_uniform(U32.is_le(U32.add(x,side),width) &&
          U32.is_le(U32.add(y,side),height),image,projection,x,y,side),unit =>
          Qua{projected(rest,image,projection,x,y,half),
            projected(rest,image,projection,U32.add(x,half),y,half),
            projected(rest,image,projection,x,U32.add(y,half),half),
            projected(rest,image,projection,U32.add(x,half),U32.add(y,half),half)}))

def project(image:Image,+source_width:U32,+source_height:U32,+width:U32,+height:U32) -> Image:
  +source_depth = P.array_depth(13n,U32.max(source_width,source_height),1)
  +depth = P.array_depth(13n,U32.max(width,height),1)
  projected(depth,image,Projection{source_width,source_height,source_depth,U32.shln(1,source_depth),width,height},
    0,0,U32.shln(1,depth))

def presentation(image:Image,human:Bool,width:U32,height:U32) -> Image:
  match human:
    case False{}: image
    case True{}: project(image,width,height,960,540)

def project_matching(image:Image,width:U32,height:U32,output_width:U32,output_height:U32,same:Bool) -> Image:
  match same:
    case True{}: image
    case False{}: project(image,width,height,output_width,output_height)

def compose(image:Image,view:View,plan:Presentation.Plan) -> Image:
  Presentation.Plan{settings,+viewport,+width,+height,point_width,point_height} = plan
  Presentation.Viewport{hud_width,hud_height,+output_width,+output_height} = viewport
  draw_native(project_matching(image,width,height,output_width,output_height,
    U32.is_eq(width,output_width) && U32.is_eq(height,output_height)),view,viewport)

def command_result(command:Wire.Command,status:Result<&2,&2,String,Wire.Reply>) -> Result<&2,&2,String,Unit>:
  match command status:
    case Wire.Action{button} Done{Wire.ActionReply{epoch,sequence,changed,message}}: Done{Unit{}}
    case Wire.Hotbar{index} Done{Wire.Ack{epoch,sequence}}: Done{Unit{}}
    case Wire.Action{button} Done{other}: Fail{"Wire:ExpectedAction"}
    case Wire.Hotbar{index} Done{other}: Fail{"Wire:ExpectedAck"}
    case _ Fail{message}: Fail{message}
    case _ _: Fail{"Wire:UnexpectedGameCommand"}
