import Base
import ./block_light.bend as B
import ./core.bend as C

# Sky uses the same exact facing-shape edge law as block light. Java does not
# propagate a special zero-cost DOWN edge: level15 comes from column sources.
type Lowest is Data:
  Everywhere{}
  From{y:U32}
type Column is Data:
  Column{lowest:Lowest,enabled:Bool,min_y:U32,height:U32}
type State is Type:
  State{field:B.State,columns:Map<&2,Maybe<&2,Column>>}
type Error is Data:
  MissingColumn{position:C.Position}
  MissingCell{position:C.Position}
  InvalidDescriptor{}

def new() -> State:
  State{B.new(),MTip{}}
def signed_lt(a:U32,b:U32) -> Bool:
  U32.is_lt(U32.xor(a,2147483648),U32.xor(b,2147483648))
def signed_ge(a:U32,b:U32) -> Bool:
  Bool.not(signed_lt(a,b))
def column_key(position:C.Position) -> String:
  C.Position{dimension,x,y,z} = position
  dimension ++ "/" ++ U32.show(x) ++ "/" ++ U32.show(z)
def source_lowest(y:U32,lowest:Lowest) -> Bool:
  match lowest:
    case Everywhere{}: True{}
    case From{minimum}: signed_ge(y,minimum)
def source_y(+y:U32,column:Column) -> Bool:
  Column{lowest,enabled,+minimum,+height} = column
  enabled && signed_ge(y,minimum) && signed_lt(y,U32.add(minimum,height)) && source_lowest(y,lowest)
def source(position:C.Position,found:Maybe<&2,Column>) -> Bool:
  C.Position{dimension,x,y,z} = position
  match found:
    case None{}: False{}
    case Some{column}: source_y(y,column)
def injection(enabled:Bool) -> U32:
  match enabled:
    case False{}: 0
    case True{}: 15
def descriptor(physical:B.Descriptor,direct:Bool) -> B.Descriptor:
  B.Descriptor{state,ignored,dampening} = physical
  B.Descriptor{state,injection(direct),dampening}

# This is precisely ChunkSkyLightSources.isEdgeOccluded: target opacity OR
# upper DOWN/lower UP shape union. Actual Java tables establish its inputs.
def blocks_source(~Context:Data,~occludes:Context -> B.Descriptor -> B.Descriptor -> B.Direction -> Bool,
    +context:Context,above:B.Descriptor,+below:B.Descriptor) -> Bool:
  U32.is_gt(B.dampening(below),0) || occludes(context,above,below,B.Down{})
def set_column(state:State,+position:C.Position,column:Column) -> State:
  State{field,columns} = state
  State{field,Map.set(&2,Maybe<&2,Column>,columns,column_key(position),Some{column})}
def set_physical(state:State,+position:C.Position,physical:B.Descriptor) -> State:
  State{B.State{cells,front,back,queued,pending},columns} = state
  State{B.State{Map.set(&2,Maybe<&2,B.Cell>,cells,B.key(position),
    Some{B.Cell{descriptor(physical,False{}),0}}),front,back,queued,pending},columns}
def cell_descriptor(cell:B.Cell) -> B.Descriptor:
  B.Cell{descriptor,level} = cell
  descriptor
def physical_read(state:State,read:Map<&2,Maybe<&2,B.Cell>> & Maybe<&2,B.Cell>) -> State & Maybe<&2,B.Descriptor>:
  State{B.State{ignored,front,back,queued,pending},columns} = state
  (cells,found) = read
  (State{B.State{cells,front,back,queued,pending},columns},Maybe.map(&2,B.Cell,B.Descriptor,cell_descriptor,found))
def physical(state:State,+position:C.Position) -> State & Maybe<&2,B.Descriptor>:
  State{B.State{cells,front,back,queued,pending},columns} = state
  physical_read(State{B.State{MTip{},front,back,queued,pending},columns},
    Map.get(Maybe<&2,B.Cell>,None{},cells,B.key(position)))
def column_read(state:State,read:Map<&2,Maybe<&2,Column>> & Maybe<&2,Column>) -> State & Maybe<&2,Column>:
  State{field,ignored} = state
  (columns,found) = read
  (State{field,columns},found)
def column(state:State,+position:C.Position) -> State & Maybe<&2,Column>:
  State{field,columns} = state
  column_read(State{field,MTip{}},Map.get(Maybe<&2,Column>,None{},columns,column_key(position)))
def source_neighbor(~unused:Unit,adjacent:List<&2,B.Neighbor>,columns:Map<&2,Maybe<&2,Column>>) ->
    Map<&2,Maybe<&2,Column>> & Bool:
  match adjacent:
    case Nil{}: (columns,False{})
    case B.Neighbor{+position,direction} <> tail:
      B.paired(Map<&2,Maybe<&2,Column>>,Maybe<&2,Column>,Map<&2,Maybe<&2,Column>> & Bool,
        Map.get(Maybe<&2,Column>,None{},columns,column_key(position)),columns => found =>
        B.paired(Map<&2,Maybe<&2,Column>>,Bool,Map<&2,Maybe<&2,Column>> & Bool,
          source_neighbor(~Unit{},tail,columns),columns => rest => (columns,source(position,found) || rest)))
def initial_notify(needs:Bool,field:B.State,position:C.Position) -> B.State:
  match needs:
    case False{}: field
    case True{}: B.enqueue(field,position)

# Initialization establishes all direct sources simultaneously. Only dark
# cells beside a source enter the FIFO; changed dark levels schedule consumers.
def seed_read(state:State,+position:C.Position,+direct:Bool,
    read:Map<&2,Maybe<&2,B.Cell>> & Maybe<&2,B.Cell>) -> State:
  State{B.State{ignored,front,back,queued,pending},columns} = state
  (cells,found) = read
  match found:
    case None{}: State{B.State{cells,front,back,queued,pending},columns}
    case Some{B.Cell{physical,old}}:
      B.paired(Map<&2,Maybe<&2,Column>>,Bool,State,source_neighbor(~Unit{},B.neighbors(position),columns),
        columns => adjacent_source => State{initial_notify(Bool.not(direct) && adjacent_source,
        B.State{Map.set(&2,Maybe<&2,B.Cell>,cells,B.key(position),
          Some{B.Cell{descriptor(physical,direct),injection(direct)}}),front,back,queued,pending},position),columns})
def seed_column(state:State,+position:C.Position,found:Maybe<&2,Column>) -> State:
  State{B.State{cells,front,back,queued,pending},columns} = state
  seed_read(State{B.State{MTip{},front,back,queued,pending},columns},position,source(position,found),
    Map.get(Maybe<&2,B.Cell>,None{},cells,B.key(position)))
def seed(state:State,+position:C.Position) -> State:
  B.paired(State,Maybe<&2,Column>,State,column(state,position),state => found => seed_column(state,position,found))
def published(state:State,result:B.State & Result<&2,&2,B.Error,Unit>) -> State:
  State{ignored,columns} = state
  (field,status) = result
  State{field,columns}

# Edits are published only after the sole Core owner accepted them. Source
# threshold changes republish the affected complete vertical column.
def publish_found(state:State,+position:C.Position,physical:B.Descriptor,found:Maybe<&2,Column>) -> State & Result<&2,&2,Error,Unit>:
  State{field,columns} = state
  match found:
    case None{}: (State{field,columns},Fail{MissingColumn{position}})
    case Some{column}:
      B.paired(B.State,Result<&2,&2,B.Error,Unit>,State & Result<&2,&2,Error,Unit>,
        B.publish(field,position,descriptor(physical,source(position,Some{column}))),
        field => status => (State{field,columns},Done{Unit{}}))
def publish_valid(valid:Bool,state:State,+position:C.Position,physical:B.Descriptor) -> State & Result<&2,&2,Error,Unit>:
  match valid:
    case False{}: (state,Fail{InvalidDescriptor{}})
    case True{}:
      B.paired(State,Maybe<&2,Column>,State & Result<&2,&2,Error,Unit>,column(state,position),
        state => found => publish_found(state,position,physical,found))
def publish(state:State,position:C.Position,+physical:B.Descriptor) -> State & Result<&2,&2,Error,Unit>:
  publish_valid(B.descriptor_valid(physical),state,position,physical)
def resource_found(state:State,position:C.Position,found:Maybe<&2,B.Descriptor>) -> State & Result<&2,&2,Error,Unit>:
  match found:
    case None{}: (state,Fail{MissingCell{position}})
    case Some{physical}: publish(state,position,physical)
def resource(state:State,+position:C.Position) -> State & Result<&2,&2,Error,Unit>:
  B.paired(State,Maybe<&2,B.Descriptor>,State & Result<&2,&2,Error,Unit>,physical(state,position),
    state => found => resource_found(state,position,found))
def sample(state:State,position:C.Position) -> State & Maybe<&2,U32>:
  State{field,columns} = state
  B.paired(B.State,Maybe<&2,U32>,State & Maybe<&2,U32>,B.sample(field,position),
    field => level => (State{field,columns},level))
def status(state:State) -> State & B.Status:
  State{field,columns} = state
  B.paired(B.State,B.Status,State & B.Status,B.status(field),field => status => (State{field,columns},status))
def advance(~Context:Data,~occludes:Context -> B.Descriptor -> B.Descriptor -> B.Direction -> Bool,
    context:Context,budget:Nat,state:State) -> State & B.Status:
  State{field,columns} = state
  B.paired(B.State,B.Status,State & B.Status,B.advance(~Context,~occludes,context,budget,field),
    field => status => (State{field,columns},status))
