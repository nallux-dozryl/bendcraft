import Base
import ./inventory.bend as I
import ./mesh_render.bend as M
import ./block_model.bend as B
import ./block_bake.bend as K
import ./vanilla_entity_fields.bend as V
import ./cooking_effect_entities_model.bend as E

# Narrow presentation publication. It carries no simulation RNG/UUID/factory,
# inventory owner, health, pickup timers or entropy tickets.
type Common is Data:
  Common{dimension:String,id:U32,current:V.Vec3,old:V.Vec3,tick_count:U32,
    removed:Bool,accessible:Bool,source_order:Nat}
type Record is Data:
  Item{common:Common,item:I.Slot,bob:F32}
  Orb{common:Common,value:U32}
type Snapshot is Data:
  Unbound{}
  Bound{records:List<&2,Record>}

# Ground quads have the actual resource ground display transform applied once.
# The initialized registry/key authority is established by the resource loader.
type Ground is Data:
  Ground{key:I.ItemKey,seed:U32,quads:List<&2,M.Quad>,low:M.Vec3,high:M.Vec3,block_light:Bool}
type Catalog is Data:
  Catalog{items:List<&2,Ground>,texture_count:U32,orb_texture:Maybe<&2,U32>}
type Quaternion is Data:
  Quaternion{x:F32,y:F32,z:F32,w:F32}
type Light is Data:
  Light{id:U32,block:U32,sky:U32,item_rgb:U32,orb_rgb:U32}
type Context is Data:
  Context{dimension:String,camera_origin:V.Vec3,partial:F32,billboard:Quaternion,
    catalog:Catalog,lights:List<&2,Light>,scan_budget:Nat,quad_budget:Nat}
type ItemInput is Data:
  ItemInput{ground:Ground,light:Light}
type OrbInput is Data:
  OrbInput{texture:U32,light:Light}
type Draw is Data:
  ItemDraw{id:U32,key:I.ItemKey,age_in_ticks:F32,origin:M.Vec3,hover:F32,spin:F32,
    copies:List<&2,M.Vec3>,packed_light:U32,block_light:Bool,quads:List<&2,M.Quad>}
  OrbDraw{id:U32,age_in_ticks:F32,origin:M.Vec3,icon:U32,packed_light:U32,color:U32,quad:M.Quad}
type Frame is Data:
  Frame{draws:List<&2,Draw>,quads:List<&2,M.Quad>}
type Error is Data:
  Refused{message:String}
  ScanBudget{}
  QuadBudget{}

def guard(valid:Bool,message:String) -> Result<&2,&2,Error,Unit>:
  match valid:
    case False{}: Fail{Refused{message}}
    case True{}: Done{Unit{}}
def converted(-A:Data,value:Result<&2,&2,String,A>) -> Result<&2,&2,Error,A>:
  match value:
    case Fail{message}: Fail{Refused{message}}
    case Done{answer}: Done{answer}
def matrix(q:Quaternion) -> K.Mat:
  Quaternion{x,y,z,w} = q
  K.quaternion(x,y,z,w)
def packed(block:U32,sky:U32) -> U32:
  U32.or(U32.shln(block,4n),U32.shln(sky,20n))
def key_equal(a:I.ItemKey,b:I.ItemKey) -> Bool: I.key_equal(a,b)
def ground_chosen(found:Bool,head:Ground,next:Maybe<&2,Ground>) -> Maybe<&2,Ground>:
  match found:
    case False{}: next
    case True{}: Some{head}
def ground(values:List<&2,Ground>,+key:I.ItemKey) -> Maybe<&2,Ground>:
  match values:
    case Nil{}: None{}
    case +head <> rest:
      Ground{actual,seed,quads,low,high,light} = head
      ground_chosen(key_equal(actual,key),head,ground(rest,key))
def light_chosen(found:Bool,head:Light,next:Maybe<&2,Light>) -> Maybe<&2,Light>:
  match found:
    case False{}: next
    case True{}: Some{head}
def light(values:List<&2,Light>,+id:U32) -> Maybe<&2,Light>:
  match values:
    case Nil{}: None{}
    case +head <> rest:
      Light{actual,b,s,i,o} = head
      light_chosen(U32.is_eq(actual,id),head,light(rest,id))
def required_ground(value:Maybe<&2,Ground>) -> Result<&2,&2,Error,Ground>:
  match value:
    case None{}: Fail{Refused{"render:exact initialized item ground model not loaded"}}
    case Some{answer}: Done{answer}
def required_light(value:Maybe<&2,Light>) -> Result<&2,&2,Error,Light>:
  match value:
    case None{}: Fail{Refused{"render:settled block/sky light and lightmap sample required"}}
    case Some{+answer}:
      Light{id,b,s,i,o} = answer
      do Result<&2,&2,Error,Light>:
        guard(U32.is_le(b,15) && U32.is_le(s,15),"render:light levels outside0..15")
        return answer

def render_fields(fields:V.Fields,dimension:String,id:U32,tick:U32,removed:Bool,accessible:Bool,order:Nat) -> Common:
  V.Fields{current,velocity,position_o,old_position,look,head,body,fall,ground,air,fire,portal,invulnerable,needs_sync} = fields
  Common{dimension,id,current,old_position,tick,removed,accessible,order}
def render_common(common:E.Common) -> Common:
  E.Common{dimension,id,most,least,random,fields,tick,first,removed,accessible,order} = common
  render_fields(fields,dimension,id,tick,removed,accessible,order)
def render_record(record:E.Record) -> Record:
  match record:
    case E.Item{base,item,age,delay,health,thrower,target,bob}: Item{render_common(base),item,bob}
    case E.Orb{base,value,age,health,count,following}: Orb{render_common(base),value}
def render_records(values:List<&2,E.Record>) -> List<&2,Record>:
  match values:
    case Nil{}: []
    case head <> rest: render_record(head) <> render_records(rest)
def render_snapshot(view:E.View) -> Snapshot:
  E.View{level,seed,cursor,order,values} = view
  Bound{render_records(values)}
