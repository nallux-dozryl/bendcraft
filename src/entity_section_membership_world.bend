import Base
import ./core.bend as C
import ./entity_section_membership_model.bend as M
import ./entity_section_membership.bend as Membership
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./vanilla_entity_fields.bend as V
import ./geometry.bend as A

# Physical presence is captured from the actual Core owner. Visibility is a
# separate actual chunk-manager observation: absent visibility is never mapped
# to Ticking, and physical section presence alone never implies accessibility.
def core_position(dimension:String,position:V.Vec3) -> C.Position:
  V.Vec3{x,y,z}=position
  C.Position{dimension,V.floor_word(x),V.floor_word(y),V.floor_word(z)}
def captured_visibility(+dimension:String,+point:V.Vec3,visibility:Maybe<&2,M.Visibility>) -> Result<&2,&2,T.Error,M.Chunk>:
  V.Vec3{+x,y,+z}=point
  match visibility:
    case None{}: Fail{T.Refused{"actual entity chunk visibility observation is missing"}}
    case Some{status}: Done{M.Chunk{dimension,Membership.signed_section(x),Membership.signed_section(z),True{},status}}
def observed(+dimension:String,+point:V.Vec3,+visibility:Maybe<&2,M.Visibility>,result:C.World & Result<&2,&2,C.Error,U32>) -> C.World & Result<&2,&2,T.Error,M.Chunk>:
  (world,status)=result
  match status:
    case Fail{error}: (world,Fail{T.Refused{"actual entity destination Core section is unavailable"}})
    case Done{state}: (world,captured_visibility(dimension,point,visibility))
def capture(world:C.World,+dimension:String,+point:V.Vec3,visibility:Maybe<&2,M.Visibility>) -> C.World & Result<&2,&2,T.Error,M.Chunk>:
  observed(dimension,point,visibility,C.read_block(world,core_position(dimension,point)))
def moved(+view:M.View,+original:E.Common,+registered:M.SectionKey,+proposed:T.Snapshot,+box:A.AABB,+next_order:Nat,+records:List<&2,E.Record>,result:C.World & Result<&2,&2,C.Error,U32>) -> C.World & Result<&2,&2,T.Error,M.Moved>:
  (world,status)=result
  match status:
    case Fail{error}: (world,Fail{T.Refused{"actual moved entity destination Core section is unavailable"}})
    case Done{state}: (world,Membership.on_move(view,original,registered,proposed,box,next_order,records))
def on_move(world:C.World,+view:M.View,+original:E.Common,registered:M.SectionKey,+proposed:T.Snapshot,box:A.AABB,next_order:Nat,records:List<&2,E.Record>) -> C.World & Result<&2,&2,T.Error,M.Moved>:
  T.Snapshot{+record,runtime}=proposed
  moved(view,original,registered,proposed,box,next_order,records,C.read_block(world,core_position(Membership.common_dimension(original),U.pos(record))))
def added(+view:M.View,+proposed:T.Snapshot,+box:A.AABB,+next_order:Nat,+records:List<&2,E.Record>,+created:Bool,result:C.World & Result<&2,&2,C.Error,U32>) -> C.World & Result<&2,&2,T.Error,M.Moved>:
  (world,status)=result
  match status:
    case Fail{error}: (world,Fail{T.Refused{"actual registered entity Core section is unavailable"}})
    case Done{state}: (world,Membership.on_add(view,proposed,box,next_order,records,created))
def on_add(world:C.World,view:M.View,+proposed:T.Snapshot,box:A.AABB,next_order:Nat,records:List<&2,E.Record>,created:Bool) -> C.World & Result<&2,&2,T.Error,M.Moved>:
  T.Snapshot{+record,runtime}=proposed
  added(view,proposed,box,next_order,records,created,C.read_block(world,core_position(Membership.common_dimension(E.common(record)),U.pos(record))))
