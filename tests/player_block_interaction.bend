import Base
import ../src/player_block_interaction.bend as BI
import ../src/player_core_edit.bend as Edit
import ../src/core.bend as C
import ../src/schedule.bend as Q
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/movement.bend as M
import ../src/f64.bend as F

def require(ok:Bool,message:String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)

def bits_equal(a:F.F64,b:F.F64) -> Bool:
  match a b:
    case F.F64{hi,lo} F.F64{other,tail}: U32.is_eq(hi,other) && U32.is_eq(lo,tail)

def vector_equal(a:M.Vec3,b:M.Vec3) -> Bool:
  match a b:
    case M.Vec3{x,y,z} M.Vec3{a,b,c}: bits_equal(x,a) && bits_equal(y,b) && bits_equal(z,c)

def face_equal(a:BI.Face,b:BI.Face) -> Bool:
  match a b:
    case BI.Down{} BI.Down{}: True{}
    case BI.Up{} BI.Up{}: True{}
    case BI.North{} BI.North{}: True{}
    case BI.South{} BI.South{}: True{}
    case BI.West{} BI.West{}: True{}
    case BI.East{} BI.East{}: True{}
    case _ _: False{}

def position_equal(a:C.Position,b:C.Position) -> Bool:
  match a b:
    case C.Position{d,x,y,z} C.Position{e,a,b,c}:
      String.eq(d,e) && U32.is_eq(x,a) && U32.is_eq(y,b) && U32.is_eq(z,c)

def hit_expect(position:C.Position,state:U32,face:BI.Face,location:M.Vec3,inside:Bool,hit:Maybe<&2,BI.Hit>) -> IO(Unit):
  match hit:
    case None{}: IO.die(Unit,1,"expected full-cube hit")
    case Some{BI.Hit{other,stored,side,point,interior}}:
      require(position_equal(position,other) && U32.is_eq(state,stored) && face_equal(face,side) &&
        vector_equal(location,point) && U32.is_eq(Bool.to_u32(inside),Bool.to_u32(interior)),"wrong full-cube hit")

def hit_absent(hit:Maybe<&2,BI.Hit>) -> Bool:
  match hit:
    case None{}: True{}
    case Some{value}: False{}

def geometry() -> IO(Unit):
  +origin : C.Position = C.Position{"minecraft:overworld",0,0,0}
  +half = F.from_f32(0.5)
  +minus = F.neg(F.from_u32(1))
  +two = F.from_u32(2)
  +zero = F.from_u32(0)
  +one = F.from_u32(1)
  do IO<Unit>:
    hit_expect(origin,1,BI.West{},M.Vec3{zero,half,half},False{},
      BI.clip_cube(origin,1,M.Vec3{minus,half,half},M.Vec3{two,half,half}))
    hit_expect(origin,1,BI.Down{},M.Vec3{half,zero,half},False{},
      BI.clip_cube(origin,1,M.Vec3{half,minus,half},M.Vec3{half,two,half}))
    hit_expect(origin,1,BI.North{},M.Vec3{half,half,zero},False{},
      BI.clip_cube(origin,1,M.Vec3{half,half,minus},M.Vec3{half,half,two}))
    hit_expect(origin,1,BI.West{},M.Vec3{zero,zero,zero},False{},
      BI.clip_cube(origin,1,M.Vec3{minus,minus,minus},M.Vec3{two,two,two}))
    require(hit_absent(BI.clip_cube(origin,1,M.Vec3{minus,half,half},M.Vec3{zero,half,half})),"terminal plane must be strict")
    require(hit_absent(BI.clip_cube(origin,1,M.Vec3{half,half,half},M.Vec3{half,half,half})),"zero ray must miss")
    require(hit_absent(BI.clip_cube(origin,1,M.Vec3{half,half,half},M.Vec3{F.from_f32(0.5001),half,half})),"short squared-length ray must miss")
    require(face_equal(BI.nearest_x(one,one,one),BI.Up{}),"inside nearest three-axis tie order")
    require(face_equal(BI.nearest_x(one,zero,one),BI.South{}),"inside nearest x/z tie order")
    require(face_equal(BI.nearest_x(zero,zero,zero),BI.North{}),"inside nearest zero default")
    require(face_equal(BI.nearest_x(F.F64{1072693248,1},one,zero),BI.Up{}),"inside nearest must narrow to float before comparing")

def loaded(result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(C.World):
  (world,status) = result
  match status:
    case Fail{error}: IO.die(C.World,1,"fixture Core write/create failed")
    case Done{unit}: IO.pure(C.World,world)

def block_expect(state:U32,result:C.World & Result<&2,&2,C.Error,U32>) -> IO(C.World):
  (world,status) = result
  match status:
    case Fail{cause}: IO.die(C.World,1,"expected retained loaded section")
    case Done{value}:
      do IO<C.World>:
        require(U32.is_eq(state,value),"world block mismatch")
        return world

def clock_expect(tick:Nat,revision:Nat,pending:Nat,result:C.World & C.Clock) -> IO(C.World):
  (world,C.Clock{time,daytime,paused,daylight,rev,queued}) = result
  do IO<C.World>:
    require(Nat.is_eq(tick,time) && Nat.is_eq(revision,rev) && Nat.is_eq(pending,queued),"edit changed clock, revision or pending work incorrectly")
    return world

def error_code(error:Edit.Error) -> U32:
  match error:
    case Edit.PermissionDenied{}: 1
    case Edit.InvalidSequence{}: 2
    case Edit.StaleRevision{expected,actual}: 3
    case Edit.CoreError{C.InvalidState{state}}: 4
    case Edit.CoreError{C.MissingSection{key}}: 5
    case Edit.CoreError{C.UnknownDimension{dimension}}: 6
    case _: 99

def refused(code:U32,result:C.World & Result<&2,&2,Edit.Error,Unit>) -> IO(C.World):
  (world,status) = result
  match status:
    case Done{unit}: IO.die(C.World,1,"invalid player edit succeeded")
    case Fail{error}:
      do IO<C.World>:
        require(U32.is_eq(code,error_code(error)),"wrong player edit refusal")
        return world

def accepted(result:C.World & Result<&2,&2,Edit.Error,Unit>) -> IO(C.World):
  (world,status) = result
  match status:
    case Fail{cause}: IO.die(C.World,1,"authorized player edit refused")
    case Done{unit}: IO.pure(C.World,world)

def event_expected(events:List<&2,C.CoreEvent>) -> Bool:
  match events:
    case C.Applied{Q.Stamp{tick,peer,sequence},revision} <> Nil{}:
      Nat.is_eq(tick,41n) && U32.is_eq(peer,23) && Nat.is_eq(sequence,9n) && Nat.is_eq(revision,1n)
    case _: False{}

def event_checked(result:C.World & List<&2,C.CoreEvent>) -> IO(C.World):
  (world,events) = result
  do IO<C.World>:
    require(event_expected(events),"accepted edit must retain actual tick/peer/sequence")
    return world

def core_admission() -> IO(Unit):
  +origin : C.Position = C.Position{"minecraft:overworld",0,0,0}
  +missing : C.Position = C.Position{"minecraft:overworld",16,0,0}
  do IO<Unit>:
    a:C.World <- loaded(C.create_section(C.advance(41n,C.new(3)),origin,0))
    b:C.World <- refused(1,Edit.edit(a,C.Observer{},origin,1,0n,1n,True{}))
    c:C.World <- refused(1,Edit.edit(b,C.Developer{},origin,1,0n,2n,True{}))
    d:C.World <- refused(1,Edit.edit(c,C.Player{0},origin,1,0n,3n,True{}))
    e:C.World <- refused(1,Edit.edit(d,C.Player{23},origin,1,0n,4n,False{}))
    f:C.World <- refused(2,Edit.edit(e,C.Player{23},origin,1,0n,0n,True{}))
    g:C.World <- refused(3,Edit.edit(f,C.Player{23},origin,1,1n,5n,True{}))
    h:C.World <- refused(4,Edit.edit(g,C.Player{23},origin,3,0n,6n,True{}))
    i:C.World <- refused(5,Edit.edit(h,C.Player{23},missing,1,0n,7n,True{}))
    j:C.World <- refused(6,Edit.edit(i,C.Player{23},C.Position{"custom:void",0,0,0},1,0n,8n,True{}))
    k:C.World <- clock_expect(41n,0n,0n,C.clock(j))
    l:C.World <- block_expect(0,C.read_block(k,origin))
    m:C.World <- accepted(Edit.edit(l,C.Player{23},origin,2,0n,9n,True{}))
    n:C.World <- block_expect(2,C.read_block(m,origin))
    o:C.World <- clock_expect(41n,1n,0n,C.clock(n))
    p:C.World <- event_checked(C.events(o))
    q:C.World <- refused(3,Edit.edit(p,C.Player{23},origin,1,0n,10n,True{}))
    r:C.World <- block_expect(2,C.read_block(q,origin))
    s:C.World <- event_checked(C.events(r))
    return Unit{}

# This explicitly synthetic registry tests registry-derived dispatch, never
# substitutes IDs for the installed Java reference in product execution.
def registry_loaded(status:Result<&2,&1,B.Error,B.Registry>) -> IO(B.Registry):
  match status:
    case Fail{cause}: IO.die(B.Registry,1,"synthetic registry fixture failed")
    case Done{registry}: IO.pure(B.Registry,registry)

def registry_fixture() -> IO(B.Registry):
  registry_loaded(B.Registry.parse("block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n0\tminecraft:air\t0\t1\t0\t[]\n1\tminecraft:stone\t1\t1\t1\t[]\n2\tminecraft:dirt\t2\t1\t2\t[]\n3\tminecraft:oak_planks\t3\t1\t3\t[]\n4\tminecraft:water\t4\t1\t4\t[]\n"))

def pick_expected(position:C.Position,face:BI.Face,result:G.Engine & Result<&2,&2,String,Maybe<&2,BI.Hit>>) -> IO(G.Engine):
  (engine,status) = result
  match status:
    case Fail{message}: IO.die(G.Engine,1,"loaded supported ray refused")
    case Done{hit}:
      do IO<G.Engine>:
        hit_expect(position,1,face,M.Vec3{F.from_f32(0.5),F.from_f32(0.5),F.from_u32(1)},False{},hit)
        return engine

def pick_refused(message:String,result:G.Engine & Result<&2,&2,String,Maybe<&2,BI.Hit>>) -> IO(G.Engine):
  (engine,status) = result
  match status:
    case Done{hit}: IO.die(G.Engine,1,"unsupported/missing ray did not refuse")
    case Fail{actual}:
      do IO<G.Engine>:
        require(String.eq(message,actual),"wrong authoritative ray refusal")
        return engine

def engine_written(registry:B.Registry,result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(G.Engine):
  do IO<G.Engine>:
    world:C.World <- loaded(result)
    return G.Engine{world,registry}

def engine_write(engine:G.Engine,position:C.Position,state:U32) -> IO(G.Engine):
  G.Engine{world,registry} = engine
  engine_written(registry,C.write_block(world,position,state))

def authoritative_pick() -> IO(Unit):
  +origin : C.Position = C.Position{"minecraft:overworld",0,0,0}
  +target : C.Position = C.Position{"minecraft:overworld",0,0,1}
  +from : M.Vec3 = M.Vec3{F.from_f32(0.5),F.from_f32(0.5),F.from_f32(0.5)}
  +to : M.Vec3 = M.Vec3{F.from_f32(0.5),F.from_f32(0.5),F.from_u32(5)}
  do IO<Unit>:
    registry:B.Registry <- registry_fixture()
    world:C.World <- loaded(C.create_section(C.new(5),origin,0))
    world:C.World <- loaded(C.write_block(world,target,1))
    engine:G.Engine <- pick_expected(target,BI.North{},BI.pick(G.Engine{world,registry},from,to))
    engine:G.Engine <- engine_write(engine,target,4)
    engine:G.Engine <- pick_refused("interaction:unsupported-shape:minecraft:water",BI.pick(engine,from,to))
    engine:G.Engine <- engine_write(engine,target,0)
    engine:G.Engine <- pick_refused("missing-section:minecraft:overworld/0/0/1",BI.pick(engine,from,M.Vec3{F.from_f32(0.5),F.from_f32(0.5),F.from_u32(20)}))
    return Unit{}

def run() -> IO(Unit):
  do IO<Unit>:
    geometry()
    core_admission()
    authoritative_pick()
    IO.print("PASS player block interaction: exact cube clip/ties/gate, authoritative DDA/shape refusals, player authority/sequence/revision/state/section gates and real accepted stamp")

def main() -> IO(Unit):
  run()
