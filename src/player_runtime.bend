import Base
import ./f64.bend as F
import ./client_world.bend as W
import ./client_render.bend as R
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as B
import ./movement.bend as M
import ./locomotion.bend as L
import ./player_tick.bend as P
import ./player_tick_world.bend as PW
import ./player_input.bend as I
import ./player_look.bend as PL
import ./mouse_input.bend as MI
import ./player_controls.bend as PC
import ./client_controls.bend as CC
import ./support.bend as SP
import ./player_record.bend as PR
import ./player_codec.bend as PS

# W owns the sole body; metadata owns the remaining admitted aiStep projection.
# This explicit plain Player facade is separate from LocalPlayer's override.
type Metadata is Data:
  Metadata{input:P.Input,jumping:Bool,jump_delay:U32,jump_trigger:U32,
    needs_sync:Bool,stored_speed:F32,head_yaw:F32}

type State is Type:
  State{world:W.State,tables:L.Tables,metadata:Metadata,support:SP.State,
    controls:PC.Controller,last_error:Maybe<&2,String>}

type Driver is Type:
  Driver{context:W.State -> SP.State -> I.Buttons -> F32 -> W.State & Result<&2,&2,String,P.Context>,
    support:W.State -> SP.State -> M.Transition -> W.State & Result<&2,&2,String,SP.State>}

# Boxing keeps rollback fields within the installed native word limit.
type Prior is Data:
  Prior{view:W.View,metadata:Metadata,support:SP.State,controls:PC.Controller,
    tail:List<&2,Prior>}

def metadata(player:P.State) -> Metadata:
  P.State{body,input,jumping,delay,trigger,sync,speed,head} = player
  Metadata{input,jumping,delay,trigger,sync,speed,head}

def compose(body:M.Body,metadata:Metadata) -> P.State:
  Metadata{input,jumping,delay,trigger,sync,speed,head} = metadata
  P.State{body,input,jumping,delay,trigger,sync,speed,head}

def held_sample(body:M.Body,metadata:Metadata,sample:I.Sample) -> P.State:
  Metadata{old_input,old_jump,delay,trigger,sync,speed,head} = metadata
  I.Sample{I.Buttons{f,b,l,r,jump,shift,sprint},I.Vector{x,z},forward} = sample
  P.State{body,P.Input{x,0.0,z},jump,delay,trigger,sync,speed,head}

def buttons(controls:PC.Controller) -> I.Buttons:
  PC.Controller{buttons,look,mouse,options} = controls
  buttons

def look(controls:PC.Controller) -> PL.State:
  PC.Controller{buttons,look,mouse,options} = controls
  look

def held(body:M.Body,metadata:Metadata,controls:PC.Controller) -> P.State:
  held_sample(body,metadata,I.sample(buttons(controls)))

def view_body(view:W.View) -> M.Body:
  W.View{body,yaw,pitch,palette,region,cache} = view
  body

def runtime_error(error:PW.Error) -> String:
  match error:
    case PW.BodyMismatch{}: "player-body-mismatch"
    case PW.PreparationError{cause}: "player-preparation-rejected"
    case PW.TravelError{cause}: "player-travel-rejected"
    case PW.FinishError{cause}: "player-finish-rejected"

def yaw(look:PL.State) -> F32:
  PL.State{yaw,pitch,previous_yaw,previous_pitch} = look
  yaw

def restored_view(tables:L.Tables,prior:Prior,error:String,result:G.Engine & W.View) -> State:
  Prior{view,metadata,support,controls,tail} = prior
  (engine,discarded) = result
  State{W.attach(engine,view),tables,metadata,support,controls,Some{error}}

def rejected(world:W.State,tables:L.Tables,prior:Prior,error:String) -> State:
  restored_view(tables,prior,error,W.take(world))

def accepted(tables:L.Tables,prior:Prior,player:P.State,world:W.State,support:SP.State) -> State:
  Prior{view,old_metadata,old_support,controls,tail} = prior
  State{world,tables,metadata(player),support,controls,None{}}

def supported(tables:L.Tables,prior:Prior,player:P.State,result:W.State & Result<&2,&2,String,SP.State>) -> State:
  (world,status) = result
  match status:
    case Fail{error}: rejected(world,tables,prior,"player-support: " ++ error)
    case Done{support}: accepted(tables,prior,player,world,support)

def prior_support(prior:Prior) -> SP.State:
  Prior{view,metadata,support,controls,tail} = prior
  support

def prior_player(prior:Prior) -> P.State:
  Prior{view,metadata,support,controls,tail} = prior
  held(view_body(view),metadata,controls)

def moved(after:W.State -> SP.State -> M.Transition -> W.State & Result<&2,&2,String,SP.State>,+prior:Prior,result:W.State & L.Tables & P.State & Result<&2,&2,PW.Error,P.Transition>) -> State:
  (world,tables,player,status) = result
  match status:
    case Fail{error}: rejected(world,tables,prior,runtime_error(error))
    case Done{P.Transition{next,+movement,attempted,jumped}}:
      supported(tables,prior,player,after(world,prior_support(prior),movement))

def resolved(after:W.State -> SP.State -> M.Transition -> W.State & Result<&2,&2,String,SP.State>,tables:L.Tables,+prior:Prior,result:W.State & Result<&2,&2,String,P.Context>) -> State:
  (world,status) = result
  match status:
    case Fail{error}: rejected(world,tables,prior,"player-context: " ++ error)
    case Done{context}: moved(after,prior,PW.tick_checked(world,tables,prior_player(prior),context))

def physics_extracted(context:W.State -> SP.State -> I.Buttons -> F32 -> W.State & Result<&2,&2,String,P.Context>,after:W.State -> SP.State -> M.Transition -> W.State & Result<&2,&2,String,SP.State>,tables:L.Tables,+metadata:Metadata,+support:SP.State,+controls:PC.Controller,result:G.Engine & W.View) -> State:
  (engine,+view) = result
  resolved(after,tables,Prior{view,metadata,support,controls,[]},context(W.attach(engine,view),support,buttons(controls),yaw(look(controls))))

def physics(driver:Driver,state:State) -> State:
  Driver{context,after} = driver
  State{world,tables,metadata,support,controls,error} = state
  physics_extracted(context,after,tables,metadata,support,controls,W.take(world))

def stepped_engine(result:G.Engine & W.View) -> W.State:
  (G.Engine{world,registry},view) = result
  W.attach(G.Engine{C.step(world),registry},view)

# Due Core edits precede each individual player step. Failure retains that Core
# advance but restores body/view/metadata/support and the prior controls.
def step(driver:Driver,state:State) -> State:
  State{world,tables,metadata,support,controls,error} = state
  physics(driver,State{stepped_engine(W.take(world)),tables,metadata,support,controls,error})

def advance(~driver:Driver,ticks:Nat,state:State) -> State:
  match ticks:
    case 0n: state
    case 1n+rest: advance(~driver,rest,step(driver,state))

def realtime_selected(driver:Driver,state:State,paused:Bool) -> State:
  match paused:
    case True{}: state
    case False{}: step(driver,state)

def clocked(driver:Driver,registry:B.Registry,view:W.View,tables:L.Tables,metadata:Metadata,support:SP.State,controls:PC.Controller,error:Maybe<&2,String>,result:C.World & C.Clock) -> State:
  (world,C.Clock{tick,time,paused,daylight,revision,pending}) = result
  realtime_selected(driver,State{W.attach(G.Engine{world,registry},view),tables,metadata,support,controls,error},paused)

def realtime_extracted(driver:Driver,tables:L.Tables,metadata:Metadata,support:SP.State,controls:PC.Controller,error:Maybe<&2,String>,result:G.Engine & W.View) -> State:
  (G.Engine{world,registry},view) = result
  clocked(driver,registry,view,tables,metadata,support,controls,error,C.clock(world))

def realtime_step(driver:Driver,state:State) -> State:
  State{world,tables,metadata,support,controls,error} = state
  realtime_extracted(driver,tables,metadata,support,controls,error,W.take(world))

def queried(-A:Type,tables:L.Tables,metadata:Metadata,support:SP.State,controls:PC.Controller,error:Maybe<&2,String>,result:W.State & A) -> State & A:
  (world,value) = result
  (State{world,tables,metadata,support,controls,error},value)

def query(-A:Type,state:State,operation:W.State -> W.State & A) -> State & A:
  State{world,tables,metadata,support,controls,error} = state
  queried(A,tables,metadata,support,controls,error,operation(world))

def snapshot(state:State,width:U32,height:U32) -> State & Result<&2,&2,String,R.Snapshot>:
  query(Result<&2,&2,String,R.Snapshot>,state,w => W.relative_snapshot(w,width,height))

def keyed(controls:PC.Controller,bindings:I.Bindings,code:U32,down:Bool) -> PC.Controller:
  PC.Controller{buttons,look,mouse,options} = controls
  PC.Controller{I.key(bindings,buttons,code,down),look,mouse,options}

def key(state:State,bindings:I.Bindings,code:U32,down:Bool) -> State:
  State{world,tables,metadata,support,controls,error} = state
  State{world,tables,metadata,support,keyed(controls,bindings,code,down),error}

def release(state:State) -> State:
  State{world,tables,metadata,support,controls,error} = state
  State{world,tables,metadata,support,PC.release(controls),error}

# Degree fields are authoritative; rendering has a checked rounded projection.
def projected(look:PL.State) -> F32 & F32:
  PL.State{yaw,pitch,previous_yaw,previous_pitch} = look
  (PL.mul(yaw,PL.float_bits(1016003125)),PL.mul(pitch,PL.float_bits(1016003125)))

def input_installed(tables:L.Tables,metadata:Metadata,support:SP.State,old:PC.Controller,next:PC.Controller,error:Maybe<&2,String>,result:W.State & Result<&2,&2,String,Unit>) -> State & Result<&2,&2,String,Unit>:
  (world,status) = result
  match status:
    case Fail{cause}: (State{world,tables,metadata,support,old,error},Fail{cause})
    case Done{unit}: (State{world,tables,metadata,support,next,error},Done{unit})

def input_projected(world:W.State,tables:L.Tables,metadata:Metadata,support:SP.State,old:PC.Controller,next:PC.Controller,error:Maybe<&2,String>,angles:F32 & F32) -> State & Result<&2,&2,String,Unit>:
  (yaw,pitch) = angles
  input_installed(tables,metadata,support,old,next,error,W.look(world,yaw,pitch))

def input_selected(world:W.State,tables:L.Tables,metadata:Metadata,support:SP.State,old:PC.Controller,error:Maybe<&2,String>,result:Result<&2,&2,PC.Error,PC.Controller>) -> State & Result<&2,&2,String,Unit>:
  match result:
    case Fail{cause}: (State{world,tables,metadata,support,old,error},Fail{PC.describe_error(cause)})
    case Done{+next}: input_projected(world,tables,metadata,support,old,next,error,projected(look(next)))

# Accepted complete packets publish key/mouse/look state and renderer projection
# together. A failed fold or projection retains the entire earlier controller.
def input(state:State,bindings:I.Bindings,packet:CC.Packet) -> State & Result<&2,&2,String,Unit>:
  State{world,tables,metadata,support,+controls,error} = state
  input_selected(world,tables,metadata,support,controls,error,PC.apply(controls,bindings,packet))

def fresh(world:W.State,tables:L.Tables) -> State:
  W.State{engine,body,yaw,pitch,palette,region,cache} = world
  State{W.State{engine,body,0.0,0.0,palette,region,cache},tables,Metadata{P.Input{0.0,0.0,0.0},False{},0,0,False{},0.0,0.0},SP.State{None{},False{}},PC.Controller{I.empty(),PL.State{0.0,0.0,0.0,0.0},MI.initial(),MI.default_options()},None{}}

def new(world:W.State,tables:L.Tables) -> State:
  fresh(world,tables)

# Read-only save projection. The degree fields are included directly; the
# bundle codec checks their agreement with the renderer's rounded radians.
def record_result(state:State,record:PR.Record) -> State & PR.Record:
  (state,record)

def record_view(engine:G.Engine,tables:L.Tables,+metadata:Metadata,+support:SP.State,+controls:PC.Controller,error:Maybe<&2,String>,+view:W.View) -> State & PR.Record:
  W.View{body,yaw,pitch,palette,region,cache} = view
  record_result(State{W.attach(engine,view),tables,metadata,support,controls,error},PR.Record{PS.Snapshot{compose(body,metadata),support,yaw,pitch,"minecraft:overworld"},look(controls)})

def record_extracted(tables:L.Tables,metadata:Metadata,support:SP.State,controls:PC.Controller,error:Maybe<&2,String>,result:G.Engine & W.View) -> State & PR.Record:
  (engine,view) = result
  record_view(engine,tables,metadata,support,controls,error,view)

def record(state:State) -> State & PR.Record:
  State{world,tables,metadata,support,controls,error} = state
  record_extracted(tables,metadata,support,controls,error,W.take(world))

def player_body(player:P.State) -> M.Body:
  P.State{body,input,jumping,delay,trigger,sync,speed,head} = player
  body

def restored_controls(old:PC.Controller,look:PL.State) -> PC.Controller:
  PC.Controller{buttons,old_look,mouse,options} = old
  PC.Controller{I.empty(),look,MI.initial(),options}

def restored_motion(state:State,record:PR.Record) -> State & Result<&2,&2,String,Unit>:
  match state record:
    case State{W.State{engine,old_body,old_yaw,old_pitch,palette,region,cache},tables,old_metadata,old_support,controls,error}
         PR.Record{PS.Snapshot{+player,support,yaw,pitch,"minecraft:overworld"},look}:
      (State{W.State{engine,player_body(player),yaw,pitch,palette,region,cache},tables,metadata(player),support,restored_controls(controls,look),None{}},Done{Unit{}})
    case _ _: (state,Fail{"current player runtime requires minecraft:overworld"})

def restore_selected(state:State,result:Result<&2,&2,PR.Error,PR.Record>) -> State & Result<&2,&2,String,Unit>:
  match result:
    case Fail{error}: (state,Fail{"invalid player record"})
    case Done{record}: restored_motion(state,record)

# Restore admission is atomic and clears ephemeral physical-device state.
def restore(state:State,record:PR.Record) -> State & Result<&2,&2,String,Unit>:
  restore_selected(state,PR.validate(record))

law paused_runtime_retains_every_owner_and_field:
  for driver:Driver
  for state:State
  {realtime_selected(driver,state,True{}) == state : State}

def paused_runtime_retains_every_owner_and_field(driver,state):
  {==}

law player_metadata_roundtrip:
  for body:M.Body
  for +fields:Metadata
  {metadata(compose(body,fields)) == fields : Metadata}

def player_metadata_roundtrip(body,fields):
  match fields:
    case Metadata{input,jumping,delay,trigger,sync,speed,head}: {==}
