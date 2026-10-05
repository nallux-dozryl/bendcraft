import Base
import ../src/json.bend as J
import ../src/crafting_recipe_decoder.bend as D
import ../src/cooking_effect_entities_model.bend as E
import ../src/item_entity_tick_model.bend as T
import ../src/item_entity_tick_fields.bend as U
import ../src/entity_section_membership.bend as MS
import ../src/entity_section_membership_model.bend as M
import ../src/entity_section_membership_recovery.bend as Recovery
import ../src/entity_section_membership_recovery_model.bend as Model
import ../src/entity_membership_codec.bend as MembershipCodec
import ../src/entity_membership_codec_validation.bend as Check
import ../src/local_player_effect_tick_recovery.bend as Q
import ../src/local_player_effect_tick_recovery_codec.bend as Codec
import ../src/local_player_cooking_tick_storage.bend as Storage
import ../src/nbt.bend as N
import ../src/random.bend as Random
import ../src/geometry.bend as A
import ../src/cooking_effect_entities_spawn.bend as Spawn
import ../src/f64.bend as F
import ../src/vanilla_entity_fields.bend as V
import ../src/player_look.bend as Look
import ../src/inventory.bend as I
import ../src/support.bend as Support
import ../src/travel.bend as Travel
import ./cooking_effect_entities_values.bend as Values
import ./entity_section_membership.bend as H

# Full snapshots use the installed runtime/entity and manager codecs. Every
# refusal returns the actual owners; no second persistent entity owner exists.
type Restored is Type:
  Restored{scene:T.State,membership:M.View}
def limits() -> N.Limits: N.Limits{16777216,128,1048576}
def bytes(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,U32>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,U32>>:
        head : U32 <- D.number(head)
        tail : List<&2,U32> <- bytes(rest)
        return head <> tail
def wire(result:Result<&2,&2,String,List<&2,U32>>) -> J.Value:
  match result:
    case Done{values}: J.JArray{H.ids_value(values)}
    case Fail{message}: Values.obj([J.JMember{"codec_error",Values.txt(message)}])
def uuid() -> E.Uuid: E.Uuid{Random.Bits64{101,103},Random.Bits64{107,109}}
def kind_record(common:E.Common,item:Bool) -> E.Record:
  match item:
    case True{}: E.Item{common,I.InvStack{I.ItemKey{"minecraft:stone",""},3},7,13,5,Some{uuid()},Some{uuid()},Look.float_bits(1069547520)}
    case False{}: E.Orb{common,11,7,5,2,Some{uuid()}}
def read_record(+raw:J.Value) -> Result<&2,&2,String,E.Record>:
  do Result<&2,&2,String,E.Record>:
    dimension : String <- D.text_field(raw,"dimension")
    id : U32 <- D.number_field(raw,"id")
    point : V.Vec3 <- Values.vector_field(raw,"position")
    a : Random.Bits64 <- Values.bits_field(raw,"uuid_most")
    b : Random.Bits64 <- Values.bits_field(raw,"uuid_least")
    order : U32 <- D.number_field(raw,"order")
    accessible : Bool <- Values.flag(raw,"accessible")
    removed : Bool <- Values.flag(raw,"removed")
    kind : String <- D.text_field(raw,"kind")
    return kind_record(E.Common{dimension,id,a,b,Random.Xoroshiro{Random.Bits64{71,73},Random.Bits64{79,83}},U.set_position_fields(V.default_fields(),point),23,False{},removed,accessible,U32.to_nat(order)},String.eq(kind,"item"))
def read_records(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,E.Record>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,E.Record>>:
        head : E.Record <- read_record(head)
        tail : List<&2,E.Record> <- read_records(rest)
        return head <> tail
def marker(+id:U32) -> V.Vec3: V.Vec3{F.from_u32(id),F.from_f32(0.125),F.from_i32(4294967293)}
def runtime(+id:U32) -> T.Runtime:
  T.Runtime{T.Physical{True{},False{},True{},True{},False{},True{},False{},marker(id)},
    T.BaseState{41,43,True{},False{},True{},False{},True{},False{},True{},False{},Some{marker(id)},marker(id)},
    T.Fluids{T.Fluid{F.from_f32(0.125),marker(id),7,True{}},T.Fluid{F.from_f32(0.5),marker(id),11,True{}},True{},False{},True{}},
    [T.Movement{marker(id),marker(id),marker(id)}],[T.Movement{marker(id),marker(id),marker(id)}],Support.State{Some{Travel.BlockPos{4294967295,2,3}},True{}},[]}
def read_runtimes(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,T.RuntimeEntry>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,T.RuntimeEntry>>:
        +id : U32 <- D.number(head)
        tail : List<&2,T.RuntimeEntry> <- read_runtimes(rest)
        return T.RuntimeEntry{id,runtime(id)} <> tail
def sound() -> Maybe<&2,Random.Source>: Some{Random.Xoroshiro{Random.Bits64{47,53},Random.Bits64{59,61}}}
def snapshot_value(entities:E.View,runtimes:List<&2,T.RuntimeEntry>,sound:Maybe<&2,Random.Source>) -> J.Value:
  wire(Codec.encode(limits(),Q.Recovery{entities,Some{runtimes},sound}))
def inspected_scene(+runtimes:List<&2,T.RuntimeEntry>,+sound:Maybe<&2,Random.Source>,result:E.State & E.View) -> T.State & J.Value:
  (entities,view)=result
  (T.State{entities,runtimes,sound},snapshot_value(view,runtimes,sound))
def inspect_scene(state:T.State) -> T.State & J.Value:
  T.State{entities,runtimes,sound}=state
  inspected_scene(runtimes,sound,E.inspect(entities))
def restored_scene(value:Result<&2,&1,String,Storage.Restored>) -> Result<&2,&1,String,Restored>:
  match value:
    case Fail{message}: Fail{message}
    case Done{Storage.Restored{scene,clocks,Some{membership}}}: Done{Restored{scene,membership}}
    case Done{Storage.Restored{scene,clocks,None{}}}: Fail{"test storage restored no structural membership image"}
def decoded_scene(value:Result<&2,&2,String,Storage.Stored>) -> Result<&2,&1,String,Restored>:
  match value:
    case Fail{message}: Fail{message}
    case Done{stored}: restored_scene(Storage.restore(stored))
def encoded_scene(value:Result<&2,&2,String,Storage.Payload>) -> Result<&2,&1,String,Restored>:
  match value:
    case Fail{message}: Fail{message}
    case Done{Storage.Payload{bytes,clocks}}: decoded_scene(Storage.decode(limits(),bytes,clocks))
def make_scene(+entities:E.View,+runtimes:List<&2,T.RuntimeEntry>,+image:M.View,codec:Bool) -> Result<&2,&1,String,Restored>:
  match codec:
    case False{}: Done{Restored{T.State{E.install(entities),runtimes,sound()},image}}
    case True{}: encoded_scene(Storage.encode(limits(),Storage.Stored{Q.Recovery{entities,Some{runtimes},sound()},[Random.Bits64{113,127},Random.Bits64{113,127}],Some{image}}))
def accepted(value:Bool) -> Result<&2,&2,T.Error,Unit>:
  match value:
    case True{}: Done{Unit{}}
    case False{}: Fail{T.Refused{"test callback publication refused"}}
def callbacks(value:Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>) -> J.Value:
  match value:
    case Done{events}: J.JArray{H.events_value(events)}
    case Fail{error}: Values.obj([J.JMember{"error",H.error_value(Some{error})}])
def query_box() -> A.AABB:
  A.AABB{F.from_i32(4294967256),F.from_i32(4294967256),F.from_i32(4294967256),F.from_u32(80),F.from_u32(80),F.from_u32(80)}
def after_entities(id:String,before:J.Value,+prior:M.View,+view:M.View,events:J.Value,remaining:J.Value,+runtimes:List<&2,T.RuntimeEntry>,+source:Maybe<&2,Random.Source>,result:E.State & E.View) -> J.Value:
  (owner,+entities)=result
  E.View{level,unique,cursor,order,+records}=entities
  Values.obj([J.JMember{"id",Values.txt(id)},J.JMember{"before",before},J.JMember{"after",snapshot_value(entities,runtimes,source)},J.JMember{"prior_membership",H.view_value(prior)},J.JMember{"prior_membership_wire",wire(MembershipCodec.encode(limits(),prior))},J.JMember{"membership",H.view_value(view)},J.JMember{"membership_wire",wire(MembershipCodec.encode(limits(),view))},J.JMember{"events",events},J.JMember{"remaining_times",remaining},J.JMember{"query_ids",H.query_value(MS.query(view,"minecraft:overworld",query_box(),records))}])
def after_manager(id:String,before:J.Value,prior:M.View,scene:T.State,events:J.Value,remaining:J.Value,result:M.State & M.View) -> J.Value:
  T.State{entities,runtimes,source}=scene
  (manager,view)=result
  after_entities(id,before,prior,view,events,remaining,runtimes,source,E.inspect(entities))
def after(id:String,before:J.Value,prior:M.View,result:T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>) -> J.Value:
  (scene,manager,events)=result
  after_manager(id,before,prior,scene,callbacks(events),J.JNull{},MS.inspect(manager))
def before(id:String,+prior:M.View,image:Maybe<&2,M.View>,current:Maybe<&2,List<&2,M.Chunk>>,publish:Bool,result:T.State & J.Value) -> J.Value:
  (scene,snapshot)=result
  after(id,snapshot,prior,Recovery.activate(scene,M.State{prior},image,current,accepted(publish)))
def time_values(values:List<&2,Random.Bits64>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: Values.bits(head) <> time_values(rest)
def fresh_after(id:String,before:J.Value,prior:M.View,result:T.State & M.State & Result<&2,&2,T.Error,Model.FreshPublication>) -> J.Value:
  (scene,manager,publication)=result
  match publication:
    case Fail{error}: after_manager(id,before,prior,scene,callbacks(Fail{error}),J.JNull{},MS.inspect(manager))
    case Done{Model.FreshPublication{events,times}}: after_manager(id,before,prior,scene,callbacks(Done{events}),J.JArray{time_values(times)},MS.inspect(manager))
def adjusted_constructor(plan:E.Plan,delta:U32) -> E.Plan:
  E.Plan{E.View{level,unique,id,order,records},times}=plan
  E.Plan{E.View{level,unique,id,Nat.add(order,U32.to_nat(delta)),records},times}
def fresh_before(id:String,+image:M.View,constructed:E.Plan,+fresh_id:U32,current:Maybe<&2,List<&2,M.Chunk>>,publish:Bool,result:T.State & J.Value) -> J.Value:
  (scene,snapshot)=result
  fresh_after(id,snapshot,image,Recovery.fresh(scene,M.State{image},constructed,fresh_id,runtime(fresh_id),current,accepted(publish)))
def fresh_created(id:String,+image:M.View,constructed:E.Plan,+fresh_id:U32,current:Maybe<&2,List<&2,M.Chunk>>,publish:Bool,result:Result<&2,&1,String,Restored>) -> Result<&2,&2,String,J.Value>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Restored{scene,membership}}: Done{fresh_before(id,membership,constructed,fresh_id,current,publish,inspect_scene(scene))}
def constructor_plan(+level:Random.Source,+fresh_id:U32,+pre_order:Nat,+prefix:List<&2,E.Record>,+record:E.Record,delta:U32,exhausted:Bool) -> E.Plan:
  match exhausted:
    case True{}: E.Plan{E.View{level,Random.Bits64{131,137},fresh_id,pre_order,List.append(&2,E.Record,prefix,[record])},[Random.Bits64{211,223},Random.Bits64{227,229}]}
    case False{}: adjusted_constructor(Spawn.item_created(level,fresh_id,pre_order,prefix,[Random.Bits64{211,223},Random.Bits64{227,229}],(Random.Bits64{131,137},record)),delta)
def fresh_case(+raw:J.Value,+entities:E.View,+runtimes:List<&2,T.RuntimeEntry>,+image:M.View,current:Maybe<&2,List<&2,M.Chunk>>,publish:Bool) -> Result<&2,&2,String,J.Value>:
  E.View{+level,unique,cursor,+pre_order,records}=entities
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(raw,"id")
    +fresh_id : U32 <- D.number_field(raw,"fresh_id")
    delta : U32 <- D.number_field(raw,"constructor_delta")
    exhausted : Bool <- Values.flag(raw,"constructor_exhausted")
    raw_prefix : List<&2,J.Value> <- Values.array_field(raw,"constructor_prefix")
    prefix : List<&2,E.Record> <- read_records(raw_prefix)
    raw_record : J.Value <- D.field(raw,"fresh_record")
    record : E.Record <- read_record(raw_record)
    fresh_created(id,image,constructor_plan(level,fresh_id,pre_order,prefix,record,delta,exhausted),fresh_id,current,publish,make_scene(entities,runtimes,image,False{}))
def created(id:String,prior:M.View,+image:M.View,+current:List<&2,M.Chunk>,publish:Bool,image_available:Bool,observations_available:Bool,result:Result<&2,&1,String,Restored>) -> Result<&2,&2,String,J.Value>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Restored{scene,membership}}: Done{before(id,prior,MS.choose(Maybe<&2,M.View>,Some{membership},None{},image_available),MS.choose(Maybe<&2,List<&2,M.Chunk>>,Some{current},None{},observations_available),publish,inspect_scene(scene))}
def run_case(+raw:J.Value,id:String,+entities:E.View,+runtimes:List<&2,T.RuntimeEntry>,prior:M.View,+image:M.View,+current:List<&2,M.Chunk>,codec:Bool,publish:Bool,image_available:Bool,observations_available:Bool,fresh:Bool) -> Result<&2,&2,String,J.Value>:
  match fresh:
    case True{}: fresh_case(raw,entities,runtimes,image,MS.choose(Maybe<&2,List<&2,M.Chunk>>,Some{current},None{},observations_available),publish)
    case False{}: created(id,prior,image,current,publish,image_available,observations_available,make_scene(entities,runtimes,image,codec))
def fixture(+raw:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(raw,"id")
    cursor : U32 <- D.number_field(raw,"cursor")
    cursor_max : Bool <- Values.flag(raw,"cursor_max")
    mode : String <- D.text_field(raw,"mode")
    codec : Bool <- Values.flag(raw,"codec")
    publish : Bool <- Values.flag(raw,"publish")
    image_available : Bool <- Values.flag(raw,"image_available")
    observations_available : Bool <- Values.flag(raw,"observations_available")
    raw_records : List<&2,J.Value> <- Values.array_field(raw,"records")
    records : List<&2,E.Record> <- read_records(raw_records)
    runtime_ids : List<&2,J.Value> <- Values.array_field(raw,"runtimes")
    +runtimes : List<&2,T.RuntimeEntry> <- read_runtimes(runtime_ids)
    raw_bytes : List<&2,J.Value> <- Values.array_field(raw,"saved")
    wire : List<&2,U32> <- bytes(raw_bytes)
    +image : M.View <- MembershipCodec.decode(limits(),wire)
    raw_bytes : List<&2,J.Value> <- Values.array_field(raw,"prior")
    wire : List<&2,U32> <- bytes(raw_bytes)
    prior : M.View <- MembershipCodec.decode(limits(),wire)
    observation : J.Value <- D.field(raw,"observations")
    raw_chunks : List<&2,J.Value> <- Values.array_field(observation,"chunks")
    current : List<&2,M.Chunk> <- H.read_chunks(raw_chunks)
    run_case(raw,id,E.View{Random.Legacy{Random.Bits64{11,22}},Random.Bits64{33,44},91,MS.choose(Nat,Check.maximum_order(),U32.to_nat(cursor),cursor_max),records},runtimes,prior,image,current,codec,publish,image_available,observations_available,String.eq(mode,"fresh"))
def fixtures(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- fixture(head)
        tail : List<&2,J.Value> <- fixtures(rest)
        return head <> tail
def execute(value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    values : List<&2,J.Value> <- D.array(value)
    result : List<&2,J.Value> <- fixtures(values)
    return J.JArray{result}
def respond(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{result}: IO.print(J.encode(result))
def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{result}: respond(execute(result))
def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status)=value
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,16777216n,64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read_done(result)
    case _: IO.die(Unit,2,"expected recovery fixture path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
