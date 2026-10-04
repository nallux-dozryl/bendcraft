import Base
import ./core.bend as C

# Block light only. Descriptors come from the authoritative state catalog;
# emission is effective emission (zero while section lighting is disabled).
type Descriptor is Data:
  Descriptor{state:U32,emission:U32,dampening:U32}

type Direction is Data:
  Down{}
  Up{}
  North{}
  South{}
  West{}
  East{}

type Neighbor is Data:
  Neighbor{position:C.Position,direction:Direction}

type Cell is Data:
  Cell{descriptor:Descriptor,level:U32}

type Status is Data:
  Stable{}
  MoreWork{pending:Nat}

type Error is Data:
  InvalidDescriptor{}

# One affine owner threads the resident field and deduplicated FIFO. A caller
# must publish only accepted world edits and run advance before settled reads.
type State is Type:
  State{cells:Map<&2,Maybe<&2,Cell>>,front:List<&2,C.Position>,
    back:List<&2,C.Position>,queued:Set(),pending:Nat}

def paired(-A:Type,-B:Type,-R:Type,pair:A & B,body:A -> B -> R) -> R:
  (a,b) = pair
  body(a,b)

def new() -> State:
  State{MTip{},[],[],Set.new(),0n}

def key(position:C.Position) -> String:
  C.Position{dimension,x,y,z} = position
  dimension ++ "/" ++ U32.show(x) ++ "/" ++ U32.show(y) ++ "/" ++ U32.show(z)

def opposite(direction:Direction) -> Direction:
  match direction:
    case Down{}: Up{}
    case Up{}: Down{}
    case North{}: South{}
    case South{}: North{}
    case West{}: East{}
    case East{}: West{}

def direction_id(direction:Direction) -> U32:
  match direction:
    case Down{}: 0
    case Up{}: 1
    case North{}: 2
    case South{}: 3
    case West{}: 4
    case East{}: 5

# Signed coordinates use Core's raw two's-complement U32 representation.
# The finite I32 domain has no periodic edge at either signed endpoint.
def neighbor_if(valid:Bool,position:C.Position,direction:Direction,
    rest:List<&2,Neighbor>) -> List<&2,Neighbor>:
  match valid:
    case True{}: Neighbor{position,direction} <> rest
    case False{}: rest

def neighbors(position:C.Position) -> List<&2,Neighbor>:
  C.Position{+d,+x,+y,+z} = position
  neighbor_if(U32.is_ne(y,2147483648),C.Position{d,x,U32.sub(y,1),z},Down{},
  neighbor_if(U32.is_ne(y,2147483647),C.Position{d,x,U32.inc(y),z},Up{},
  neighbor_if(U32.is_ne(z,2147483648),C.Position{d,x,y,U32.sub(z,1)},North{},
  neighbor_if(U32.is_ne(z,2147483647),C.Position{d,x,y,U32.inc(z)},South{},
  neighbor_if(U32.is_ne(x,2147483648),C.Position{d,U32.sub(x,1),y,z},West{},
  neighbor_if(U32.is_ne(x,2147483647),C.Position{d,U32.inc(x),y,z},East{},[]))))))

def descriptor_valid(descriptor:Descriptor) -> Bool:
  Descriptor{state,emission,dampening} = descriptor
  U32.is_le(emission,15) && U32.is_le(dampening,15)

def emission(descriptor:Descriptor) -> U32:
  Descriptor{state,value,dampening} = descriptor
  value

def dampening(descriptor:Descriptor) -> U32:
  Descriptor{state,emission,value} = descriptor
  value

def cell_level(cell:Maybe<&2,Cell>) -> U32:
  match cell:
    case None{}: 0
    case Some{Cell{descriptor,level}}: level

# At least one level is lost on every open edge. Subtraction is saturating;
# opaque targets (dampening15) receive no positive light from a valid level.
def transfer_open(+level:U32,+cost:U32,room:Bool) -> U32:
  match room:
    case False{}: 0
    case True{}: U32.sub(level,cost)

def transfer(closed:Bool,+level:U32,+target_dampening:U32) -> U32:
  match closed:
    case True{}: 0
    case False{}:
      +cost = U32.max(1,target_dampening)
      transfer_open(level,cost,U32.is_gt(level,cost))

def status_count(pending:Nat) -> Status:
  match pending:
    case 0n: Stable{}
    case 1n+p: MoreWork{1n+p}

def status(state:State) -> State & Status:
  State{cells,front,back,queued,+pending} = state
  (State{cells,front,back,queued,pending},status_count(pending))

def enqueue_checked(state:State,position:C.Position,+address:String,
    checked:Set() & Bool) -> State:
  State{cells,front,back,old,pending} = state
  (queued,hit) = checked
  match hit:
    case True{}: State{cells,front,back,queued,pending}
    case False{}: State{cells,front,position <> back,Set.add(queued,address),1n+pending}

def enqueue(state:State,+position:C.Position) -> State:
  State{cells,front,back,queued,pending} = state
  +address = key(position)
  enqueue_checked(State{cells,front,back,Set.new(),pending},position,address,Set.has(queued,address))

def enqueue_neighbors(adjacent:List<&2,Neighbor>,state:State) -> State:
  match adjacent:
    case Nil{}: state
    case Neighbor{position,direction} <> rest:
      enqueue_neighbors(rest,enqueue(state,position))

def notify(state:State,+position:C.Position) -> State:
  enqueue_neighbors(neighbors(position),enqueue(state,position))

def publish_read(state:State,+position:C.Position,descriptor:Descriptor,
    read:Map<&2,Maybe<&2,Cell>> & Maybe<&2,Cell>) -> State:
  State{old,front,back,queued,pending} = state
  (cells,previous) = read
  notify(State{Map.set(&2,Maybe<&2,Cell>,cells,key(position),
    Some{Cell{descriptor,cell_level(previous)}}),front,back,queued,pending},position)

def publish_valid(valid:Bool,state:State,+position:C.Position,
    descriptor:Descriptor) -> State & Result<&2,&2,Error,Unit>:
  match valid:
    case False{}: (state,Fail{InvalidDescriptor{}})
    case True{}:
      State{cells,front,back,queued,pending} = state
      (publish_read(State{MTip{},front,back,queued,pending},position,descriptor,
        Map.get(Maybe<&2,Cell>,None{},cells,key(position))),Done{Unit{}})

def publish(state:State,position:C.Position,+descriptor:Descriptor) ->
    State & Result<&2,&2,Error,Unit>:
  publish_valid(descriptor_valid(descriptor),state,position,descriptor)

def unload(state:State,+position:C.Position) -> State:
  State{cells,front,back,queued,pending} = state
  notify(State{Map.del(&2,Maybe<&2,Cell>,cells,key(position)),front,back,queued,pending},position)

def sample_read(state:State,read:Map<&2,Maybe<&2,Cell>> & Maybe<&2,Cell>) ->
    State & Maybe<&2,U32>:
  State{old,front,back,queued,pending} = state
  (cells,cell) = read
  match cell:
    case None{}: (State{cells,front,back,queued,pending},None{})
    case Some{Cell{descriptor,level}}:
      (State{cells,front,back,queued,pending},Some{level})

# None means unknown/unloaded, rather than known darkness. While MoreWork is
# reported, Some is a provisional value from the last processed revision.
def sample(state:State,position:C.Position) -> State & Maybe<&2,U32>:
  State{cells,front,back,queued,pending} = state
  sample_read(State{MTip{},front,back,queued,pending},
    Map.get(Maybe<&2,Cell>,None{},cells,key(position)))

def pop_front(cells:Map<&2,Maybe<&2,Cell>>,front:List<&2,C.Position>,
    back:List<&2,C.Position>,queued:Set(),pending:Nat) -> State & Maybe<&2,C.Position>:
  match front:
    case Nil{}: (State{cells,[],back,queued,pending},None{})
    case +position <> rest:
      (State{cells,rest,back,Set.del(queued,key(position)),Nat.sub(pending,1n)},Some{position})

def pop(state:State) -> State & Maybe<&2,C.Position>:
  State{cells,front,back,queued,pending} = state
  match front:
    case Nil{}: pop_front(cells,List.reverse(&2,C.Position,back),[],queued,pending)
    case position <> rest: pop_front(cells,position <> rest,back,queued,pending)

# The caller supplies exact merged facing-shape occlusion for arbitrary state
# IDs. It is called with source, target and source-to-target direction.
def contribution(~Context:Data,~occludes:Context -> Descriptor -> Descriptor -> Direction -> Bool,
    context:Context,+target:Descriptor,direction:Direction,source:Maybe<&2,Cell>) -> U32:
  match source:
    case None{}: 0
    case Some{Cell{+descriptor,level}}:
      transfer(occludes(context,descriptor,target,direction),level,dampening(target))

def gather(~Context:Data,~occludes:Context -> Descriptor -> Descriptor -> Direction -> Bool,
    +context:Context,+target:Descriptor,adjacent:List<&2,Neighbor>,
    cells:Map<&2,Maybe<&2,Cell>>,best:U32) -> Map<&2,Maybe<&2,Cell>> & U32:
  match adjacent:
    case Nil{}: (cells,best)
    case Neighbor{position,direction} <> rest:
      paired(Map<&2,Maybe<&2,Cell>>,Maybe<&2,Cell>,Map<&2,Maybe<&2,Cell>> & U32,
        Map.get(Maybe<&2,Cell>,None{},cells,key(position)),cells => source =>
          gather(~Context,~occludes,context,target,rest,cells,
            U32.max(best,contribution(~Context,~occludes,context,target,opposite(direction),source))))

def update_level_choose(unchanged:Bool,state:State,+position:C.Position,
    descriptor:Descriptor,cells:Map<&2,Maybe<&2,Cell>>,level:U32) -> State:
  match unchanged:
    case True{}:
      State{unused,front,back,queued,pending} = state
      State{cells,front,back,queued,pending}
    case False{}:
      State{unused,front,back,queued,pending} = state
      enqueue_neighbors(neighbors(position),State{Map.set(&2,Maybe<&2,Cell>,cells,key(position),
        Some{Cell{descriptor,level}}),front,back,queued,pending})

def update_level(state:State,position:C.Position,descriptor:Descriptor,old:U32,
    read:Map<&2,Maybe<&2,Cell>> & U32) -> State:
  (cells,+level) = read
  update_level_choose(U32.is_eq(old,level),state,position,descriptor,cells,level)

def update_cell(~Context:Data,~occludes:Context -> Descriptor -> Descriptor -> Direction -> Bool,
    context:Context,state:State,+position:C.Position,
    read:Map<&2,Maybe<&2,Cell>> & Maybe<&2,Cell>) -> State:
  State{old,front,back,queued,pending} = state
  (cells,cell) = read
  match cell:
    case None{}: State{cells,front,back,queued,pending}
    case Some{Cell{+descriptor,level}}:
      update_level(State{MTip{},front,back,queued,pending},position,descriptor,level,
        gather(~Context,~occludes,context,descriptor,neighbors(position),cells,emission(descriptor)))

def step_position(~Context:Data,~occludes:Context -> Descriptor -> Descriptor -> Direction -> Bool,
    context:Context,state:State,position:Maybe<&2,C.Position>) -> State:
  State{cells,front,back,queued,pending} = state
  match position:
    case None{}: State{cells,front,back,queued,pending}
    case Some{+position}:
      update_cell(~Context,~occludes,context,State{MTip{},front,back,queued,pending},position,
        Map.get(Maybe<&2,Cell>,None{},cells,key(position)))

def step(~Context:Data,~occludes:Context -> Descriptor -> Descriptor -> Direction -> Bool,
    context:Context,state:State) -> State:
  paired(State,Maybe<&2,C.Position>,State,pop(state),state => position =>
    step_position(~Context,~occludes,context,state,position))

# Bounded incremental relaxation, for additions AND removals. Every open edge
# strictly attenuates; processing a changed level schedules all six consumers.
# Queue order/transient levels intentionally differ from Java's two-queue engine.
def advance(~Context:Data,~occludes:Context -> Descriptor -> Descriptor -> Direction -> Bool,
    +context:Context,budget:Nat,state:State) -> State & Status:
  match budget state:
    case 0n state: status(state)
    case 1n+remaining State{cells,front,back,queued,0n}:
      (State{cells,front,back,queued,0n},Stable{})
    case 1n+remaining State{cells,front,back,queued,1n+pending}:
      advance(~Context,~occludes,context,remaining,
        step(~Context,~occludes,context,State{cells,front,back,queued,1n+pending}))
