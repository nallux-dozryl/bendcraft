import Base
import ./client_world.bend as W
import ./section_map.bend as SM
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B
import ./movement.bend as M
import ./f64.bend as F
import ./schedule.bend as Q
import ./world_generation_settings.bend as WG
import ./superflat_population.bend as Population
import ./superflat_resolver.bend as Resolver
import ./section.bend as Section

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

# Production view policy is independent of image dimensions. The current mesh
# provider admits 4096 source quads; the default below guarantees at most3072
# full-cube quads. Larger requested policies require resource culling/batching.
type ViewPolicy is Data:
  ViewPolicy{width:U32,height:U32,depth:U32,max_cells:Nat}

def default_view_policy() -> ViewPolicy:
  ViewPolicy{8,8,8,512n}

def view_policy_valid(policy:ViewPolicy) -> Bool:
  ViewPolicy{+width,+height,+depth,cells} = policy
  U32.is_lt(0,width) && U32.is_lt(0,height) && U32.is_lt(0,depth) &&
    U32.is_le(width,2147483647) && U32.is_le(height,2147483647) && U32.is_le(depth,2147483647) &&
    Nat.is_le(Nat.mul(U32.to_nat(width),Nat.mul(U32.to_nat(height),U32.to_nat(depth))),cells)

def centered_axis(+center:U32,+extent:U32) -> Bool:
  +half = U32.div(extent,2)
  +before = U32.add(half,1)
  +after = U32.sub(extent,half)
  W.signed_le(U32.add(2147483648,before),center) &&
    W.signed_le(center,U32.sub(2147483647,after))

def centered_gate(policy:ViewPolicy,cx:U32,cy:U32,cz:U32,valid:Bool) -> Result<&2,&2,String,W.Bounds>:
  ViewPolicy{+width,+height,+depth,cells} = policy
  match valid:
    case False{}: Fail{"invalid view policy or signed coordinate neighbor halo"}
    case True{}: Done{W.Bounds{U32.sub(cx,U32.div(width,2)),U32.sub(cy,U32.div(height,2)),
      U32.sub(cz,U32.div(depth,2)),width,height,depth}}

def centered(+policy:ViewPolicy,+cx:U32,+cy:U32,+cz:U32) -> Result<&2,&2,String,W.Bounds>:
  ViewPolicy{width,height,depth,cells} = policy
  centered_gate(policy,cx,cy,cz,view_policy_valid(policy) &&
    centered_axis(cx,width) && centered_axis(cy,height) && centered_axis(cz,depth))

def production_region(policy:ViewPolicy,body:M.Body) -> Result<&2,&2,String,W.Bounds>:
  M.Body{M.Vec3{x,y,z},box,velocity,width,height,ground,horizontal,vertical,below} = body
  do Result<&2,&2,String,W.Bounds>:
    cx : U32 <- W.floor_coordinate(x)
    cy : U32 <- W.floor_coordinate(y)
    cz : U32 <- W.floor_coordinate(z)
    centered(policy,cx,cy,cz)

def configure_production(state:W.State,policy:ViewPolicy) -> W.State & Result<&2,&2,String,Unit>:
  W.State{engine,+body,yaw,pitch,palette,region,cache} = state
  configured(W.State{engine,body,yaw,pitch,palette,region,cache},production_region(policy,body))

def lower_signed(+a:U32,+b:U32) -> U32:
  W.choose(U32,a,b,W.signed_le(a,b))

def upper_signed(+a:U32,+b:U32) -> U32:
  W.choose(U32,b,a,W.signed_le(a,b))

def demand_region(settings:WG.Settings,bounds:W.Bounds) -> Result<&2,&2,String,Population.Region>:
  match settings:
    case WG.Unspecified{}: Fail{"generator settings unavailable for legacy save"}
    case WG.Settings{dimension,+min_y,world_height,seed,generator}:
      W.Bounds{+x,+y,+z,width,height,depth} = bounds
      +cx = Section.Coord.section(U32.sub(x,1))
      +cz = Section.Coord.section(U32.sub(z,1))
      +bottom = lower_signed(U32.sub(Section.Coord.section(min_y),1),Section.Coord.section(U32.sub(y,1)))
      +top = upper_signed(U32.add(Section.Coord.section(min_y),U32.div(world_height,16)),
        Section.Coord.section(U32.add(y,height)))
      +region = {Population.Region{cx,cz,
        U32.inc(U32.sub(Section.Coord.section(U32.add(x,width)),cx)),
        U32.inc(U32.sub(Section.Coord.section(U32.add(z,depth)),cz)),bottom,U32.inc(U32.sub(top,bottom))} : Population.Region}
      Population.column_valid(region,Population.region_valid(region))

def demand_populated(view:W.View,registry:B.Registry,result:C.World & Result<&2,&2,String,Population.Receipt>) -> W.State & Result<&2,&2,String,Population.Receipt>:
  (world,status) = result
  (W.attach(G.Engine{world,registry},view),status)

def demand_resolved(world:C.World,view:W.View,region:Population.Region,budget:Population.Budget,stamp:Q.Stamp,
    result:B.Registry & Result<&2,&2,String,Population.Flat>) -> W.State & Result<&2,&2,String,Population.Receipt>:
  (registry,status) = result
  match status:
    case Fail{message}: (W.attach(G.Engine{world,registry},view),Fail{message})
    case Done{flat}: demand_populated(view,registry,Population.populate(flat,region,stamp,budget,world))

def demand_rectangle(settings:WG.Settings,budget:Population.Budget,stamp:Q.Stamp,engine:G.Engine,view:W.View,
    result:Result<&2,&2,String,Population.Region>) -> W.State & Result<&2,&2,String,Population.Receipt>:
  G.Engine{world,registry} = engine
  match result:
    case Fail{message}: (W.attach(G.Engine{world,registry},view),Fail{message})
    case Done{region}:
      demand_resolved(world,view,region,budget,stamp,Resolver.resolve(registry,settings))

def demand_planned(state:W.State,+settings:WG.Settings,budget:Population.Budget,stamp:Q.Stamp,
    planned:Result<&2,&2,String,W.Bounds>) -> W.State & Result<&2,&2,String,Population.Receipt>:
  W.State{engine,body,yaw,pitch,palette,region,cache} = state
  match planned:
    case Fail{message}: (W.State{engine,body,yaw,pitch,palette,region,cache},Fail{message})
    case Done{bounds}:
      demand_rectangle(settings,budget,stamp,engine,W.View{body,yaw,pitch,palette,region,cache},demand_region(settings,bounds))

def demand_supported(state:W.State,settings:WG.Settings,policy:ViewPolicy,budget:Population.Budget,stamp:Q.Stamp,supported:Bool) -> W.State & Result<&2,&2,String,Population.Receipt>:
  W.State{engine,+body,yaw,pitch,palette,region,cache} = state
  match supported:
    case False{}: (W.State{engine,body,yaw,pitch,palette,region,cache},Fail{"requested generator pipeline unavailable: noise, structures, features or lakes"})
    case True{}:
      demand_planned(W.State{engine,body,yaw,pitch,palette,region,cache},settings,budget,stamp,production_region(policy,body))

# Populate the complete requested chunk columns, including one section above
# and below the dimension and the current view's neighbor halo. This leaves
# Body, View/cache, clocks, pending work and events untouched; revision changes once if new
# sections were created. Following/configuring is a separate owner operation.
def demand(state:W.State,+settings:WG.Settings,policy:ViewPolicy,budget:Population.Budget,stamp:Q.Stamp) -> W.State & Result<&2,&2,String,Population.Receipt>:
  demand_supported(state,settings,policy,budget,stamp,WG.base_only(settings))

# Explicit provenance gates generation before inspecting any world state.
def initialize_if_fresh(state:W.State,profile:Profile,fresh:Bool) -> W.State & Result<&2,&2,String,Outcome>:
  match fresh:
    case False{}: (state,Done{Existing{}})
    case True{}: initialize_profile(state,profile)

def generator_surface_gate(surface:U32,valid:Bool) -> Result<&2,&2,String,M.Body>:
  match valid:
    case False{}: Fail{"flat spawn surface exceeds signed coordinate representation"}
    case True{}:
      Done{M.Body.new(M.Vec3{F.from_f32(0.5),F.from_i32(surface),F.from_f32(0.5)},
        0.6,1.8,M.Vec3.zero(),False{})}

def generator_surface(+min_y:U32,+total:Nat) -> Result<&2,&2,String,M.Body>:
  +surface = U32.add(min_y,U32.from_nat(total))
  generator_surface_gate(surface,Nat.is_le(total,2147483647n) && WG.signed_le(min_y,surface))

def generator_body(min_y:U32,generator:WG.Generator) -> Result<&2,&2,String,M.Body>:
  match generator:
    case WG.Noise{settings,biome_source}: Fail{"noise spawn requires completed terrain and biome pipeline"}
    case WG.Flat{profile,biome,layers,features,lakes,structures}:
      generator_surface(min_y,WG.layer_height(layers))

def settings_body(settings:WG.Settings) -> Result<&2,&2,String,M.Body>:
  match settings:
    case WG.Unspecified{}: Fail{"fresh world requires explicit generator settings"}
    case WG.Settings{dimension,min_y,height,seed,generator}:
      generator_body(min_y,generator)

def fresh_event(state:W.State,stamp:Q.Stamp) -> W.State:
  W.State{G.Engine{C.World{tick,time,paused,daylight,+revision,count,sections,pending,events},registry},body,yaw,pitch,palette,region,cache} = state
  W.State{G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,C.Applied{stamp,revision} <> events},registry},body,yaw,pitch,palette,region,cache}

def initialized_configured(stamp:Q.Stamp,result:W.State & Result<&2,&2,String,Unit>) -> W.State & Result<&2,&2,String,Outcome>:
  (state,status) = result
  match status:
    case Fail{message}: (state,Fail{message})
    case Done{unit}: (fresh_event(state,stamp),Done{Generated{}})

def initialized_demanded(old_view:W.View,+policy:ViewPolicy,stamp:Q.Stamp,result:W.State & Result<&2,&2,String,Population.Receipt>) -> W.State & Result<&2,&2,String,Outcome>:
  (W.State{engine,body,yaw,pitch,palette,region,cache},status) = result
  match status:
    case Fail{message}: (W.attach(engine,old_view),Fail{message})
    case Done{receipt}:
      initialized_configured(stamp,configure_production(W.State{engine,body,yaw,pitch,palette,region,cache},policy))

def initialized_body(settings:WG.Settings,+policy:ViewPolicy,budget:Population.Budget,+stamp:Q.Stamp,engine:G.Engine,+view:W.View,
    result:Result<&2,&2,String,M.Body>) -> W.State & Result<&2,&2,String,Outcome>:
  W.View{old_body,yaw,pitch,palette,region,cache} = view
  match result:
    case Fail{message}: (W.attach(engine,view),Fail{message})
    case Done{body}:
      initialized_demanded(view,policy,stamp,demand(W.State{engine,body,0.0,0.0,palette,region,None{}},settings,policy,budget,stamp))

def initialized_settings(policy:ViewPolicy,budget:Population.Budget,stamp:Q.Stamp,engine:G.Engine,view:W.View,
    result:Result<&2,&2,String,WG.Settings>) -> W.State & Result<&2,&2,String,Outcome>:
  match result:
    case Fail{message}: (W.attach(engine,view),Fail{message})
    case Done{+settings}: initialized_body(settings,policy,budget,stamp,engine,view,settings_body(settings))

def initialized_pristine(settings:WG.Settings,policy:ViewPolicy,budget:Population.Budget,stamp:Q.Stamp,view:W.View,
    result:G.Engine & Bool) -> W.State & Result<&2,&2,String,Outcome>:
  (engine,empty) = result
  match empty:
    case False{}: (W.attach(engine,view),Fail{"fresh world initialization requires pristine authoritative Core"})
    case True{}: initialized_settings(policy,budget,stamp,engine,view,WG.validate(settings))

def initialize_generated_taken(settings:WG.Settings,policy:ViewPolicy,budget:Population.Budget,stamp:Q.Stamp,
    result:G.Engine & W.View) -> W.State & Result<&2,&2,String,Outcome>:
  (engine,view) = result
  initialized_pristine(settings,policy,budget,stamp,view,pristine(engine))

# The durable loaded owner is an unconditional identity branch, including its
# complete View/cache. Fresh initialization alone may select a spawn and reset
# transient camera/history through the Scene's ordinary R.fresh owner.
def initialize_generated(state:W.State,settings:WG.Settings,policy:ViewPolicy,budget:Population.Budget,stamp:Q.Stamp,fresh:Bool) -> W.State & Result<&2,&2,String,Outcome>:
  match fresh:
    case False{}: (state,Done{Existing{}})
    case True{}: initialize_generated_taken(settings,policy,budget,stamp,W.take(state))

def stamp_at_tick(tick:Nat,peer:U32,sequence:Nat,same:Bool) -> Q.Stamp:
  match same:
    case True{}: Q.Stamp{tick,peer,1n+sequence}
    case False{}: Q.Stamp{tick,0,0n}

def generation_stamp_head(+tick:Nat,stamp:Q.Stamp) -> Q.Stamp:
  Q.Stamp{old,peer,sequence} = stamp
  stamp_at_tick(tick,peer,sequence,Nat.is_eq(tick,old))

def generation_stamp(+tick:Nat,events:List<&2,C.CoreEvent>) -> Q.Stamp:
  match events:
    case Nil{}: Q.Stamp{tick,0,0n}
    case event <> rest: generation_stamp_head(tick,Population.event_stamp(event))

def demand_current(state:W.State,settings:WG.Settings,policy:ViewPolicy,budget:Population.Budget) -> W.State & Result<&2,&2,String,Population.Receipt>:
  W.State{G.Engine{C.World{+tick,time,paused,daylight,revision,count,sections,pending,+events},registry},body,yaw,pitch,palette,region,cache} = state
  demand(W.State{G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},body,yaw,pitch,palette,region,cache},
    settings,policy,budget,generation_stamp(tick,events))

def ensured_configured(receipt:Population.Receipt,result:W.State & Result<&2,&2,String,Unit>) -> W.State & Result<&2,&2,String,Population.Receipt>:
  (state,status) = result
  match status:
    case Fail{message}: (state,Fail{message})
    case Done{unit}: (state,Done{receipt})

def ensured_demanded(policy:ViewPolicy,result:W.State & Result<&2,&2,String,Population.Receipt>) -> W.State & Result<&2,&2,String,Population.Receipt>:
  (state,status) = result
  match status:
    case Fail{message}: (state,Fail{message})
    case Done{receipt}: ensured_configured(receipt,configure_production(state,policy))

def ensure_result(result:W.State & Result<&2,&2,String,Population.Receipt>) -> W.State & Result<&2,&2,String,Unit>:
  (state,status) = result
  match status:
    case Fail{message}: (state,Fail{message})
    case Done{receipt}: (state,Done{Unit{}})

def ensure_current(state:W.State,settings:WG.Settings,+policy:ViewPolicy,budget:Population.Budget) -> W.State & Result<&2,&2,String,Unit>:
  ensure_result(ensured_demanded(policy,demand_current(state,settings,policy,budget)))
