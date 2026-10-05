import Base
import ./client_render.bend as R
import ./mesh_render.bend as M
import ./resource_catalog_world.bend as CW
import ./resource_block_catalog.bend as C
import ./item_entity_render_resources.bend as IR
import ./item_entity_render_model.bend as D
import ./entity_scene_render_model.bend as A

def ground_valid(value:D.Ground,count:U32) -> Bool:
  D.Ground{key,seed,quads,low,high,block} = value
  String.is_empty(M.quads_error(quads,count,0,0))
def grounds_valid(values:List<&2,D.Ground>,+count:U32) -> Bool:
  match values:
    case Nil{}: True{}
    case head <> rest: ground_valid(head,count) && grounds_valid(rest,count)
def orb_valid(value:Maybe<&2,U32>,count:U32) -> Bool:
  match value:
    case None{}: True{}
    case Some{slot}: U32.is_lt(slot,count)
def join_valid(world:CW.Assets,entities:IR.Assets) -> (CW.Assets & IR.Assets) & Bool:
  CW.Assets{R.Assets{+world_images},+catalog,+wc} = world
  IR.Assets{R.Assets{+item_images},+items} = entities
  D.Catalog{grounds,+ec,orb} = items
  ( (CW.Assets{R.Assets{world_images},catalog,wc},IR.Assets{R.Assets{item_images},items}),
    Nat.is_eq(List.length(&2,R.Texture,world_images),U32.to_nat(wc)) &&
    Nat.is_eq(List.length(&2,R.Texture,item_images),U32.to_nat(ec)) &&
    U32.is_le(ec,U32.sub(4294967295,wc)) && M.textures_valid(world_images) &&
    M.textures_valid(item_images) && grounds_valid(grounds,ec) && orb_valid(orb,ec))
def assemble(world:CW.Assets,entities:IR.Assets) -> A.Assets:
  CW.Assets{R.Assets{+world_images},catalog,wc} = world
  IR.Assets{R.Assets{item_images},+items} = entities
  D.Catalog{grounds,ec,orb} = items
  A.Assets{R.Assets{List.append(&2,R.Texture,world_images,item_images)},catalog,wc,
    List.length(&2,R.Texture,world_images),items,ec}
def admitted(valid:Bool,world:CW.Assets,entities:IR.Assets) -> A.Join:
  match valid:
    case False{}: A.Rejected{world,entities,A.Refused{"scene:invalid physical texture domain"}}
    case True{}: A.Joined{assemble(world,entities)}
def checked(value:(CW.Assets & IR.Assets) & Bool) -> A.Join:
  ((world,entities),valid) = value
  admitted(valid,world,entities)
def join(world:CW.Assets,entities:IR.Assets) -> A.Join:
  checked(join_valid(world,entities))

def prepend(head:R.Texture,value:List<&2,R.Texture> & List<&2,R.Texture>) -> List<&2,R.Texture> & List<&2,R.Texture>:
  (prefix,suffix) = value
  (head <> prefix,suffix)
def split_images(prefix:Nat,values:List<&2,R.Texture>) -> List<&2,R.Texture> & List<&2,R.Texture>:
  match prefix:
    case 0n: ([],values)
    case 1n+rest:
      match values:
        case Nil{}: ([],[])
        case head <> tail: prepend(head,split_images(rest,tail))
def split_ready(value:List<&2,R.Texture> & List<&2,R.Texture>,world:C.Catalog,wc:U32,entities:D.Catalog) -> CW.Assets & IR.Assets:
  (world_images,item_images) = value
  (CW.Assets{R.Assets{world_images},world,wc},IR.Assets{R.Assets{item_images},entities})
# Demand reload can temporarily recover the exact original owners. Every join
# recomputes its prefix; an old rebasing offset is never reused after replacement.
def split(assets:A.Assets) -> CW.Assets & IR.Assets:
  A.Assets{R.Assets{images},world,wc,prefix,entities,ec} = assets
  split_ready(split_images(prefix,images),world,wc,entities)
