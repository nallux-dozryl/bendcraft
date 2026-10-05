import Base
import ./entity_scene_render_laws.bend as L
import ./entity_scene_render_assets.bend as Assets
import ./entity_scene_render_model.bend as A
import ./client_render.bend as R
import ./resource_catalog_world.bend as CW
import ./item_entity_render_resources.bend as IR
import ./resource_block_catalog.bend as C
import ./item_entity_render_model.bend as D

def L.texture_prefix_split_is_exact(prefix,suffix):
  match prefix:
    case Nil{}: {==}
    case head <> tail:
      %Equal.sym(List<&2,R.Texture> & List<&2,R.Texture>,Assets.split_images(List.length(&2,R.Texture,tail),List.append(&2,R.Texture,tail,suffix)),(tail,suffix),L.texture_prefix_split_is_exact(tail,suffix)) :
        {Assets.prepend(head,_) == (head <> tail,suffix) : List<&2,R.Texture> & List<&2,R.Texture>}
      {==}

def L.joined_owner_can_recover_both_complete_original_owners(world_images,item_images,world,wc,items):
  match items:
    case D.Catalog{grounds,ec,orb}:
      %Equal.sym(List<&2,R.Texture> & List<&2,R.Texture>,Assets.split_images(List.length(&2,R.Texture,world_images),List.append(&2,R.Texture,world_images,item_images)),(world_images,item_images),L.texture_prefix_split_is_exact(world_images,item_images)) :
        {Assets.split_ready(_,world,wc,D.Catalog{grounds,ec,orb}) == (CW.Assets{R.Assets{world_images},world,wc},IR.Assets{R.Assets{item_images},D.Catalog{grounds,ec,orb}}) : CW.Assets & IR.Assets}
      {==}
