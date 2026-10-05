import Base
import ./random.bend as R
import ./f64.bend as F
import ./locomotion.bend as L
import ./vanilla_lightmap_model.bend as M
import ./vanilla_lightmap_eval.bend as E

# This client-only RandomSource is independent from world/entity/sound RNGs.
# Fresh construction requires the actual chosen Legacy source (the Java factory
# uses a unique host seed); durable restoration supplies every field explicitly.
type State is Type:
  State{random:R.Source,flicker:F32,dirty:Bool,uniforms:M.Uniforms,texture:M.Texture}
def fresh(random:R.Source) -> State:
  State{random,0.0,False{},M.initial_uniforms(),M.InitialWhite{}}
def tick_d(flicker:F32,u:M.Uniforms,texture:M.Texture,a:F32,b:F32,c:F32,result:R.Source & F32) -> State:
  (random,d)=result
  State{random,F32.mul(F32.add(flicker,F32.mul(F32.mul(F32.mul(F32.sub(a,b),c),d),0.1)),0.9),True{},u,texture}
def tick_c(flicker:F32,u:M.Uniforms,texture:M.Texture,a:F32,b:F32,result:R.Source & F32) -> State:
  (random,c)=result
  tick_d(flicker,u,texture,a,b,c,R.next_float(random))
def tick_b(flicker:F32,u:M.Uniforms,texture:M.Texture,a:F32,result:R.Source & F32) -> State:
  (random,b)=result
  tick_c(flicker,u,texture,a,b,R.next_float(random))
def tick_a(flicker:F32,u:M.Uniforms,texture:M.Texture,result:R.Source & F32) -> State:
  (random,a)=result
  tick_b(flicker,u,texture,a,R.next_float(random))
def tick(state:State) -> State:
  State{random,flicker,dirty,u,texture}=state
  tick_a(flicker,u,texture,R.next_float(random))
def lerp(value:M.Interpolation,+partial:F32) -> F32:
  M.Interpolation{+previous,current}=value
  F32.add(previous,F32.mul(partial,F32.sub(current,previous)))
def flash_divide(value:F32,fog:Bool) -> F32:
  match fog:
    case False{}: value
    case True{}: F32.div(value,3.0)
def visible_flash(value:Maybe<&2,M.Interpolation>,fog:Bool,partial:F32) -> F32:
  match value:
    case None{}: 0.0
    case Some{interpolation}: flash_divide(lerp(interpolation,partial),fog)
def flash(value:Maybe<&2,M.Interpolation>,fog:Bool,partial:F32,hidden:Bool) -> F32:
  match hidden:
    case True{}: 0.0
    case False{}: visible_flash(value,fog,partial)
def night_sine(result:L.Tables & F32) -> L.Tables & F32:
  (tables,sine)=result
  (tables,F32.add(0.7,F32.mul(sine,0.3)))
def night_ready(tables:L.Tables,duration:U32,partial:F32,short:Bool) -> L.Tables & F32:
  match short:
    case False{}: (tables,1.0)
    case True{}:
      angle=F32.mul(F32.mul(F32.sub(F.to_f32(F.from_i32(duration)),partial),3.1415927),0.2)
      night_sine(L.sin(tables,F.from_f32(angle)))
def F64_signed_less_200(+ticks:U32) -> Bool:
  U32.is_le(ticks,200) || U32.is_ge(ticks,2147483648)
def night(tables:L.Tables,duration:Maybe<&2,U32>,+water:F32,conduit:Bool,partial:F32) -> L.Tables & F32:
  match duration:
    case Some{+ticks}: night_ready(tables,ticks,partial,Bool.not(U32.is_eq(ticks,4294967295)) && F64_signed_less_200(ticks))
    case None{}: (tables,Bool.pick(F32,F32.is_gt(water,0.0) && conduit,water,0.0))
def prepare_night(u:M.Uniforms,result:L.Tables & F32) -> L.Tables & M.Uniforms:
  M.Uniforms{s,b,old,d,o,g,bt,sc,a,nc}=u
  (tables,nv)=result
  (tables,M.Uniforms{s,b,nv,d,o,g,bt,sc,a,nc})
def prepare_cosine(flicker:F32,inputs:M.Inputs,result:L.Tables & F32) -> L.Tables & M.Uniforms:
  M.Inputs{M.Environment{bt,sf,sc,ambient,nc},M.Player{ticks,darkness_blend,duration,water,conduit},M.Options{gamma,darkness_scale,hidden},M.Transitions{end_flash,fog,boss},+partial}=inputs
  (tables,cosine)=result
  +setting=F.to_f32(darkness_scale)
  +blend=F32.mul(darkness_blend,setting)
  dark=F32.mul(F32.max(0.0,F32.mul(cosine,F32.mul(0.45,blend))),setting)
  brightness=F32.max(0.0,F32.sub(F.to_f32(gamma),blend))
  prepare_night(M.Uniforms{F32.add(sf,flash(end_flash,fog,partial,hidden)),F32.add(flicker,1.4),0.0,dark,lerp(boss,partial),brightness,bt,sc,ambient,nc},night(tables,duration,water,conduit,partial))
def prepare(tables:L.Tables,flicker:F32,inputs:M.Inputs) -> L.Tables & M.Uniforms:
  M.Inputs{env,M.Player{+ticks,darkness_blend,duration,water,conduit},options,transitions,+partial}=inputs
  angle=F32.mul(F32.mul(F32.sub(F.to_f32(F.from_i32(ticks)),partial),3.1415927),0.025)
  prepare_cosine(flicker,M.Inputs{env,M.Player{ticks,darkness_blend,duration,water,conduit},options,transitions,partial},L.cos(tables,F.from_f32(angle)))
def interpolation_finite(value:M.Interpolation) -> Bool:
  M.Interpolation{p,c}=value
  E.finite(p) && E.finite(c)
def flash_finite(value:Maybe<&2,M.Interpolation>) -> Bool:
  match value:
    case None{}: True{}
    case Some{v}: interpolation_finite(v)
def inputs_finite(inputs:M.Inputs) -> Bool:
  M.Inputs{M.Environment{bt,sf,sc,a,nc},M.Player{ticks,db,duration,w,c},M.Options{g,d,h},M.Transitions{flash,fog,boss},p}=inputs
  E.color_finite(bt) && E.finite(sf) && E.color_finite(sc) && E.color_finite(a) && E.color_finite(nc) && E.finite(db) && E.finite(w) && E.finite(F.to_f32(g)) && E.finite(F.to_f32(d)) && interpolation_finite(boss) && flash_finite(flash) && E.finite(p)
def prepared_success(state:State,tables:L.Tables,+uniforms:M.Uniforms) -> State & (L.Tables & Result<&2,&2,M.Error,M.Publication>):
  State{random,flicker,dirty,old,texture}=state
  (State{random,flicker,False{},uniforms,M.Evaluated{uniforms}},(tables,Done{M.Publication{True{},M.Evaluated{uniforms}}}))
def prepared(state:State,tables:L.Tables,uniforms:M.Uniforms,valid:Bool) -> State & (L.Tables & Result<&2,&2,M.Error,M.Publication>):
  match valid:
    case False{}: (state,(tables,Fail{M.Refused{"lightmap: nonfinite evaluated uniforms"}}))
    case True{}: prepared_success(state,tables,uniforms)
def ready_prepared(state:State,result:L.Tables & M.Uniforms) -> State & (L.Tables & Result<&2,&2,M.Error,M.Publication>):
  (tables,+next)=result
  prepared(state,tables,next,E.uniforms_finite(next))
def ready_success(state:State,tables:L.Tables,inputs:M.Inputs) -> State & (L.Tables & Result<&2,&2,M.Error,M.Publication>):
  State{random,+flicker,dirty,u,texture}=state
  ready_prepared(State{random,flicker,dirty,u,texture},prepare(tables,flicker,inputs))
def ready(valid:Bool,state:State,tables:L.Tables,inputs:M.Inputs) -> State & (L.Tables & Result<&2,&2,M.Error,M.Publication>):
  match valid:
    case False{}: (state,(tables,Fail{M.Refused{"lightmap: nonfinite context"}}))
    case True{}: ready_success(state,tables,inputs)
def extract_absent(state:State,tables:L.Tables) -> State & (L.Tables & Result<&2,&2,M.Error,M.Publication>):
  State{random,f,d,+u,texture}=state
  (State{random,f,d,u,M.Evaluated{u}},(tables,Done{M.Publication{True{},M.Evaluated{u}}}))
def extract_present(presence:M.Presence,state:State,tables:L.Tables) -> State & (L.Tables & Result<&2,&2,M.Error,M.Publication>):
  match presence:
    case M.Absent{}: extract_absent(state,tables)
    case M.Ready{+inputs}: ready(inputs_finite(inputs),state,tables,inputs)
def extract_clean(state:State,tables:L.Tables) -> State & (L.Tables & Result<&2,&2,M.Error,M.Publication>):
  State{random,f,d,u,+texture}=state
  (State{random,f,d,u,texture},(tables,Done{M.Publication{False{},texture}}))
def extract_dirty(dirty:Bool,presence:M.Presence,state:State,tables:L.Tables) -> State & (L.Tables & Result<&2,&2,M.Error,M.Publication>):
  match dirty:
    case False{}: extract_clean(state,tables)
    case True{}: extract_present(presence,state,tables)
def extract(presence:M.Presence,state:State,tables:L.Tables) -> State & (L.Tables & Result<&2,&2,M.Error,M.Publication>):
  State{random,f,+dirty,u,texture}=state
  extract_dirty(dirty,presence,State{random,f,dirty,u,texture},tables)
