import Base
import ./client_render.bend as R
import ./mesh_render.bend as M
import ./world_mesh.bend as WM
import ./resource_block_catalog.bend as C
import ./resource_catalog_world.bend as CW
import ./item_entity_render_model.bend as D
import ./item_entity_render_resources.bend as IR
import ./remote_entity_snapshot_wire.bend as Wire

# One physical texture owner. World slots occupy the prefix, item/orb slots
# occupy the suffix. Catalogs remain immutable and retain their original slots.
type Assets is Type:
  Assets{resources:R.Assets,world:C.Catalog,world_count:U32,world_prefix:Nat,
    entities:D.Catalog,entity_count:U32}
type Join is Type:
  Joined{assets:Assets}
  Rejected{world:CW.Assets,entities:IR.Assets,error:Error}
type Error is Data:
  Refused{message:String}
type WorldLight is Data:
  WorldLight{state:U32,block:U32,sky:U32,rgb:U32}
type Lighting is Data:
  Missing{reason:String}
  Stable{stamp:Wire.Stamp,cells:Map<&2,Maybe<&2,WorldLight>>,entities:List<&2,D.Light>}
type Context is Data:
  Context{stamp:Wire.Stamp,lighting:Lighting,render:WM.Frame,limits:WM.Limits,
    entity_scan:Nat,entity_quads:Nat}
type Prepared is Data:
  Prepared{stamp:Wire.Stamp,scene:M.Scene,entities:D.Frame}

def guard(valid:Bool,message:String) -> Result<&2,&2,Error,Unit>:
  match valid:
    case False{}: Fail{Refused{message}}
    case True{}: Done{Unit{}}
def count(value:Assets) -> Assets & U32:
  Assets{resources,world,+wc,+prefix,entities,+ec} = value
  (Assets{resources,world,wc,prefix,entities,ec},U32.add(wc,ec))
