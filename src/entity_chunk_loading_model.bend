import Base

# A transient actual-loader owner. These identifiers are Bend callback guards;
# Java's manager does not contain a world epoch or a request counter.
type Word64 is Data:
  Word64{hi:U32,lo:U32}
type Scope is Data:
  Scope{world:String,dimension:String,epoch:Word64}
type ChunkKey is Data:
  ChunkKey{x:U32,z:U32}
type FullStatus is Data:
  Inaccessible{}
  Full{}
  BlockTicking{}
  EntityTicking{}
type Visibility is Data:
  Hidden{}
  Tracked{}
  Ticking{}
type TicketType is Data:
  TicketType{identity:String,timeout:Word64,flags:U32}
type Ticket is Data:
  Ticket{kind:TicketType,level:U32,ticks_left:Word64}
type Bucket is Data:
  Bucket{key:ChunkKey,tickets:List<&2,Ticket>}
type Channel is Data:
  Loading{}
  Simulation{}
type HolderReadiness is Data:
  AbsentHolder{}
  NotReadyForSaving{}
  ReadyForSaving{}
type Promotion is Data:
  Promotion{request:Word64,status:FullStatus}
type EntityPhase is Data:
  Fresh{}
  Pending{request:Word64}
  Inbox{request:Word64,artifact:String}
  Loaded{request:Word64,artifact:String}
type Chunk is Data:
  Chunk{key:ChunkKey,level:U32,confirmed:FullStatus,full_loaded:Bool,
    promotion:Maybe<&2,Promotion>,entities:EntityPhase,holder:Maybe<&2,HolderReadiness>}
type Context is Data:
  Context{scope:Scope,ticket_types:List<&2,TicketType>,maximum_loading_level:U32}
type Receipt is Data:
  Receipt{scope:Scope,key:ChunkKey,request:Word64}
type FullCompletion is Data:
  FullCompletion{receipt:Receipt,status:FullStatus}
type EntityBatch is Data:
  EntityBatch{receipt:Receipt,artifact:String}
type LoaderEvent is Data:
  SourceLevelChanged{key:ChunkKey,channel:Channel,level:U32,decrease:Bool}
  PromotionRequested{receipt:Receipt,status:FullStatus}
  PromotionCancelled{receipt:Receipt}
  StatusChanged{key:ChunkKey,previous:FullStatus,current:FullStatus}
  EntitiesRequested{receipt:Receipt}
  EntitiesAvailable{batch:EntityBatch}
  EntitiesInserted{batch:EntityBatch}
  EntityReadFailed{receipt:Receipt,message:String}
  EntitiesUnloaded{batch:EntityBatch}
type View is Data:
  View{context:Context,active:List<&2,Bucket>,inactive:List<&2,Bucket>,
    chunks:List<&2,Chunk>,next_request:Word64,journal:List<&2,LoaderEvent>}
type State is Type:
  Unavailable{scope:Scope,reason:String}
  State{view:View}
type TicketsChanged is Data:
  TicketsChanged{tickets:List<&2,Ticket>,changed:Bool,loading_removed:Bool,simulation_removed:Bool}
