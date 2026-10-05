import Base
import ./vanilla_lightmap_model.bend as M

def finite(value:F32) -> Bool:
  U32.is_lt(U32.and(F32.bits(value),2139095040),2139095040)
def color_finite(value:M.Color) -> Bool:
  M.Color{r,g,b}=value
  finite(r) && finite(g) && finite(b)
def uniforms_finite(value:M.Uniforms) -> Bool:
  M.Uniforms{s,b,n,d,o,g,bt,sc,a,nc}=value
  finite(s) && finite(b) && finite(n) && finite(d) && finite(o) && finite(g) && color_finite(bt) && color_finite(sc) && color_finite(a) && color_finite(nc)
def add(a:M.Color,b:M.Color) -> M.Color:
  M.Color{ar,ag,ab}=a
  M.Color{br,bg,bb}=b
  M.Color{F32.add(ar,br),F32.add(ag,bg),F32.add(ab,bb)}
def scale(value:M.Color,+factor:F32) -> M.Color:
  M.Color{r,g,b}=value
  M.Color{F32.mul(r,factor),F32.mul(g,factor),F32.mul(b,factor)}
def maximum(a:M.Color,b:M.Color) -> M.Color:
  M.Color{ar,ag,ab}=a
  M.Color{br,bg,bb}=b
  M.Color{F32.max(ar,br),F32.max(ag,bg),F32.max(ab,bb)}
# GLSL mix is x*(1-a)+y*a, distinct from Java Mth.lerp's x+a*(y-x).
def mix(a:M.Color,b:M.Color,+factor:F32) -> M.Color:
  add(scale(a,F32.sub(1.0,factor)),scale(b,factor))
def clamp(value:M.Color) -> M.Color:
  M.Color{r,g,b}=value
  M.Color{F32.clamp(r,0.0,1.0),F32.clamp(g,0.0,1.0),F32.clamp(b,0.0,1.0)}
def largest(value:M.Color) -> F32:
  M.Color{r,g,b}=value
  F32.max(F32.max(r,g),b)
def coordinate(level:U32) -> F32: F32.div(F32.from_nat(U32.to_nat(level)),15.0)
def brightness(+level:F32) -> F32: F32.div(level,F32.sub(4.0,F32.mul(3.0,level)))
def parabolic(+level:F32) -> F32:
  +p=F32.sub(F32.mul(2.0,level),1.0)
  F32.mul(p,p)
def not_gamma(+color:M.Color) -> M.Color:
  +maximum=largest(color)
  +inverse=F32.sub(1.0,maximum)
  +power=F32.mul(F32.mul(F32.mul(inverse,inverse),inverse),inverse)
  scale(color,F32.div(F32.sub(1.0,power),maximum))
def multiply(a:M.Color,b:M.Color) -> M.Color:
  M.Color{ar,ag,ab}=a
  M.Color{br,bg,bb}=b
  M.Color{F32.mul(ar,br),F32.mul(ag,bg),F32.mul(ab,bb)}
def pre_gamma(u:M.Uniforms,+block:U32,sky:U32) -> M.Color:
  M.Uniforms{sf,bf,nv,+dark,boss,gamma,bt,sc,ambient,nc}=u
  +color=add(add(maximum(ambient,scale(nc,nv)),scale(sc,F32.mul(brightness(coordinate(sky)),sf))),scale(mix(bt,M.white(),F32.mul(0.9,parabolic(coordinate(block)))),F32.mul(brightness(coordinate(block)),bf)))
  +darkened=mix(color,multiply(color,M.Color{0.7,0.6,0.6}),boss)
  clamp(add(darkened,M.Color{F32.sub(0.0,dark),F32.sub(0.0,dark),F32.sub(0.0,dark)}))
def gamma(value:M.Uniforms,+color:M.Color) -> M.Color:
  M.Uniforms{s,b,n,d,o,g,bt,sc,a,nc}=value
  mix(color,not_gamma(color),g)
def nonblack(admitted:Bool,uniforms:M.Uniforms,color:M.Color) -> Result<&2,&2,M.Error,M.Color>:
  match admitted:
    case False{}: Fail{M.Refused{"lightmap: shader notGamma has undefined zero division at black"}}
    case True{}: Done{gamma(uniforms,color)}
def shader_ready(+u:M.Uniforms,block:U32,sky:U32) -> Result<&2,&2,M.Error,M.Color>:
  +color=pre_gamma(u,block,sky)
  nonblack(F32.is_gt(largest(color),0.0),u,color)
def pixel_gate(valid:Bool,u:M.Uniforms,block:U32,sky:U32) -> Result<&2,&2,M.Error,M.Color>:
  match valid:
    case False{}: Fail{M.Refused{"lightmap: nonfinite uniforms or coordinate outside 0..15"}}
    case True{}: shader_ready(u,block,sky)
def pixel(+u:M.Uniforms,+block:U32,+sky:U32) -> Result<&2,&2,M.Error,M.Color>:
  pixel_gate(uniforms_finite(u) && U32.is_lt(block,16) && U32.is_lt(sky,16),u,block,sky)
# Explicit CPU RGBA8_UNORM nearest quantization. Raw F32 shader output remains
# available above; this is not a claim of identical GPU rounding/FMA behavior.
def channel(value:F32) -> U32:
  F32.to_u32(F32.add(F32.mul(F32.clamp(value,0.0,1.0),255.0),0.5))
def argb(value:M.Color) -> U32:
  M.Color{r,g,b}=value
  U32.or(4278190080,U32.or(U32.shln(channel(r),16n),U32.or(U32.shln(channel(g),8n),channel(b))))
def argb_result(value:Result<&2,&2,M.Error,M.Color>) -> Result<&2,&2,M.Error,U32>:
  match value:
    case Fail{error}: Fail{error}
    case Done{color}: Done{argb(color)}
def storage_gamma(color:M.Color,finite:Bool) -> Result<&2,&2,M.Error,U32>:
  match finite:
    case False{}: Fail{M.Refused{"lightmap: nonfinite shader result cannot be quantized"}}
    case True{}: Done{argb(color)}
def storage_nonblack(+color:M.Color) -> Result<&2,&2,M.Error,U32>:
  storage_gamma(color,color_finite(color))
def storage_color(black:Bool,u:M.Uniforms,color:M.Color) -> Result<&2,&2,M.Error,U32>:
  match black:
    # Observed actual installed shader on Apple M3 Pro CGL RGBA8_UNORM: NaN
    # components at black become zero bytes. The raw pixel API still refuses
    # this shader's undefined division; storage conversion is a named boundary.
    case True{}: Done{4278190080}
    case False{}: storage_nonblack(gamma(u,color))
def storage_ready(+u:M.Uniforms,block:U32,sky:U32) -> Result<&2,&2,M.Error,U32>:
  +color=pre_gamma(u,block,sky)
  storage_color(F32.is_eq(largest(color),0.0),u,color)
def storage_gate(valid:Bool,u:M.Uniforms,block:U32,sky:U32) -> Result<&2,&2,M.Error,U32>:
  match valid:
    case False{}: Fail{M.Refused{"lightmap: nonfinite uniforms or coordinate outside 0..15"}}
    case True{}: storage_ready(u,block,sky)
def storage_pixel(+u:M.Uniforms,+block:U32,+sky:U32) -> Result<&2,&2,M.Error,U32>:
  storage_gate(uniforms_finite(u) && U32.is_lt(block,16) && U32.is_lt(sky,16),u,block,sky)
def texture_pixel(texture:M.Texture,block:U32,sky:U32) -> Result<&2,&2,M.Error,U32>:
  match texture:
    case M.InitialWhite{}: Done{4294967295}
    case M.Evaluated{uniforms}: storage_pixel(uniforms,block,sky)
