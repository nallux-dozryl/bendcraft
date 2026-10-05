import Base
import ./local_player_cooking_edit.bend as E
import ./local_player_cooking.bend as K
import ./core.bend as C
import ./block_light.bend as L
import ./block_light_world.bend as W
import ./cooking_world.bend as CW
import ./cooking_world_edit.bend as Edit
import ./cooking_world_store.bend as Store
import ./cooking_world_bindings.bend as B
import ./player_core_edit.bend as P
import ./local_player_cooking_incarnation_guard.bend as Incarnation

# Equality includes the entire actual Core trie/arrays and Sidecar, including
# arbitrary entity/RNG/geometry owners, physical Details and recursive tails.
law disabled_build_retains_complete_core_and_cooking_owner:
  for world:C.World
  for sidecar:K.Sidecar
  for cap:C.Capability
  for position:C.Position
  for state:U32
  for expected:Nat
  for sequence:Nat
  {E.player_edit(world,sidecar,cap,position,state,expected,sequence,False{}) ==
    (world,sidecar,Fail{"local-cooking:interaction:permission-denied"}) : C.World & K.Sidecar & Result<&2,&2,String,Unit>}

law observer_retains_complete_core_and_cooking_owner:
  for world:C.World
  for sidecar:K.Sidecar
  for position:C.Position
  for state:U32
  for expected:Nat
  for sequence:Nat
  for maybuild:Bool
  {E.player_edit(world,sidecar,C.Observer{},position,state,expected,sequence,maybuild) ==
    (world,sidecar,Fail{"local-cooking:interaction:permission-denied"}) : C.World & K.Sidecar & Result<&2,&2,String,Unit>}

law invalid_player_retains_complete_core_and_cooking_owner:
  for world:C.World
  for sidecar:K.Sidecar
  for position:C.Position
  for state:U32
  for expected:Nat
  for sequence:Nat
  for maybuild:Bool
  {E.player_edit(world,sidecar,C.Player{0},position,state,expected,sequence,maybuild) ==
    (world,sidecar,Fail{"local-cooking:interaction:permission-denied"}) : C.World & K.Sidecar & Result<&2,&2,String,Unit>}

# This is the actual prepared edit continuation called by CWEdit.world_apply.
# A PlayerCoreEdit refusal cannot invoke changed_light or Store.change. Its
# complete returned Core and the incoming light/store owners remain together.
law refused_prepared_edit_retains_core_light_and_entry_owners:
  for operation:W.Prepared
  for position:C.Position
  for classification:B.Classification
  for light:L.State
  for loading:Maybe<&2,W.Cursor>
  for entries:List<&1,Store.Entry>
  for views:List<&2,Store.View>
  for world:C.World
  for error:P.Error
  {Edit.applied(operation,position,classification,light,loading,entries,views,(world,Fail{error})) ==
    (CW.State{W.State{world,light,loading},entries,CW.Idle{},[]},Fail{CW.Player{error}}) :
    CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>}

# This is the actual pre-write continuation, after existing admission. Every
# affine field and array in the incoming prepared owner is retained on overflow.
law incarnation_exhaustion_retains_prepared_owners:
  for world:W.State
  for entries:List<&1,Store.Entry>
  for views:List<&2,Store.View>
  for operation:W.Prepared
  for classification:B.Classification
  for cap:C.Capability
  for position:C.Position
  for state:U32
  for expected:Nat
  for sequence:Nat
  for maybuild:Bool
  {E.capacity_checked(world,entries,views,operation,classification,cap,position,state,expected,sequence,maybuild,False{}) ==
    (CW.State{world,entries,CW.Idle{},[]},Fail{CW.Authority{"incarnation-exhausted"}}) :
    CW.State & Result<&2,&2,CW.Error,List<&2,Store.Effect>>}

# The actual outer result seam cannot publish/reset any part of an arbitrary
# Sidecar on refusal, including its publisher, Details, clocks and affine tail.
law refused_capacity_result_retains_complete_owner:
  for world:C.World
  for sidecar:K.Sidecar
  {E.returned((world,sidecar,Fail{"local-cooking:authority:incarnation-exhausted"})) ==
    (world,sidecar,Fail{"local-cooking:authority:incarnation-exhausted"}) :
    C.World & K.Sidecar & Result<&2,&2,String,Unit>}

law no_reset_has_capacity_at_every_counter:
  for incarnations:Map<&2,Nat>
  for headers:List<&2,Incarnation.Header>
  {E.capacity(incarnations,Incarnation.Change{headers,None{}}) == True{} : Bool}
