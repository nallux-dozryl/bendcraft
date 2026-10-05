import Base
import ./vanilla_block_lighting_model.bend as M

def choose(~A:Data,yes:A,no:A,value:Bool) -> A:
  match value:
    case True{}: yes
    case False{}: no
def finite(value:F32) -> Bool: U32.is_lt(U32.and(F32.bits(value),2139095040),2139095040)
def unit(+value:F32) -> Bool: finite(value) && F32.is_ge(value,0.0) && F32.is_le(value,1.0)
def word(value:U32) -> F32:
  U32{bits}=value
  F32{bits}
def float(value:U32) -> F32: F32.from_nat(U32.to_nat(value))
def int_small(+value:F32,negative:Bool) -> U32:
  match negative:
    case True{}: U32.sub(0,F32.to_u32(F32.sub(0.0,value)))
    case False{}: F32.to_u32(value)
def int_finite(+value:F32,large:Bool) -> U32:
  match large:
    case True{}: choose(U32,2147483648,2147483647,F32.is_lt(value,0.0))
    case False{}: int_small(value,F32.is_lt(value,0.0))
def int_nan(+value:F32,nan:Bool) -> U32:
  match nan:
    case True{}: 0
    case False{}: int_finite(value,F32.is_ge(F32.abs(value),2147483648.0))
def java_int(+value:F32) -> U32: int_nan(value,Bool.not(F32.is_eq(value,value)))
def pack(block:U32,sky:U32) -> U32: U32.or(U32.shln(block,4n),U32.shln(sky,20n))
def block(value:U32) -> U32: U32.and(U32.shrn(value,4n),15)
def sky(value:U32) -> U32: U32.and(U32.shrn(value,20n),15)
def smooth_block(value:U32) -> U32: U32.and(value,255)
def smooth_sky(value:U32) -> U32: U32.and(U32.shrn(value,16n),255)
def smooth_pack(block:U32,sky:U32) -> U32: U32.or(U32.and(block,255),U32.shln(U32.and(sky,255),16n))
def fallback(+value:U32,+center:U32) -> U32:
  choose(U32,center,choose(U32,U32.or(value,U32.and(center,16711680)),value,U32.is_eq(sky(value),0)),U32.is_eq(value,0))
def blend_ready(a:U32,b:U32,c:U32,d:U32) -> U32:
  U32.and(U32.shrn(U32.add(U32.add(U32.add(a,b),c),d),2n),16711935)
def blend_gate(+a:U32,+b:U32,+c:U32,+d:U32,bright:Bool) -> U32:
  match bright:
    case False{}: blend_ready(a,b,c,d)
    case True{}: blend_ready(fallback(a,d),fallback(b,d),fallback(c,d),d)
def blend(+a:U32,+b:U32,+c:U32,+d:U32) -> U32: blend_gate(a,b,c,d,U32.is_gt(sky(d),2) || U32.is_gt(block(d),2))
def weighted(a:F32,b:F32,c:F32,d:F32,w:M.Weights) -> F32:
  M.Weights{x,y,z,t}=w
  F32.add(F32.add(F32.add(F32.mul(a,x),F32.mul(b,y)),F32.mul(c,z)),F32.mul(d,t))
def weighted_light(+a:U32,+b:U32,+c:U32,+d:U32,+weights:M.Weights) -> U32:
  smooth_pack(java_int(weighted(float(smooth_block(a)),float(smooth_block(b)),float(smooth_block(c)),float(smooth_block(d)),weights)),java_int(weighted(float(smooth_sky(a)),float(smooth_sky(b)),float(smooth_sky(c)),float(smooth_sky(d)),weights)))
def emission_gate(+light:U32,+emission:U32,empty:Bool) -> U32:
  match empty:
    case True{}: light
    case False{}: pack(U32.max(block(light),emission),U32.max(sky(light),emission))
def with_emission(+light:U32,+emission:U32) -> U32: emission_gate(light,emission,U32.is_eq(emission,0))
def gray(value:F32) -> U32:
  +channel=java_int(F32.mul(value,255.0))
  U32.or(4278190080,U32.or(U32.shln(channel,16n),U32.or(U32.shln(channel,8n),channel)))
def channel(+color:U32,shift:Nat) -> U32: U32.and(U32.shrn(color,shift),255)
def scale_channel(value:U32,factor:F32) -> U32: F32.to_u32(F32.clamp(F32.mul(float(value),factor),0.0,255.0))
def scale_color(+color:U32,+factor:F32) -> U32:
  U32.or(U32.and(color,4278190080),U32.or(U32.shln(scale_channel(channel(color,16n),factor),16n),U32.or(U32.shln(scale_channel(channel(color,8n),factor),8n),scale_channel(channel(color,0n),factor))))
def mean(a:F32,b:F32,c:F32,d:F32) -> F32: F32.mul(F32.add(F32.add(F32.add(a,b),c),d),0.25)
def vertex(+light:U32,shade:F32,side:F32,emission:U32) -> M.Vertex:
  M.Vertex{light,with_emission(light,emission),scale_color(gray(shade),side)}
def flat_vertex(+light:U32,side:F32,emission:U32) -> M.Vertex: M.Vertex{light,with_emission(light,emission),gray(side)}
def multiply_channel(a:U32,b:U32) -> U32: U32.div(U32.mul(a,b),255)
def multiply_color(+a:U32,+b:U32) -> U32:
  U32.or(U32.shln(multiply_channel(channel(a,24n),channel(b,24n)),24n),U32.or(U32.shln(multiply_channel(channel(a,16n),channel(b,16n)),16n),U32.or(U32.shln(multiply_channel(channel(a,8n),channel(b,8n)),8n),multiply_channel(channel(a,0n),channel(b,0n)))))
