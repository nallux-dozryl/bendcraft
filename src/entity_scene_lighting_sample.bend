import Base
import ./entity_scene_lighting_model.bend as M
import ./entity_scene_lighting.bend as L
import ./block_light.bend as B
import ./block_light_world.bend as BW
import ./sky_light_world.bend as SW
import ./sky_light_flat_authority.bend as F
import ./core.bend as C
import ./remote_entity_snapshot_wire.bend as W
import ./vanilla_lightmap_model.bend as VM

def positions(sites:List<&2,M.Site>) -> List<&2,C.Position>:
  match sites:
    case Nil{}: []
    case M.Site{role,position} <> rest: position <> positions(rest)
def role_valid(role:M.Role) -> Bool:
  match role:
    case M.Face{face,vertex,point}: U32.is_lt(face,6) && U32.is_lt(vertex,4)
    case M.Entity{entity,point}: True{}
def site_checked(role:M.Role,+position:C.Position,valid:Bool,dimension:Bool,
    rest:Result<&2,&2,M.Error,Unit>) -> Result<&2,&2,M.Error,Unit>:
  match valid dimension:
    case False{} _: Fail{M.InvalidSite{}}
    case True{} False{}: Fail{M.DimensionMismatch{position}}
    case True{} True{}: rest
def sites_checked(fuel:Nat,+dimension:String,sites:List<&2,M.Site>) -> Result<&2,&2,M.Error,Unit>:
  match fuel sites:
    case _ Nil{}: Done{Unit{}}
    case 0n _: Fail{M.StencilLimit{}}
    case 1n+p M.Site{+role,+position} <> rest:
      site_checked(role,position,role_valid(role),String.eq(dimension,C.dimension(position)),
        sites_checked(p,dimension,rest))
def environment_partial(partial:F32,environment:Maybe<&2,VM.Inputs>) -> Bool:
  match environment:
    case None{}: True{}
    case Some{VM.Inputs{environment,player,options,transitions,current}}:
      U32.is_eq(F32.bits(partial),F32.bits(current))
def capture_checked(epoch:Bool,stamp:Bool,partial:Bool) -> Result<&2,&2,M.Error,Unit>:
  match epoch stamp partial:
    case False{} _ _: Fail{M.EpochMismatch{}}
    case True{} False{} _: Fail{M.StampMismatch{}}
    case True{} True{} False{}: Fail{M.InvalidPartial{}}
    case True{} True{} True{}: Done{Unit{}}
def capture_valid(+capture:M.Capture,+request:M.Request,+authority:F.Context,+epoch:String) ->
    Result<&2,&2,M.Error,Unit>:
  M.Capture{+actual,+stamp,+environment} = capture
  W.Stamp{registry,tick,revision,dimension,origin,camera,+partial} = stamp
  M.Request{+expected,+requested,sites} = request
  capture_checked(String.eq(actual,epoch) && String.eq(expected,epoch),
    W.stamp_equal(stamp,requested) && String.eq(registry,L.registry(authority)),
    W.partial_valid(partial) && environment_partial(partial,environment))
def bool_equal(a:Bool,b:Bool) -> Bool:
  match a b:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}
def clock_equal(left:C.Clock,right:C.Clock) -> Bool:
  C.Clock{tick,time,paused,daylight,revision,pending} = left
  C.Clock{a,b,c,d,e,f} = right
  Nat.is_eq(tick,a) && Nat.is_eq(time,b) && bool_equal(paused,c) && bool_equal(daylight,d) &&
    Nat.is_eq(revision,e) && Nat.is_eq(pending,f)
def stamp_clock(stamp:W.Stamp,clock:C.Clock) -> Bool:
  W.Stamp{registry,tick,revision,dimension,origin,camera,partial} = stamp
  C.Clock{actual,time,paused,daylight,current,pending} = clock
  Nat.is_eq(tick,actual) && Nat.is_eq(revision,current)

def merged_levels(site:M.Site,state:U32,block:U32,sky:U32,valid:Bool) -> Result<&2,&2,M.Error,M.Sample>:
  M.Site{role,+position} = site
  match valid:
    case True{}: Done{M.Sample{M.Site{role,position},state,block,sky}}
    case False{}: Fail{M.InconsistentSample{position}}
def merged_positions(+site:M.Site,block:Maybe<&2,U32>,level:Maybe<&2,U32>,
    state:Maybe<&2,U32>,sky:Maybe<&2,U32>,valid:Bool) -> Result<&2,&2,M.Error,M.Sample>:
  M.Site{role,+position} = site
  match block level state sky valid:
    case None{} None{} None{} None{} True{}: Fail{M.MissingResident{position}}
    case Some{+a} Some{+b} Some{+c} Some{+d} True{}:
      merged_levels(site,a,b,d,U32.is_eq(a,c) && U32.is_le(b,15) && U32.is_le(d,15))
    case _ _ _ _ _: Fail{M.InconsistentSample{position}}
def merged(+site:M.Site,block:BW.Observation,sky:SW.Observation) -> Result<&2,&2,M.Error,M.Sample>:
  M.Site{role,+position} = site
  BW.Observation{bp,bs,bl} = block
  SW.Observation{sp,ss,sl} = sky
  merged_positions(site,bs,bl,ss,sl,
    String.eq(B.key(position),B.key(bp)) && String.eq(B.key(position),B.key(sp)))
def cons(head:Result<&2,&2,M.Error,M.Sample>,tail:Result<&2,&2,M.Error,List<&2,M.Sample>>) ->
    Result<&2,&2,M.Error,List<&2,M.Sample>>:
  match head tail:
    case Fail{error} _: Fail{error}
    case Done{sample} Fail{error}: Fail{error}
    case Done{sample} Done{rest}: Done{sample <> rest}
def zip(sites:List<&2,M.Site>,block:List<&2,BW.Observation>,sky:List<&2,SW.Observation>) ->
    Result<&2,&2,M.Error,List<&2,M.Sample>>:
  match sites block sky:
    case Nil{} Nil{} Nil{}: Done{[]}
    case site <> rest b <> bs s <> ss: cons(merged(site,b,s),zip(rest,bs,ss))
    case _ _ _: Fail{M.InvalidSite{}}
def publication(capture:M.Capture,clock:C.Clock,result:Result<&2,&2,M.Error,List<&2,M.Sample>>) ->
    Result<&2,&2,M.Error,M.Publication>:
  Result.map(&2,&2,M.Error,List<&2,M.Sample>,M.Publication,
    samples => M.Publication{capture,clock,samples},result)
def sampled_clocks(state:M.State,capture:M.Capture,clock:C.Clock,
    samples:Result<&2,&2,M.Error,List<&2,M.Sample>>,valid:Bool) ->
    M.State & Result<&2,&2,M.Error,M.Publication>:
  match valid:
    case False{}: (state,Fail{M.StampMismatch{}})
    case True{}: (state,publication(capture,clock,samples))
def sampled_sky_checked(capture:M.Capture,sites:List<&2,M.Site>,+clock:C.Clock,
    cells:List<&2,BW.Observation>,state:M.State,status:Result<&2,&2,SW.Error,SW.FrameSamples>) ->
    M.State & Result<&2,&2,M.Error,M.Publication>:
  match status:
    case Fail{error}: (state,Fail{M.SkyFailure{error}})
    case Done{SW.FrameSamples{+current,sky}}:
      sampled_clocks(state,capture,clock,zip(sites,cells,sky),clock_equal(clock,current))
def sampled_sky(+capture:M.Capture,sites:List<&2,M.Site>,clock:C.Clock,
    cells:List<&2,BW.Observation>,light:B.State,loading:Maybe<&2,BW.Cursor>,authority:F.Context,epoch:String,
    result:C.World & (SW.State & Result<&2,&2,SW.Error,SW.FrameSamples>)) ->
    M.State & Result<&2,&2,M.Error,M.Publication>:
  (world,(sky,status)) = result
  sampled_sky_checked(capture,sites,clock,cells,
    M.State{BW.State{world,light,loading},sky,authority,epoch},status)
def sampled_block(+capture:M.Capture,+sites:List<&2,M.Site>,sky:SW.State,authority:F.Context,epoch:String,
    result:BW.State & Result<&2,&2,BW.Error,BW.FrameSamples>) ->
    M.State & Result<&2,&2,M.Error,M.Publication>:
  (block,status) = result
  match block status:
    case block Fail{error}: (M.State{block,sky,authority,epoch},Fail{M.BlockFailure{error}})
    case BW.State{world,light,loading} Done{BW.FrameSamples{clock,cells}}:
      sampled_sky(capture,sites,clock,cells,light,loading,authority,epoch,
        SW.sample_batch(positions(sites),world,sky))
def sample_clock_checked(capture:M.Capture,+sites:List<&2,M.Site>,state:M.State,valid:Bool) ->
    M.State & Result<&2,&2,M.Error,M.Publication>:
  match state valid:
    case state False{}: (state,Fail{M.StampMismatch{}})
    case M.State{block,sky,authority,epoch} True{}:
      sampled_block(capture,sites,sky,authority,epoch,BW.sample_batch(positions(sites),block))
def sample_clock(+capture:M.Capture,sites:List<&2,M.Site>,sky:SW.State,light:B.State,
    loading:Maybe<&2,BW.Cursor>,authority:F.Context,epoch:String,result:C.World & C.Clock) ->
    M.State & Result<&2,&2,M.Error,M.Publication>:
  M.Capture{actual,+stamp,environment} = capture
  (world,clock) = result
  sample_clock_checked(capture,sites,M.State{BW.State{world,light,loading},sky,authority,epoch},stamp_clock(stamp,clock))
def sample_checked(capture:M.Capture,sites:List<&2,M.Site>,state:M.State,
    valid:Result<&2,&2,M.Error,Unit>) -> M.State & Result<&2,&2,M.Error,M.Publication>:
  match state valid:
    case state Fail{error}: (state,Fail{error})
    case M.State{BW.State{world,light,loading},sky,authority,epoch} Done{u}:
      sample_clock(capture,sites,sky,light,loading,authority,epoch,C.clock(world))
def request_checked(capture:M.Capture,+request:M.Request,state:M.State,
    status:Result<&2,&2,M.Error,Unit>) -> M.State & Result<&2,&2,M.Error,M.Publication>:
  M.Request{epoch,W.Stamp{registry,tick,revision,+dimension,origin,camera,partial},+sites} = request
  match status:
    case Fail{error}: (state,Fail{error})
    case Done{u}: sample_checked(capture,sites,state,sites_checked(4096n,dimension,sites))

# Capture is trusted only as an actual same-continuation frame projection. A
# remote Request never chooses the producer epoch/clock/camera/environment.
def sample(+capture:M.Capture,+request:M.Request,state:M.State) ->
    M.State & Result<&2,&2,M.Error,M.Publication>:
  M.State{block,sky,+authority,+epoch} = state
  request_checked(capture,request,M.State{block,sky,authority,epoch},
    capture_valid(capture,request,authority,epoch))
