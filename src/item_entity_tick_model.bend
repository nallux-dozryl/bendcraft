import Base
import ./cooking_effect_entities_model.bend as E
import ./vanilla_entity_fields.bend as V
import ./f64.bend as F
import ./geometry.bend as A
import ./inventory.bend as I
import ./campfire_authority_items.bend as CI
import ./cooking_effect_geometry.bend as G
import ./support.bend as S
import ./travel.bend as Travel
import ./random.bend as R

# Runtime fields absent from the persisted cooking spawn Record. Fresh defaults
# require an actual fresh-spawn join; a restored/missing runtime is not guessed.
type Fluid is Data:
  Fluid{height:F.F64,flow:V.Vec3,count:U32,present:Bool}
type Fluids is Data:
  Fluids{water:Fluid,lava:Fluid,eye_water:Bool,eye_lava:Bool,fast_lava:Bool}
type Movement is Data:
  Movement{from:V.Vec3,to:V.Vec3,requested:V.Vec3}
type Physical is Data:
  Physical{no_gravity:Bool,no_physics:Bool,suppress_bounce:Bool,
    horizontal:Bool,vertical:Bool,below:Bool,minor_horizontal:Bool,stuck:V.Vec3}
type BaseState is Data:
  BaseState{invulnerable_time:U32,boarding_cooldown:U32,was_touching_water:Bool,
    was_eye_water:Bool,powder_snow:Bool,was_powder_snow:Bool,sprinting:Bool,
    swimming:Bool,freezing:Bool,silent:Bool,last_position:Maybe<&2,V.Vec3>,speed:V.Vec3}
type Runtime is Data:
  Runtime{physical:Physical,base:BaseState,fluids:Fluids,pending:List<&2,Movement>,movements:List<&2,Movement>,support:S.State,tail:List<&2,Runtime>}
type Owner is Type:
  Owner{entity:E.Entity,runtime:Runtime}
type RuntimeEntry is Data:
  RuntimeEntry{id:U32,runtime:Runtime}
type State is Type:
  State{entities:E.State,runtimes:List<&2,RuntimeEntry>,sound:Maybe<&2,R.Source>}
type Snapshot is Data:
  Snapshot{record:E.Record,runtime:Runtime}
type Error is Data:
  Refused{reason:String}
  EntityError{cause:E.Error}
type Query is Data:
  FluidQuery{snapshot:Snapshot,box:A.AABB}
  CollisionQuery{snapshot:Snapshot,box:A.AABB}
  EscapeQuery{snapshot:Snapshot,point:V.Vec3}
  MovementQuery{snapshot:Snapshot,box:A.AABB,requested:V.Vec3}
  SupportQuery{snapshot:Snapshot,position:V.Vec3}
  BlocksQuery{snapshot:Snapshot,movements:List<&2,Movement>,last_movements:Bool}
  LifecycleQuery{snapshot:Snapshot}
# Full event values are owned immutable publications; accepted delivery is a
# separate actual sound/particle/damage/portal/scheduler consumer transaction.
type Publication is Data:
  Removed{id:U32}
  Synced{id:U32}
  Merge{source:U32,target:U32,count:U32}
  Splash{position:V.Vec3,volume:F32,pitch:F32,high:Bool}
  SeededSplash{position:V.Vec3,volume:F32,pitch:F32,high:Bool,seed:R.Bits64}
  SplashEvent{position:V.Vec3}
  GroundEvent{position:V.Vec3,support:Travel.BlockPos,state:U32}
  Particle{bubble:Bool,position:V.Vec3,velocity:V.Vec3}
  Bounce{id:U32}

# Complete cells inside coverage, including air. Fluids retain actual holder/tag
# membership, float surface heights and world-computed flow, not a host tick.
type Cell is Data:
  Cell{state:U32,x:U32,y:U32,z:U32,water:Bool,lava:Bool,height:F32,camera_height:F32,
    flow:V.Vec3,fluid:Bool,full_collision:Bool,friction:F32,speed:F32,
    restitution:F32,suppresses_bounce:Bool,neutral_inside:Bool,neutral_step:Bool,
    water_block:Bool,bubble_column:Bool,fall_resetting:Bool,tail:List<&2,Cell>}
type Context is Data:
  Context{items:CI.Context,geometry:G.Context,cells:List<&2,Cell>,
    cells_coverage:A.AABB,min_y:U32,server:Bool,fast_lava:Bool,
    loaded_fluid_sections:Bool,entity_queries_complete:Bool,
    rain:Bool,neutral_portal:Bool,neutral_mount:Bool,
    step_budget:Nat,fall_clip:Maybe<&2,Bool>,tail:List<&2,Context>}
type Plan is Data:
  Plan{snapshot:Snapshot,records:List<&2,E.Record>,publications:List<&2,Publication>}
# Both routes share physical preparation. A settled empty-item discard requires
# removal authority, while Physics requires its real move callback before query.
type Prepared is Data:
  Physics{snapshot:Snapshot,publications:List<&2,Publication>,old_position:V.Vec3,old_velocity:V.Vec3}
  Settled{plan:Plan}
