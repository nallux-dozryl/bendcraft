import Base
import ../src/item_entity_tick.bend as Tick
import ../src/item_entity_tick_model.bend as T
import ../src/item_entity_tick_fields.bend as U
import ../src/item_entity_tick_scene.bend as Scene
import ../src/item_entity_tick_merge.bend as Merge
import ../src/cooking_effect_entities_query.bend as Q
import ../src/cooking_effect_entities_model.bend as E
import ../src/cooking_effect_geometry.bend as G
import ../src/geometry.bend as A
import ../src/campfire_authority_loader.bend as L
import ../src/campfire_authority_items.bend as CI
import ../src/crafting_recipe_components.bend as C
import ../src/crafting_recipe_decoder.bend as D
import ../src/json.bend as J
import ../src/random.bend as R
import ../src/f64.bend as F
import ../src/vanilla_entity_fields.bend as V
import ./cooking_effect_entities_values.bend as Values
import ./item_entity_tick.bend as Fixture

def boundary(+raw:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    id : String <- D.text_field(raw,"id")
    +first : V.Vec3 <- Values.vector_field(raw,"first")
    +second : V.Vec3 <- Values.vector_field(raw,"second")
    return Values.obj([J.JMember{"id",Values.txt(id)},J.JMember{"same",J.JBool{Tick.same_section(first,second)}},J.JMember{"less",J.JBool{Q.less(Merge.section_key(first,0n),Merge.section_key(second,0n))}}])
def boundaries(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case +head <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- boundary(head)
        tail : List<&2,J.Value> <- boundaries(rest)
        return head <> tail
def refused(+items:CI.Context,+record:E.Record,+runtime:T.Runtime) -> J.Value:
  +coverage : A.AABB = A.AABB{F.from_i32(4294967295),F.from_i32(4294967294),F.from_i32(4294967295),F.from_u32(3),F.from_u32(4),F.from_u32(3)}
  +context : T.Context = T.Context{items,G.Context{"minecraft:overworld",coverage,[],[],100000},[],coverage,4294967232,True{},False{},True{},True{},False{},True{},True{},10000n,None{},[]}
  +view : E.View = E.View{R.Legacy{R.Bits64{11,22}},R.Bits64{33,44},91,9n,[record]}
  +runtimes : List<&2,T.RuntimeEntry> = [T.RuntimeEntry{E.record_id(record),runtime}]
  +sound : Maybe<&2,R.Source> = Some{R.Legacy{R.Bits64{55,66}}}
  Fixture.scene_result("migration-refusal",Scene.committed(T.State{E.install(view),runtimes,sound},view,runtimes,Tick.section_ready(context,[record],[],U.pos(record),U.velocity(record),T.Snapshot{record,runtime},False{}),sound))
def execute_items(+raw:J.Value,+items:CI.Context) -> Result<&2,&2,String,J.Value>:
  CI.Context{+recipes,+defaults,+features}=items
  do Result<&2,&2,String,J.Value>:
    before : J.Value <- D.field(raw,"before")
    +record : E.Record <- Fixture.read_record(before,defaults)
    raw_boundaries : List<&2,J.Value> <- Values.array_field(raw,"boundaries")
    values : List<&2,J.Value> <- boundaries(raw_boundaries)
    return Values.obj([J.JMember{"boundaries",J.JArray{values}},J.JMember{"refusal",refused(items,record,U.fresh_runtime())}])
def execute(+raw:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    catalog : J.Value <- D.field(raw,"catalog")
    +items : CI.Context <- L.catalog(catalog)
    execute_items(raw,items)
def parsed(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{raw}: Fixture.respond(execute(raw))
def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status)=value
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,1048576n,64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case +program <> +path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,1048576)
        read_done(result)
    case _: IO.die(Unit,2,"expected actual section observation path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
