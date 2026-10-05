import Base
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./random.bend as R
import ./f64.bend as F
import ./vanilla_entity_fields.bend as V
import ./cooking_effect_entities_model.bend as E

type SplashResult is Data:
  SplashResult{+source:R.Source,publications:List<&2,T.Publication>}
def volume(+v:V.Vec3) -> F32:
  V.Vec3{+x,+y,+z}=v
  F32.min(1.0,F32.mul(F.to_f32(F.sqrt(F.add(F.add(F.mul(F.mul(x,x),F.from_f32(0.2)),F.mul(y,y)),F.mul(F.mul(z,z),F.from_f32(0.2))))),0.2))
def offset(+value:F.F64) -> F.F64: F.mul(F.sub(F.mul(value,F.from_u32(2)),F.from_u32(1)),F.from_f32(0.25))
def particle_done(+x:F.F64,+y:F.F64,+z:F.F64,+point:V.Vec3,+velocity:V.Vec3,+bubble:Bool,+source:R.Source) -> SplashResult:
  V.Vec3{a,b,c}=point
  SplashResult{source,[T.Particle{bubble,V.Vec3{F.add(a,x),y,F.add(c,z)},velocity}]}
def bubble_noise(+x:F.F64,+y:F.F64,+z:F.F64,+point:V.Vec3,+velocity:V.Vec3,result:R.Source & F.F64) -> SplashResult:
  V.Vec3{a,b,c}=velocity
  (source,noise)=result
  particle_done(x,y,z,point,V.Vec3{a,F.sub(b,F.mul(noise,F.from_f32(0.2))),c},True{},source)
def particle_noise(+x:F.F64,+y:F.F64,+z:F.F64,+point:V.Vec3,+velocity:V.Vec3,+bubble:Bool,+source:R.Source) -> SplashResult:
  match bubble:
    case False{}: particle_done(x,y,z,point,velocity,False{},source)
    case True{}: bubble_noise(x,y,z,point,velocity,R.next_double(source))
def particle_z(+x:F.F64,+y:F.F64,+point:V.Vec3,+velocity:V.Vec3,+bubble:Bool,result:R.Source & F.F64) -> SplashResult:
  (source,z)=result
  particle_noise(x,y,offset(z),point,velocity,bubble,source)
def particle_x(+y:F.F64,+point:V.Vec3,+velocity:V.Vec3,+bubble:Bool,result:R.Source & F.F64) -> SplashResult:
  (source,x)=result
  particle_z(offset(x),y,point,velocity,bubble,R.next_double(source))
def append(events:List<&2,T.Publication>,result:SplashResult) -> SplashResult:
  SplashResult{source,rest}=result
  SplashResult{source,List.append(&2,T.Publication,events,rest)}
def particle_more(result:SplashResult,continue:R.Source -> SplashResult) -> SplashResult:
  SplashResult{source,events}=result
  append(events,continue(source))
def particles(+left:Nat,+y:F.F64,+point:V.Vec3,+velocity:V.Vec3,+bubble:Bool,+source:R.Source) -> SplashResult:
  match left:
    case 0n: SplashResult{source,[]}
    case 1n+rest: particle_more(particle_x(y,point,velocity,bubble,R.next_double(source)),next => particles(rest,y,point,velocity,bubble,next))
def second_particles(+point:V.Vec3,+velocity:V.Vec3,+y:F.F64,result:SplashResult) -> SplashResult:
  SplashResult{source,events}=result
  append(events,particles(6n,y,point,velocity,False{},source))
def sound(+point:V.Vec3,+velocity:V.Vec3,+volume:F32,+pitch:F32,+source:R.Source) -> SplashResult:
  V.Vec3{x,+y,z}=point
  +py=F.from_f32(F32.add(F.to_f32(F.from_i32(V.floor_word(y))),1.0))
  append([T.Splash{point,volume,pitch,F32.is_ge(volume,0.25)}],second_particles(point,velocity,py,particles(6n,py,point,velocity,True{},source)))
def pitch_second(+point:V.Vec3,+velocity:V.Vec3,+volume:F32,+first:F32,result:R.Source & F32) -> SplashResult:
  (source,second)=result
  sound(point,velocity,volume,F32.add(1.0,F32.mul(F32.sub(first,second),0.4)),source)
def pitch_first(+point:V.Vec3,+velocity:V.Vec3,+volume:F32,result:R.Source & F32) -> SplashResult:
  (source,first)=result
  pitch_second(point,velocity,volume,first,R.next_float(source))
def completed(+point:V.Vec3,value:SplashResult) -> SplashResult:
  SplashResult{+source,+events}=value
  SplashResult{source,List.append(&2,T.Publication,events,[T.SplashEvent{point}])}
def run(+point:V.Vec3,+velocity:V.Vec3,+source:R.Source) -> SplashResult:
  completed(point,pitch_first(point,velocity,volume(velocity),R.next_float(source)))
