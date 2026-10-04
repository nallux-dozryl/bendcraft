import Base
import ../src/runtime_block_inside.bend as R
import ../src/player_block_inside_stuck.bend as P
import ../src/player_block_inside_stuck_motion.bend as PM
import ../src/player_block_inside_sweep_world.bend as W
import ../src/player_block_inside_sweep_travel.bend as ST
import ../src/local_travel_history.bend as TH
import ../src/local_move_history.bend as MH
import ../src/local_move_world.bend as LM
import ../src/local_collision_world.bend as E
import ../src/client_world.bend as CW
import ../src/support.bend as SP
import ../src/player_fall_history.bend as H
import ../src/movement.bend as M
import ../src/travel.bend as T
import ../src/f64.bend as F
import ../src/geometry.bend as A
import ../src/game.bend as G
import ../src/core.bend as C
import ../src/registry.bend as B
import ../src/section.bend as Section
import ../src/section_map.bend as Sections
import ../src/schedule.bend as Q
import ../src/world_codec.bend as WC
import ./player_block_inside_stuck.bend as O
import ./player_block_inside_sweep.bend as Sweep

# This tests the new adapter, not an X/local_player_runtime/Scene consumer. Existing immutable
# original observations provide its record fields; no travel is executed here.
# Core/Registry signatures reuse the unchanged capacity/bucket observer.
type Owner is Data:
  Owner{core: O.Owner, header: String, children: String, tail: List<&2, Owner>}

type BodyRead is Data:
  BodyRead{body: M.Body, rest: List<&2, String>, tail: List<&2, BodyRead>}

type ReceiverRead is Data:
  ReceiverRead{receiver: P.Receiver, rest: List<&2, String>, tail: List<&2, ReceiverRead>}

type Input is Data:
  Input{body: M.Body, prepared: M.Body, old_position: M.Vec3,
        original: M.Vec3, displacement: M.Vec3, changed: Bool,
        framed: Bool, malformed: Bool, traversal: Nat, reads: Nat,
        tail: List<&2, Input>}

type Return is Data:
  Return{context: O.Context, retained: Bool, previous: Owner,
         receiver: P.Receiver, status: Result<&2,&2,R.Error,W.Observation>,
         trace: Bool, tail: List<&2, Return>}

def flag(word: String) -> Bool:
  U32.is_ne(O.number(word), 0)

def float_word(word: U32) -> F32:
  match word:
    case U32{value}: F32{value}

def box_text(box: A.AABB) -> String:
  A.AABB{a,b,c,d,e,f} = box
  O.wide(a) ++ "," ++ O.wide(b) ++ "," ++ O.wide(c) ++ "," ++ O.wide(d) ++ "," ++ O.wide(e) ++ "," ++ O.wide(f)

def body_text(body: M.Body) -> String:
  M.Body{position,box,velocity,width,height,ground,horizontal,vertical,below} = body
  O.vector(position) ++ "/" ++ box_text(box) ++ "/" ++ O.vector(velocity) ++ "/" ++
    U32.show(F32.bits(width)) ++ "," ++ U32.show(F32.bits(height)) ++ "/" ++
    O.flag(ground) ++ O.flag(horizontal) ++ O.flag(vertical) ++ O.flag(below)

def bounds(value: CW.Bounds) -> String:
  CW.Bounds{x,y,z,width,height,depth} = value
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++
    U32.show(width) ++ "," ++ U32.show(height) ++ "," ++ U32.show(depth)

def palette(value: CW.Palette) -> String:
  CW.Palette{air,stone,dirt,planks} = value
  U32.show(air) ++ "," ++ U32.show(stone) ++ "," ++ U32.show(dirt) ++ "," ++ U32.show(planks)

def optional_palette(value: Maybe<&2,CW.Palette>) -> String:
  match value:
    case None{}: "none"
    case Some{value}: palette(value)

def raw_blocks(values: List<&2,CW.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case CW.RawBlock{CW.Cell{x,y,z,boundary},state,material} <> rest:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++
        U32.show(boundary) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ raw_blocks(rest)

def cache(value: Maybe<&2,CW.SnapshotCache>) -> String:
  match value:
    case None{}: "none"
    case Some{CW.SnapshotCache{revision,region,colors,blocks}}:
      Nat.show(revision) ++ "/" ++ bounds(region) ++ "/" ++ palette(colors) ++ "/" ++ raw_blocks(blocks)

def support(value: SP.State) -> String:
  match value:
    case SP.State{None{},missing}: "none:" ++ O.flag(missing)
    case SP.State{Some{T.BlockPos{x,y,z}},missing}:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ ":" ++ O.flag(missing)

def header(view: CW.View, supporting: SP.State, minor: LM.MinorState) -> String:
  CW.View{body,yaw,pitch,colors,region,cached} = view
  LM.MinorState{minor} = minor
  body_text(body) ++ "|" ++ U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|" ++
    optional_palette(colors) ++ "|" ++ bounds(region) ++ "|" ++ cache(cached) ++ "|" ++ support(supporting) ++ "|" ++ O.flag(minor)

def owner_text(owner: Owner) -> String:
  Owner{O.Owner{world,registry,receiver,core_tail},header,children,tail} = owner
  world ++ "|" ++ registry ++ "|" ++ receiver ++ "|" ++ header ++ "|" ++ children

def restore_snapshot(frame: PM.Frame, children: String, result: P.State & O.Owner) -> MH.State & Owner:
  match frame result:
    case PM.Frame{+view,+support,+minor,tail} Tuple{P.State{world,registry,receiver,history,unused},core}:
      (MH.State{CW.attach(G.Engine{world,registry},view),support,minor,history,tail},
        Owner{core,header(view,support,minor),children,[]})

def leaf_extracted(result: P.State & PM.Frame) -> MH.State & Owner:
  (state,frame) = result
  restore_snapshot(frame,"",O.snapshot(state))

def leaf_snapshot(motion: MH.State) -> MH.State & Owner:
  match motion:
    case MH.State{world,support,minor,history,Nil{}}:
      leaf_extracted(PM.extract(MH.State{world,support,minor,history,[]},P.empty()))
    case other:
      (other,Owner{O.Owner{"noncanonical","noncanonical","noncanonical",[]},"unsupported-child-depth","",[]})

def child_snapshots(values: List<&1,MH.State>) -> List<&1,MH.State> & String:
  match values:
    case Nil{}: ([],"")
    case child <> rest:
      P.paired(MH.State,Owner,List<&1,MH.State> & String,leaf_snapshot(child),child => observation =>
        P.paired(List<&1,MH.State>,String,List<&1,MH.State> & String,child_snapshots(rest),rest => text =>
          (child <> rest,owner_text(observation) ++ "\nchild\n" ++ text)))

def snapshot_extracted(text: String, result: P.State & PM.Frame) -> MH.State & Owner:
  (state,frame) = result
  restore_snapshot(frame,text,O.snapshot(state))

def snapshot_children(world: CW.State, support: SP.State, minor: LM.MinorState,
                      history: H.State, receiver: P.Receiver,
                      result: List<&1,MH.State> & String) -> MH.State & Owner:
  (children,text) = result
  snapshot_extracted(text,PM.extract(MH.State{world,support,minor,history,children},receiver))

def snapshot(motion: MH.State, receiver: P.Receiver) -> MH.State & Owner:
  MH.State{world,support,minor,history,children} = motion
  snapshot_children(world,support,minor,history,receiver,child_snapshots(children))

def same_owner(a: Owner, b: Owner, failed: Bool) -> Bool:
  Owner{core,header,children,tail} = a
  Owner{next,next_header,next_children,next_tail} = b
  O.same_owner(core,next,failed) && String.eq(header,next_header) && String.eq(children,next_children)

# Distinct small affine child owners test tail retention without another
# heavyweight registry load. Every capacity cell and inactive block is observed.
def child(+tag: U32) -> MH.State:
  +body = M.Body.new(M.Vec3{F.from_u32(tag),M.one(),M.zero()},0.6,1.8,M.Vec3.zero(),False{})
  world = C.World{U32.to_nat(tag),37n,False{},True{},91n,3,
    Sections.Bucket{[Sections.Entry{"child:" ++ U32.show(tag),Section.Section{[4294967295 : U32*4n]}}]},
    [Q.Pending{Q.Stamp{101n,tag,9n},C.TimeSet{31n}}],[C.Applied{Q.Stamp{3n,tag,4n},17n}]}
  registry = B.Registry{[B.Block{tag,"child:block",0,0,4294967295,[]} : B.Block*2n],MLeaf{"child",tag},0,3}
  MH.State{CW.State{G.Engine{world,registry},body,float_word(2147483648),float_word(2143289345),None{},CW.Bounds{tag,0,1,2,3,4},None{}},
    SP.State{Some{T.BlockPos{tag,4294967295,17}},True{}},LM.MinorState{True{}},H.State{H.History{F.F64{2147483648,tag}}},[]}

def wrap_motion(body: M.Body, state: P.State) -> MH.State & P.Receiver:
  P.State{world,registry,receiver,history,tail} = state
  +colors = CW.Palette{0,1,2,3}
  +region = CW.Bounds{4294967295,7,11,3,5,9}
  cached = CW.SnapshotCache{97n,region,colors,[CW.RawBlock{CW.Cell{0,1,2,3},4294967295,13},CW.RawBlock{CW.Cell{7,8,9,10},2,17}]}
  (MH.State{CW.State{G.Engine{world,registry},body,float_word(2147483648),float_word(2143289345),Some{colors},region,Some{cached}},
    SP.State{Some{T.BlockPos{4294967295,2147483648,7}},True{}},LM.MinorState{True{}},history,[child(3),child(5)]},receiver)

def carrier(input: Input) -> TH.Outcome:
  # Unused numerical carrier fields are explicit inert data. The compared
  # production record projection reads original captured Body/request/displacement.
  Input{+final,prepared,old,+original,displacement,changed,framed,malformed,traversal,reads,tail} = input
  +transition = M.Transition{final,displacement,False{},changed}
  +move = LM.Outcome{LM.Motion{transition,[]},E.Observation{original,[]},LM.BodySnapshot{final,[]},None{},[]}
  TH.Outcome{TH.Preparation{T.Prepared{prepared,original,0.0,0.0,0.0,M.zero(),M.one(),False{}},[]},
    MH.Outcome{move,H.History{M.zero()},[]},LM.Motion{transition,[]},[]}

def hooks(input: Input, context: O.Context) -> R.Hooks:
  Input{body,prepared,+old,original,displacement,changed,framed,malformed,+traversal,+reads,tail} = input
  O.Context{+facts,+level,+removed,+physics,+alive,context_tail} = context
  +request = R.Hooks{facts,level,old,"minecraft:overworld",removed,physics,alive,traversal,reads,[]}
  R.Hooks{facts,level,old,"minecraft:overworld",removed,physics,alive,traversal,reads,
    P.choose(List<&2,R.Hooks>,[request],[],malformed)}

def apply_framed(receiver: P.Receiver, +request: R.Hooks, +outcome: TH.Outcome,
                 result: P.State & PM.Frame) -> MH.State & P.Receiver & Result<&2,&2,R.Error,W.Observation>:
  (state,frame) = result
  R.framed(receiver,state,frame,request,ST.travel_record(outcome))

def apply_mode(motion: MH.State, +receiver: P.Receiver, +request: R.Hooks,
               +outcome: TH.Outcome, framed: Bool) -> MH.State & P.Receiver & Result<&2,&2,R.Error,W.Observation>:
  match framed:
    case False{}: R.after_successful_travel(motion,receiver,request,outcome)
    case True{}: apply_framed(receiver,request,outcome,PM.extract(motion,receiver))

def apply(motion: MH.State, receiver: P.Receiver, +input: Input, context: O.Context) -> MH.State & P.Receiver & Result<&2,&2,R.Error,W.Observation>:
  Input{body,prepared,old,original,displacement,changed,framed,malformed,traversal,reads,tail} = input
  apply_mode(motion,receiver,hooks(input,context),carrier(input),framed)

def status_failed(status: Result<&2,&2,R.Error,W.Observation>) -> Bool:
  match status:
    case Fail{cause}: True{}
    case Done{observation}: False{}

def emit_trace(id: String, trace: Bool, reads: List<&2,W.Read>, callbacks: List<&2,W.Callback>) -> IO(Unit):
  match trace:
    case False{}: IO.pure(Unit,Unit{})
    case True{}: IO.print(id ++ "\ttraces\t" ++ Sweep.reads_text(reads) ++ "\t" ++ Sweep.callbacks_text(callbacks))

def emit_status(+id: String, status: Result<&2,&2,R.Error,W.Observation>,
                +held: P.Receiver, +history: H.History, trace: Bool) -> IO(Unit):
  match status:
    case Fail{cause}: IO.print(id ++ "\terror\t" ++ R.error_text(cause) ++ "\t" ++ O.receiver_text(held,history))
    case Done{W.Observation{P.Observation{+observed,fall,reset,effect_reads},reads,callbacks}}:
      do IO<Unit>:
        emit_trace(id,trace,reads,callbacks)
        IO.print(id ++ "\tok\t" ++ O.receiver_text(held,history) ++ "\t" ++ O.flag(reset))
        IO.print(id ++ "\tauthority\t" ++ O.flag(R.same_receiver(held,observed) && String.eq(O.receiver_text(held,history),O.receiver_text(observed,fall))))

def returned_extracted(+id: String, info: Return, +valid: Bool, result: P.State & PM.Frame) -> IO(O.State):
  Return{context,retained,previous,receiver,+status,trace,info_tail} = info
  (active,frame) = result
  P.State{world,registry,+held,H.State{+history},tail} = active
  do IO<O.State>:
    emit_status(id,status,held,history,trace)
    IO.print(id ++ "\towners\t" ++ O.flag(valid))
    return O.State{P.State{world,registry,held,H.State{history},tail},context,None{},retained && valid,[]}

def returned(id: String, +info: Return, result: MH.State & Owner) -> IO(O.State):
  Return{context,retained,previous,+receiver,+status,trace,info_tail} = info
  (motion,next) = result
  returned_extracted(id,info,same_owner(previous,next,status_failed(status)),PM.extract(motion,receiver))

def applied(id: String, context: O.Context, retained: Bool, previous: Owner, trace: Bool,
            result: MH.State & P.Receiver & Result<&2,&2,R.Error,W.Observation>) -> IO(O.State):
  (motion,+receiver,status) = result
  returned(id,Return{context,retained,previous,receiver,status,trace,[]},snapshot(motion,receiver))

def checkpointed(id: String, +context: O.Context, retained: Bool, +receiver: P.Receiver,
                 +input: Input, result: MH.State & Owner) -> IO(O.State):
  (motion,previous) = result
  Input{body,prepared,old,original,displacement,changed,+framed,malformed,traversal,reads,tail} = input
  applied(id,context,retained,previous,framed,apply(motion,receiver,input,context))

def joined_wrapped(id: String, context: O.Context, retained: Bool, +input: Input,
                   result: MH.State & P.Receiver) -> IO(O.State):
  (motion,+receiver) = result
  checkpointed(id,context,retained,receiver,input,snapshot(motion,receiver))

def joined(id: String, state: O.State, +input: Input) -> IO(O.State):
  O.State{active,+context,checkpoint,retained,tail} = state
  Input{+body,prepared,old,original,displacement,changed,framed,malformed,traversal,reads,input_tail} = input
  joined_wrapped(id,context,retained,input,wrap_motion(body,active))

def body_fields(fields: List<&2,String>) -> Maybe<&2,BodyRead>:
  match fields:
    case pxh <> pxl <> pyh <> pyl <> pzh <> pzl <>
         axh <> axl <> ayh <> ayl <> azh <> azl <> bxh <> bxl <> byh <> byl <> bzh <> bzl <>
         vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> rest:
      Some{BodyRead{M.Body{M.Vec3{F.F64{O.number(pxh),O.number(pxl)},F.F64{O.number(pyh),O.number(pyl)},F.F64{O.number(pzh),O.number(pzl)}},
        A.AABB{F.F64{O.number(axh),O.number(axl)},F.F64{O.number(ayh),O.number(ayl)},F.F64{O.number(azh),O.number(azl)},F.F64{O.number(bxh),O.number(bxl)},F.F64{O.number(byh),O.number(byl)},F.F64{O.number(bzh),O.number(bzl)}},
        M.Vec3{F.F64{O.number(vxh),O.number(vxl)},F.F64{O.number(vyh),O.number(vyl)},F.F64{O.number(vzh),O.number(vzl)}},
        float_word(O.number(width)),float_word(O.number(height)),flag(ground),flag(horizontal),flag(vertical),flag(below)},rest,[]}}
    case _: None{}

def join_displacement(id: String, state: O.State, input: Input, parsed: Maybe<&2,O.VectorRead>) -> IO(O.State):
  Input{body,prepared,old,original,previous,changed,framed,malformed,traversal,reads,tail} = input
  match parsed:
    case Some{O.VectorRead{displacement,changed <> Nil{}}}:
      joined(id,state,Input{body,prepared,old,original,displacement,flag(changed),framed,malformed,traversal,reads,[]})
    case _: IO.die(O.State,2,"invalid join displacement")

def join_original(id: String, state: O.State, input: Input, parsed: Maybe<&2,O.VectorRead>) -> IO(O.State):
  Input{body,prepared,old,previous,displacement,changed,framed,malformed,traversal,reads,tail} = input
  match parsed:
    case Some{O.VectorRead{original,rest}}:
      join_displacement(id,state,Input{body,prepared,old,original,displacement,changed,framed,malformed,traversal,reads,[]},O.read_vector(rest))
    case _: IO.die(O.State,2,"invalid join original request")

def join_old(id: String, state: O.State, input: Input, parsed: Maybe<&2,O.VectorRead>) -> IO(O.State):
  Input{body,prepared,previous,original,displacement,changed,framed,malformed,traversal,reads,tail} = input
  match parsed:
    case Some{O.VectorRead{old,rest}}:
      join_original(id,state,Input{body,prepared,old,original,displacement,changed,framed,malformed,traversal,reads,[]},O.read_vector(rest))
    case _: IO.die(O.State,2,"invalid join old position")

def join_prepared(id: String, state: O.State, input: Input, parsed: Maybe<&2,BodyRead>) -> IO(O.State):
  Input{body,previous,old,original,displacement,changed,framed,malformed,traversal,reads,tail} = input
  match parsed:
    case Some{BodyRead{prepared,rest,body_tail}}:
      join_old(id,state,Input{body,prepared,old,original,displacement,changed,framed,malformed,traversal,reads,[]},O.read_vector(rest))
    case _: IO.die(O.State,2,"invalid join preparation body")

def join_body(id: String, state: O.State, framed: Bool, malformed: Bool, traversal: Nat, reads: Nat,
              parsed: Maybe<&2,BodyRead>) -> IO(O.State):
  match parsed:
    case Some{BodyRead{+body,rest,tail}}:
      join_prepared(id,state,Input{body,body,M.Vec3.zero(),M.Vec3.zero(),M.Vec3.zero(),False{},framed,malformed,traversal,reads,[]},body_fields(rest))
    case _: IO.die(O.State,2,"invalid join held body")

def receiver_impact(multiplier: M.Vec3, grace: U32, present: Bool,
                    parsed: Maybe<&2,O.VectorRead>) -> Maybe<&2,ReceiverRead>:
  match parsed:
    case Some{O.VectorRead{impact,rest}}:
      Some{ReceiverRead{P.Receiver{multiplier,P.Impulse{grace,P.choose(Maybe<&2,M.Vec3>,Some{impact},None{},present)}},rest,[]}}
    case _: None{}

def receiver_fields(parsed: Maybe<&2,O.VectorRead>) -> Maybe<&2,ReceiverRead>:
  match parsed:
    case Some{O.VectorRead{multiplier,grace <> present <> rest}}: receiver_impact(multiplier,O.number(grace),flag(present),O.read_vector(rest))
    case _: None{}

def compare_right(id: String, state: O.State, receiver: P.Receiver,
                  parsed: Maybe<&2,ReceiverRead>) -> IO(O.State):
  match parsed:
    case Some{ReceiverRead{other,Nil{},tail}}:
      do IO<O.State>:
        IO.print(id ++ "\tcompare\t" ++ O.flag(R.same_receiver(receiver,other)))
        return state
    case _: IO.die(O.State,2,"invalid comparison receiver")

def compare_left(id: String, state: O.State, parsed: Maybe<&2,ReceiverRead>) -> IO(O.State):
  match parsed:
    case Some{ReceiverRead{receiver,rest,tail}}: compare_right(id,state,receiver,receiver_fields(O.read_vector(rest)))
    case _: IO.die(O.State,2,"invalid comparison receiver")

def consumed(id: String, state: O.State, physics: Bool, parsed: Maybe<&2,ReceiverRead>) -> IO(O.State):
  match parsed:
    case Some{ReceiverRead{receiver,Nil{},tail}}:
      do IO<O.State>:
        IO.print(id ++ "\tconsume\t" ++ O.receiver_text(R.consume(receiver,physics),H.History{M.zero()}))
        return state
    case _: IO.die(O.State,2,"invalid consume receiver")

def operation(fields: List<&2,String>, state: O.State, count: U32, identity: String) -> IO(O.State):
  match fields:
    case id <> "compare" <> rest: compare_left(id,state,receiver_fields(O.read_vector(rest)))
    case id <> "consume" <> physics <> rest: consumed(id,state,flag(physics),receiver_fields(O.read_vector(rest)))
    case id <> "join" <> framed <> malformed <> traversal <> reads <> rest:
      join_body(id,state,flag(framed),flag(malformed),U32.to_nat(O.number(traversal)),U32.to_nat(O.number(reads)),body_fields(rest))
    case id <> "seed" <> rest: O.seed_vector(id,state,O.read_vector(rest))
    case id <> "context" <> flags <> level <> rest: O.context_position(id,state,O.number(flags),O.number(level),O.read_vector(rest))
    case id <> "world" <> path <> Nil{}: O.world_file(id,state,path,count,identity)
    case id <> "raw-cell" <> x <> y <> z <> value <> Nil{}:
      O.raw_cell(id,state,C.Position{"minecraft:overworld",O.number(x),O.number(y),O.number(z)},O.number(value))
    case "" <> Nil{}: IO.pure(O.State,state)
    case _: IO.die(O.State,2,"invalid runtime adapter request")

def operations(lines: List<&2,String>, state: O.State, +count: U32, +identity: String) -> IO(O.State):
  match lines:
    case Nil{}: IO.pure(O.State,state)
    case line <> rest:
      do IO<O.State>:
        next: O.State <- operation(String.split(line,Chr{9}),state,count,identity)
        operations(rest,next,count,identity)

def loaded(state: O.State, count: U32, identity: String, result: Result<&2,&2,B.Error,String>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,2,B.error_text(cause))
    case Done{text}:
      do IO<Unit>:
        final: O.State <- operations(String.split(text,Chr{10}),state,count,identity)
        O.final_report(final)

def initial(registry: B.Registry, requests: String, count: U32, identity: String,
            result: Result<&2,&1,String,WC.Loaded>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,2,cause)
    case Done{WC.Loaded{world,peer}}:
      do IO<Unit>:
        text: Result<&2,&2,B.Error,String> <- B.read_text(requests)
        loaded(O.State{P.State{world,registry,P.empty(),H.State{H.History{M.zero()}},[]},
          O.Context{P.Player{False{},False{}},P.ClientLevel{},False{},False{},True{},[]},None{},True{},[]},count,identity,text)

def registry_loaded(world: String, requests: String, +count: U32, +identity: String,
                    result: Result<&2,&1,B.Error,B.Registry>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,2,B.error_text(cause))
    case Done{registry}:
      do IO<Unit>:
        bytes: List<&2,U32> <- O.raw_file(world)
        initial(registry,requests,count,identity,WC.decode(bytes,count,identity))

def main_args(args: List<String>) -> IO(Unit):
  match args:
    case registry <> world <> requests <> count <> identity <> Nil{}:
      do IO<Unit>:
        parsed: Result<&2,&1,B.Error,B.Registry> <- B.load(registry)
        registry_loaded(world,requests,O.number(count),identity,parsed)
    case _: IO.die(Unit,2,"runtime adapter test arguments")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.get_args(),main_args)
