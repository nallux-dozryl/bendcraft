import Base
import ./entity_scene_lighting_model.bend as M
import ./block_light.bend as B
import ./block_light_world.bend as BW
import ./block_light_registry.bend as BR
import ./sky_light_world.bend as SW
import ./sky_light_flat_authority.bend as F
import ./world_generation_settings.bend as G
import ./core.bend as C
import ./schedule.bend as Q

def registry(context:F.Context) -> String:
  F.Context{BR.Catalog{identity,count,shapes,states,rows},generation,air,sky,enabled} = context
  identity
def authority_valid(+context:F.Context,+count:U32) -> Bool:
  F.Context{BR.Catalog{identity,+registered,shapes,states,rows},generation,+air,sky,enabled} = context
  U32.is_eq(count,registered) && Bool.not(String.is_empty(identity)) &&
    U32.is_lt(air,count) && G.valid(generation) &&
    Maybe.is_some(&2,B.Descriptor,F.properties(context,air))

def join(epoch:String,authority:F.Context,block:BW.State,sky:SW.State) -> M.State:
  M.State{block,sky,authority,epoch}
def attached(light:B.State,loading:Maybe<&2,BW.Cursor>,authority:F.Context,epoch:String,
    result:C.World & SW.State) -> M.Attachment:
  (world,sky) = result
  M.Attached{M.State{BW.State{world,light,loading},sky,authority,epoch}}
def attach_checked(authority:F.Context,epoch:String,block:BW.State,valid:Bool) -> M.Attachment:
  match block valid:
    case block False{}: M.Retained{block,M.AuthorityUnavailable{}}
    case BW.State{world,light,loading} True{}:
      attached(light,loading,authority,epoch,SW.begin(world))

# Attach to the existing gameplay block owner; never BW.begin an already
# initialized world. It retains the current block FIFO, descriptors and cursor.
def attach(+epoch:String,+authority:F.Context,block:BW.State) -> M.Attachment:
  BW.State{C.World{tick,time,paused,daylight,revision,+count,sections,pending,events},light,loading} = block
  attach_checked(authority,epoch,
    BW.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},
    authority_valid(authority,count) && Bool.not(String.is_empty(epoch)))

def sky_error(status:Result<&2,&2,SW.Error,Unit>) -> Result<&2,&2,M.Error,Unit>:
  match status:
    case Fail{error}: Fail{M.SkyFailure{error}}
    case Done{u}: Done{u}
def block_error(status:Result<&2,&2,BW.Error,Unit>) -> Result<&2,&2,M.Error,Unit>:
  match status:
    case Fail{error}: Fail{M.BlockFailure{error}}
    case Done{u}: Done{u}

def progress_sky(block:BW.State,authority:F.Context,epoch:String,bp:BW.Progress,
    result:SW.State & SW.Progress) -> M.State & M.Progress:
  (sky,sp) = result
  (M.State{block,sky,authority,epoch},M.Progress{bp,sp})
def progress_block(sky:SW.State,authority:F.Context,epoch:String,
    result:BW.State & BW.Progress) -> M.State & M.Progress:
  (block,bp) = result
  progress_sky(block,authority,epoch,bp,SW.progress(sky))
def progress(state:M.State) -> M.State & M.Progress:
  M.State{block,sky,authority,epoch} = state
  progress_block(sky,authority,epoch,BW.progress(block))

def sky_loaded(light:B.State,loading:Maybe<&2,BW.Cursor>,authority:F.Context,epoch:String,
    result:C.World & (SW.State & Result<&2,&2,SW.Error,Unit>)) ->
    M.State & Result<&2,&2,M.Error,Unit>:
  (world,(sky,status)) = result
  (M.State{BW.State{world,light,loading},sky,authority,epoch},
    sky_error(status))
def load_sky(state:M.State,budget:Nat) -> M.State & Result<&2,&2,M.Error,Unit>:
  M.State{BW.State{world,light,loading},sky,+authority,epoch} = state
  sky_loaded(light,loading,authority,epoch,
    SW.load_resume(~F.Context,~F.properties,~F.bounds,~F.policy,~F.enabled,~F.occludes,
      authority,budget,world,sky))
def block_loaded(sky:SW.State,authority:F.Context,epoch:String,budget:Nat,
    result:BW.State & Result<&2,&2,BW.Error,Unit>) -> M.State & Result<&2,&2,M.Error,Unit>:
  (block,status) = result
  match status:
    case Fail{error}: (M.State{block,sky,authority,epoch},Fail{M.BlockFailure{error}})
    case Done{u}: load_sky(M.State{block,sky,authority,epoch},budget)

# Independent budgets count real block acquisition and sky lifecycle work.
# A missing descriptor/section retains both cursors and all actual Core arrays.
def load(block_budget:Nat,sky_budget:Nat,state:M.State) -> M.State & Result<&2,&2,M.Error,Unit>:
  M.State{block,sky,+authority,epoch} = state
  block_loaded(sky,authority,epoch,sky_budget,
    BW.load_resume(~F.Context,~F.properties,~F.enabled,authority,block_budget,block))
def advanced(sky:SW.State,+authority:F.Context,epoch:String,sky_budget:Nat,
    result:BW.State & BW.Progress) -> M.State & M.Progress:
  (block,bp) = result
  progress_sky(block,authority,epoch,bp,
    SW.advance(~F.Context,~F.occludes,authority,sky_budget,sky))
def advance(block_budget:Nat,sky_budget:Nat,state:M.State) -> M.State & M.Progress:
  M.State{block,sky,+authority,epoch} = state
  advanced(sky,authority,epoch,sky_budget,
    BW.advance(~F.Context,~F.occludes,authority,block_budget,block))

def sky_status(block:BW.State,authority:F.Context,epoch:String,
    result:SW.State & Result<&2,&2,SW.Error,Unit>) -> M.State & Result<&2,&2,M.Error,Unit>:
  (sky,status) = result
  (M.State{block,sky,authority,epoch},
    sky_error(status))
# This is specifically sky enablement, with Java's retained-field semantics.
# It does not pretend to implement block-light section enable/disable callbacks.
def sky_enabled(position:C.Position,enabled:Bool,state:M.State) -> M.State & Result<&2,&2,M.Error,Unit>:
  M.State{block,sky,authority,epoch} = state
  sky_status(block,authority,epoch,SW.set_enabled(position,enabled,sky))
def sky_sources(position:C.Position,state:M.State) -> M.State & Result<&2,&2,M.Error,Unit>:
  M.State{block,sky,authority,epoch} = state
  sky_status(block,authority,epoch,SW.propagate_sources(position,sky))

def invalidate(sky:SW.State) -> SW.State:
  SW.State{light,phase,chunks,domains,repairs,revision} = sky
  SW.State{light,phase,chunks,domains,repairs,None{}}
def sky_reacquired(light:B.State,loading:Maybe<&2,BW.Cursor>,authority:F.Context,epoch:String,
    result:C.World & SW.State) -> M.State:
  (world,sky) = result
  M.State{BW.State{world,light,loading},sky,authority,epoch}
# Explicit complete reacquisition is needed after an unsupported residency or
# post-commit sky failure; it is not an invisible per-frame rebuild.
def reacquire_sky(state:M.State) -> M.State:
  M.State{BW.State{world,light,loading},sky,authority,epoch} = state
  sky_reacquired(light,loading,authority,epoch,SW.rebuild(world,sky))

def committed(light:B.State,loading:Maybe<&2,BW.Cursor>,authority:F.Context,epoch:String,
    result:C.World & (SW.State & Result<&2,&2,SW.Error,Unit>)) ->
    M.State & Result<&2,&2,M.Error,M.Commit>:
  (world,(sky,status)) = result
  match status:
    case Done{u}: (M.State{BW.State{world,light,loading},sky,authority,epoch},Done{M.Applied{}})
    case Fail{error}:
      (M.State{BW.State{world,light,loading},invalidate(sky),authority,epoch},Done{M.RepairRequired{error}})
def applied(+mutation:C.Mutation,sky:SW.State,+authority:F.Context,epoch:String,
    result:BW.State & Result<&2,&2,BW.Error,Unit>) -> M.State & Result<&2,&2,M.Error,M.Commit>:
  (BW.State{world,light,loading},status) = result
  match status:
    case Fail{error}: (M.State{BW.State{world,light,loading},sky,authority,epoch},Fail{M.BlockFailure{error}})
    case Done{u}:
      committed(light,loading,authority,epoch,
        SW.accept_result(~F.Context,~F.properties,authority,mutation,sky,(world,Done{Unit{}})))
def apply_checked(+mutation:C.Mutation,state:M.State,preflight:Result<&2,&2,SW.Error,Unit>) ->
    M.State & Result<&2,&2,M.Error,M.Commit>:
  M.State{block,sky,+authority,epoch} = state
  match preflight:
    case Fail{error}: (M.State{block,sky,authority,epoch},Fail{M.SkyFailure{error}})
    case Done{u}: applied(mutation,sky,authority,epoch,
      BW.apply(~F.Context,~F.properties,~F.enabled,authority,block,mutation))

# Low-level mutation seam, for an already-authorized sole-owner continuation.
# Both catalog preflights happen before Core mutation. SW accepts only success.
# Successful edits during sky repair explicitly restart SW's current-Core
# bootstrap, as specified by SW.accepted; they never publish a stale frame.
def apply(+mutation:C.Mutation,state:M.State) -> M.State & Result<&2,&2,M.Error,M.Commit>:
  M.State{block,sky,+authority,epoch} = state
  apply_checked(mutation,M.State{block,sky,authority,epoch},
    SW.preflight(~F.Context,~F.properties,authority,mutation))
def apply_finished_checked(+stamp:Q.Stamp,+mutation:C.Mutation,state:M.State,
    preflight:Result<&2,&2,SW.Error,Unit>) -> M.State & Result<&2,&2,M.Error,M.Commit>:
  M.State{block,sky,+authority,epoch} = state
  match preflight:
    case Fail{error}: (M.State{block,sky,authority,epoch},Fail{M.SkyFailure{error}})
    case Done{u}: applied(mutation,sky,authority,epoch,
      BW.apply_finished(stamp,BW.apply(~F.Context,~F.properties,~F.enabled,authority,block,mutation)))
def apply_finished(stamp:Q.Stamp,+mutation:C.Mutation,state:M.State) ->
    M.State & Result<&2,&2,M.Error,M.Commit>:
  M.State{block,sky,+authority,epoch} = state
  apply_finished_checked(stamp,mutation,M.State{block,sky,authority,epoch},
    SW.preflight(~F.Context,~F.properties,authority,mutation))

def admitted(sky:SW.State,authority:F.Context,epoch:String,
    result:BW.State & Result<&2,&2,BW.Error,Unit>) -> M.State & Result<&2,&2,M.Error,Unit>:
  (block,status) = result
  (M.State{block,sky,authority,epoch},
    block_error(status))
def admit(cap:C.Capability,stamp:Q.Stamp,mutation:C.Mutation,state:M.State) ->
    M.State & Result<&2,&2,M.Error,Unit>:
  M.State{block,sky,+authority,epoch} = state
  admitted(sky,authority,epoch,
    BW.admit(~F.Context,~F.properties,~F.enabled,authority,block,cap,stamp,mutation))

# The caller can take both exact engines out for an outer engine continuation.
# No Core clone, shadow world, implicit tick, or clock normalization is involved.
def separate(state:M.State) -> BW.State & (SW.State & (F.Context & String)):
  M.State{block,sky,authority,epoch} = state
  (block,(sky,(authority,epoch)))
def split(state:M.State) -> BW.State & M.Detached:
  M.State{block,sky,authority,epoch} = state
  (block,M.Detached{sky,authority,epoch})
def rejoin(block:BW.State,detached:M.Detached) -> M.State:
  M.Detached{sky,authority,epoch} = detached
  M.State{block,sky,authority,epoch}
