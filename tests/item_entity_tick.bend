import Base
import ../src/json.bend as J
import ../src/crafting_recipe_decoder.bend as D
import ../src/crafting_recipe_components.bend as C
import ../src/campfire_authority_items.bend as CI
import ../src/campfire_authority_loader.bend as L
import ../src/item_entity_tick.bend as Tick
import ../src/item_entity_tick_model.bend as T
import ../src/item_entity_tick_fields.bend as U
import ../src/item_entity_tick_merge.bend as Merge
import ../src/item_entity_tick_scene.bend as Scene
import ../src/cooking_effect_entities_model.bend as E
import ../src/cooking_effect_geometry.bend as G
import ../src/cooking_effect_geometry_voxel.bend as Grid
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/vanilla_entity_fields.bend as V
import ../src/player_look.bend as PL
import ../src/random.bend as R
import ../src/support.bend as S
import ../src/travel.bend as Travel
import ./cooking_effect_entities_values.bend as Values
import ../src/inventory.bend as I
import ../src/item_entity_tick_motion.bend as M


def item_raw(+raw:J.Value,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,I.Slot>:
  match raw:
    case J.JNull{}: Done{I.InvEmpty{}}
    case _:
      do Result<&2,&2,String,I.Slot>:
        id : String <- D.text_field(raw,"id")
        count : U32 <- D.number_field(raw,"count")
        patch : String <- C.patch_text(J.member(raw,"components"))
        D.resolve_output(I.InvStack{I.ItemKey{id,patch},count},defaults)
def uuid(+value:J.Value) -> Result<&2,&2,String,Maybe<&2,E.Uuid>>:
  match value:
    case J.JNull{}: Done{None{}}
    case J.JArray{+a <> +b <> Nil{}}:
      do Result<&2,&2,String,Maybe<&2,E.Uuid>>:
        +a : R.Bits64 <- Values.read_bits(a)
        +b : R.Bits64 <- Values.read_bits(b)
        return Some{E.Uuid{a,b}}
    case _: Fail{"expected UUID words"}
def uuid_field(+value:J.Value,name:String) -> Result<&2,&2,String,Maybe<&2,E.Uuid>>:
  do Result<&2,&2,String,Maybe<&2,E.Uuid>>:
    +raw : J.Value <- D.field(value,name)
    uuid(raw)
def read_record(+raw:J.Value,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,E.Record>:
  do Result<&2,&2,String,E.Record>:
    +c : J.Value <- D.field(raw,"common")
    +common : E.Common <- Values.read_common(c)
    +i : J.Value <- D.field(raw,"item")
    +item : I.Slot <- item_raw(i,defaults)
    age : U32 <- D.number_field(raw,"age")
    delay : U32 <- D.number_field(raw,"pickup_delay")
    health : U32 <- D.number_field(raw,"health")
    bob : U32 <- D.number_field(raw,"bob")
    thrower : Maybe<&2,E.Uuid> <- uuid_field(raw,"thrower")
    target : Maybe<&2,E.Uuid> <- uuid_field(raw,"target")
    return E.Item{common,item,age,delay,health,thrower,target,PL.float_bits(bob)}
def float_field(+value:J.Value,name:String) -> Result<&2,&2,String,F32>:
  do Result<&2,&2,String,F32>:
    raw : U32 <- D.number_field(value,name)
    return PL.float_bits(raw)
def read_cell(+raw:J.Value) -> Result<&2,&2,String,T.Cell>:
  do Result<&2,&2,String,T.Cell>:
    state : U32 <- D.number_field(raw,"state")
    x : U32 <- D.number_field(raw,"x")
    y : U32 <- D.number_field(raw,"y")
    z : U32 <- D.number_field(raw,"z")
    water : Bool <- Values.flag(raw,"water")
    lava : Bool <- Values.flag(raw,"lava")
    height : F32 <- float_field(raw,"height")
    camera : F32 <- float_field(raw,"camera_height")
    +flow : V.Vec3 <- Values.vector_field(raw,"flow")
    fluid : Bool <- Values.flag(raw,"fluid")
    full : Bool <- Values.flag(raw,"full")
    friction : F32 <- float_field(raw,"friction")
    speed : F32 <- float_field(raw,"speed")
    restitution : F32 <- float_field(raw,"restitution")
    suppress : Bool <- Values.flag(raw,"suppresses")
    inside : Bool <- Values.flag(raw,"neutral_inside")
    step : Bool <- Values.flag(raw,"neutral_step")
    return T.Cell{state,x,y,z,water,lava,height,camera,flow,fluid,full,friction,speed,restitution,suppress,inside,step,False{},False{},False{},[]}
def read_cells(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,T.Cell>>:
  match values:
    case Nil{}: Done{[]}
    case +head <> +rest:
      do Result<&2,&2,String,List<&2,T.Cell>>:
        +head : T.Cell <- read_cell(head)
        tail : List<&2,T.Cell> <- read_cells(rest)
        return head <> tail
def box_words(value:List<&2,J.Value>) -> Result<&2,&2,String,A.AABB>:
  match value:
    case +a <> +b <> +c <> +d <> +e <> +f <> Nil{}:
      do Result<&2,&2,String,A.AABB>:
        +a : R.Bits64 <- Values.read_bits(a)
        +b : R.Bits64 <- Values.read_bits(b)
        +c : R.Bits64 <- Values.read_bits(c)
        +d : R.Bits64 <- Values.read_bits(d)
        +e : R.Bits64 <- Values.read_bits(e)
        +f : R.Bits64 <- Values.read_bits(f)
        return A.AABB{Values.read_double(a),Values.read_double(b),Values.read_double(c),Values.read_double(d),Values.read_double(e),Values.read_double(f)}
    case _: Fail{"expected AABB words"}
def obstacle(+box:A.AABB) -> Result<&2,&2,String,G.Obstacle>:
  do Result<&2,&2,String,G.Obstacle>:
    +shape : Grid.Shape <- Grid.create(box)
    return G.Obstacle{box,shape,False{}}
def boxes(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,G.Obstacle>>:
  match values:
    case Nil{}: Done{[]}
    case +head <> +rest:
      do Result<&2,&2,String,List<&2,G.Obstacle>>:
        raw : List<&2,J.Value> <- D.array(head)
        +box : A.AABB <- box_words(raw)
        +head : G.Obstacle <- obstacle(box)
        tail : List<&2,G.Obstacle> <- boxes(rest)
        return head <> tail
def read_boxes(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,G.Obstacle>>:
  match values:
    case Nil{}: Done{[]}
    case +head <> +rest:
      do Result<&2,&2,String,List<&2,G.Obstacle>>:
        raw : List<&2,J.Value> <- Values.array_field(head,"boxes")
        head : List<&2,G.Obstacle> <- boxes(raw)
        tail : List<&2,G.Obstacle> <- read_boxes(rest)
        return List.append(&2,G.Obstacle,head,tail)
def uuid_value(value:Maybe<&2,E.Uuid>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{E.Uuid{+a,+b}}: J.JArray{[Values.bits(a),Values.bits(b)]}
def record_value(+value:E.Record) -> J.Value:
  match value:
    case E.Item{+c,+item,+age,+delay,+health,+thrower,+target,+bob}:
      Values.obj([J.JMember{"kind",Values.txt("item")},J.JMember{"common",Values.common(c)},J.JMember{"item",Values.slot(item)},J.JMember{"age",Values.num(age)},J.JMember{"pickup_delay",Values.num(delay)},J.JMember{"health",Values.num(health)},J.JMember{"thrower",uuid_value(thrower)},J.JMember{"target",uuid_value(target)},J.JMember{"bob",Values.num(PL.raw(bob))}])
    case +other: Values.record(other)
def support_value(value:S.State) -> J.Value:
  match value:
    case S.State{None{},+n}: J.JNull{}
    case S.State{Some{Travel.BlockPos{+x,+y,+z}},+n}: J.JArray{[Values.num(x),Values.num(y),Values.num(z)]}
def optional_vector(value:Maybe<&2,V.Vec3>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{+point}: Values.vector(point)
def runtime_value(+runtime:T.Runtime,+record:E.Record) -> J.Value:
  T.Runtime{T.Physical{+g,+np,+s,+h,+v,+b,+minor,+stuck},T.BaseState{+inv,+boarding,+wet,+eye,+p,+wp,+sprint,+swimming,+freeze,silent,+last,+speed},T.Fluids{T.Fluid{+water,+wf,+wn,+w},T.Fluid{+lava,+lf,+ln,+l},+ew,+el,+fast},+pending,+moves,+support,+runtime_tail}=runtime
  Values.obj([J.JMember{"position_old",Values.vector(M.old_position(U.fields(record)))},J.JMember{"noPhysics",Values.bool(np)},J.JMember{"horizontalCollision",Values.bool(h)},J.JMember{"verticalCollision",Values.bool(v)},J.JMember{"verticalCollisionBelow",Values.bool(b)},J.JMember{"minorHorizontalCollision",Values.bool(minor)},J.JMember{"boardingCooldown",Values.num(boarding)},J.JMember{"wasTouchingWater",Values.bool(wet)},J.JMember{"wasEyeInWater",Values.bool(eye)},J.JMember{"lastKnownPosition",optional_vector(last)},J.JMember{"lastKnownSpeed",Values.vector(speed)},J.JMember{"invulnerableTime",Values.num(inv)},J.JMember{"noGravity",Values.bool(g)},J.JMember{"silent",Values.bool(silent)},J.JMember{"water",Values.double(water)},J.JMember{"lava",Values.double(lava)},J.JMember{"fall_distance",Values.double(M.fall_fields(U.fields(record)))},J.JMember{"support",support_value(support)}])
def runtime_base(base:T.BaseState,+quiet:Bool) -> T.BaseState:
  T.BaseState{+a,+b,+w,+e,+p,+wp,+s,+sw,+f,+silent,+last,+speed}=base
  T.BaseState{a,b,w,e,p,wp,s,sw,f,quiet,last,speed}
def runtime_gravity(+runtime:T.Runtime,gravity:Bool,+quiet:Bool) -> T.Runtime:
  T.Runtime{T.Physical{+g,+np,+s,+h,+v,+b,+minor,+stuck},+base,+fluid,+pending,+moves,+support,+runtime_tail}=runtime
  T.Runtime{T.Physical{gravity,np,s,h,v,b,minor,stuck},runtime_base(base,quiet),fluid,pending,moves,support,runtime_tail}
def publication(value:T.Publication) -> J.Value:
  match value:
    case T.SeededSplash{+p,+v,+pitch,+high,+seed}: Values.obj([J.JMember{"kind",Values.txt("sound")},J.JMember{"volume",Values.num(PL.raw(v))},J.JMember{"pitch",Values.num(PL.raw(pitch))},J.JMember{"seed",Values.bits(seed)}])
    case T.Particle{+bubble,+p,+v}: Values.obj([J.JMember{"kind",Values.txt("particle")},J.JMember{"type",Values.txt(U.select(String,"minecraft:bubble","minecraft:splash",bubble))},J.JMember{"position",Values.vector(p)},J.JMember{"velocity",Values.vector(v)}])
    case T.GroundEvent{+p,+b,+state}: Values.obj([J.JMember{"kind",Values.txt("game_event")},J.JMember{"id",Values.txt("minecraft:hit_ground")},J.JMember{"position",Values.vector(p)},J.JMember{"state",Values.num(state)}])
    case T.SplashEvent{+p}: Values.obj([J.JMember{"kind",Values.txt("game_event")},J.JMember{"id",Values.txt("minecraft:splash")}])
    case _: J.JNull{}
def publications(values:List<&2,T.Publication>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case +head <> +rest: publication(head) <> publications(rest)
def sounded_tick(+id:String,+record:E.Record,+runtime:T.Runtime,result:Result<&2,&2,T.Error,Scene.Sounds>) -> J.Value:
  match result:
    case Fail{e}: Values.obj([J.JMember{"id",Values.txt(id)},J.JMember{"error",Values.txt("sound refused")}])
    case Done{Scene.Sounds{Some{+source},+events}}: Values.obj([J.JMember{"id",Values.txt(id)},J.JMember{"after",record_value(record)},J.JMember{"runtime_after",runtime_value(runtime,record)},J.JMember{"events",J.JArray{publications(events)}},J.JMember{"sound_after",Values.source(source)}])
    case Done{other}: J.JNull{}
def tick_result(+id:String,result:Result<&2,&2,T.Error,T.Plan>,+source:R.Source) -> J.Value:
  match result:
    case Fail{T.Refused{+reason}}: Values.obj([J.JMember{"id",Values.txt(id)},J.JMember{"error",Values.txt(reason)}])
    case Fail{T.EntityError{+e}}: Values.obj([J.JMember{"id",Values.txt(id)},J.JMember{"error",Values.txt("entity error")}])
    case Done{T.Plan{T.Snapshot{+record,+runtime},+records,+events}}: sounded_tick(id,record,runtime,Scene.sounds(events,Some{source}))
def merge_result(id:String,result:Result<&2,&2,T.Error,Merge.MergePair>) -> J.Value:
  match result:
    case Fail{+e}: Values.obj([J.JMember{"id",Values.txt(id)},J.JMember{"error",Values.txt("merge refused")}])
    case Done{Merge.MergePair{+first,+second,+events}}: Values.obj([J.JMember{"id",Values.txt(id)},J.JMember{"after",record_value(first)},J.JMember{"other_after",record_value(second)}])
def case_mode(+raw:J.Value,+id:String,+context:T.Context,+items:CI.Context,+defaults:List<&2,C.Default>,+record:E.Record,+runtime:T.Runtime,+common:Bool,merge:Bool) -> Result<&2,&2,String,J.Value>:
  match merge:
    case False{}:
      do Result<&2,&2,String,J.Value>:
        +sound_raw : J.Value <- D.field(raw,"sound_before")
        +source : R.Source <- Values.read_source(sound_raw)
        return tick_result(id,Tick.plan(context,U.select(T.Snapshot,Tick.common_tick(T.Snapshot{record,runtime}),T.Snapshot{record,runtime},common),[record]),source)
    case True{}:
      do Result<&2,&2,String,J.Value>:
        +raw : J.Value <- D.field(raw,"other_before")
        +second : E.Record <- read_record(raw,defaults)
        return merge_result(id,Merge.pair(items,record,second))
def entity_values(records:List<&2,E.Record>) -> List<&2,J.Value>:
  match records:
    case Nil{}: []
    case +record <> rest: record_value(record) <> entity_values(rest)
def runtime_entry(+id:U32,+runtime:T.Runtime,result:Result<&2,&2,T.Error,E.Record>) -> J.Value:
  match result:
    case Fail{error}: J.JNull{}
    case Done{record}: Values.obj([J.JMember{"id",Values.num(id)},J.JMember{"runtime",runtime_value(runtime,record)}])
def runtime_values(values:List<&2,T.RuntimeEntry>,+records:List<&2,E.Record>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case T.RuntimeEntry{+id,+runtime} <> +rest: runtime_entry(id,runtime,Scene.found(records,id)) <> runtime_values(rest,records)
def scene_error(status:Result<&2,&2,T.Error,List<&2,T.Publication>>) -> List<&2,J.Member>:
  match status:
    case Fail{T.Refused{message}}: [J.JMember{"error",Values.txt(message)}]
    case Fail{T.EntityError{cause}}: [J.JMember{"error",Values.txt("entity error")}]
    case Done{events}: [J.JMember{"events",J.JArray{publications(events)}}]
def optional_source(value:Maybe<&2,R.Source>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{+source}: Values.source(source)
def scene_view(id:String,runtimes:List<&2,T.RuntimeEntry>,sound:Maybe<&2,R.Source>,status:Result<&2,&2,T.Error,List<&2,T.Publication>>,result:E.State & E.View) -> J.Value:
  (owner,E.View{+level,+unique,+cursor,+order,+records})=result
  Values.obj(List.append(&2,J.Member,[J.JMember{"id",Values.txt(id)},J.JMember{"level",Values.source(level)},J.JMember{"unique",Values.bits(unique)},J.JMember{"cursor",Values.num(cursor)},J.JMember{"order",Values.num(U32.from_nat(order))},J.JMember{"records",J.JArray{entity_values(records)}},J.JMember{"runtimes",J.JArray{runtime_values(runtimes,records)}},J.JMember{"sound",optional_source(sound)}],scene_error(status)))
def scene_result(id:String,result:T.State & Result<&2,&2,T.Error,List<&2,T.Publication>>) -> J.Value:
  (T.State{owner,+runtimes,+sound},status)=result
  scene_view(id,runtimes,sound,status,E.inspect(owner))
def scene_fixture(+id:String,+context:T.Context,+record:E.Record,+runtime:T.Runtime,+mode:String,+source:Maybe<&2,R.Source>) -> J.Value:
  scene_result(id,Scene.tick_id(context,E.record_id(record),True{},T.State{E.install(E.View{R.Legacy{R.Bits64{11,22}},R.Bits64{33,44},91,9n,[record]}),U.select(List<&2,T.RuntimeEntry>,[],[T.RuntimeEntry{E.record_id(record),runtime}],String.eq(mode,"missing-runtime")),source}))
def fixture_mode(+raw:J.Value,+id:String,+context:T.Context,+items:CI.Context,+defaults:List<&2,C.Default>,+record:E.Record,+runtime:T.Runtime,+common:Bool,+merge:Bool,+mode:String) -> Result<&2,&2,String,J.Value>:
  match mode:
    case "": case_mode(raw,id,context,items,defaults,record,runtime,common,merge)
    case _:
      do Result<&2,&2,String,J.Value>:
        +sound_raw : J.Value <- D.field(raw,"sound_before")
        +source : R.Source <- Values.read_source(sound_raw)
        return scene_fixture(id,context,record,runtime,mode,U.select(Maybe<&2,R.Source>,Some{source},U.select(Maybe<&2,R.Source>,None{},Some{R.Legacy{R.Bits64{55,66}}},String.eq(mode,"missing-sound")),String.eq(mode,"scene-fall") || String.eq(mode,"scene-splash")))
def fixture(+raw:J.Value,+items:CI.Context) -> Result<&2,&2,String,J.Value>:
  CI.Context{+recipes,+defaults,+features}=items
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(raw,"id")
    +input : J.Value <- D.field(raw,"before")
    +record : E.Record <- read_record(input,defaults)
    gravity : Bool <- Values.flag(raw,"no_gravity")
    quiet : Bool <- Values.flag(raw,"silent")
    common : Bool <- Values.flag(raw,"common")
    server : Bool <- Values.flag(raw,"server")
    merge : Bool <- Values.flag(raw,"merge")
    mode : String <- D.text_field(raw,"guard")
    geometry_dimension : String <- D.text_field(raw,"geometry_dimension")
    portal : Bool <- Values.flag(raw,"neutral_portal")
    available : Bool <- Values.flag(raw,"available_cells")
    +values : List<&2,J.Value> <- Values.array_field(raw,"cells")
    cells : List<&2,T.Cell> <- read_cells(values)
    blocks : List<&2,G.Obstacle> <- read_boxes(values)
    +coverage : A.AABB = A.AABB{F.from_i32(4294967295),F.from_i32(4294967294),F.from_i32(4294967295),F.from_u32(3),F.from_u32(4),F.from_u32(3)}
    +context : T.Context = T.Context{items,G.Context{geometry_dimension,coverage,blocks,[],100000},U.select(List<&2,T.Cell>,cells,[],available),coverage,4294967232,server,False{},True{},True{},False{},portal,True{},10000n,None{},[]}
    fixture_mode(raw,id,context,items,defaults,record,runtime_gravity(U.fresh_runtime(),gravity,quiet),common,merge,mode)
def fixture_id(value:Maybe<&2,J.Value>) -> J.Value:
  match value:
    case Some{+id}: id
    case None{}: J.JString{"unknown"}
def fixture_observation(raw:J.Value,result:Result<&2,&2,String,J.Value>) -> J.Value:
  match result:
    case Done{+value}: value
    case Fail{+message}: Values.obj([J.JMember{"id",fixture_id(J.member(raw,"id"))},J.JMember{"fixture_error",Values.txt(message)}])
def fixtures(values:List<&2,J.Value>,+items:CI.Context) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case +head <> +rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        +observation : J.Value = fixture_observation(head,fixture(head,items))
        tail : List<&2,J.Value> <- fixtures(rest,items)
        return observation <> tail
def execute(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    +catalog : J.Value <- D.field(value,"catalog")
    +items : CI.Context <- L.catalog(catalog)
    cases : List<&2,J.Value> <- Values.array_field(value,"cases")
    results : List<&2,J.Value> <- fixtures(cases,items)
    return J.JArray{results}
def respond(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{+message}: IO.die(Unit,2,message)
    case Done{+value}: IO.print(J.encode(value))
def parsed(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{+message}: IO.die(Unit,2,message)
    case Done{+value}: respond(execute(value))
def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = value
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,16777216n,64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case +program <> +path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read_done(result)
    case _: IO.die(Unit,2,"expected item tick fixture path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
