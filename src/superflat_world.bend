import Base
import ./client_world.bend as W
import ./section_map.bend as SM
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B
import ./movement.bend as M
import ./f64.bend as F
import ./schedule.bend as Q

# Bounded base-layer generation into the existing authoritative Core. This is
# neither noise terrain nor structures/features/biomes generation. ClassicFlat
# is the pinned vanilla flat preset's layers. StoneDirtFlat is an explicitly
# customized vanilla flat settings profile supported by today's client domain.
type Profile is Data:
  ClassicFlat{}
  StoneDirtFlat{}

type Palette is Data:
  Palette{air:U32,foundation:U32,middle:U32,surface:U32}

type Outcome is Data:
  Generated{}
  Existing{}

def profile_name(profile:Profile) -> String:
  match profile:
    case ClassicFlat{}: "minecraft:classic_flat"
    case StoneDirtFlat{}: "bendex:stone-dirt-superflat"

def client_profile() -> Profile:
  StoneDirtFlat{}

def foundation_name(profile:Profile) -> String:
  match profile:
    case ClassicFlat{}: "minecraft:bedrock"
    case StoneDirtFlat{}: "minecraft:stone"

def surface_name(profile:Profile) -> String:
  match profile:
    case ClassicFlat{}: "minecraft:grass_block"
    case StoneDirtFlat{}: "minecraft:stone"

def resolved(result:B.Registry & Result<&2,&2,B.Error,U32>) -> B.Registry & Result<&2,&2,String,U32>:
  (registry,status) = result
  match status:
    case Fail{error}: (registry,Fail{B.error_text(error)})
    case Done{state}: (registry,Done{state})

def resolve(registry:B.Registry,name:String) -> B.Registry & Result<&2,&2,String,U32>:
  resolved(B.Registry.resolve(registry,name,[],B.Defaults{}))

def surface_resolved(air:U32,foundation:U32,middle:U32,result:B.Registry & Result<&2,&2,String,U32>) -> B.Registry & Result<&2,&2,String,Palette>:
  (registry,status) = result
  match status:
    case Fail{message}: (registry,Fail{message})
    case Done{surface}: (registry,Done{Palette{air,foundation,middle,surface}})

def middle_resolved(profile:Profile,air:U32,foundation:U32,result:B.Registry & Result<&2,&2,String,U32>) -> B.Registry & Result<&2,&2,String,Palette>:
  (registry,status) = result
  match status:
    case Fail{message}: (registry,Fail{message})
    case Done{middle}: surface_resolved(air,foundation,middle,resolve(registry,surface_name(profile)))

def foundation_resolved(profile:Profile,air:U32,result:B.Registry & Result<&2,&2,String,U32>) -> B.Registry & Result<&2,&2,String,Palette>:
  (registry,status) = result
  match status:
    case Fail{message}: (registry,Fail{message})
    case Done{foundation}: middle_resolved(profile,air,foundation,resolve(registry,"minecraft:dirt"))

def air_resolved(+profile:Profile,result:B.Registry & Result<&2,&2,String,U32>) -> B.Registry & Result<&2,&2,String,Palette>:
  (registry,status) = result
  match status:
    case Fail{message}: (registry,Fail{message})
    case Done{air}: foundation_resolved(profile,air,resolve(registry,foundation_name(profile)))

def palette(registry:B.Registry,profile:Profile) -> B.Registry & Result<&2,&2,String,Palette>:
  air_resolved(profile,resolve(registry,"minecraft:air"))

# Five by five complete chunk columns, signed x/z -32 through 47. Three
# explicitly loaded vertical sections cover y=-80 through -33. The lowest
# section is the finite client's outside-world air halo; vanilla terrain
# layers begin at the pinned Overworld min_y=-64.
def section_position(+index:U32) -> C.Position:
  C.Position{"minecraft:overworld",
    U32.add(4294967264,U32.mul(U32.mod(index,5),16)),
    U32.add(4294967216,U32.mul(U32.mod(U32.div(index,25),3),16)),
    U32.add(4294967264,U32.mul(U32.mod(U32.div(index,5),5),16))}

def layer_state(palette:Palette,y:U32) -> U32:
  Palette{air,foundation,middle,surface} = palette
  match y:
    case 0: foundation
    case 3: surface
    case _: middle

def terrain_position(+index:U32) -> C.Position:
  C.Position{"minecraft:overworld",
    U32.add(4294967264,U32.mod(index,80)),
    U32.add(4294967232,U32.div(index,6400)),
    U32.add(4294967264,U32.mod(U32.div(index,80),80))}

def core_result(result:C.World & Result<&2,&2,C.Error,Unit>) -> C.World & Result<&2,&2,String,Unit>:
  (world,status) = result
  match status:
    case Fail{error}: (world,Fail{W.error_text(error)})
    case Done{unit}: (world,Done{unit})

def create_sections(fuel:Nat,+index:U32,+air:U32,world:C.World,status:Result<&2,&2,String,Unit>) -> C.World & Result<&2,&2,String,Unit>:
  match fuel status:
    case _ Fail{message}: (world,Fail{message})
    case 0n Done{unit}: (world,Done{unit})
    case 1n+rest Done{unit}:
      W.paired(C.World,Result<&2,&2,String,Unit>,C.World & Result<&2,&2,String,Unit>,
        core_result(C.create_section(world,section_position(index),air)),
        next => result => create_sections(rest,U32.inc(index),air,next,result))

def write_layers(fuel:Nat,+index:U32,+palette:Palette,world:C.World,status:Result<&2,&2,String,Unit>) -> C.World & Result<&2,&2,String,Unit>:
  match fuel status:
    case _ Fail{message}: (world,Fail{message})
    case 0n Done{unit}: (C.accepted(world,Q.Stamp{0n,0,0n}),Done{unit})
    case 1n+rest Done{unit}:
      W.paired(C.World,Result<&2,&2,String,Unit>,C.World & Result<&2,&2,String,Unit>,
        core_result(C.write_block(world,terrain_position(index),layer_state(palette,U32.div(index,6400)))),
        next => result => write_layers(rest,U32.inc(index),palette,next,result))

def layers_ready(palette:Palette,result:C.World & Result<&2,&2,String,Unit>) -> C.World & Result<&2,&2,String,Unit>:
  (world,status) = result
  write_layers(25600n,0,palette,world,status)

def generate(world:C.World,+palette:Palette) -> C.World & Result<&2,&2,String,Unit>:
  Palette{air,foundation,middle,surface} = palette
  layers_ready(palette,create_sections(75n,0,air,world,Done{Unit{}}))

def spawn_body() -> M.Body:
  M.Body.new(M.Vec3{F.from_f32(0.5),F.from_i32(4294967236),F.from_f32(0.5)},0.6,1.8,M.Vec3.zero(),True{})

def initial_region() -> W.Bounds:
  W.Bounds{4294967293,4294967232,4294967293,8,8,8}

def clamp_signed(+value:U32,+low:U32,+high:U32) -> U32:
  W.choose(U32,low,W.choose(U32,high,value,Bool.not(W.signed_le(value,high))),Bool.not(W.signed_le(low,value)))

def region_gate(+cx:U32,+cy:U32,+cz:U32,inside:Bool) -> Result<&2,&2,String,W.Bounds>:
  match inside:
    case False{}: Fail{"unsupported-superflat-view:outside-generated-region"}
    case True{}:
      # Clamp before subtracting; a complete neighbor halo remains loaded.
      Done{W.Bounds{U32.sub(clamp_signed(cx,4294967268,42),3),
        U32.sub(clamp_signed(cy,4294967221,4294967259),4),
        U32.sub(clamp_signed(cz,4294967268,42),3),8,8,8}}

def region_coordinates(+cx:U32,+cy:U32,+cz:U32) -> Result<&2,&2,String,W.Bounds>:
  region_gate(cx,cy,cz,W.signed_le(4294967264,cx) && W.signed_le(cx,47) &&
    W.signed_le(4294967216,cy) && W.signed_le(cy,4294967263) &&
    W.signed_le(4294967264,cz) && W.signed_le(cz,47))

def body_region(body:M.Body) -> Result<&2,&2,String,W.Bounds>:
  M.Body{M.Vec3{x,y,z},box,velocity,width,height,ground,horizontal,vertical,below} = body
  do Result<&2,&2,String,W.Bounds>:
    cx : U32 <- W.floor_coordinate(x)
    cy : U32 <- W.floor_coordinate(y)
    cz : U32 <- W.floor_coordinate(z)
    region_coordinates(cx,cy,cz)

def configured_equal(state:W.State,actual:W.Bounds,same:Bool) -> W.State & Result<&2,&2,String,Unit>:
  W.State{engine,body,yaw,pitch,palette,region,cache} = state
  match same:
    case True{}: (W.State{engine,body,yaw,pitch,palette,region,cache},Done{Unit{}})
    case False{}: (W.State{engine,body,yaw,pitch,palette,actual,None{}},Done{Unit{}})

def configured(state:W.State,result:Result<&2,&2,String,W.Bounds>) -> W.State & Result<&2,&2,String,Unit>:
  W.State{engine,body,yaw,pitch,palette,+region,cache} = state
  match result:
    case Fail{message}: (W.State{engine,body,yaw,pitch,palette,region,cache},Fail{message})
    case Done{+actual}:
      configured_equal(W.State{engine,body,yaw,pitch,palette,region,cache},actual,W.same_region(region,actual))

# The view is transient. Its 8x8x8 aperture has at most 512 full cubes (3072
# source quads), below the current 4096 pre-occlusion budget even after edits.
# It follows the same owned player within the complete loaded neighbor halo.
def configure(state:W.State) -> W.State & Result<&2,&2,String,Unit>:
  W.State{engine,+body,yaw,pitch,palette,region,cache} = state
  configured(W.State{engine,body,yaw,pitch,palette,region,cache},body_region(body))

def follow_result(result:W.State & Result<&2,&2,String,Unit>) -> W.State & Unit:
  (state,status) = result
  (state,Unit{})

def follow(state:W.State) -> W.State & Unit:
  W.State{engine,body,yaw,pitch,palette,+region,cache} = state
  W.Bounds{x,y,z,width,+height,depth} = region
  match height:
    case 8: follow_result(configure(W.State{engine,body,yaw,pitch,palette,region,cache}))
    case _: (W.State{engine,body,yaw,pitch,palette,region,cache},Unit{})

def generated(registry:B.Registry,view:W.View,result:C.World & Result<&2,&2,String,Unit>) -> W.State & Result<&2,&2,String,Outcome>:
  W.View{old_body,yaw,pitch,palette,region,cache} = view
  (world,status) = result
  match status:
    case Fail{message}: (W.attach(G.Engine{world,registry},W.View{old_body,yaw,pitch,palette,region,cache}),Fail{message})
    case Done{unit}:
      (W.State{G.Engine{world,registry},spawn_body(),0.0,0.0,palette,initial_region(),None{}},Done{Generated{}})

def palette_ready(world:C.World,view:W.View,result:B.Registry & Result<&2,&2,String,Palette>) -> W.State & Result<&2,&2,String,Outcome>:
  (registry,status) = result
  match status:
    case Fail{message}: (W.attach(G.Engine{world,registry},view),Fail{message})
    case Done{colors}: generated(registry,view,generate(world,colors))

def pristine_sections(sections:SM.Sections) -> SM.Sections & Bool:
  match sections:
    case SM.EmptySections{}: (SM.EmptySections{},True{})
    case other: (other,False{})

def pristine_result(registry:B.Registry,+tick:Nat,+time:Nat,+paused:Bool,+daylight:Bool,+revision:Nat,count:U32,
    +pending:List<&2,Q.Pending<C.Mutation>>,+events:List<&2,C.CoreEvent>,result:SM.Sections & Bool) -> G.Engine & Bool:
  (sections,empty) = result
  (G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},
    empty && Nat.is_eq(tick,0n) && Nat.is_eq(time,0n) && paused && daylight && Nat.is_eq(revision,0n) &&
    List.is_empty(&2,Q.Pending<C.Mutation>,pending) && List.is_empty(&2,C.CoreEvent,events))

def pristine(engine:G.Engine) -> G.Engine & Bool:
  G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry} = engine
  pristine_result(registry,tick,time,paused,daylight,revision,count,pending,events,pristine_sections(sections))

def pristine_gate(profile:Profile,view:W.View,result:G.Engine & Bool) -> W.State & Result<&2,&2,String,Outcome>:
  (engine,pristine) = result
  G.Engine{world,registry} = engine
  match pristine:
    case False{}: (W.attach(G.Engine{world,registry},view),Done{Existing{}})
    case True{}:
      palette_ready(world,view,palette(registry,profile))

def extracted(profile:Profile,result:G.Engine & W.View) -> W.State & Result<&2,&2,String,Outcome>:
  (engine,view) = result
  pristine_gate(profile,view,pristine(engine))

# Existing saves return exactly their Core and View. There is no fill-on-read,
# implicit unloaded air, regeneration, or replacement of edited sections.
def initialize_profile(world:W.State,profile:Profile) -> W.State & Result<&2,&2,String,Outcome>:
  extracted(profile,W.take(world))

def initialize(world:W.State) -> W.State & Result<&2,&2,String,Outcome>:
  initialize_profile(world,client_profile())

law existing_world_retains_owned_state:
  for engine:G.Engine
  for view:W.View
  for profile:Profile
  {pristine_gate(profile,view,(engine,False{})) == (W.attach(engine,view),Done{Existing{}}) : W.State & Result<&2,&2,String,Outcome>}
def existing_world_retains_owned_state(engine,view,profile):
  match engine:
    case G.Engine{world,registry}: {==}
