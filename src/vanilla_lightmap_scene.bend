import Base
import ./vanilla_lightmap_model.bend as M
import ./vanilla_lightmap_eval.bend as E
import ./vanilla_lightmap_sample.bend as S
import ./entity_scene_render_model.bend as Scene
import ./item_entity_render_model.bend as Item

# Live publication must match the original Core light stamp and this renderer
# context. This adapter computes RGB; it does not invent block/sky observations
# or certify a caller's stamp. Entity light is sampled at its actual light probe.
def entity(+texture:M.Texture,id:U32,+block:U32,+sky:U32) -> Result<&2,&2,M.Error,Item.Light>:
  do Result<&2,&2,M.Error,Item.Light>:
    item : U32 <- E.texture_pixel(texture,block,sky)
    orb : U32 <- E.texture_pixel(texture,U32.min(U32.add(block,7),15),sky)
    return Item.Light{id,block,sky,item,orb}
# Existing flat material compatibility. Use a real face light sample here,
# never the opaque block's own zero-light center for an exposed face.
def world(texture:M.Texture,state:U32,+block:U32,+sky:U32) -> Result<&2,&2,M.Error,Scene.WorldLight>:
  do Result<&2,&2,M.Error,Scene.WorldLight>:
    rgb : U32 <- E.texture_pixel(texture,block,sky)
    return Scene.WorldLight{state,block,sky,rgb}
# Exact AO packed coordinates retain sub-level bits and LINEAR sampling. The
# actual model lighter supplies each vertex's packed coordinate and shade;
# renderer integration must retain these per-vertex values until interpolation.
def vertex(texture:M.Texture,packed:U32) -> Result<&2,&2,M.Error,M.Color>:
  S.sample_packed(texture,packed)
