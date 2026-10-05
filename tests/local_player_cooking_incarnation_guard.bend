import Base
import ../src/core.bend as C
import ../src/section.bend as Section
import ../src/section_map.bend as M
import ../src/section_map_update.bend as U
import ../src/schedule.bend as Q
import ../src/block_light.bend as L
import ../src/block_light_world.bend as W
import ../src/cooking_world.bend as CW
import ../src/cooking_world_store.bend as S
import ../src/cooking_world_bindings.bend as B
import ../src/furnace_authority.bend as F
import ../src/cooking_recipe.bend as K
import ../src/inventory.bend as I
import ../src/local_player_cooking_incarnation_guard.bend as G
import ./core_refusal.bend as Raw
import ./cooking_world_lifecycle.bend as Life

# These tests use actual C.apply as the application-status oracle and the
# existing complete Core observer. No prospective World is copied or applied.
def unit_status(a:Result<&2,&2,C.Error,Unit>,b:Result<&2,&2,C.Error,Unit>) -> Bool:
  match a b:
    case Done{unit} Done{other}: True{}
    case Fail{error} Fail{other}: Raw.error_equal(error,other)
    case _ _: False{}
def compared(expected:Result<&2,&2,C.Error,Unit>,result:C.World & Result<&2,&2,C.Error,Unit>,
    next:C.World -> IO(Unit)) -> IO(Unit):
  (world,status) = result
  do IO<Unit>:
    Raw.require(unit_status(expected,status),"prospective status differs from actual C.apply")
    next(world)
def actual(values:List<&2,C.Mutation>,statuses:List<&2,Result<&2,&2,C.Error,Unit>>,world:C.World) -> IO(Unit):
  match values statuses:
    case Nil{} Nil{}: Life.guard("prospective ordered statuses agree with actual apply",True{})
    case value <> rest status <> tail: compared(status,C.apply(world,value),world => actual(rest,tail,world))
    case _ _: IO.die(Unit,2,"prospective status count differs")
def probed_image(values:List<&2,C.Mutation>,statuses:List<&2,Result<&2,&2,C.Error,Unit>>,before:Raw.WorldImage,
    result:C.World & Raw.WorldImage) -> IO(Unit):
  (world,after) = result
  do IO<Unit>:
    Life.guard("prospective retains complete raw Core owner",Raw.worlds_equal(before,after))
    actual(values,statuses,world)
def probed(values:List<&2,C.Mutation>,before:Raw.WorldImage,
    result:C.World & List<&2,Result<&2,&2,C.Error,Unit>>) -> IO(Unit):
  (world,statuses) = result
  probed_image(values,statuses,before,Raw.world_image(world))
def probe(+values:List<&2,C.Mutation>,result:C.World & Raw.WorldImage) -> IO(Unit):
  (world,before) = result
  probed(values,before,C.prospective_results(world,values))
def core_probes() -> IO(Unit):
  +a = Life.position(0)
  +b = Life.position(16)
  +first : C.Position = C.Position{"minecraft:overworld",192145824,578455600,1247992560}
  +second : C.Position = C.Position{"minecraft:overworld",343086944,1893213456,2117633648}
  do IO<Unit>:
    probe([C.BlockSet{a,1},C.SectionCreate{a,0},C.BlockSet{a,2},C.SectionCreate{a,3},
      C.SectionCreate{b,1},C.BlockSet{b,3},C.TimeSet{19n},C.DaylightSet{True{}}],
      Raw.world_image(Raw.fixture(M.EmptySections{},a)))
    probe([C.SectionCreate{a,0},C.BlockSet{a,1},C.SectionCreate{b,3},C.TimeSet{7n}],
      Raw.world_image(Raw.fixture(M.Bucket{[M.Entry{"malformed-payload",Section.Section{[91 : U32*4n]}}]},a)))
    probe([C.SectionCreate{first,1},C.BlockSet{second,3},C.BlockSet{first,2},C.SectionCreate{second,0}],
      Raw.world_image(Raw.fixture(Raw.odd_path(U.path(32n,M.hash(C.section_key(first))),
        M.Bucket{[M.Entry{C.section_key(second),Section.Section.new(3)},
          M.Entry{C.section_key(first),Section.Section.new(1)},
          M.Entry{C.section_key(first),Section.Section{[99 : U32*4n]}}]}),first)))

def map_equal(~A:Data,~equal:A -> A -> Bool,a:Map<&2,A>,b:Map<&2,A>) -> Bool:
  match a b:
    case MTip{} MTip{}: True{}
    case MLeaf{x,v} MLeaf{y,w}: String.eq(x,y) && equal(v,w)
    case MNode{x,lo,hi} MNode{y,other_lo,other_hi}:
      Nat.is_eq(x,y) && map_equal(~A,~equal,lo,other_lo) && map_equal(~A,~equal,hi,other_hi)
    case _ _: False{}
def unit_equal(a:Unit,b:Unit) -> Bool: True{}
def cell_equal(a:Maybe<&2,L.Cell>,b:Maybe<&2,L.Cell>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{L.Cell{L.Descriptor{s,e,d},v}} Some{L.Cell{L.Descriptor{ss,ee,dd},vv}}:
      U32.is_eq(s,ss) && U32.is_eq(e,ee) && U32.is_eq(d,dd) && U32.is_eq(v,vv)
    case _ _: False{}
def light_cells() -> Map<&2,Maybe<&2,L.Cell>>:
  Map.set(&2,Maybe<&2,L.Cell>,MLeaf{"absent-marker",None{}},"cell-marker",Some{L.Cell{L.Descriptor{1,13,0},7}})
def light() -> L.State:
  L.State{light_cells(),[Life.position(3)],[Life.position(2)],MLeaf{"queued-marker",Unit{}},99n}
def light_valid(value:L.State) -> Bool:
  match value:
    case L.State{cells,a <> Nil{},b <> Nil{},queued,99n}:
      map_equal(~Maybe<&2,L.Cell>,~cell_equal,cells,light_cells()) &&
        B.equal_position(a,Life.position(3)) && B.equal_position(b,Life.position(2)) &&
        map_equal(~Unit,~unit_equal,queued,MLeaf{"queued-marker",Unit{}})
    case _: False{}
def padded(owner:F.State) -> F.State:
  F.State{I.Inventory{cells,length},frame} = owner
  F.State{I.Inventory{Array.set(I.Slot,cells,3,Life.stack("minecraft:dirt",6)),length},frame}
def entries() -> List<&1,S.Entry>:
  [S.Entry{Life.position(0),Life.furnace(1,False{}),S.Furnace{padded(F.install(Life.snapshot()))}}]
def entry_valid(value:S.Entry) -> Bool:
  match value:
    case S.Entry{position,B.Binding{1,"minecraft:furnace",B.Furnace{K.Smelting{}},False{},1,2},
      S.Furnace{F.State{I.Inventory{ANode{ANode{ALeaf{a},ALeaf{b}},ANode{ALeaf{c},ALeaf{d}}},3},
        F.Frame{K.Smelting{},11,13,17,19,speed,Some{"fixture:smelt"},F.Use{"fixture:smelt",2} <> Nil{}}}}}:
      B.equal_position(position,Life.position(0)) && K.slot_equal(a,Life.stack("minecraft:iron_ore",2)) &&
        K.slot_equal(b,Life.stack("minecraft:coal",1)) && K.slot_equal(c,Life.stack("minecraft:iron_ingot",3)) &&
        K.slot_equal(d,Life.stack("minecraft:dirt",6)) && U32.is_eq(F32.bits(speed),1065353216)
    case _: False{}
def entries_valid(values:List<&1,S.Entry>,present:Bool) -> Bool:
  match values present:
    case Nil{} False{}: True{}
    case entry <> Nil{} True{}: entry_valid(entry)
    case _ _: False{}
def counters(value:Nat) -> Map<&2,Nat>:
  Map.set(&2,Nat,MLeaf{"unrelated-counter",17n},B.key(Life.position(0)),value)
def due(values:List<&2,C.Mutation>,+sequence:Nat) -> List<&2,Q.Pending<C.Mutation>>:
  match values:
    case Nil{}: [Q.Pending{Q.Stamp{100n,31,37n},C.DaylightSet{True{}}}]
    case head <> rest: Q.Pending{Q.Stamp{30n,0,sequence},head} <> due(rest,1n+sequence)
def marked(+values:List<&2,C.Mutation>,present:Bool,result:CW.State) -> CW.State:
  CW.State{W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},old_light,loading},old_entries,phase,keys} = result
  CW.State{W.State{C.World{29n,13499n,False{},False{},7n,count,sections,due(values,1n),
    [C.Applied{Q.Stamp{11n,5,13n},3n}]},light(),None{}},
    Bool.pick(List<&1,S.Entry>,present,entries(),[]),CW.Idle{},[]}
def prepared(values:List<&2,C.Mutation>,present:Bool,next:CW.State -> IO(Unit),result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(Unit):
  (world,status) = result
  match status:
    case Fail{error}: IO.die(Unit,2,"guard fixture original write refused")
    case Done{unit}: next(marked(values,present,CW.State{W.State{world,L.new(),None{}},[],CW.Idle{},[]}))
def created(+values:List<&2,C.Mutation>,+present:Bool,next:CW.State -> IO(Unit),result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(Unit):
  (world,status) = result
  match status:
    case Fail{error}: IO.die(Unit,2,"guard fixture original create refused")
    case Done{unit}: prepared(values,present,next,C.write_block(world,Life.position(0),Bool.pick(U32,present,1,0)))
def initial(values:List<&2,C.Mutation>,present:Bool,next:CW.State -> IO(Unit)) -> IO(Unit):
  created(values,present,next,C.create_section(C.new(4),Life.position(0),0))
def refused_values(label:String,present:Bool,before:Raw.WorldImage,world:C.World,after:Raw.WorldImage,
    light:L.State,loading:Maybe<&2,W.Cursor>,entities:List<&1,S.Entry>,phase:CW.Phase,keys:List<&2,String>,status:Result<&2,&2,CW.Error,Unit>) -> IO(Unit):
  match loading phase keys status:
    case None{} CW.Idle{} Nil{} Fail{CW.Authority{"local-cooking:incarnation-exhausted"}}:
      Life.guard(label,Raw.worlds_equal(before,after) && light_valid(light) && entries_valid(entities,present))
    case _ _ _ _: IO.die(Unit,2,"MAX guard refused with wrong phase/cursor/status")
def refused_image(label:String,present:Bool,before:Raw.WorldImage,light:L.State,loading:Maybe<&2,W.Cursor>,
    entities:List<&1,S.Entry>,phase:CW.Phase,keys:List<&2,String>,status:Result<&2,&2,CW.Error,Unit>,result:C.World & Raw.WorldImage) -> IO(Unit):
  (world,after) = result
  refused_values(label,present,before,world,after,light,loading,entities,phase,keys,status)
def refused(label:String,present:Bool,before:Raw.WorldImage,result:CW.State & Result<&2,&2,CW.Error,Unit>) -> IO(Unit):
  (CW.State{W.State{world,light,loading},entities,phase,keys},status) = result
  refused_image(label,present,before,light,loading,entities,phase,keys,status,Raw.world_image(world))
def ready_refusal(label:String,present:Bool,token:Nat,light:L.State,loading:Maybe<&2,W.Cursor>,entities:List<&1,S.Entry>,
    phase:CW.Phase,keys:List<&2,String>,result:C.World & Raw.WorldImage) -> IO(Unit):
  (world,before) = result
  refused(label,present,before,CW.start_tick_owned(~Unit,~Life.properties,~Life.enabled,Unit{},Life.context(),counters(token),0n,
    CW.State{W.State{world,light,loading},entities,phase,keys}))
def fail_case(label:String,present:Bool,token:Nat,owner:CW.State) -> IO(Unit):
  CW.State{W.State{world,light,loading},entities,phase,keys} = owner
  ready_refusal(label,present,token,light,loading,entities,phase,keys,Raw.world_image(world))
def resets(values:List<&2,S.Effect>) -> Nat:
  match values:
    case Nil{}: 0n
    case S.OwnerReset{position} <> rest: 1n+resets(rest)
    case _ <> rest: resets(rest)
def successful(label:String,wanted:Nat,result:CW.State & Result<&2,&2,CW.Error,Unit>) -> IO(Unit):
  match result:
    case (CW.State{W.State{C.World{30n,time,False{},False{},revision,count,sections,
        Q.Pending{Q.Stamp{100n,31,37n},C.DaylightSet{True{}}} <> Nil{},events},light,None{}},entities,CW.Cooking{30n,effects},Nil{}},Done{unit}):
      Life.guard(label,Nat.is_eq(time,13499n) && Nat.is_eq(resets(effects),wanted))
    case _: IO.die(Unit,2,"owned start did not publish exactly one due tick")
def pass_case(label:String,token:Nat,ack:Nat,wanted:Nat,owner:CW.State) -> IO(Unit):
  successful(label,wanted,CW.start_tick_owned(~Unit,~Life.properties,~Life.enabled,Unit{},Life.context(),counters(token),ack,owner))
def scenarios() -> IO(Unit):
  +p = Life.position(0)
  do IO<Unit>:
    initial([C.BlockSet{p,0}],True{},owner => fail_case("MAX teardown retains full Core/light/physical furnace",True{},G.maximum(),owner))
    initial([C.BlockSet{p,3},C.BlockSet{p,1}],True{},owner => fail_case("MAX-1 rejects second replacement before either write",True{},Nat.sub(G.maximum(),1n),owner))
    initial([C.BlockSet{p,0},C.BlockSet{p,1},C.BlockSet{p,0}],True{},owner => fail_case("remove recreate remove counts both teardown markers",True{},Nat.sub(G.maximum(),1n),owner))
    initial([C.BlockSet{p,1},C.BlockSet{p,0}],False{},owner => fail_case("new entry after absent owner is tracked before later teardown",False{},G.maximum(),owner))
    fail_case("accepted section create overlay and 4096 fresh headers admit later reset before any allocation",False{},G.maximum(),
      marked([C.SectionCreate{p,1},C.BlockSet{p,0}],False{},CW.State{W.State{C.new(4),L.new(),None{}},[],CW.Idle{},[]}))
    initial([C.BlockSet{p,2},C.BlockSet{p,0}],True{},owner => fail_case("late refusal restores earlier prospective LIT edit and whole due queue",True{},G.maximum(),owner))
    initial([C.SectionCreate{p,3},C.BlockSet{p,2},C.BlockSet{p,1}],True{},owner => pass_case("rejected existing-section fill and same-block properties have no resets",G.maximum(),0n,0n,owner))
    initial([C.BlockSet{Life.position(32),0}],True{},owner => pass_case("rejected missing-section write cannot reset loaded owner",G.maximum(),0n,0n,owner))
    initial([C.BlockSet{p,3},C.BlockSet{p,1}],True{},owner => pass_case("two replacements admit at exactly two remaining tokens",Nat.sub(G.maximum(),2n),0n,2n,owner))
    initial([C.BlockSet{p,0}],True{},owner => pass_case("acknowledged reset prefix does not consume a token twice",G.maximum(),1n,1n,owner))

def main() -> IO(Unit):
  do IO<Unit>:
    core_probes()
    scenarios()
