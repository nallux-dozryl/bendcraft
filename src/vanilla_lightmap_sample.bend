import Base
import ./vanilla_lightmap_model.bend as M
import ./vanilla_lightmap_eval.bend as E

# sample_lightmap.glsl: uv/256 + half a texel, clamp to texel centers.
# RenderSetup binds its lightmap with LINEAR clamp-to-edge. Fractional AO
# coordinates are retained: interpolating integer levels first is incorrect.
def normalized(value:U32) -> F32: F32.div(F32.from_nat(U32.to_nat(value)),255.0)
def color(+argb:U32) -> M.Color:
  M.Color{normalized(U32.and(U32.shrn(argb,16n),255)),normalized(U32.and(U32.shrn(argb,8n),255)),normalized(U32.and(argb,255))}
def weight(coord:U32) -> F32:
  F32.div(F32.from_nat(U32.to_nat(U32.mod(coord,16))),16.0)
def sample_ready(+texture:M.Texture,+block:U32,+sky:U32) -> Result<&2,&2,M.Error,M.Color>:
  +x=U32.div(block,16)
  +y=U32.div(sky,16)
  +right=U32.min(U32.add(x,1),15)
  +top=U32.min(U32.add(y,1),15)
  do Result<&2,&2,M.Error,M.Color>:
    a : U32 <- E.texture_pixel(texture,x,y)
    b : U32 <- E.texture_pixel(texture,right,y)
    c : U32 <- E.texture_pixel(texture,x,top)
    d : U32 <- E.texture_pixel(texture,right,top)
    return E.mix(E.mix(color(a),color(b),weight(block)),E.mix(color(c),color(d),weight(block)),weight(sky))
def sample(texture:M.Texture,block_coord:U32,sky_coord:U32) -> Result<&2,&2,M.Error,M.Color>:
  sample_ready(texture,U32.min(block_coord,240),U32.min(sky_coord,240))
def sample_packed(texture:M.Texture,+packed:U32) -> Result<&2,&2,M.Error,M.Color>:
  sample(texture,U32.and(packed,65535),U32.shrn(packed,16n))
def sample_argb(texture:M.Texture,packed:U32) -> Result<&2,&2,M.Error,U32>:
  E.argb_result(sample_packed(texture,packed))
