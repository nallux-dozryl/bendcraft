import Base
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./geometry.bend as A

# PersistentEntitySectionManager authority. No entity/random/runtime owner lives
# here: the sole E.State stays in the actual scene transaction.
type SectionKey is Data:
  SectionKey{x:U32,y:U32,z:U32}
type Visibility is Data:
  Hidden{}
  Tracked{}
  Ticking{}
type Chunk is Data:
  Chunk{dimension:String,x:U32,z:U32,loaded:Bool,visibility:Visibility}
type Member is Data:
  Member{dimension:String,id:U32,key:SectionKey,order:Nat,box:A.AABB,uuid:E.Uuid}
type Section is Data:
  Section{dimension:String,key:SectionKey,visibility:Visibility,ids:List<&2,U32>}
type Registration is Data:
  Registration{dimension:String,id:U32}
type View is Data:
  View{members:List<&2,Member>,sections:List<&2,Section>,chunks:List<&2,Chunk>,tracked:List<&2,Registration>,ticked:List<&2,Registration>}
type State is Type:
  State{view:View}
type CallbackEvent is Data:
  SectionCreated{dimension:String,key:SectionKey,visibility:Visibility}
  SectionDeleted{dimension:String,key:SectionKey}
  Inserted{dimension:String,id:U32,key:SectionKey,order:Nat}
  Detached{dimension:String,id:U32,key:SectionKey}
  Created{dimension:String,id:U32}
  TrackingStart{dimension:String,id:U32}
  TrackingEnd{dimension:String,id:U32}
  TickingStart{dimension:String,id:U32}
  TickingEnd{dimension:String,id:U32}
  SectionChange{dimension:String,id:U32}
  Destroyed{dimension:String,id:U32}
type Proposal is Data:
  Proposal{view:View,next_section_order:Nat,records:List<&2,E.Record>,journal:List<&2,CallbackEvent>}
type Moved is Data:
  Moved{snapshot:T.Snapshot,proposal:Proposal}
type Located is Data:
  Located{member:Member,section:Section}
type Destination is Data:
  Destination{section:Section,created:Bool}
type ChunkChanged is Data:
  ChunkChanged{sections:List<&2,Section>,records:List<&2,E.Record>,journal:List<&2,CallbackEvent>}
