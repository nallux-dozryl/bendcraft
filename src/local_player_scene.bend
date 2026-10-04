import Base
import ./local_player_session.bend as S
import ./local_player_runtime.bend as R
import ./player_input.bend as I
import ./client_controls.bend as CC
import ./client_world.bend as W
import ./persistent_client_world.bend as PW
import ./client_render.bend as CR
import ./client_presenter.bend as CP
import ./game.bend as G
import ./core.bend as C
import ./live.bend as L
import ./json.bend as J
import ./superflat_world.bend as SF
import ./local_phase_runtime.bend as X
import ./local_move_history.bend as MH
import ./locomotion.bend as Motion
import ./support.bend as Support
import ./local_move_world.bend as Move
import ./player_fall_history.bend as Fall
import ./world_generation_settings.bend as WG
import ./superflat_population.bend as Population
import ./schedule.bend as Schedule
import ./superflat_player.bend as TerrainPlayer

# One explicit supported neutral LocalPlayer profile. The runtime driver
# resolves ground and post-sprint attributes from the authoritative owner.
def motion_driver() -> R.Driver:
  R.driver()

def followed(result:S.State & Unit) -> S.State:
  (state,unit) = result
  state

def bindings() -> I.Bindings:
  I.Bindings{119,115,97,100,32,65592,65595}

def input(state:S.State,packet:CC.Packet) -> S.State & Result<&2,&2,String,Unit>:
  S.input(state,bindings(),packet)

def capture_allowed(frame:CR.Snapshot) -> Bool:
  True{}

def presenter_driver() -> CP.Driver<S.State,CR.Snapshot>:
  CP.Driver{S.snapshot,input,capture_allowed}

def rendered(result:CR.Assets & Image) -> CR.Assets & Result<&2,&2,String,Image>:
  (assets,image) = result
  (assets,Done{image})

def draw(frame:CR.Snapshot,assets:CR.Assets,width:U32,height:U32) -> CR.Assets & Result<&2,&2,String,Image>:
  rendered(CR.render(frame,assets,width,height))

def describe(frame:CR.Snapshot) -> String:
  CR.Snapshot{tick,revision,blocks,CR.Camera{x,y,z,yaw,pitch}} = frame
  "{\"event\":\"client.frame\",\"tick\":" ++ Nat.show(tick) ++ ",\"revision\":" ++ Nat.show(revision) ++ ",\"renderer\":\"local-player-cube-instrument\",\"yaw_f32\":" ++ U32.show(F32.bits(yaw)) ++ ",\"pitch_f32\":" ++ U32.show(F32.bits(pitch)) ++ "}"

# Loading closes the archive. Assets contain owned image values, no live handles.
def close_assets(assets:CR.Assets) -> IO(Unit):
  IO.pure(Unit,Unit{})

def renderer() -> CP.Renderer<CR.Snapshot,CR.Assets>:
  CP.Renderer{draw,describe,close_assets}

def pristine_result(view:W.View,result:G.Engine & Bool) -> W.State & Bool:
  (engine,valid) = result
  (W.attach(engine,view),valid)

def pristine_extracted(result:G.Engine & W.View) -> W.State & Bool:
  (engine,view) = result
  pristine_result(view,PW.pristine(engine))

def pristine(world:W.State) -> W.State & Bool:
  pristine_extracted(W.take(world))

def fixture_world(world:W.State) -> W.State & Result<&2,&2,String,Unit>:
  W.fixture_status(Done{Unit{}},world)

def fixture_failed(state:S.State,message:String) -> IO(S.Ready):
  S.State{player,shell} = state
  S.startup_failed(shell,"finite scene: " ++ message)

def fixture_finished(first_peer:U32,result:S.State & Result<&2,&2,String,Unit>) -> IO(S.Ready):
  (state,status) = result
  match status:
    case Fail{message}: fixture_failed(state,message)
    case Done{unit}: IO.pure(S.Ready,S.Ready{state,first_peer})

def fixture_gate(first_peer:U32,result:S.State & Bool) -> IO(S.Ready):
  (state,valid) = result
  match valid:
    case False{}: IO.pure(S.Ready,S.Ready{state,first_peer})
    case True{}: fixture_finished(first_peer,S.query(Result<&2,&2,String,Unit>,state,p => R.query(Result<&2,&2,String,Unit>,p,fixture_world)))

# Only a pristine Core is initialized. Loaded terrain, player and pause survive.
def initialize(ready:S.Ready) -> IO(S.Ready):
  S.Ready{state,first_peer} = ready
  fixture_gate(first_peer,S.query(Bool,state,p => R.query(Bool,p,pristine)))

def superflat_player_result(tables:Motion.Tables,support:Support.State,minor:Move.MinorState,
    history:Fall.State,metadata:X.Metadata,motion_tail:List<&1,MH.State>,tail:List<&1,X.State>,
    result:W.State & Result<&2,&2,String,SF.Outcome>) -> X.State & Result<&2,&2,String,Unit>:
  (world,status) = result
  match status:
    case Fail{message}:
      (X.State{MH.State{world,support,minor,history,motion_tail},tables,metadata,tail},Fail{message})
    case Done{SF.Existing{}}:
      R.query(Result<&2,&2,String,Unit>,
        X.State{MH.State{world,support,minor,history,motion_tail},tables,metadata,tail},SF.configure)
    case Done{SF.Generated{}}:
      # Startup is pristine: initialize Body, support, fall history and both
      # commonTick old positions together through the ordinary runtime owner.
      (R.fresh(world,tables),Done{Unit{}})

def superflat_player(player:X.State) -> X.State & Result<&2,&2,String,Unit>:
  X.State{MH.State{world,support,minor,history,motion_tail},tables,metadata,tail} = player
  superflat_player_result(tables,support,minor,history,metadata,motion_tail,tail,SF.initialize(world))

def superflat_failed(state:S.State,message:String) -> IO(S.Ready):
  S.State{player,shell} = state
  S.startup_failed(shell,"superflat scene: " ++ message)

def superflat_finished(first_peer:U32,result:S.State & Result<&2,&2,String,Unit>) -> IO(S.Ready):
  (state,status) = result
  match status:
    case Fail{message}: superflat_failed(state,message)
    case Done{unit}: IO.pure(S.Ready,S.Ready{S.mark_initialized(state),first_peer})

def superflat_gate(first_peer:U32,result:S.State & Bool) -> IO(S.Ready):
  (state,fresh) = result
  match fresh:
    case True{}: superflat_finished(first_peer,S.query(Result<&2,&2,String,Unit>,state,superflat_player))
    case False{}:
      superflat_finished(first_peer,S.query(Result<&2,&2,String,Unit>,state,
        p => R.query(Result<&2,&2,String,Unit>,p,SF.configure)))

# Explicit custom vanilla-flat layer settings. Freshness comes from the codec
# initializer/decoder, never from guessing whether a loaded Core looks empty.
# Loaded Core/player state is retained; only its transient view is configured.
def initialize_superflat(ready:S.Ready) -> IO(S.Ready):
  S.Ready{state,first_peer} = ready
  superflat_gate(first_peer,S.fresh(state))

def production_player_result(tables:Motion.Tables,support:Support.State,minor:Move.MinorState,
    history:Fall.State,metadata:X.Metadata,motion_tail:List<&1,MH.State>,tail:List<&1,X.State>,
    result:W.State & Result<&2,&2,String,SF.Outcome>) -> X.State & Result<&2,&2,String,Unit>:
  TerrainPlayer.initialized(tables,support,minor,history,metadata,motion_tail,tail,result)

def production_player(settings:WG.Settings,fresh:Bool,player:X.State) -> X.State & Result<&2,&2,String,Unit>:
  TerrainPlayer.initialize(settings,fresh,player)

def production_settings_set(first_peer:U32,settings:WG.Settings,result:S.State & Result<&2,&2,String,Unit>) -> IO(S.Ready):
  (state,status) = result
  match status:
    case Fail{message}: superflat_failed(state,message)
    case Done{unit}:
      superflat_finished(first_peer,S.query(Result<&2,&2,String,Unit>,state,p => production_player(settings,True{},p)))

def demanded_configured(receipt:Population.Receipt,result:W.State & Result<&2,&2,String,Unit>) -> W.State & Result<&2,&2,String,Population.Receipt>:
  (state,status) = result
  match status:
    case Fail{message}: (state,Fail{message})
    case Done{unit}: (state,Done{receipt})

def demanded_followed(result:W.State & Result<&2,&2,String,Population.Receipt>) -> W.State & Result<&2,&2,String,Population.Receipt>:
  (state,status) = result
  match status:
    case Fail{message}: (state,Fail{message})
    case Done{receipt}: demanded_configured(receipt,SF.configure_production(state,SF.default_view_policy()))

def demand_world(state:W.State,settings:WG.Settings,stamp:Schedule.Stamp) -> W.State & Result<&2,&2,String,Population.Receipt>:
  demanded_followed(SF.demand(state,settings,SF.default_view_policy(),Population.default_budget(),stamp))

def demand_supported(state:S.State,settings:WG.Settings,stamp:Schedule.Stamp,supported:Bool) -> S.State & Result<&2,&2,String,Population.Receipt>:
  match supported:
    case False{}: (state,Fail{"player world adapter only supports minecraft:overworld"})
    case True{}:
      S.query(Result<&2,&2,String,Population.Receipt>,state,p => R.query(Result<&2,&2,String,Population.Receipt>,p,w => demand_world(w,settings,stamp)))

def demand_settings(stamp:Schedule.Stamp,result:S.State & WG.Settings) -> S.State & Result<&2,&2,String,Population.Receipt>:
  (state,+settings) = result
  demand_supported(state,settings,stamp,TerrainPlayer.supported_dimension(settings))

# The actor calls this before reads/ticks that need a new region. An admission
# failure retains the authoritative owner and is available to the actor as an
# explicit error; it is not silently converted to air or a clamped position.
def demand(state:S.State,stamp:Schedule.Stamp) -> S.State & Result<&2,&2,String,Population.Receipt>:
  demand_settings(stamp,S.generation(state))

def ensure_legacy(state:S.State,settings:WG.Settings,legacy:Bool) -> S.State & Result<&2,&2,String,Unit>:
  match legacy:
    case True{}: (state,Done{Unit{}})
    case False{}: S.query(Result<&2,&2,String,Unit>,state,p => TerrainPlayer.ensure(settings,p))

def ensure_settings(result:S.State & WG.Settings) -> S.State & Result<&2,&2,String,Unit>:
  (state,+settings) = result
  ensure_legacy(state,settings,WG.is_legacy(settings))

def ensure(state:S.State) -> S.State & Result<&2,&2,String,Unit>:
  ensure_settings(S.generation(state))

def terrain_error_player(player:X.State,message:String) -> X.State & Unit:
  (R.with_error(player,Some{message}),Unit{})

def terrain_error(state:S.State,message:String) -> S.State:
  followed(S.query(Unit,state,p => terrain_error_player(p,message)))

def follow_ensured(result:S.State & Result<&2,&2,String,Unit>) -> S.State:
  (state,status) = result
  match status:
    case Fail{message}: terrain_error(state,message)
    case Done{unit}: state

def follow_legacy(state:S.State,legacy:Bool) -> S.State:
  match legacy:
    case True{}: followed(S.query(Unit,state,p => R.query(Unit,p,SF.follow)))
    case False{}: follow_ensured(ensure(state))

def follow_settings(result:S.State & WG.Settings) -> S.State:
  (state,settings) = result
  follow_legacy(state,WG.is_legacy(settings))

def follow(state:S.State) -> S.State:
  follow_settings(S.generation(state))

def player_step_error(player:X.State) -> X.State & Maybe<&2,String>:
  X.State{motion,tables,X.Metadata{local,record,sprint,pose,controls,entity,+error,metadata_tail},tail} = player
  (X.State{motion,tables,X.Metadata{local,record,sprint,pose,controls,entity,error,metadata_tail},tail},error)


def realtime_ensured(result:S.State & Result<&2,&2,String,Unit>) -> S.State:
  (state,status) = result
  match status:
    case Fail{message}: terrain_error(state,message)
    case Done{unit}: follow(S.run_with_status(state,status => player => R.realtime_status(motion_driver(),status,player)))

def realtime_step(state:S.State) -> S.State:
  realtime_ensured(ensure(state))

def scheduled_step(state:S.State) -> S.State:
  S.run_with_status(state,status => player => R.step_status(motion_driver(),status,player))

def advance_checked(next:S.State -> S.State,result:S.State & Maybe<&2,String>) -> S.State:
  (state,error) = result
  match error:
    case None{}: next(state)
    case Some{message}: state

def advance_ensured(result:S.State & Result<&2,&2,String,Unit>,next:S.State -> S.State) -> S.State:
  (state,status) = result
  match status:
    case Fail{message}: terrain_error(state,message)
    case Done{unit}: advance_checked(next,S.query(Maybe<&2,String>,follow(scheduled_step(state)),player_step_error))

def advance_go(fuel:Nat,state:S.State) -> S.State:
  match fuel:
    case 0n: state
    case 1n+rest: advance_ensured(ensure(state),next => advance_go(rest,next))

def advance(state:S.State,ticks:U32) -> S.State:
  advance_go(U32.to_nat(ticks),state)

def dispatched(result:S.State & L.Session & J.Value) -> S.State & L.Session & J.Value:
  (state,session,value) = result
  (state,session,value)

def step_request(found:Maybe<&2,J.Value>) -> Bool:
  match found:
    case Some{J.JString{"simulation.step"}}: True{}
    case _: False{}

def success_value(found:Maybe<&2,J.Value>) -> Bool:
  match found:
    case Some{J.JBool{True{}}}: True{}
    case _: False{}


def dispatch_step_error(session:L.Session,+value:J.Value,result:S.State & Maybe<&2,String>) -> S.State & L.Session & J.Value:
  (state,error) = result
  match error:
    case None{}: (state,session,value)
    case Some{message}: S.failure(state,session,L.id_of(J.member(value,"id")),L.bad("PlayerStepUnavailable",message))

def dispatch_checked(state:S.State,session:L.Session,value:J.Value,check:Bool) -> S.State & L.Session & J.Value:
  match check:
    case False{}: (state,session,value)
    case True{}: dispatch_step_error(session,value,S.query(Maybe<&2,String>,state,player_step_error))

def dispatch_value(state:S.State,session:L.Session,+value:J.Value,step:Bool) -> S.State & L.Session & J.Value:
  dispatch_checked(state,session,value,step && success_value(J.member(value,"ok")))

def dispatch_response(request:J.Value,result:S.State & L.Session & J.Value) -> S.State & L.Session & J.Value:
  (state,session,value) = result
  dispatch_value(state,session,value,step_request(J.member(request,"op")))

def dispatch(state:S.State,session:L.Session,token:String,+request:J.Value) -> IO(S.State & L.Session & J.Value):
  do IO<S.State & L.Session & J.Value>:
    result : S.State & L.Session & J.Value <- S.dispatch_using(state => ticks => advance(state,ticks),state,session,token,request)
    return dispatch_response(request,result)

# Base macOS lowercases characters; modifier events use 65536 + hardware code.
# Physical input verification remains separate from this source-derived mapping.
def production_gate(first_peer:U32,+settings:WG.Settings,result:S.State & Bool) -> IO(S.Ready):
  (state,fresh) = result
  match fresh:
    case False{}: superflat_finished(first_peer,ensure(state))
    case True{}: production_settings_set(first_peer,settings,S.set_generation(state,settings))

# CLI settings are chosen only for a new world. A loaded world keeps its saved
# generator, complete player record, view/cache and all runtime metadata.
def initialize_generated(ready:S.Ready,settings:WG.Settings) -> IO(S.Ready):
  S.Ready{state,first_peer} = ready
  production_gate(first_peer,settings,S.fresh(state))

def unpaused_world(result:G.Engine & W.View) -> W.State & Unit:
  (G.Engine{world,registry},view) = result
  (W.attach(G.Engine{C.set_paused(world,False{}),registry},view),Unit{})

def unpause(world:W.State) -> W.State & Unit:
  unpaused_world(W.take(world))

def started_unpaused(result:S.State & Unit,first_peer:U32) -> S.Ready:
  (state,unit) = result
  S.Ready{state,first_peer}

def run_requested(ready:S.Ready,run:Bool) -> S.Ready:
  S.Ready{state,first_peer} = ready
  match run:
    case False{}: S.Ready{state,first_peer}
    case True{}: started_unpaused(S.query(Unit,state,p => R.query(Unit,p,unpause)),first_peer)
