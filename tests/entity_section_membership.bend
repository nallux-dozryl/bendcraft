import Base
import ../src/json.bend as J
import ../src/crafting_recipe_decoder.bend as D
import ../src/entity_section_membership.bend as Authority
import ../src/entity_section_membership_model.bend as M
import ../src/cooking_effect_entities_model.bend as E
import ../src/item_entity_tick_model.bend as T
import ../src/item_entity_tick_fields.bend as U
import ../src/vanilla_entity_fields.bend as V
import ../src/geometry.bend as A
import ../src/random.bend as R
import ../src/f64.bend as F
import ../src/player_look.bend as PL
import ../src/core.bend as Core
import ../src/entity_section_membership_world.bend as World
import ./cooking_effect_entities_values.bend as Values

# This receiver owns one E.State. Manager facts are staged beside that owner;
# no host code computes section transitions or supplies expected native output.
type State is Type:
  State{entities:E.State,membership:M.State}
type Outcome is Type:
  Outcome{state:State,journal:List<&2,M.CallbackEvent>,error:Maybe<&2,T.Error>}
type Operation is Data:
  Operation{mode:String,id:U32,point:V.Vec3,box:A.AABB,uuid:E.Uuid,
    created:Bool,destroy:Bool,chunk:M.Chunk}

def visibility_gate(ticking:Bool,tracked:Bool) -> M.Visibility:
  match ticking tracked:
    case True{} _: M.Ticking{}
    case _ True{}: M.Tracked{}
    case _ _: M.Hidden{}
def visibility(+value:String) -> M.Visibility: visibility_gate(String.eq(value,"TICKING"),String.eq(value,"TRACKED"))
def visibility_value(value:M.Visibility) -> J.Value:
  match value:
    case M.Hidden{}: Values.txt("HIDDEN")
    case M.Tracked{}: Values.txt("TRACKED")
    case M.Ticking{}: Values.txt("TICKING")
def key_value(value:M.SectionKey) -> J.Value:
  M.SectionKey{x,y,z}=value
  J.JArray{[Values.num(x),Values.num(y),Values.num(z)]}
def box_value(value:A.AABB) -> J.Value:
  A.AABB{a,b,c,d,e,f}=value
  J.JArray{[Values.double(a),Values.double(b),Values.double(c),Values.double(d),Values.double(e),Values.double(f)]}
def ids_value(values:List<&2,U32>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: Values.num(head) <> ids_value(rest)
def record_ids(values:List<&2,E.Record>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: Values.num(E.record_id(head)) <> record_ids(rest)
def common_complete(value:E.Common,base:J.Value) -> J.Value:
  E.Common{d,id,a,b,r,V.Fields{p,v,o,old,l,head,body,fall,g,air,fire,portal,invulnerable,sync},t,first,removed,accessible,order}=value
  match base:
    case J.JObject{members}: Values.obj(List.append(&2,J.Member,members,[J.JMember{"position_old",Values.vector(old)},J.JMember{"head",Values.num(PL.raw(head))},J.JMember{"body",Values.num(PL.raw(body))},J.JMember{"fall_distance",Values.double(fall)}]))
    case other: other
def complete_record(value:E.Record) -> J.Value:
  match value:
    case E.Orb{+c,value,age,health,count,following}:
      Values.obj([J.JMember{"kind",Values.txt("orb")},J.JMember{"common",common_complete(c,Values.common(c))},J.JMember{"value",Values.num(value)},J.JMember{"age",Values.num(age)},J.JMember{"health",Values.num(health)},J.JMember{"count",Values.num(count)},J.JMember{"following",J.JNull{}}])
    case other: Values.record(other)
def complete_records(values:List<&2,E.Record>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: complete_record(head) <> complete_records(rest)
def members_value(values:List<&2,M.Member>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case M.Member{dimension,id,key,order,box,E.Uuid{most,least}} <> rest:
      Values.obj([J.JMember{"dimension",Values.txt(dimension)},J.JMember{"id",Values.num(id)},J.JMember{"key",key_value(key)},J.JMember{"order",Values.num(U32.from_nat(order))},J.JMember{"box",box_value(box)},J.JMember{"uuid",J.JArray{[Values.bits(most),Values.bits(least)]}}]) <> members_value(rest)
def sections_value(values:List<&2,M.Section>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case M.Section{dimension,key,status,ids} <> rest:
      Values.obj([J.JMember{"dimension",Values.txt(dimension)},J.JMember{"key",key_value(key)},J.JMember{"status",visibility_value(status)},J.JMember{"members",J.JArray{ids_value(ids)}}]) <> sections_value(rest)
def chunks_value(values:List<&2,M.Chunk>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case M.Chunk{dimension,x,z,loaded,status} <> rest:
      Values.obj([J.JMember{"dimension",Values.txt(dimension)},J.JMember{"x",Values.num(x)},J.JMember{"z",Values.num(z)},J.JMember{"loaded",Values.bool(loaded)},J.JMember{"status",visibility_value(status)}]) <> chunks_value(rest)
def registrations_value(values:List<&2,M.Registration>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case M.Registration{dimension,id} <> rest:
      Values.obj([J.JMember{"dimension",Values.txt(dimension)},J.JMember{"id",Values.num(id)}]) <> registrations_value(rest)
def view_value(value:M.View) -> J.Value:
  M.View{members,sections,chunks,tracked,ticked}=value
  Values.obj([J.JMember{"members",J.JArray{members_value(members)}},J.JMember{"sections",J.JArray{sections_value(sections)}},J.JMember{"chunks",J.JArray{chunks_value(chunks)}},J.JMember{"tracked",J.JArray{registrations_value(tracked)}},J.JMember{"ticked",J.JArray{registrations_value(ticked)}}])
def event(name:String,dimension:String,id:U32) -> J.Value:
  Values.obj([J.JMember{"event",Values.txt(name)},J.JMember{"dimension",Values.txt(dimension)},J.JMember{"id",Values.num(id)}])
def section_event(name:String,dimension:String,key:M.SectionKey) -> J.Value:
  Values.obj([J.JMember{"event",Values.txt(name)},J.JMember{"dimension",Values.txt(dimension)},J.JMember{"key",key_value(key)}])
def event_value(value:M.CallbackEvent) -> J.Value:
  match value:
    case M.SectionCreated{dimension,key,status}: Values.obj([J.JMember{"event",Values.txt("section_created")},J.JMember{"dimension",Values.txt(dimension)},J.JMember{"key",key_value(key)},J.JMember{"status",visibility_value(status)}])
    case M.SectionDeleted{dimension,key}: section_event("section_deleted",dimension,key)
    case M.Inserted{dimension,id,key,order}: Values.obj([J.JMember{"event",Values.txt("inserted")},J.JMember{"dimension",Values.txt(dimension)},J.JMember{"id",Values.num(id)},J.JMember{"key",key_value(key)},J.JMember{"order",Values.num(U32.from_nat(order))}])
    case M.Detached{dimension,id,key}: Values.obj([J.JMember{"event",Values.txt("detached")},J.JMember{"dimension",Values.txt(dimension)},J.JMember{"id",Values.num(id)},J.JMember{"key",key_value(key)}])
    case M.Created{dimension,id}: event("created",dimension,id)
    case M.TrackingStart{dimension,id}: event("tracking_start",dimension,id)
    case M.TrackingEnd{dimension,id}: event("tracking_end",dimension,id)
    case M.TickingStart{dimension,id}: event("ticking_start",dimension,id)
    case M.TickingEnd{dimension,id}: event("ticking_end",dimension,id)
    case M.SectionChange{dimension,id}: event("section_change",dimension,id)
    case M.Destroyed{dimension,id}: event("destroyed",dimension,id)
def events_value(values:List<&2,M.CallbackEvent>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: event_value(head) <> events_value(rest)
def error_value(value:Maybe<&2,T.Error>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{T.Refused{reason}}: Values.txt(reason)
    case Some{T.EntityError{cause}}: Values.txt("entity error")
def query_value(value:Result<&2,&2,T.Error,List<&2,E.Record>>) -> J.Value:
  match value:
    case Done{values}: J.JArray{record_ids(values)}
    case Fail{error}: Values.obj([J.JMember{"error",error_value(Some{error})}])
def read_box(values:List<&2,J.Value>) -> Result<&2,&2,String,A.AABB>:
  match values:
    case a <> b <> c <> d <> e <> f <> Nil{}:
      do Result<&2,&2,String,A.AABB>:
        a : R.Bits64 <- Values.read_bits(a)
        b : R.Bits64 <- Values.read_bits(b)
        c : R.Bits64 <- Values.read_bits(c)
        d : R.Bits64 <- Values.read_bits(d)
        e : R.Bits64 <- Values.read_bits(e)
        f : R.Bits64 <- Values.read_bits(f)
        return A.AABB{Values.read_double(a),Values.read_double(b),Values.read_double(c),Values.read_double(d),Values.read_double(e),Values.read_double(f)}
    case _: Fail{"expected six AABB word pairs"}
def box_field(+raw:J.Value,name:String) -> Result<&2,&2,String,A.AABB>:
  do Result<&2,&2,String,A.AABB>:
    values : List<&2,J.Value> <- Values.array_field(raw,name)
    read_box(values)
def read_chunk(+raw:J.Value) -> Result<&2,&2,String,M.Chunk>:
  do Result<&2,&2,String,M.Chunk>:
    dimension : String <- D.text_field(raw,"dimension")
    x : U32 <- D.number_field(raw,"x")
    z : U32 <- D.number_field(raw,"z")
    loaded : Bool <- Values.flag(raw,"loaded")
    status : String <- D.text_field(raw,"status")
    return M.Chunk{dimension,x,z,loaded,visibility(status)}
def read_chunks(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,M.Chunk>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,M.Chunk>>:
        head : M.Chunk <- read_chunk(head)
        tail : List<&2,M.Chunk> <- read_chunks(rest)
        return head <> tail
def read_operation(+raw:J.Value) -> Result<&2,&2,String,Operation>:
  do Result<&2,&2,String,Operation>:
    mode : String <- D.text_field(raw,"mode")
    id : U32 <- D.number_field(raw,"id")
    point : V.Vec3 <- Values.vector_field(raw,"point")
    box : A.AABB <- box_field(raw,"box")
    a : R.Bits64 <- Values.bits_field(raw,"uuid_most")
    b : R.Bits64 <- Values.bits_field(raw,"uuid_least")
    created : Bool <- Values.flag(raw,"created")
    destroy : Bool <- Values.flag(raw,"destroy")
    chunk : J.Value <- D.field(raw,"chunk")
    chunk : M.Chunk <- read_chunk(chunk)
    return Operation{mode,id,point,box,E.Uuid{a,b},created,destroy,chunk}
def fixture_record(dimension:String,id:U32,point:V.Vec3,uuid:E.Uuid) -> E.Record:
  E.Uuid{a,b}=uuid
  E.Orb{E.Common{dimension,id,a,b,R.Legacy{R.Bits64{77,88}},U.set_position_fields(V.default_fields(),point),23,False{},False{},False{},0n},1,7,5,2,None{}}
def find_record(values:List<&2,E.Record>,+id:U32) -> Result<&2,&2,T.Error,E.Record>:
  match values:
    case Nil{}: Fail{T.Refused{"fixture entity is absent"}}
    case +head <> rest: Authority.choose(Result<&2,&2,T.Error,E.Record>,Done{head},find_record(rest,id),U32.is_eq(E.record_id(head),id) && String.eq(Authority.common_dimension(E.common(head)),"minecraft:overworld"))
def erase_record(values:List<&2,E.Record>,+id:U32) -> List<&2,E.Record>:
  match values:
    case Nil{}: []
    case +head <> rest:
      +tail=erase_record(rest,id)
      Authority.choose(List<&2,E.Record>,tail,head <> tail,U32.is_eq(E.record_id(head),id))
def moved_result(value:Result<&2,&2,T.Error,M.Moved>) -> Result<&2,&2,T.Error,M.Proposal>:
  match value:
    case Done{M.Moved{snapshot,proposal}}: Done{proposal}
    case Fail{error}: Fail{error}
def move_key(+view:M.View,+records:List<&2,E.Record>,order:Nat,+record:E.Record,key:M.SectionKey,point:V.Vec3,box:A.AABB,removed:Bool) -> Result<&2,&2,T.Error,M.Proposal>:
  +original=Authority.choose(E.Common,U.common_removed(E.common(record)),E.common(record),removed)
  moved_result(Authority.on_move(view,original,key,T.Snapshot{U.set_position(record,point),U.fresh_runtime()},box,order,records))
def move_located(+view:M.View,+records:List<&2,E.Record>,order:Nat,+record:E.Record,point:V.Vec3,box:A.AABB,removed:Bool,result:Result<&2,&2,T.Error,M.Located>) -> Result<&2,&2,T.Error,M.Proposal>:
  match result:
    case Done{M.Located{M.Member{d,i,key,o,b,u},section}}: move_key(view,records,order,record,key,point,box,removed)
    case Fail{error}: move_key(view,records,order,record,Authority.key(U.pos(record)),point,box,removed)
def move_operation(+view:M.View,+records:List<&2,E.Record>,+order:Nat,+id:U32,point:V.Vec3,box:A.AABB,removed:Bool) -> Result<&2,&2,T.Error,M.Proposal>:
  do Result<&2,&2,T.Error,M.Proposal>:
    +record : E.Record <- find_record(records,id)
    move_located(view,records,order,record,point,box,removed,Authority.locate(view,"minecraft:overworld",id))
def proposal_mode(+view:M.View,+records:List<&2,E.Record>,+order:Nat,+operation:Operation,add:Bool,move:Bool,remove:Bool,visibility:Bool) -> Result<&2,&2,T.Error,M.Proposal>:
  Operation{mode,+id,point,box,uuid,created,destroy,chunk}=operation
  match add move remove visibility:
    case True{} _ _ _:
      do Result<&2,&2,T.Error,M.Proposal>:
        +record : E.Record <- find_record(records,id)
        moved_result(Authority.on_add(view,T.Snapshot{record,U.fresh_runtime()},box,order,records,created))
    case _ True{} _ _: move_operation(view,records,order,id,point,box,False{})
    case _ _ True{} _: Authority.on_removed(view,"minecraft:overworld",id,destroy,order,records)
    case _ _ _ True{}: Authority.update_chunk(view,chunk,order,records)
    case _ _ _ _:
      Authority.choose(Result<&2,&2,T.Error,M.Proposal>,Done{M.Proposal{view,order,records,[]}},move_operation(view,records,order,id,point,box,True{}),String.eq(mode,"shadow"))
def proposal_for(view:M.View,records:List<&2,E.Record>,order:Nat,+operation:Operation) -> Result<&2,&2,T.Error,M.Proposal>:
  Operation{+mode,id,point,box,uuid,created,destroy,chunk}=operation
  proposal_mode(view,records,order,operation,String.eq(mode,"add"),String.eq(mode,"move"),String.eq(mode,"remove"),String.eq(mode,"visibility"))
def stage_record(+view:E.View,+operation:Operation) -> E.View:
  E.View{level,unique,cursor,order,+records}=view
  Operation{+mode,id,point,box,uuid,created,destroy,M.Chunk{dimension,x,z,loaded,status}}=operation
  E.View{level,unique,cursor,order,Authority.choose(List<&2,E.Record>,List.append(&2,E.Record,records,[fixture_record(dimension,id,point,uuid)]),records,String.eq(mode,"add") || String.eq(mode,"shadow"))}
def installed_view(proposal:M.Proposal,value:E.State & E.View) -> Outcome:
  M.Proposal{view,order,records,journal}=proposal
  (entities,E.View{level,unique,cursor,old_order,old_records})=value
  Outcome{State{E.install(E.View{level,unique,cursor,order,records}),M.State{view}},journal,None{}}
def installed(entities:E.State,membership:M.State,result:Result<&2,&2,T.Error,M.Proposal>) -> Outcome:
  match result:
    case Fail{error}: Outcome{State{entities,membership},[],Some{error}}
    case Done{proposal}: installed_view(proposal,E.inspect(entities))
def applied(+staged:E.View,membership:M.State,view:M.View,operation:Operation) -> Outcome:
  E.View{level,unique,cursor,+order,+records}=staged
  installed(E.install(staged),membership,proposal_for(view,records,order,operation))
def apply_membership(+operation:Operation,entity_view:E.View,result:M.State & M.View) -> Outcome:
  (membership,view)=result
  applied(stage_record(entity_view,operation),membership,view,operation)
def apply_entities(operation:Operation,membership:M.State,result:E.State & E.View) -> Outcome:
  (entities,entity_view)=result
  apply_membership(operation,entity_view,Authority.inspect(membership))
def apply(state:State,+operation:Operation) -> Outcome:
  State{entities,membership}=state
  apply_entities(operation,membership,E.inspect(entities))
def operation_join(journal:List<&2,M.CallbackEvent>,next:Outcome) -> Outcome:
  Outcome{state,events,error}=next
  Outcome{state,List.append(&2,M.CallbackEvent,journal,events),error}
def operation_next(outcome:Outcome,next:State -> Result<&2,&1,String,Outcome>) -> Result<&2,&1,String,Outcome>:
  Outcome{state,journal,error}=outcome
  match error:
    case Some{error}: Done{Outcome{state,journal,Some{error}}}
    case None{}:
      do Result<&2,&1,String,Outcome>:
        result : Outcome <- next(state)
        return operation_join(journal,result)
def operation_read(state:State,result:Result<&2,&2,String,Operation>,next:State -> Result<&2,&1,String,Outcome>) -> Result<&2,&1,String,Outcome>:
  match result:
    case Fail{message}: Fail{message}
    case Done{operation}: operation_next(apply(state,operation),next)
def operations(values:List<&2,J.Value>,state:State) -> Result<&2,&1,String,Outcome>:
  match values:
    case Nil{}: Done{Outcome{state,[],None{}}}
    case head <> rest: operation_read(state,read_operation(head),next => operations(rest,next))
def state_value(+entity_view:E.View,+view:M.View,+query:A.AABB,+query_missing:Bool) -> J.Value:
  E.View{level,unique,cursor,order,+records}=entity_view
  +query_records=Authority.choose(List<&2,E.Record>,erase_record(records,1),records,query_missing)
  Values.obj([J.JMember{"provider",view_value(view)},J.JMember{"level",Values.source(level)},J.JMember{"unique",Values.bits(unique)},J.JMember{"cursor",Values.num(cursor)},J.JMember{"next_order",Values.num(U32.from_nat(order))},J.JMember{"records",J.JArray{complete_records(records)}},J.JMember{"query_ids",query_value(Authority.query(view,"minecraft:overworld",query,query_records))},J.JMember{"global_ids",J.JArray{ids_value(Authority.tracked(view,"minecraft:overworld"))}},J.JMember{"scheduled_ids",J.JArray{ids_value(Authority.scheduled(view,"minecraft:overworld"))}}])
def observed_membership(journal:List<&2,M.CallbackEvent>,error:Maybe<&2,T.Error>,label:String,query:A.AABB,missing:Bool,entities:E.State,entity_view:E.View,result:M.State & M.View) -> State & J.Value:
  (membership,view)=result
  (State{entities,membership},Values.obj([J.JMember{"action",Values.txt(label)},J.JMember{"events",J.JArray{events_value(journal)}},J.JMember{"error",error_value(error)},J.JMember{"state",state_value(entity_view,view,query,missing)}]))
def observed_entities(journal:List<&2,M.CallbackEvent>,error:Maybe<&2,T.Error>,label:String,query:A.AABB,missing:Bool,membership:M.State,result:E.State & E.View) -> State & J.Value:
  (entities,entity_view)=result
  observed_membership(journal,error,label,query,missing,entities,entity_view,Authority.inspect(membership))
def observed(outcome:Outcome,label:String,query:A.AABB,missing:Bool) -> State & J.Value:
  Outcome{State{entities,membership},journal,error}=outcome
  observed_entities(journal,error,label,query,missing,membership,E.inspect(entities))
def steps_tail(result:State & J.Value,next:State -> Result<&2,&2,String,List<&2,J.Value>>) -> Result<&2,&2,String,List<&2,J.Value>>:
  (state,head)=result
  do Result<&2,&2,String,List<&2,J.Value>>:
    tail : List<&2,J.Value> <- next(state)
    return head <> tail
def steps_done(result:Result<&2,&1,String,Outcome>,label:String,query:A.AABB,missing:Bool,next:State -> Result<&2,&2,String,List<&2,J.Value>>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{outcome}: steps_tail(observed(outcome,label,query,missing),next)
def steps(values:List<&2,J.Value>,state:State) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case +head <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        label : String <- D.text_field(head,"action")
        query : A.AABB <- box_field(head,"query")
        missing : Bool <- Values.flag(head,"query_missing")
        values : List<&2,J.Value> <- Values.array_field(head,"operations")
        steps_done(operations(values,state),label,query,missing,next => steps(rest,next))
def fixture(+raw:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(raw,"id")
    values : List<&2,J.Value> <- Values.array_field(raw,"chunks")
    chunks : List<&2,M.Chunk> <- read_chunks(values)
    values : List<&2,J.Value> <- Values.array_field(raw,"steps")
    results : List<&2,J.Value> <- steps(values,State{E.install(E.View{R.Legacy{R.Bits64{11,22}},R.Bits64{33,44},91,0n,[]}),M.State{M.View{[],[],chunks,[],[]}}})
    return Values.obj([J.JMember{"id",Values.txt(id)},J.JMember{"steps",J.JArray{results}}])
def fixtures(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- fixture(head)
        tail : List<&2,J.Value> <- fixtures(rest)
        return head <> tail
def capture_value(value:Result<&2,&2,T.Error,M.Chunk>) -> J.Value:
  match value:
    case Fail{error}: Values.obj([J.JMember{"error",error_value(Some{error})}])
    case Done{M.Chunk{dimension,x,z,loaded,status}}:
      Values.obj([J.JMember{"dimension",Values.txt(dimension)},J.JMember{"x",Values.num(x)},J.JMember{"z",Values.num(z)},J.JMember{"loaded",Values.bool(loaded)},J.JMember{"status",visibility_value(status)}])
def core_read_value(value:Result<&2,&2,Core.Error,U32>) -> J.Value:
  match value:
    case Fail{error}: Values.txt("read failed")
    case Done{state}: Values.num(state)
def capture_clock(label:String,captured:J.Value,value:Result<&2,&2,Core.Error,U32>,result:Core.World & Core.Clock) -> Core.World & J.Value:
  (world,Core.Clock{tick,time,paused,daylight,revision,pending})=result
  (world,Values.obj([J.JMember{"id",Values.txt(label)},J.JMember{"capture",captured},J.JMember{"retained_block",core_read_value(value)},J.JMember{"tick",Values.num(U32.from_nat(tick))},J.JMember{"day_time",Values.num(U32.from_nat(time))},J.JMember{"paused",Values.bool(paused)},J.JMember{"daylight",Values.bool(daylight)},J.JMember{"revision",Values.num(U32.from_nat(revision))},J.JMember{"pending",Values.num(U32.from_nat(pending))}]))
def capture_read(label:String,captured:J.Value,result:Core.World & Result<&2,&2,Core.Error,U32>) -> Core.World & J.Value:
  (world,value)=result
  capture_clock(label,captured,value,Core.clock(world))
def capture_done(label:String,result:Core.World & Result<&2,&2,T.Error,M.Chunk>) -> Core.World & J.Value:
  (world,captured)=result
  capture_read(label,capture_value(captured),Core.read_block(world,Core.Position{"minecraft:overworld",1,1,1}))
def capture_one(world:Core.World,label:String,x:U32,dimension:String,status:Maybe<&2,M.Visibility>) -> Core.World & J.Value:
  capture_done(label,World.capture(world,dimension,V.Vec3{F.from_u32(x),F.from_u32(1),F.from_u32(1)},status))
def captures_e(a:J.Value,b:J.Value,c:J.Value,d:J.Value,result:Core.World & J.Value) -> List<&2,J.Value>:
  (world,e)=result
  [a,b,c,d,e]
def captures_d(a:J.Value,b:J.Value,c:J.Value,result:Core.World & J.Value) -> List<&2,J.Value>:
  (world,d)=result
  captures_e(a,b,c,d,capture_one(world,"wrong-dimension",1,"minecraft:the_nether",Some{M.Ticking{}}))
def captures_c(a:J.Value,b:J.Value,result:Core.World & J.Value) -> List<&2,J.Value>:
  (world,c)=result
  captures_d(a,b,c,capture_one(world,"missing-destination",19,"minecraft:overworld",Some{M.Ticking{}}))
def captures_b(a:J.Value,result:Core.World & J.Value) -> List<&2,J.Value>:
  (world,b)=result
  captures_c(a,b,capture_one(world,"missing-visibility",1,"minecraft:overworld",None{}))
def captures_a(result:Core.World & J.Value) -> List<&2,J.Value>:
  (world,a)=result
  captures_b(a,capture_one(world,"loaded-hidden",1,"minecraft:overworld",Some{M.Hidden{}}))
def captures(world:Core.World) -> List<&2,J.Value>:
  captures_a(capture_one(world,"loaded-ticking",1,"minecraft:overworld",Some{M.Ticking{}}))
def captures_created(value:Core.World & Result<&2,&2,Core.Error,Unit>) -> List<&2,J.Value>:
  (world,result)=value
  captures(world)
def world_captures() -> List<&2,J.Value>:
  captures_created(Core.create_section(Core.new(4),Core.Position{"minecraft:overworld",0,0,0},2))
def execute(raw:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    values : List<&2,J.Value> <- D.array(raw)
    values : List<&2,J.Value> <- fixtures(values)
    return Values.obj([J.JMember{"cases",J.JArray{values}},J.JMember{"core_captures",J.JArray{world_captures()}}])
def respond(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: IO.print(J.encode(value))
def parsed(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: respond(execute(value))
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
        value : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read_done(value)
    case _: IO.die(Unit,2,"expected entity membership fixture path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
