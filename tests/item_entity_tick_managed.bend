import Base
import ../src/item_entity_tick_managed_scene.bend as ManagedScene
import ../src/item_entity_tick_managed.bend as Managed
import ../src/item_entity_tick_model.bend as T
import ../src/item_entity_tick_fields.bend as U
import ../src/item_entity_tick_merge.bend as Merge
import ../src/cooking_effect_entities_model.bend as E
import ../src/entity_section_membership_model.bend as M
import ../src/entity_section_membership.bend as MS
import ../src/cooking_effect_geometry.bend as G
import ../src/geometry.bend as A
import ../src/campfire_authority_items.bend as CI
import ../src/campfire_authority_loader.bend as Loader
import ../src/crafting_recipe_components.bend as C
import ../src/crafting_recipe_decoder.bend as D
import ../src/json.bend as J
import ../src/random.bend as R
import ./item_entity_tick.bend as Fixture
import ./entity_section_membership.bend as ManagerFixture
import ./cooking_effect_entities_values.bend as Values

def read_records(values:List<&2,J.Value>,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,E.Record>>:
  match values:
    case Nil{}: Done{[]}
    case raw <> rest:
      do Result<&2,&2,String,List<&2,E.Record>>:
        head : E.Record <- Fixture.read_record(raw,defaults)
        tail : List<&2,E.Record> <- read_records(rest,defaults)
        return head <> tail
def registered_tail(moved:M.Moved,continue:M.View -> Nat -> List<&2,E.Record> -> Result<&2,&2,T.Error,M.Proposal>) -> Result<&2,&2,T.Error,M.Proposal>:
  M.Moved{snapshot,M.Proposal{view,order,records,journal}}=moved
  continue(view,order,records)
def register_all(values:List<&2,E.Record>,+view:M.View,order:Nat,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,M.Proposal>:
  match values:
    case Nil{}: Done{M.Proposal{view,order,records,[]}}
    case +head <> rest:
      do Result<&2,&2,T.Error,M.Proposal>:
        moved : M.Moved <- MS.on_add(view,T.Snapshot{head,U.fresh_runtime()},U.body(head),order,records,True{})
        registered_tail(moved,v => o => r => register_all(rest,v,o,r))
def runtimes(values:List<&2,E.Record>) -> List<&2,T.RuntimeEntry>:
  match values:
    case Nil{}: []
    case head <> rest: T.RuntimeEntry{E.record_id(head),Fixture.runtime_gravity(U.fresh_runtime(),True{},False{})} <> runtimes(rest)
def record_ids(values:List<&2,E.Record>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: Values.num(E.record_id(head)) <> record_ids(rest)
def query_value(value:Result<&2,&2,T.Error,List<&2,E.Record>>) -> J.Value:
  match value:
    case Fail{T.Refused{message}}: J.JString{message}
    case Fail{error}: J.JString{"query error"}
    case Done{records}: J.JArray{record_ids(records)}
def snapshot_value(+view:E.View,runtimes:List<&2,T.RuntimeEntry>,sound:Maybe<&2,R.Source>,+membership:M.View,query:A.AABB) -> J.Value:
  E.View{level,unique,cursor,order,+records}=view
  Values.obj([J.JMember{"level",Values.source(level)},J.JMember{"unique",Values.bits(unique)},J.JMember{"cursor",Values.num(cursor)},J.JMember{"order",Values.num(U32.from_nat(order))},J.JMember{"records",J.JArray{Fixture.entity_values(records)}},J.JMember{"runtimes",J.JArray{Fixture.runtime_values(runtimes,records)}},J.JMember{"sound",Fixture.optional_source(sound)},J.JMember{"manager",ManagerFixture.view_value(membership)},J.JMember{"query",query_value(MS.query(membership,"minecraft:overworld",query,records))}])
def observed(+runtimes:List<&2,T.RuntimeEntry>,+sound:Maybe<&2,R.Source>,query:A.AABB,entities:E.State & E.View,sections:M.State & M.View) -> T.State & M.State & J.Value:
  (owner,+view)=entities
  (manager,+membership)=sections
  (T.State{owner,runtimes,sound},manager,snapshot_value(view,runtimes,sound,membership,query))
def observe(scene:T.State,manager:M.State,query:A.AABB) -> T.State & M.State & J.Value:
  T.State{entities,runtimes,sound}=scene
  observed(runtimes,sound,query,E.inspect(entities),MS.inspect(manager))
def status(value:Result<&2,&2,T.Error,Managed.Publication>) -> List<&2,J.Member>:
  match value:
    case Fail{T.Refused{message}}: [J.JMember{"error",Values.txt(message)},J.JMember{"callbacks",J.JArray{[]}}]
    case Fail{error}: [J.JMember{"error",Values.txt("entity error")},J.JMember{"callbacks",J.JArray{[]}}]
    case Done{Managed.Publication{effects,journal}}: [J.JMember{"error",J.JNull{}},J.JMember{"effects",J.JArray{Fixture.publications(effects)}},J.JMember{"callbacks",J.JArray{ManagerFixture.events_value(journal)}}]
def after(id:String,before:J.Value,value:Result<&2,&2,T.Error,Managed.Publication>,observed:T.State & M.State & J.Value) -> J.Value:
  (scene,manager,after)=observed
  Values.obj(List.append(&2,J.Member,[J.JMember{"id",Values.txt(id)},J.JMember{"before",before},J.JMember{"after",after}],status(value)))
def finished(id:String,before:J.Value,+query:A.AABB,result:T.State & M.State & Result<&2,&2,T.Error,Managed.Publication>) -> J.Value:
  (scene,manager,status)=result
  after(id,before,status,observe(scene,manager,query))
def execute_observed(id:String,context:T.Context,+query:A.AABB,observed:T.State & M.State & J.Value) -> J.Value:
  (scene,manager,before)=observed
  finished(id,before,query,ManagedScene.tick_id(context,71,True{},scene,manager))
def guarded_view(+view:M.View,+mode:String) -> M.View:
  M.View{+members,+sections,+chunks,+tracked,+ticked}=view
  M.View{U.select(List<&2,M.Member>,MS.erase_member(members,"minecraft:overworld",72),U.select(List<&2,M.Member>,MS.erase_member(members,"minecraft:overworld",71),members,String.eq(mode,"missing-registration")),String.eq(mode,"missing-neighbour")),sections,chunks,tracked,U.select(List<&2,M.Registration>,[],ticked,String.eq(mode,"unscheduled"))}
def run(id:String,+context:T.Context,+query:A.AABB,+mode:String,+source:Maybe<&2,R.Source>,proposal:M.Proposal) -> J.Value:
  M.Proposal{+membership,order,+records,journal}=proposal
  scene : T.State = T.State{E.install(E.View{R.Legacy{R.Bits64{11,22}},R.Bits64{33,44},91,order,records}),runtimes(records),source}
  execute_observed(id,context,query,observe(scene,M.State{guarded_view(membership,mode)},query))
def registration_string(result:Result<&2,&2,T.Error,M.Proposal>) -> Result<&2,&2,String,M.Proposal>:
  match result:
    case Fail{T.Refused{message}}: Fail{message}
    case Fail{error}: Fail{"registration error"}
    case Done{proposal}: Done{proposal}
def fixture_items(+raw:J.Value,+items:CI.Context) -> Result<&2,&2,String,J.Value>:
  CI.Context{recipes,+defaults,features}=items
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(raw,"id")
    +mode : String <- D.text_field(raw,"guard")
    +before : List<&2,J.Value> <- Values.array_field(raw,"before")
    +records : List<&2,E.Record> <- read_records(before,defaults)
    +coverage : A.AABB <- ManagerFixture.box_field(raw,"coverage")
    +cells_raw : List<&2,J.Value> <- Values.array_field(raw,"cells")
    cells : List<&2,T.Cell> <- Fixture.read_cells(cells_raw)
    boxes : List<&2,G.Obstacle> <- Fixture.read_boxes(cells_raw)
    chunks_raw : List<&2,J.Value> <- Values.array_field(raw,"chunks")
    chunks : List<&2,M.Chunk> <- ManagerFixture.read_chunks(chunks_raw)
    +sound_raw : J.Value <- D.field(raw,"sound_before")
    +sound : R.Source <- Values.read_source(sound_raw)
    +context : T.Context = T.Context{items,G.Context{"minecraft:overworld",coverage,boxes,[],100000},cells,coverage,4294967232,True{},False{},True{},True{},False{},True{},True{},10000n,None{},[]}
    +membership : M.View = M.View{[],[],chunks,[],[]}
    registered : M.Proposal <- registration_string(register_all(records,membership,0n,records))
    return run(id,context,coverage,mode,U.select(Maybe<&2,R.Source>,None{},Some{sound},String.eq(mode,"missing-sound")),registered)
def fixtures(values:List<&2,J.Value>,+items:CI.Context) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case raw <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- fixture_items(raw,items)
        tail : List<&2,J.Value> <- fixtures(rest,items)
        return head <> tail
def execute(+raw:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    catalog : J.Value <- D.field(raw,"catalog")
    +items : CI.Context <- Loader.catalog(catalog)
    cases : List<&2,J.Value> <- Values.array_field(raw,"cases")
    rows : List<&2,J.Value> <- fixtures(cases,items)
    return J.JArray{rows}
def parsed(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{raw}: Fixture.respond(execute(raw))
def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status)=value
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,8388608n,64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case +program <> +path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        read_done(result)
    case _: IO.die(Unit,2,"expected managed tick observations")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
