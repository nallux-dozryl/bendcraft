import Base
import ./png.bend as P

# Shared production policy. Pixel arithmetic stays bounded U32; backing depth
# and the structural allocation recurrence use the same Nat depth as Image.
type Settings is Data:
  Settings{width:U32,height:U32,render_percent:U32,hud_scale:U32,native:Bool,fullscreen:Bool}
type Geometry is Data:
  Geometry{width:U32,height:U32,point_width:U32,point_height:U32}
type Viewport is Data:
  Viewport{width:U32,height:U32,native_width:U32,native_height:U32}
type Plan is Data:
  Plan{settings:Settings,viewport:Viewport,scene_width:U32,scene_height:U32,point_width:U32,point_height:U32}

def dimensions(+width:U32,+height:U32) -> Bool:
  U32.is_ge(width,4) && U32.is_ge(height,4) && U32.is_le(width,4096) && U32.is_le(height,4096)

def geometry_valid(geometry:Geometry) -> Bool:
  Geometry{width,height,+point_width,+point_height} = geometry
  dimensions(width,height) && U32.is_ge(point_width,1) && U32.is_ge(point_height,1) &&
    U32.is_le(point_width,4096) && U32.is_le(point_height,4096)

def depth(+width:U32,+height:U32) -> Nat:
  P.array_depth(13n,U32.max(width,height),1)

def side(width:U32,height:U32) -> U32:
  U32.shln(1,depth(width,height))

def backing_pixels(+width:U32,+height:U32) -> U32:
  +backing = side(width,height)
  U32.mul(backing,backing)

# Number of leaves in the full backing allocation used by Mesh.frame. These
# are logical Image leaves, not a byte/RSS estimate for the runtime allocator.
def leaves(n:Nat) -> Nat:
  match n:
    case 0n: 1n
    case 1n+rest:
      +child = leaves(rest)
      Nat.add(child,Nat.add(child,Nat.add(child,child)))

def image_leaves(image:Image) -> Nat:
  match image:
    case Pix{color}: 1n
    case Qua{tl,tr,bl,br}:
      Nat.add(image_leaves(tl),Nat.add(image_leaves(tr),Nat.add(image_leaves(bl),image_leaves(br))))

def defaults(human:Bool) -> Settings:
  P.choose(Settings,Settings{1920,1080,100,0,False{},False{}},
    Settings{128,128,100,1,False{},False{}},human)

def valid(settings:Settings) -> Bool:
  Settings{+width,+height,+percent,+scale,native,fullscreen} = settings
  dimensions(width,height) && U32.is_ge(percent,25) && U32.is_le(percent,100) &&
    U32.is_le(scale,4)

def valid_requested(settings:Settings) -> Bool:
  Settings{+width,+height,+percent,+scale,native,fullscreen} = settings
  (U32.is_eq(width,0) || (U32.is_ge(width,4) && U32.is_le(width,4096))) &&
    (U32.is_eq(height,0) || (U32.is_ge(height,4) && U32.is_le(height,4096))) &&
    U32.is_ge(percent,25) && U32.is_le(percent,100) && U32.is_le(scale,4)

def resolve_configured(settings:Settings,default:Settings) -> Settings:
  match settings default:
    case Settings{+width,+height,percent,scale,native,fullscreen} Settings{dw,dh,dp,ds,dn,df}:
      Settings{P.choose(U32,dw,width,U32.is_eq(width,0)),P.choose(U32,dh,height,U32.is_eq(height,0)),
        percent,scale,native,fullscreen}

def resolve(settings:Settings,human:Bool) -> Settings:
  resolve_configured(settings,defaults(human))

def setting(settings:Settings,field:U32,value:U32) -> Settings:
  match settings field:
    case Settings{width,height,percent,scale,native,fullscreen} 0: Settings{value,height,percent,scale,False{},fullscreen}
    case Settings{width,height,percent,scale,native,fullscreen} 1: Settings{width,value,percent,scale,False{},fullscreen}
    case Settings{width,height,percent,scale,native,fullscreen} 2: Settings{width,height,value,scale,native,fullscreen}
    case Settings{width,height,percent,scale,native,fullscreen} _: Settings{width,height,percent,value,native,fullscreen}

def mode(settings:Settings,native:Bool,fullscreen:Bool) -> Settings:
  Settings{width,height,percent,scale,old_native,old_fullscreen} = settings
  Settings{width,height,percent,scale,native,fullscreen}

def effective_scale(+width:U32,+height:U32,+scale:U32) -> U32:
  P.choose(U32,U32.max(1,U32.min(4,U32.min(U32.div(width,320),U32.div(height,180)))),scale,U32.is_eq(scale,0))

def viewport(+width:U32,+height:U32,scale:U32) -> Viewport:
  +actual_scale = U32.max(1,effective_scale(width,height,scale))
  Viewport{U32.max(1,U32.div(width,actual_scale)),U32.max(1,U32.div(height,actual_scale)),width,height}

def extent(+value:U32,percent:U32) -> U32:
  U32.max(4,U32.div(U32.mul(value,percent),100))

def plan(+settings:Settings,geometry:Geometry,+human:Bool) -> Plan:
  Settings{width,height,+percent,scale,native,fullscreen} = settings
  Geometry{actual_width,actual_height,point_width,point_height} = geometry
  +output_width = P.choose(U32,actual_width,width,human)
  +output_height = P.choose(U32,actual_height,height,human)
  Plan{settings,viewport(output_width,output_height,scale),extent(output_width,percent),
    extent(output_height,percent),point_width,point_height}

def output_width(plan:Plan) -> U32:
  Plan{settings,Viewport{width,height,native_width,native_height},scene_width,scene_height,point_width,point_height} = plan
  native_width

def output_height(plan:Plan) -> U32:
  Plan{settings,Viewport{width,height,native_width,native_height},scene_width,scene_height,point_width,point_height} = plan
  native_height

def scene_width(plan:Plan) -> U32:
  Plan{settings,viewport,width,height,point_width,point_height} = plan
  width

def scene_height(plan:Plan) -> U32:
  Plan{settings,viewport,width,height,point_width,point_height} = plan
  height

def hud_viewport(plan:Plan) -> Viewport:
  Plan{settings,viewport,width,height,point_width,point_height} = plan
  viewport

def hud_width(plan:Plan) -> U32:
  Plan{settings,Viewport{width,height,native_width,native_height},sw,sh,pw,ph} = plan
  width

def hud_height(plan:Plan) -> U32:
  Plan{settings,Viewport{width,height,native_width,native_height},sw,sh,pw,ph} = plan
  height

# All admitted dimensions are <=4096. Thus the largest numerator is below
# 4096² and fits U32. Runtime U32 division/conversion remains a native boundary.
def coordinate(+pixel:U32,+source:U32,+target:U32) -> U32:
  U32.min(U32.sub(U32.max(1,target),1),
    U32.div(U32.mul(U32.min(pixel,U32.sub(U32.max(1,source),1)),target),U32.max(1,source)))

# Mouse events can occur outside content bounds during a drag. Preserve that
# fact as an output-extent sentinel, so hit testing rejects the event instead
# of treating it as a click on the right/bottom edge.
def pointer_coordinate_checked(+pixel:U32,+source:U32,+target:U32,inside:Bool) -> U32:
  match inside:
    case True{}: coordinate(pixel,source,target)
    case False{}: target

def pointer_coordinate(+pixel:U32,+source:U32,target:U32) -> U32:
  pointer_coordinate_checked(pixel,source,target,U32.is_lt(pixel,source))

def native_event(event:Event,plan:Plan) -> Event:
  match event plan:
    case Mouse{x,y,button,down} Plan{settings,Viewport{width,height,+native_width,+native_height},scene_width,scene_height,point_width,point_height}:
      Mouse{pointer_coordinate(x,point_width,native_width),pointer_coordinate(y,point_height,native_height),button,down}
    case Move{x,y} Plan{settings,Viewport{width,height,+native_width,+native_height},scene_width,scene_height,point_width,point_height}:
      Move{pointer_coordinate(x,point_width,native_width),pointer_coordinate(y,point_height,native_height)}
    case Scroll{x,y,dx,dy} Plan{settings,Viewport{width,height,+native_width,+native_height},scene_width,scene_height,point_width,point_height}:
      Scroll{pointer_coordinate(x,point_width,native_width),pointer_coordinate(y,point_height,native_height),dx,dy}
    case other _: other

def native_events(events:List<Event>,+plan:Plan) -> List<Event>:
  match events:
    case Nil{}: []
    case event <> tail: native_event(event,plan) <> native_events(tail,plan)
