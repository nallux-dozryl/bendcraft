import Base
import ./superflat_world.bend as SF
import ./superflat_population.bend as Population
import ./world_generation_settings.bend as WG
import ./client_world.bend as W
import ./local_player_runtime.bend as R
import ./local_phase_runtime.bend as X
import ./local_move_history.bend as MH
import ./locomotion.bend as Motion
import ./support.bend as Support
import ./local_move_world.bend as Move
import ./player_fall_history.bend as Fall
import ./schedule.bend as Schedule

# Actual pure Scene initialization boundary. Existing worlds carry every
# LocalPlayer owner and Data field unchanged. Fresh worlds use R.fresh once.
def initialized(tables:Motion.Tables,support:Support.State,minor:Move.MinorState,
    history:Fall.State,metadata:X.Metadata,motion_tail:List<&1,MH.State>,tail:List<&1,X.State>,
    result:W.State & Result<&2,&2,String,SF.Outcome>) -> X.State & Result<&2,&2,String,Unit>:
  (world,status) = result
  match status:
    case Fail{message}:
      (X.State{MH.State{world,support,minor,history,motion_tail},tables,metadata,tail},Fail{message})
    case Done{SF.Existing{}}:
      (X.State{MH.State{world,support,minor,history,motion_tail},tables,metadata,tail},Done{Unit{}})
    case Done{SF.Generated{}}: (R.fresh(world,tables),Done{Unit{}})

# The current World/View/collision adapters carry only an Overworld position.
# Generic dimension metadata/population must not be mistaken for a dimension-
# aware player owner. Refuse before querying or populating the actual World.
def supported_dimension(settings:WG.Settings) -> Bool:
  match settings:
    case WG.Unspecified{}: False{}
    case WG.Settings{dimension,min_y,height,seed,generator}: String.eq(dimension,"minecraft:overworld")

def initialize_fresh(settings:WG.Settings,player:X.State) -> X.State & Result<&2,&2,String,Unit>:
  X.State{MH.State{world,support,minor,history,motion_tail},tables,metadata,tail} = player
  initialized(tables,support,minor,history,metadata,motion_tail,tail,
    SF.initialize_generated(world,settings,SF.default_view_policy(),Population.default_budget(),Schedule.Stamp{0n,0,0n},True{}))

def initialize_supported(settings:WG.Settings,player:X.State,supported:Bool) -> X.State & Result<&2,&2,String,Unit>:
  match supported:
    case False{}: (player,Fail{"player world adapter only supports minecraft:overworld"})
    case True{}: initialize_fresh(settings,player)

def initialize(+settings:WG.Settings,fresh:Bool,player:X.State) -> X.State & Result<&2,&2,String,Unit>:
  match fresh:
    case False{}: (player,Done{Unit{}})
    case True{}: initialize_supported(settings,player,supported_dimension(settings))

def ensure_supported(+settings:WG.Settings,player:X.State,supported:Bool) -> X.State & Result<&2,&2,String,Unit>:
  match supported:
    case False{}: (player,Fail{"player world adapter only supports minecraft:overworld"})
    case True{}:
      R.query(Result<&2,&2,String,Unit>,player,w => SF.ensure_current(w,settings,SF.default_view_policy(),Population.default_budget()))

def ensure(+settings:WG.Settings,player:X.State) -> X.State & Result<&2,&2,String,Unit>:
  ensure_supported(settings,player,supported_dimension(settings))
