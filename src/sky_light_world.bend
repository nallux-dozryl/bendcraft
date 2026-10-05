import Base
import ./core.bend as C
import ./block_light.bend as B
import ./block_light_world.bend as BW
import ./sky_light.bend as S
import ./section_map.bend as M
import ./section.bend as Section

# The sidecar owns sky facts/work ONLY. Every operation borrows the sole affine
# Core owner by transferring it in and returning that same world representation.
type Bounds is Data:
  Bounds{min_y:U32,height:U32,air:U32,has_sky:Bool}
type SectionPolicy is Data:
  Unknown{}
  KnownEmpty{}
type Chunk is Data:
  Chunk{origin:C.Position,bounds:Bounds,enabled:Bool}
type Work is Data:
  Work{origin:C.Position,index:U32,cells:List<&2,U32>}
type Scan is Data:
  Scan{position:C.Position,min_y:U32,height:U32,remaining:Nat,above:B.Descriptor,enabled:Bool}
type Phase is Data:
  Enumerate{keys:List<&2,String>}
  Loading{todo:List<&2,C.Position>,active:Maybe<&2,Work>}
  Sources{todo:List<&2,C.Position>,active:Maybe<&2,Scan>,fresh:Bool}
  Seeding{todo:List<&2,C.Position>,index:U32}
  Republishing{todo:List<&2,C.Position>,active:Maybe<&2,Scan>}
  Injecting{todo:List<&2,C.Position>,active:Maybe<&2,Scan>}
  Ready{}
type State is Type:
  State{light:S.State,phase:Phase,chunks:List<&2,Chunk>,domains:List<&2,C.Position>,
    repairs:List<&2,C.Position>,revision:Maybe<&2,Nat>}
type Error is Data:
  InvalidSectionKey{key:String}
  MissingBounds{dimension:String}
  InvalidBounds{dimension:String}
  MissingDescriptor{state:U32}
  InvalidDescriptor{state:U32}
  UnknownSection{position:C.Position}
  MissingCell{position:C.Position}
  LoadingInProgress{}
  LightPending{pending:Nat}
  StaleRevision{}
  CoreFailure{error:C.Error}
  ResidencyMismatch{position:C.Position}
type Progress is Data:
  Bootstrap{}
  Propagating{pending:Nat}
  Settled{}
type Observation is Data:
  Observation{position:C.Position,block:Maybe<&2,U32>,level:Maybe<&2,U32>}
type FrameSamples is Data:
  FrameSamples{clock:C.Clock,cells:List<&2,Observation>}

def empty() -> State:
  State{S.new(),Ready{},[],[],[],None{}}
def begin_keys(world:C.World,result:M.Sections & List<&2,String>) -> C.World & State:
  (sections,keys) = result
  (C.replace_sections(world,sections),State{S.new(),Enumerate{keys},[],[],[],None{}})
def begin(world:C.World) -> C.World & State:
  C.World{tick,time,paused,daylight,revision,count,sections,pending,events} = world
  begin_keys(C.World{tick,time,paused,daylight,revision,count,M.EmptySections{},pending,events},BW.section_keys(sections))
def chunk_origin(position:C.Position) -> C.Position:
  C.Position{dimension,x,y,z} = position
  C.Position{dimension,Section.Coord.compose_value(Section.Coord.section(x),0),0,
    Section.Coord.compose_value(Section.Coord.section(z),0)}
def chunk_key(position:C.Position) -> String:
  C.Position{dimension,+x,y,+z} = position
  dimension ++ "/" ++ U32.show(Section.Coord.compose_value(Section.Coord.section(x),0)) ++ "/" ++ U32.show(Section.Coord.compose_value(Section.Coord.section(z),0))
def same_chunk(a:C.Position,b:C.Position) -> Bool:
  String.eq(chunk_key(a),chunk_key(b))
def chunk_found(found:Bool,chunk:Chunk,rest:Maybe<&2,Chunk>) -> Maybe<&2,Chunk>:
  match found:
    case True{}: Some{chunk}
    case False{}: rest
def find_chunk(+position:C.Position,chunks:List<&2,Chunk>) -> Maybe<&2,Chunk>:
  match chunks:
    case Nil{}: None{}
    case +chunk <> rest:
      Chunk{+origin,bounds,enabled} = chunk
      chunk_found(same_chunk(position,origin),chunk,find_chunk(position,rest))
def bounds_valid(+bounds:Bounds) -> Bool:
  Bounds{+minimum,+height,air,sky} = bounds
  U32.is_eq(U32.and(minimum,15),0) && U32.is_eq(U32.and(height,15),0) &&
    U32.is_gt(height,0) && U32.is_le(height,2147483647) && S.signed_lt(minimum,U32.add(minimum,height))
def sections(fuel:Nat,position:C.Position) -> List<&2,C.Position>:
  match fuel:
    case 0n: []
    case 1n+rest:
      C.Position{+dimension,+x,+y,+z} = position
      C.Position{dimension,x,y,z} <> sections(rest,C.Position{dimension,x,U32.add(y,16),z})
def chunk_sections(chunk:Chunk) -> List<&2,C.Position>:
  Chunk{C.Position{dimension,x,y,z},Bounds{minimum,height,air,sky},enabled} = chunk
  sections(U32.to_nat(U32.div(height,16)),C.Position{dimension,x,minimum,z})
def all_sections(chunks:List<&2,Chunk>) -> List<&2,C.Position>:
  match chunks:
    case Nil{}: []
    case chunk <> rest: List.append(&2,C.Position,chunk_sections(chunk),all_sections(rest))
def columns(fuel:Nat,+index:U32,+origin:C.Position) -> List<&2,C.Position>:
  match fuel:
    case 0n: []
    case 1n+rest:
      C.Position{+dimension,+x,+y,+z} = origin
      C.Position{dimension,U32.add(x,U32.and(index,15)),y,U32.add(z,U32.shrn(index,4n))} <>
        columns(rest,U32.inc(index),origin)
def chunk_columns(chunk:Chunk) -> List<&2,C.Position>:
  Chunk{C.Position{dimension,x,y,z},Bounds{minimum,height,air,sky},enabled} = chunk
  columns(256n,0,C.Position{dimension,x,U32.sub(U32.add(minimum,height),1),z})
def all_columns(chunks:List<&2,Chunk>) -> List<&2,C.Position>:
  match chunks:
    case Nil{}: []
    case chunk <> rest: List.append(&2,C.Position,chunk_columns(chunk),all_columns(rest))
def parse_key(result:Result<&2,&2,BW.Error,C.Position>) -> Result<&2,&2,Error,C.Position>:
  match result:
    case Done{position}: Done{position}
    case Fail{BW.InvalidSectionKey{key}}: Fail{InvalidSectionKey{key}}
    case Fail{error}: Fail{InvalidSectionKey{""}}
def descriptor_checked(valid:Bool,id:U32,descriptor:B.Descriptor) -> Result<&2,&2,Error,B.Descriptor>:
  match valid:
    case True{}: Done{S.descriptor(descriptor,False{})}
    case False{}: Fail{InvalidDescriptor{id}}
def descriptor_result(+id:U32,found:Maybe<&2,B.Descriptor>) -> Result<&2,&2,Error,B.Descriptor>:
  match found:
    case None{}: Fail{MissingDescriptor{id}}
    case Some{+descriptor}:
      B.Descriptor{state,emission,dampening} = descriptor
      descriptor_checked(U32.is_eq(state,id) && B.descriptor_valid(descriptor),id,descriptor)
def repeat(fuel:Nat,+id:U32) -> List<&2,U32>:
  match fuel:
    case 0n: []
    case 1n+rest: id <> repeat(rest,id)

def outside_if(position:C.Position,tail:List<&2,C.Position>,outside:Bool) -> List<&2,C.Position>:
  match outside:
    case True{}: position <> tail
    case False{}: tail
def outside_section(+position:C.Position,tail:List<&2,C.Position>,chunk:Maybe<&2,Chunk>) -> List<&2,C.Position>:
  C.Position{dimension,x,+y,z} = position
  match chunk:
    case None{}: position <> tail
    case Some{Chunk{origin,Bounds{+minimum,height,air,sky},enabled}}:
      outside_if(position,tail,S.signed_lt(y,minimum) || S.signed_ge(y,U32.add(minimum,height)))
def outside_sections(positions:List<&2,C.Position>,+chunks:List<&2,Chunk>) -> List<&2,C.Position>:
  match positions:
    case Nil{}: []
    case +position <> rest: outside_section(position,outside_sections(rest,chunks),find_chunk(position,chunks))
def halo_min(minimum:U32,edge:Bool) -> U32:
  match edge:
    case True{}: minimum
    case False{}: U32.sub(minimum,16)
def halo_max(maximum:U32,room:Bool) -> U32:
  match room:
    case True{}: U32.add(maximum,16)
    case False{}: maximum
def storage_column(lowest:S.Lowest,enabled:Bool,+minimum:U32,+height:U32) -> S.Column:
  +bottom = halo_min(minimum,U32.is_eq(minimum,2147483648))
  +top = halo_max(U32.add(minimum,height),S.signed_lt(U32.add(minimum,height),2147483632))
  S.Column{lowest,enabled,bottom,U32.sub(top,bottom)}
def enumerate_valid(~Context:Data,~enabled:Context -> C.Position -> Bool,context:Context,
    world:C.World,state:State,key:String,keys:List<&2,String>,+position:C.Position,bounds:Bounds,valid:Bool) -> C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,chunks,domains,repairs,revision} = state
  match valid:
    case False{}: (world,(State{light,Enumerate{key <> keys},chunks,domains,repairs,revision},Fail{InvalidBounds{C.dimension(position)}}))
    case True{}:
      (world,(State{light,Enumerate{keys},Chunk{chunk_origin(position),bounds,enabled(context,chunk_origin(position))} <> chunks,
        position <> domains,repairs,revision},Done{Unit{}}))
def enumerate_bounds(~Context:Data,~enabled:Context -> C.Position -> Bool,context:Context,
    world:C.World,state:State,key:String,keys:List<&2,String>,position:C.Position,
    result:Maybe<&2,Bounds>) -> C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,chunks,domains,repairs,revision} = state
  match result:
    case None{}:
      (world,(State{light,Enumerate{key <> keys},chunks,domains,repairs,revision},Fail{MissingBounds{C.dimension(position)}}))
    case Some{+bounds}: enumerate_valid(~Context,~enabled,context,world,State{light,phase,chunks,domains,repairs,revision},key,keys,position,bounds,bounds_valid(bounds))
def enumerate_chunk(~Context:Data,~bounds:Context -> String -> Maybe<&2,Bounds>,
    ~enabled:Context -> C.Position -> Bool,+context:Context,world:C.World,state:State,
    key:String,keys:List<&2,String>,+position:C.Position,existing:Maybe<&2,Chunk>) -> C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,chunks,domains,repairs,revision} = state
  match existing:
    case Some{chunk}: (world,(State{light,Enumerate{keys},chunks,position <> domains,repairs,revision},Done{Unit{}}))
    case None{}:
      enumerate_bounds(~Context,~enabled,context,world,State{light,phase,chunks,domains,repairs,revision},key,keys,position,
        bounds(context,C.dimension(position)))
def enumerate_key(~Context:Data,~bounds:Context -> String -> Maybe<&2,Bounds>,
    ~enabled:Context -> C.Position -> Bool,context:Context,world:C.World,state:State,
    key:String,keys:List<&2,String>,parsed:Result<&2,&2,Error,C.Position>) -> C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,+chunks,domains,repairs,revision} = state
  match parsed:
    case Fail{error}: (world,(State{light,Enumerate{key <> keys},chunks,domains,repairs,revision},Fail{error}))
    case Done{+position}:
      enumerate_chunk(~Context,~bounds,~enabled,context,world,State{light,phase,chunks,domains,repairs,revision},key,keys,position,find_chunk(position,chunks))

def load_cell(world:C.World,state:State,todo:List<&2,C.Position>,+origin:C.Position,+index:U32,+id:U32,
    tail:List<&2,U32>,result:Result<&2,&2,Error,B.Descriptor>) -> C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,chunks,domains,repairs,revision} = state
  match result:
    case Fail{error}:
      (world,(State{light,Loading{todo,Some{Work{origin,index,id <> tail}}},chunks,domains,repairs,revision},Fail{error}))
    case Done{descriptor}:
      (world,(State{S.set_physical(light,BW.indexed(origin,index),descriptor),
        Loading{todo,Some{Work{origin,U32.inc(index),tail}}},chunks,domains,repairs,revision},Done{Unit{}}))
def load_empty(world:C.World,state:State,+position:C.Position,todo:List<&2,C.Position>,
    policy:SectionPolicy,chunk:Maybe<&2,Chunk>) -> C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,chunks,domains,repairs,revision} = state
  match policy chunk:
    case KnownEmpty{} Some{Chunk{origin,Bounds{min,height,air,sky},enabled}}:
      (world,(State{light,Loading{todo,Some{Work{position,0,repeat(4096n,air)}}},chunks,domains,repairs,revision},Done{Unit{}}))
    case _ _: (world,(State{light,Loading{position <> todo,None{}},chunks,domains,repairs,revision},Fail{UnknownSection{position}}))
def load_snapshot(~Context:Data,~section_policy:Context -> C.Position -> SectionPolicy,context:Context,
    state:State,+position:C.Position,todo:List<&2,C.Position>,result:C.World & Maybe<&2,List<&2,U32>>) ->
    C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,+chunks,domains,repairs,revision} = state
  (world,found) = result
  match found:
    case Some{cells}: (world,(State{light,Loading{todo,Some{Work{position,0,cells}}},chunks,domains,repairs,revision},Done{Unit{}}))
    case None{}:
      load_empty(world,State{light,phase,chunks,domains,repairs,revision},position,todo,
        section_policy(context,position),find_chunk(position,chunks))

def scan_enabled(state:State,+position:C.Position,todo:List<&2,C.Position>,fresh:Bool,
    minimum:U32,+height:U32,above:B.Descriptor,+enabled:Bool,has_sky:Bool) -> State & Result<&2,&2,Error,Unit>:
  State{light,phase,chunks,domains,repairs,revision} = state
  match has_sky:
    case False{}:
      (State{S.set_column(light,position,storage_column(S.Everywhere{},False{},minimum,height)),
        Sources{todo,None{},fresh},chunks,domains,repairs,revision},Done{Unit{}})
    case True{}:
      (State{light,Sources{todo,Some{Scan{position,minimum,height,U32.to_nat(height),above,enabled}},fresh},
        chunks,domains,repairs,revision},Done{Unit{}})
def scan_start(state:State,+position:C.Position,todo:List<&2,C.Position>,fresh:Bool,
    chunk:Maybe<&2,Chunk>,air:Result<&2,&2,Error,B.Descriptor>) -> State & Result<&2,&2,Error,Unit>:
  State{light,phase,chunks,domains,repairs,revision} = state
  match chunk air:
    case None{} _:
      (State{light,Sources{position <> todo,None{},fresh},chunks,domains,repairs,revision},Fail{MissingCell{position}})
    case _ Fail{error}:
      (State{light,Sources{position <> todo,None{},fresh},chunks,domains,repairs,revision},Fail{error})
    case Some{Chunk{origin,Bounds{minimum,height,id,sky},enabled}} Done{above}:
      scan_enabled(State{light,phase,chunks,domains,repairs,revision},position,todo,fresh,minimum,height,above,enabled,sky)
def scan_chunk(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,context:Context,
    state:State,+position:C.Position,todo:List<&2,C.Position>,fresh:Bool,+chunk:Maybe<&2,Chunk>) -> State & Result<&2,&2,Error,Unit>:
  match chunk:
    case None{}: scan_start(state,position,todo,fresh,None{},Fail{MissingCell{position}})
    case Some{Chunk{origin,Bounds{min,height,+air,sky},enabled}}:
      scan_start(state,position,todo,fresh,chunk,descriptor_result(air,properties(context,air)))
def scan_blocked(state:State,todo:List<&2,C.Position>,fresh:Bool,
    scan:Scan,below:B.Descriptor,blocked:Bool) -> State & Result<&2,&2,Error,Unit>:
  State{light,phase,chunks,domains,repairs,revision} = state
  Scan{C.Position{+dimension,+x,+y,+z},+minimum,+height,remaining,above,+enabled} = scan
  match blocked:
    case True{}:
      (State{S.set_column(light,C.Position{dimension,x,y,z},storage_column(S.From{U32.inc(y)},enabled,minimum,height)),
        Sources{todo,None{},fresh},chunks,domains,repairs,revision},Done{Unit{}})
    case False{}:
      (State{light,Sources{todo,Some{Scan{C.Position{dimension,x,U32.sub(y,1),z},minimum,height,
        Nat.sub(remaining,1n),below,enabled}},fresh},chunks,domains,repairs,revision},Done{Unit{}})
def scan_read(~Context:Data,~occludes:Context -> B.Descriptor -> B.Descriptor -> B.Direction -> Bool,context:Context,
    state:State,todo:List<&2,C.Position>,fresh:Bool,+scan:Scan,found:Maybe<&2,B.Descriptor>) -> State & Result<&2,&2,Error,Unit>:
  State{light,phase,chunks,domains,repairs,revision} = state
  Scan{+position,min,height,remaining,+above,enabled} = scan
  match found:
    case None{}:
      (State{light,Sources{todo,Some{scan},fresh},chunks,domains,repairs,revision},Fail{MissingCell{position}})
    case Some{+below}:
      scan_blocked(State{light,phase,chunks,domains,repairs,revision},todo,fresh,scan,below,S.blocks_source(~Context,~occludes,context,above,below))
def scan_done(state:State,todo:List<&2,C.Position>,fresh:Bool,scan:Scan) -> State & Result<&2,&2,Error,Unit>:
  State{light,phase,chunks,domains,repairs,revision} = state
  Scan{position,min,height,remaining,above,enabled} = scan
  (State{S.set_column(light,position,storage_column(S.Everywhere{},enabled,min,height)),
    Sources{todo,None{},fresh},chunks,domains,repairs,revision},Done{Unit{}})

def seed_next(state:State,+origin:C.Position,todo:List<&2,C.Position>,+index:U32,valid:Bool) -> State:
  State{light,phase,chunks,domains,repairs,revision} = state
  match valid:
    case False{}: State{light,Seeding{todo,0},chunks,domains,repairs,revision}
    case True{}: State{S.seed(light,BW.indexed(origin,index)),Seeding{origin <> todo,U32.inc(index)},chunks,domains,repairs,revision}
def resume_result(result:C.World & (State & Result<&2,&2,Error,Unit>),
    next:C.World -> State -> C.World & (State & Result<&2,&2,Error,Unit>)) -> C.World & (State & Result<&2,&2,Error,Unit>):
  (world,(state,status)) = result
  match status:
    case Fail{error}: (world,(state,Fail{error}))
    case Done{u}: next(world,state)
def complete(world:C.World,state:State,clock:C.Clock) -> C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,chunks,domains,repairs,ignored} = state
  C.Clock{tick,time,paused,daylight,revision,pending} = clock
  (world,(State{light,Ready{},chunks,domains,repairs,Some{revision}},Done{Unit{}}))
def republish_found(world:C.World,state:State,todo:List<&2,C.Position>,+scan:Scan,
    result:S.State & Result<&2,&2,S.Error,Unit>) -> C.World & (State & Result<&2,&2,Error,Unit>):
  State{ignored,phase,chunks,domains,repairs,revision} = state
  Scan{C.Position{+dimension,+x,+y,+z},minimum,height,remaining,above,enabled} = scan
  (light,status) = result
  match status:
    case Fail{error}: (world,(State{light,Republishing{todo,Some{scan}},chunks,domains,repairs,revision},Fail{MissingCell{C.Position{dimension,x,y,z}}}))
    case Done{u}:
      (world,(State{light,Republishing{todo,Some{Scan{C.Position{dimension,x,U32.inc(y),z},minimum,height,
        Nat.sub(remaining,1n),above,enabled}}},chunks,domains,repairs,revision},Done{Unit{}}))
def republish_start(world:C.World,state:State,+position:C.Position,todo:List<&2,C.Position>,chunk:Maybe<&2,Chunk>) ->
    C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,chunks,domains,repairs,revision} = state
  C.Position{dimension,x,y,z} = position
  match chunk:
    case None{}: (world,(State{light,Republishing{position <> todo,None{}},chunks,domains,repairs,revision},Fail{MissingCell{position}}))
    case Some{Chunk{origin,Bounds{+minimum,+height,air,sky},enabled}}:
      (world,(State{light,Republishing{todo,Some{Scan{C.Position{dimension,x,minimum,z},minimum,height,
        U32.to_nat(height),B.Descriptor{air,0,0},enabled}}},chunks,domains,repairs,revision},Done{Unit{}}))
def republish_unit(world:C.World,state:State) -> C.World & (State & Result<&2,&2,Error,Unit>):
  match state:
    case State{light,Republishing{Nil{},None{}},chunks,domains,repairs,revision}:
      B.paired(C.World,C.Clock,C.World & (State & Result<&2,&2,Error,Unit>),C.clock(world),world => clock =>
        complete(world,State{light,Ready{},chunks,domains,[],revision},clock))
    case State{light,Republishing{+position <> todo,None{}},+chunks,domains,repairs,revision}:
      republish_start(world,State{light,Ready{},chunks,domains,repairs,revision},position,todo,find_chunk(position,chunks))
    case State{light,Republishing{todo,Some{Scan{position,min,height,0n,above,enabled}}},chunks,domains,repairs,revision}:
      (world,(State{light,Republishing{todo,None{}},chunks,domains,repairs,revision},Done{Unit{}}))
    case State{light,Republishing{todo,Some{Scan{+position,min,height,1n+remaining,above,enabled}}},chunks,domains,repairs,revision}:
      republish_found(world,State{S.new(),Ready{},chunks,domains,repairs,revision},todo,
        Scan{position,min,height,1n+remaining,above,enabled},S.resource(light,position))
    case other: (world,(other,Fail{LoadingInProgress{}}))
def inject_choose(state:S.State,position:C.Position,direct:Bool) -> S.State & Result<&2,&2,S.Error,Unit>:
  match direct:
    case False{}: (state,Done{Unit{}})
    case True{}: S.resource(state,position)
def inject_at(state:S.State,+position:C.Position) -> S.State & Result<&2,&2,S.Error,Unit>:
  B.paired(S.State,Maybe<&2,S.Column>,S.State & Result<&2,&2,S.Error,Unit>,S.column(state,position),
    state => found => inject_choose(state,position,S.source(position,found)))
def inject_rephase(result:C.World & (State & Result<&2,&2,Error,Unit>)) -> C.World & (State & Result<&2,&2,Error,Unit>):
  (original,(state,status)) = result
  match state:
    case State{light,Republishing{todo,active},chunks,domains,repairs,revision}:
      (original,(State{light,Injecting{todo,active},chunks,domains,repairs,revision},status))
    case other: (original,(other,status))
def inject_unit(world:C.World,state:State) -> C.World & (State & Result<&2,&2,Error,Unit>):
  match state:
    case State{light,Injecting{Nil{},None{}},chunks,domains,repairs,revision}:
      B.paired(C.World,C.Clock,C.World & (State & Result<&2,&2,Error,Unit>),C.clock(world),world => clock =>
        complete(world,State{light,Ready{},chunks,domains,[],revision},clock))
    case State{light,Injecting{+position <> todo,None{}},+chunks,domains,repairs,revision}:
      inject_rephase(republish_start(world,State{light,Ready{},chunks,domains,repairs,revision},position,todo,find_chunk(position,chunks)))
    case State{light,Injecting{todo,Some{Scan{position,min,height,0n,above,enabled}}},chunks,domains,repairs,revision}:
      (world,(State{light,Injecting{todo,None{}},chunks,domains,repairs,revision},Done{Unit{}}))
    case State{light,Injecting{todo,Some{Scan{+position,min,height,1n+remaining,above,enabled}}},chunks,domains,repairs,revision}:
      inject_rephase(republish_found(world,State{S.new(),Ready{},chunks,domains,repairs,revision},todo,
        Scan{position,min,height,1n+remaining,above,enabled},inject_at(light,position)))
    case other: (world,(other,Fail{LoadingInProgress{}}))
def load_resume(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~bounds:Context -> String -> Maybe<&2,Bounds>,~section_policy:Context -> C.Position -> SectionPolicy,
    ~enabled:Context -> C.Position -> Bool,~occludes:Context -> B.Descriptor -> B.Descriptor -> B.Direction -> Bool,
    +context:Context,budget:Nat,world:C.World,state:State) -> C.World & (State & Result<&2,&2,Error,Unit>):
  match budget state:
    case 0n state: (world,(state,Done{Unit{}}))
    case 1n+rest State{light,Ready{},chunks,domains,repairs,revision}:
      (world,(State{light,Ready{},chunks,domains,repairs,revision},Done{Unit{}}))
    case 1n+rest State{light,Enumerate{Nil{}},+chunks,domains,repairs,revision}:
      +complete = List.append(&2,C.Position,all_sections(chunks),outside_sections(domains,chunks))
      load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,
        State{light,Loading{complete,None{}},chunks,complete,repairs,revision})
    case 1n+rest State{light,Enumerate{+key <> keys},chunks,domains,repairs,revision}:
      resume_result(
        enumerate_key(~Context,~bounds,~enabled,context,world,State{light,Enumerate{[]},chunks,domains,repairs,revision},key,keys,parse_key(BW.key_origin(key))),world => state => load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,state))
    case 1n+rest State{light,Loading{todo,Some{Work{+origin,+index,+id <> tail}}},chunks,domains,repairs,revision}:
      resume_result(
        load_cell(world,State{light,Ready{},chunks,domains,repairs,revision},todo,origin,index,id,tail,descriptor_result(id,properties(context,id))),world => state => load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,state))
    case 1n+rest State{light,Loading{todo,Some{Work{origin,index,Nil{}}}},chunks,domains,repairs,revision}:
      load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,
        State{light,Loading{todo,None{}},chunks,domains,repairs,revision})
    case 1n+rest State{light,Loading{+position <> todo,None{}},chunks,domains,repairs,revision}:
      resume_result(
        load_snapshot(~Context,~section_policy,context,State{light,Ready{},chunks,domains,repairs,revision},position,todo,
          BW.snapshot(world,C.section_key(position))),world => state => load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,state))
    case 1n+rest State{light,Loading{Nil{},None{}},+chunks,domains,repairs,revision}:
      load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,
        State{light,Sources{all_columns(chunks),None{},True{}},chunks,domains,repairs,revision})
    case 1n+rest State{light,Sources{+position <> todo,None{},fresh},+chunks,domains,repairs,revision}:
      B.paired(State,Result<&2,&2,Error,Unit>,C.World & (State & Result<&2,&2,Error,Unit>),
        scan_chunk(~Context,~properties,context,State{light,Ready{},chunks,domains,repairs,revision},position,todo,fresh,find_chunk(position,chunks)),
        state => status => resume_result((world,(state,status)),world => state => load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,state)))
    case 1n+rest State{light,Sources{todo,Some{+scan},fresh},chunks,domains,repairs,revision}:
      Scan{+position,min,height,remaining,above,source_enabled} = scan
      match remaining:
        case 0n:
          B.paired(State,Result<&2,&2,Error,Unit>,C.World & (State & Result<&2,&2,Error,Unit>),
            scan_done(State{light,Ready{},chunks,domains,repairs,revision},todo,fresh,scan),state => status =>
            resume_result((world,(state,status)),world => state => load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,state)))
        case 1n+count:
          B.paired(S.State,Maybe<&2,B.Descriptor>,C.World & (State & Result<&2,&2,Error,Unit>),S.physical(light,position),light => found =>
            B.paired(State,Result<&2,&2,Error,Unit>,C.World & (State & Result<&2,&2,Error,Unit>),
              scan_read(~Context,~occludes,context,State{light,Ready{},chunks,domains,repairs,revision},todo,fresh,scan,found),state => status =>
              resume_result((world,(state,status)),world => state => load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,state))))
    case 1n+rest State{light,Sources{Nil{},None{},True{}},chunks,+domains,repairs,revision}:
      load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,
        State{light,Seeding{domains,0},chunks,domains,repairs,revision})
    case 1n+rest State{light,Sources{Nil{},None{},False{}},chunks,domains,+repairs,revision}:
      load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,
        State{light,Republishing{repairs,None{}},chunks,domains,repairs,revision})
    case 1n+rest State{light,Seeding{+origin <> todo,+index},chunks,domains,repairs,revision}:
      load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,
        seed_next(State{light,Ready{},chunks,domains,repairs,revision},origin,todo,index,U32.is_lt(index,4096)))
    case 1n+rest State{light,Seeding{Nil{},index},chunks,domains,repairs,revision}:
      B.paired(C.World,C.Clock,C.World & (State & Result<&2,&2,Error,Unit>),C.clock(world),world => clock =>
        complete(world,State{light,Ready{},chunks,domains,[],revision},clock))
    case 1n+rest State{light,Republishing{todo,active},chunks,domains,repairs,revision}:
      resume_result(republish_unit(world,State{light,Republishing{todo,active},chunks,domains,repairs,revision}),
        world => state => load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,state))
    case 1n+rest State{light,Injecting{todo,active},chunks,domains,repairs,revision}:
      resume_result(inject_unit(world,State{light,Injecting{todo,active},chunks,domains,repairs,revision}),
        world => state => load_resume(~Context,~properties,~bounds,~section_policy,~enabled,~occludes,context,rest,world,state))

def progress_status(status:B.Status) -> Progress:
  match status:
    case B.Stable{}: Settled{}
    case B.MoreWork{pending}: Propagating{pending}
def progress(state:State) -> State & Progress:
  match state:
    case State{light,Ready{},chunks,domains,repairs,revision}:
      B.paired(S.State,B.Status,State & Progress,S.status(light),light => status =>
        (State{light,Ready{},chunks,domains,repairs,revision},progress_status(status)))
    case other: (other,Bootstrap{})
def advance(~Context:Data,~occludes:Context -> B.Descriptor -> B.Descriptor -> B.Direction -> Bool,
    context:Context,budget:Nat,state:State) -> State & Progress:
  match state:
    case State{light,Ready{},chunks,domains,repairs,revision}:
      B.paired(S.State,B.Status,State & Progress,S.advance(~Context,~occludes,context,budget,light),light => status =>
        (State{light,Ready{},chunks,domains,repairs,revision},progress_status(status)))
    case other: (other,Bootstrap{})
def observed(position:C.Position,result:Result<&2,&2,C.Error,U32>,level:Maybe<&2,U32>) -> Result<&2,&2,Error,Observation>:
  match result level:
    case Done{id} Some{light}: Done{Observation{position,Some{id},Some{light}}}
    case Fail{C.MissingSection{key}} _: Done{Observation{position,None{},None{}}}
    case Fail{error} _: Fail{CoreFailure{error}}
    case _ _: Fail{ResidencyMismatch{position}}
def samples_cons(world:C.World,state:State,result:Result<&2,&2,Error,Observation>,
    tail:C.World -> State -> C.World & (State & Result<&2,&2,Error,List<&2,Observation>>)) ->
    C.World & (State & Result<&2,&2,Error,List<&2,Observation>>):
  match result:
    case Fail{error}: (world,(state,Fail{error}))
    case Done{cell}:
      B.paired(C.World,State & Result<&2,&2,Error,List<&2,Observation>>,C.World & (State & Result<&2,&2,Error,List<&2,Observation>>),
        tail(world,state),world => result =>
        B.paired(State,Result<&2,&2,Error,List<&2,Observation>>,C.World & (State & Result<&2,&2,Error,List<&2,Observation>>),result,
          state => cells => (world,(state,Result.map(&2,&2,Error,List<&2,Observation>,List<&2,Observation>,cells => cell <> cells,cells)))))
def samples(positions:List<&2,C.Position>,world:C.World,state:State) -> C.World & (State & Result<&2,&2,Error,List<&2,Observation>>):
  match positions:
    case Nil{}: (world,(state,Done{[]}))
    case +position <> rest:
      State{light,phase,chunks,domains,repairs,revision} = state
      B.paired(C.World,Result<&2,&2,C.Error,U32>,C.World & (State & Result<&2,&2,Error,List<&2,Observation>>),C.read_block(world,position),world => read =>
        B.paired(S.State,Maybe<&2,U32>,C.World & (State & Result<&2,&2,Error,List<&2,Observation>>),S.sample(light,position),light => level =>
          samples_cons(world,State{light,phase,chunks,domains,repairs,revision},observed(position,read,level),
            world => state => samples(rest,world,state))))
def frame_result(clock:C.Clock,result:C.World & (State & Result<&2,&2,Error,List<&2,Observation>>)) ->
    C.World & (State & Result<&2,&2,Error,FrameSamples>):
  (world,(state,cells)) = result
  (world,(state,Result.map(&2,&2,Error,List<&2,Observation>,FrameSamples,cells => FrameSamples{clock,cells},cells)))
def sample_ready(positions:List<&2,C.Position>,world:C.World,state:State,clock:C.Clock,status:B.Status) ->
    C.World & (State & Result<&2,&2,Error,FrameSamples>):
  match status:
    case B.MoreWork{pending}: (world,(state,Fail{LightPending{pending}}))
    case B.Stable{}: frame_result(clock,samples(positions,world,state))
def sample_revision(positions:List<&2,C.Position>,world:C.World,state:State,clock:C.Clock,valid:Bool) ->
    C.World & (State & Result<&2,&2,Error,FrameSamples>):
  State{light,phase,chunks,domains,repairs,revision} = state
  match valid:
    case False{}: (world,(State{light,phase,chunks,domains,repairs,revision},Fail{StaleRevision{}}))
    case True{}:
      B.paired(S.State,B.Status,C.World & (State & Result<&2,&2,Error,FrameSamples>),S.status(light),light => status =>
        sample_ready(positions,world,State{light,phase,chunks,domains,repairs,revision},clock,status))
def revision_matches(revision:Maybe<&2,Nat>,current:Nat) -> Bool:
  match revision:
    case None{}: False{}
    case Some{expected}: Nat.is_eq(expected,current)
def sample_clock(positions:List<&2,C.Position>,state:State,result:C.World & C.Clock) ->
    C.World & (State & Result<&2,&2,Error,FrameSamples>):
  State{light,phase,chunks,domains,repairs,+revision} = state
  (world,+clock) = result
  C.Clock{tick,time,paused,daylight,+current,pending} = clock
  sample_revision(positions,world,State{light,phase,chunks,domains,repairs,revision},clock,revision_matches(revision,current))
def sample_batch(positions:List<&2,C.Position>,world:C.World,state:State) -> C.World & (State & Result<&2,&2,Error,FrameSamples>):
  match state:
    case State{light,Ready{},chunks,domains,repairs,revision}:
      sample_clock(positions,State{light,Ready{},chunks,domains,repairs,revision},C.clock(world))
    case other: (world,(other,Fail{LoadingInProgress{}}))

def repair_positions(enabled:Bool,position:C.Position) -> List<&2,C.Position>:
  match enabled:
    case False{}: []
    case True{}: [position]
def refresh_top(world:C.World,state:State,+top:C.Position,enabled:Bool,
    result:S.State & Result<&2,&2,S.Error,Unit>) -> C.World & (State & Result<&2,&2,Error,Unit>):
  State{ignored,phase,chunks,domains,repairs,revision} = state
  (light,status) = result
  match status:
    case Fail{error}: (world,(State{light,phase,chunks,domains,repairs,revision},Fail{MissingCell{top}}))
    case Done{u}:
      (world,(State{light,Sources{[top],None{},False{}},chunks,domains,repair_positions(enabled,top),None{}},Done{Unit{}}))
def refresh_published(world:C.World,state:State,position:C.Position,chunk:Chunk,
    result:S.State & Result<&2,&2,S.Error,Unit>) -> C.World & (State & Result<&2,&2,Error,Unit>):
  C.Position{dimension,x,y,z} = position
  Chunk{origin,Bounds{minimum,height,air,sky},enabled} = chunk
  refresh_top(world,state,C.Position{dimension,x,U32.sub(U32.add(minimum,height),1),z},enabled,result)
def refresh_found(world:C.World,state:State,+position:C.Position,result:Result<&2,&2,Error,B.Descriptor>,chunk:Maybe<&2,Chunk>) ->
    C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,chunks,domains,repairs,revision} = state
  match result chunk:
    case Fail{error} _: (world,(State{light,phase,chunks,domains,repairs,revision},Fail{error}))
    case _ None{}: (world,(State{light,phase,chunks,domains,repairs,revision},Fail{MissingCell{position}}))
    case Done{descriptor} Some{chunk}:
      refresh_published(world,State{S.new(),phase,chunks,domains,repairs,revision},position,chunk,S.publish(light,position,descriptor))
def refresh_read(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,context:Context,
    state:State,+position:C.Position,result:C.World & Result<&2,&2,C.Error,U32>) -> C.World & (State & Result<&2,&2,Error,Unit>):
  State{light,phase,+chunks,domains,repairs,revision} = state
  (world,read) = result
  match read:
    case Fail{error}: (world,(State{light,phase,chunks,domains,repairs,revision},Fail{CoreFailure{error}}))
    case Done{+id}:
      refresh_found(world,State{light,phase,chunks,domains,repairs,revision},position,descriptor_result(id,properties(context,id)),find_chunk(position,chunks))
# Call once after an accepted Core block edit. The current physical descriptor
# and complete vertical source column are repaired before samples are allowed.
def refresh_block(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,context:Context,
    +position:C.Position,world:C.World,state:State) -> C.World & (State & Result<&2,&2,Error,Unit>):
  match state:
    case State{light,Ready{},chunks,domains,repairs,revision}:
      refresh_read(~Context,~properties,context,State{light,Ready{},chunks,domains,repairs,revision},position,C.read_block(world,position))
    case other: (world,(other,Fail{LoadingInProgress{}}))
# Section creation/replacement and changes to authoritative absent-section
# policy acquire a new bootstrap over the actual current Core, retaining owner.
def rebuild(world:C.World,state:State) -> C.World & State:
  begin(world)
def accept_clock(world:C.World,state:State,clock:C.Clock) -> C.World & State:
  State{light,phase,chunks,domains,repairs,ignored} = state
  C.Clock{tick,time,paused,daylight,revision,pending} = clock
  (world,State{light,phase,chunks,domains,repairs,Some{revision}})
def accept_plain(world:C.World,state:State) -> C.World & State:
  State{light,phase,chunks,domains,repairs,revision} = state
  B.paired(C.World,C.Clock,C.World & State,C.clock(world),world => clock =>
    accept_clock(world,State{light,phase,chunks,domains,repairs,revision},clock))

def changed_chunk_if(chunk:Chunk,enabled:Bool,hit:Bool) -> Chunk:
  Chunk{origin,bounds,old} = chunk
  match hit:
    case False{}: Chunk{origin,bounds,old}
    case True{}: Chunk{origin,bounds,enabled}
def changed_chunk(position:C.Position,+enabled:Bool,+chunk:Chunk) -> Chunk:
  Chunk{+origin,bounds,old} = chunk
  changed_chunk_if(chunk,enabled,same_chunk(position,origin))
def column_enabled(light:S.State,position:C.Position,enabled:Bool,found:Maybe<&2,S.Column>) -> S.State:
  match found:
    case None{}: light
    case Some{S.Column{lowest,old,min,height}}: S.set_column(light,position,S.Column{lowest,enabled,min,height})
def columns_enabled(positions:List<&2,C.Position>,+enabled:Bool,light:S.State) -> S.State:
  match positions:
    case Nil{}: light
    case +position <> rest:
      B.paired(S.State,Maybe<&2,S.Column>,S.State,S.column(light,position),light => found =>
        columns_enabled(rest,enabled,column_enabled(light,position,enabled,found)))
def chunks_enabled(+position:C.Position,+enabled:Bool,chunks:List<&2,Chunk>) -> List<&2,Chunk>:
  match chunks:
    case Nil{}: []
    case chunk <> rest: changed_chunk(position,enabled,chunk) <> chunks_enabled(position,enabled,rest)
def signed_max(a:U32,b:U32,choose:Bool) -> U32:
  match choose:
    case True{}: b
    case False{}: a
def maximum_threshold(old:Maybe<&2,U32>,lowest:S.Lowest) -> Maybe<&2,U32>:
  match old lowest:
    case old S.Everywhere{}: old
    case None{} S.From{y}: Some{y}
    case Some{+old} S.From{+y}: Some{signed_max(old,y,S.signed_lt(old,y))}
def threshold_found(old:Maybe<&2,U32>,found:Maybe<&2,S.Column>) -> Maybe<&2,U32>:
  match found:
    case None{}: old
    case Some{S.Column{lowest,enabled,min,height}}: maximum_threshold(old,lowest)
def highest_threshold(positions:List<&2,C.Position>,light:S.State,highest:Maybe<&2,U32>) -> S.State & Maybe<&2,U32>:
  match positions:
    case Nil{}: (light,highest)
    case position <> rest:
      B.paired(S.State,Maybe<&2,S.Column>,S.State & Maybe<&2,U32>,S.column(light,position),light => found =>
        highest_threshold(rest,light,threshold_found(highest,found)))
def zero_level(level:Maybe<&2,U32>) -> Bool:
  match level:
    case None{}: False{}
    case Some{value}: U32.is_eq(value,0)
def zero_next(light:S.State,zero:Bool,next:S.State -> S.State & Bool) -> S.State & Bool:
  match zero:
    case False{}: (light,False{})
    case True{}: next(light)
def zero_section(fuel:Nat,+index:U32,+position:C.Position,light:S.State) -> S.State & Bool:
  match fuel:
    case 0n: (light,True{})
    case 1n+rest:
      B.paired(S.State,Maybe<&2,U32>,S.State & Bool,S.sample(light,BW.indexed(position,index)),light => level =>
        zero_next(light,zero_level(level),light => zero_section(rest,U32.inc(index),position,light)))
def seed_section(fuel:Nat,+index:U32,+position:C.Position,light:S.State) -> S.State:
  match fuel:
    case 0n: light
    case 1n+rest: seed_section(rest,U32.inc(index),position,S.seed(light,BW.indexed(position,index)))
def fill_if_zero(position:C.Position,light:S.State,zero:Bool) -> S.State:
  match zero:
    case False{}: light
    case True{}: seed_section(4096n,0,position,light)
def upper_layer(position:C.Position,chunk:C.Position,first:U32) -> Bool:
  C.Position{dimension,x,+y,z} = position
  same_chunk(C.Position{dimension,x,y,z},chunk) && S.signed_ge(y,first)
def fill_upper_next(+position:C.Position,light:S.State,upper:Bool,next:S.State -> S.State) -> S.State:
  match upper:
    case False{}: next(light)
    case True{}:
      B.paired(S.State,Bool,S.State,zero_section(4096n,0,position,light),light => zero =>
        next(fill_if_zero(position,light,zero)))
def fill_upper(todo:List<&2,C.Position>,+chunk:C.Position,+first:U32,light:S.State) -> S.State:
  match todo:
    case Nil{}: light
    case +position <> rest: fill_upper_next(position,light,upper_layer(position,chunk,first),light => fill_upper(rest,chunk,first,light))
def enable_highest(state:State,position:C.Position,highest:Maybe<&2,U32>) -> State:
  State{light,phase,chunks,+domains,repairs,revision} = state
  match highest:
    # Actual all-air MIN-1 wraps MAX. It fills no upper resident section.
    case None{}: State{light,phase,chunks,domains,repairs,revision}
    case Some{y}:
      State{fill_upper(domains,position,Section.Coord.compose_value(U32.inc(Section.Coord.section(U32.sub(y,1))),0),light),
        phase,chunks,domains,repairs,revision}
def enable_fill(state:State,+position:C.Position,enabled:Bool) -> State:
  State{light,phase,+chunks,domains,repairs,revision} = state
  match enabled:
    case False{}: State{light,phase,chunks,domains,repairs,revision}
    case True{}:
      B.paired(S.State,Maybe<&2,U32>,State,highest_threshold(columns(256n,0,chunk_origin(position)),light,None{}),
        light => highest => enable_highest(State{light,phase,chunks,domains,repairs,revision},position,highest))
def enabled_chunk(state:State,+position:C.Position,+enabled:Bool,found:Maybe<&2,Chunk>) -> State & Result<&2,&2,Error,Unit>:
  State{light,phase,+chunks,domains,repairs,revision} = state
  match found:
    case None{}: (State{light,phase,chunks,domains,repairs,revision},Fail{MissingCell{position}})
    case Some{+chunk}:
      Chunk{origin,Bounds{min,height,air,+sky},old} = chunk
      (enable_fill(State{columns_enabled(chunk_columns(chunk),enabled && sky,light),Ready{},
        chunks_enabled(position,enabled,chunks),domains,repairs,revision},position,enabled && sky),Done{Unit{}})
# Matches Java setLightEnabled: existing layer values are retained. Enabling
# alone does not call propagateLightSources and does not repair stale values.
def set_enabled(+position:C.Position,enabled:Bool,state:State) -> State & Result<&2,&2,Error,Unit>:
  match state:
    case State{light,Ready{},+chunks,domains,repairs,revision}:
      enabled_chunk(State{light,Ready{},chunks,domains,repairs,revision},position,enabled,find_chunk(position,chunks))
    case other: (other,Fail{LoadingInProgress{}})
def propagate_chunk(state:State,position:C.Position,found:Maybe<&2,Chunk>) -> State & Result<&2,&2,Error,Unit>:
  State{light,phase,chunks,domains,repairs,revision} = state
  match found:
    case None{}: (State{light,phase,chunks,domains,repairs,revision},Fail{MissingCell{position}})
    case Some{chunk}:
      (State{light,Injecting{chunk_columns(chunk),None{}},chunks,domains,[],None{}},Done{Unit{}})
# Only inject current direct sources. Java does not clear old stored values
# below a newly lowered source threshold merely by repropagating sources.
def propagate_enabled(+position:C.Position,result:State & Result<&2,&2,Error,Unit>) -> State & Result<&2,&2,Error,Unit>:
  (State{light,phase,+chunks,domains,repairs,revision},status) = result
  match status:
    case Fail{error}: (State{light,phase,chunks,domains,repairs,revision},Fail{error})
    case Done{u}:
      propagate_chunk(State{light,phase,chunks,domains,repairs,revision},position,find_chunk(position,chunks))
def propagate_sources(+position:C.Position,state:State) -> State & Result<&2,&2,Error,Unit>:
  propagate_enabled(position,set_enabled(position,True{},state))
def begun(result:C.World & State) -> C.World & (State & Result<&2,&2,Error,Unit>):
  (world,state) = result
  (world,(state,Done{Unit{}}))
def plain_result(result:C.World & State) -> C.World & (State & Result<&2,&2,Error,Unit>):
  (world,state) = result
  (world,(state,Done{Unit{}}))
def accepted(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,context:Context,
    mutation:C.Mutation,world:C.World,state:State) -> C.World & (State & Result<&2,&2,Error,Unit>):
  match mutation:
    case C.BlockSet{+position,id}:
      match state:
        case State{light,Ready{},chunks,domains,repairs,revision}:
          refresh_block(~Context,~properties,context,position,world,State{light,Ready{},chunks,domains,repairs,revision})
        case other: begun(rebuild(world,other))
    case C.SectionCreate{position,id}: begun(rebuild(world,state))
    case other: plain_result(accept_plain(world,state))
# This hook accepts the actual Core result, so a refused mutation returns both
# owners without publishing any sky work. It does not authorize/apply/finish
# mutations and cannot increment the simulation revision independently.
def accept_result(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,context:Context,
    mutation:C.Mutation,state:State,result:C.World & Result<&2,&2,C.Error,Unit>) -> C.World & (State & Result<&2,&2,Error,Unit>):
  (world,status) = result
  match status:
    case Fail{error}: (world,(state,Fail{CoreFailure{error}}))
    case Done{u}: accepted(~Context,~properties,context,mutation,world,state)
def preflight(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,context:Context,
    mutation:C.Mutation) -> Result<&2,&2,Error,Unit>:
  match mutation:
    case C.BlockSet{position,+id}: Result.map(&2,&2,Error,B.Descriptor,Unit,d => Unit{},descriptor_result(id,properties(context,id)))
    case C.SectionCreate{position,+id}: Result.map(&2,&2,Error,B.Descriptor,Unit,d => Unit{},descriptor_result(id,properties(context,id)))
    case other: Done{Unit{}}
