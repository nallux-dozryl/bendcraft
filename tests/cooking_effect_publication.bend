import Base
import ../src/cooking_effect_publication.bend as P
import ../src/cooking_effect_publication_journal.bend as J
import ../src/cooking_world_bindings.bend as B
import ../src/cooking_world_bindings_loader.bend as BL
import ../src/cooking_world_store.bend as S
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as R
import ../src/world_codec.bend as WC
import ../src/furnace_authority.bend as F
import ../src/cooking_recipe.bend as K
import ../src/inventory.bend as I
import ../src/json.bend as Json
import ../src/unicode.bend as U

type OwnedEntry is Type:
  OwnedEntry{entry:S.Entry,incarnation:Nat}
type QueryResult is Type:
  Queried{owner:OwnedEntry,source:J.Source,view:Json.Value}
type Fixture is Data:
  Fixture{label:String,path:String,position:C.Position,source_state:U32,current_state:U32,gate:String,sequence:Nat,repeats:Nat}
type RestoreCase is Data:
  RestoreCase{label:String,view:J.View,authenticated:Bool}

def num(value:U32) -> Json.Value: Json.JNumber{U32.show(value)}
def natural(value:Nat) -> Json.Value: Json.JString{Nat.show(value)}
def text(value:String) -> Json.Value: Json.JString{value}
def cooking_kind(kind:K.CookingKind) -> String:
  match kind:
    case K.Smelting{}: "smelting"
    case K.Blasting{}: "blasting"
    case K.Smoking{}: "smoking"
    case K.Campfire{}: "campfire"
def family_name(value:B.Family) -> String:
  match value:
    case B.Furnace{kind}: cooking_kind(kind)
    case B.Campfire{kind}: "campfire"
def position_value(position:C.Position) -> Json.Value:
  C.Position{d,x,y,z} = position
  Json.JArray{[text(d),num(x),num(y),num(z)]}
def binding_value(binding:B.Binding) -> Json.Value:
  B.Binding{state,name,family,lit,dark,bright} = binding
  Json.JObject{[Json.JMember{"state",num(state)},Json.JMember{"block",text(name)},
    Json.JMember{"family",text(family_name(family))},Json.JMember{"lit",Json.JBool{lit}},Json.JMember{"dark",num(dark)},Json.JMember{"bright",num(bright)}]}
def source_value(source:J.Source) -> Json.Value:
  J.Source{position,binding,incarnation} = source
  Json.JObject{[Json.JMember{"position",position_value(position)},Json.JMember{"binding",binding_value(binding)},
    Json.JMember{"incarnation",natural(incarnation)}]}
def chunk_value(chunk:J.Chunk) -> Json.Value:
  J.Chunk{dimension,x,z} = chunk
  Json.JArray{[text(dimension),num(x),num(z)]}
def dirty_values(values:List<&2,J.DirtyChunk>) -> List<&2,Json.Value>:
  match values:
    case Nil{}: []
    case J.DirtyChunk{chunk,sequence} <> rest:
      Json.JObject{[Json.JMember{"chunk",chunk_value(chunk)},Json.JMember{"sequence",natural(sequence)}]} <> dirty_values(rest)
def receipt_value(receipt:J.Receipt) -> Json.Value:
  J.Receipt{position,source,chunk,sequence} = receipt
  Json.JObject{[Json.JMember{"position",position_value(position)},Json.JMember{"source",source_value(source)},
    Json.JMember{"chunk",chunk_value(chunk)},Json.JMember{"sequence",natural(sequence)}]}
def maybe_receipt(value:Maybe<&2,J.Receipt>) -> Json.Value:
  match value:
    case None{}: Json.JNull{}
    case Some{receipt}: receipt_value(receipt)
def view_value(view:J.View) -> Json.Value:
  J.View{sequence,unsaved,last} = view
  Json.JObject{[Json.JMember{"sequence",natural(sequence)},Json.JMember{"unsaved",Json.JArray{dirty_values(unsaved)}},
    Json.JMember{"last",maybe_receipt(last)}]}
def slot_value(slot:I.Slot) -> Json.Value:
  match slot:
    case I.InvEmpty{}: Json.JNull{}
    case I.InvStack{I.ItemKey{id,components},count}:
      Json.JObject{[Json.JMember{"id",text(id)},Json.JMember{"components",text(components)},Json.JMember{"count",num(count)}]}
def slot_values(values:List<I.Slot>) -> List<&2,Json.Value>:
  match values:
    case Nil{}: []
    case head <> rest: slot_value(head) <> slot_values(rest)
def use_values(values:List<&2,F.Use>) -> List<&2,Json.Value>:
  match values:
    case Nil{}: []
    case F.Use{id,count} <> rest: Json.JArray{[text(id),num(count)]} <> use_values(rest)
def cache(value:Maybe<&2,String>) -> Json.Value:
  match value:
    case None{}: Json.JNull{}
    case Some{id}: text(id)
def frame_value(frame:F.Frame) -> Json.Value:
  F.Frame{kind,remaining,total,spent,cook,speed,cached,uses} = frame
  Json.JArray{[text(cooking_kind(kind)),num(remaining),num(total),num(spent),num(cook),num(F32.bits(speed)),cache(cached),Json.JArray{use_values(uses)}]}
def queried(+position:C.Position,+binding:B.Binding,+incarnation:Nat,+frame:F.Frame,+length:U32,
    result:Array<I.Slot> & Array<I.Slot>) -> QueryResult:
  (kept,copied) = result
  Queried{OwnedEntry{S.Entry{position,binding,S.Furnace{F.State{I.Inventory{kept,length},frame}}},incarnation},
    J.Source{position,binding,incarnation},Json.JObject{[Json.JMember{"length",num(length)},
      Json.JMember{"frame",frame_value(frame)},Json.JMember{"backing",Json.JArray{slot_values(Array.to_list(~I.Slot,copied))}}]}}
# This descriptor query reads the actual test-owned Store.Entry. Publication's
# producer-captured Source is kept independently from the later current query.
def query(owner:OwnedEntry) -> QueryResult:
  match owner:
    case OwnedEntry{S.Entry{position,binding,S.Furnace{F.State{I.Inventory{slots,length},frame}}},incarnation}:
      queried(position,binding,incarnation,frame,length,Array.clone(I.Slot,slots))
    case OwnedEntry{S.Entry{+position,+binding,S.Campfire{camp}},+incarnation}:
      Queried{OwnedEntry{S.Entry{position,binding,S.Campfire{camp}},incarnation},J.Source{position,binding,incarnation},Json.JNull{}}
def float_bits(value:U32) -> F32:
  U32{word} = value
  F32{word}
def entry(position:C.Position,binding:B.Binding) -> OwnedEntry:
  cells = Array.new(I.Slot,2n,I.InvEmpty{})
  cells = Array.set(I.Slot,cells,0,I.InvStack{I.ItemKey{"minecraft:beef",""},2})
  cells = Array.set(I.Slot,cells,1,I.InvStack{I.ItemKey{"minecraft:coal",""},3})
  cells = Array.set(I.Slot,cells,2,I.InvStack{I.ItemKey{"minecraft:cooked_beef",""},5})
  cells = Array.set(I.Slot,cells,3,I.InvStack{I.ItemKey{"fixture:hidden-furnace","raw\ttail"},31})
  OwnedEntry{S.Entry{position,binding,S.Furnace{F.State{I.Inventory{cells,3},
    F.Frame{K.Smelting{},71,1600,83,200,float_bits(2147483648),Some{"minecraft:cooked_beef"},[F.Use{"minecraft:cooked_beef",7},F.Use{"minecraft:iron_ingot",9}]}}}},2n}
def replace(owner:OwnedEntry,binding:B.Binding,+gate:String) -> OwnedEntry:
  OwnedEntry{S.Entry{+position,old,entity},incarnation} = owner
  C.Position{d,+x,y,z} = position
  OwnedEntry{S.Entry{Bool.pick(C.Position,String.eq(gate,"current-position"),C.Position{d,U32.add(x,1),y,z},position),binding,entity},
    Bool.pick(Nat,String.eq(gate,"stale"),3n,incarnation)}
def forged(binding:B.Binding,+gate:String,source:Bool) -> B.Binding:
  B.Binding{state,name,family,lit,dark,bright} = binding
  B.Binding{state,Bool.pick(String,String.eq(gate,Bool.pick(String,source,"forged-source","forged-current")),"minecraft:blast_furnace",name),family,lit,dark,bright}
def source_gate(source:J.Source,+gate:String) -> J.Source:
  J.Source{position,binding,incarnation} = source
  J.Source{position,forged(binding,gate,True{}),incarnation}
def current_gate(source:J.Source,+gate:String) -> Maybe<&2,J.Source>:
  J.Source{position,binding,incarnation} = source
  Bool.pick(Maybe<&2,J.Source>,String.eq(gate,"missing-current"),None{},Some{J.Source{position,forged(binding,gate,False{}),incarnation}})
def binding(result:Result<&2,&2,String,B.Classification>) -> Result<&2,&2,String,B.Binding>:
  match result:
    case Done{B.Cooking{value}}: Done{value}
    case _: Fail{"fixture cooking binding missing"}
def bytes_equal(a:List<&2,U32>,b:List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && bytes_equal(xs,ys)
    case _ _: False{}
def raw_closed(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = result
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)
def raw(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    value : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,4194304)
    raw_closed(value)
def need(-A:Data,value:Result<&2,&2,String,A>) -> IO(A):
  match value:
    case Done{x}: IO.pure(A,x)
    case Fail{message}: IO.die(A,2,message)
def repeat_completed(result:G.Engine & J.State & Result<&2,&2,String,J.Receipt>,left:Nat,
    next:G.Engine -> J.State -> G.Engine & J.State & Result<&2,&2,String,J.Receipt>) ->
    G.Engine & J.State & Result<&2,&2,String,J.Receipt>:
  (engine,owner,status) = result
  match status left:
    case _ 0n: (engine,owner,status)
    case Fail{message} _: (engine,owner,Fail{message})
    case Done{receipt} 1n+rest: next(engine)(owner)
def dirty_repeat(+left:Nat,engine:G.Engine,+context:P.Context,+source:J.Source,+current:Maybe<&2,J.Source>,+position:C.Position,owner:J.State) ->
    G.Engine & J.State & Result<&2,&2,String,J.Receipt>:
  match left:
    case 0n: (engine,owner,Fail{"fixture zero repeat"})
    case 1n+rest:
      repeat_completed(P.dirty(engine,context,source,current,position,owner),rest,
        engine => owner => dirty_repeat(rest,engine,context,source,current,position,owner))
def status_value(value:Result<&2,&2,String,J.Receipt>) -> Json.Value:
  match value:
    case Fail{message}: text(message)
    case Done{receipt}: text("done")
def journal_value(result:J.State & J.View) -> Json.Value:
  (owner,view) = result
  view_value(view)
def entry_observation(+before:Json.Value,result:QueryResult) -> List<&2,Json.Member>:
  Queried{owner,current,+after} = result
  [Json.JMember{"entry_retained",Json.JBool{String.eq(Json.encode(before),Json.encode(after))}},
   Json.JMember{"entry",after},Json.JMember{"current",source_value(current)}]
def output_identity(label:String,+before:List<&2,U32>,+identity:String,owner:OwnedEntry,entry_before:Json.Value,
    journal:J.State,status:Json.Value,bytes:List<&2,U32>,result:R.Registry & Result<&2,&2,String,String>) -> IO(R.Registry):
  (kept,actual_identity) = result
  do IO<R.Registry>:
    registry_identity : String <- need(String,actual_identity)
    IO.print(Json.encode(Json.JObject{List.append(&2,Json.Member,[Json.JMember{"label",text(label)},Json.JMember{"status",status},
      Json.JMember{"core_retained",Json.JBool{bytes_equal(before,bytes)}},
      Json.JMember{"registry_retained",Json.JBool{String.eq(identity,registry_identity)}},
      Json.JMember{"journal",journal_value(J.inspect(journal))}],entry_observation(entry_before,query(owner)))}))
    return kept
def output(label:String,+before:List<&2,U32>,+identity:String,owner:OwnedEntry,entry_before:Json.Value,
    journal:J.State,status:Json.Value,result:C.World & Result<&2,&2,String,List<&2,U32>>,registry:R.Registry) -> IO(R.Registry):
  (world,encoded) = result
  do IO<R.Registry>:
    bytes : List<&2,U32> <- need(List<&2,U32>,encoded)
    output_identity(label,before,identity,owner,entry_before,journal,status,bytes,R.Registry.identity(registry))
def observed(+fixture:Fixture,+before:List<&2,U32>,+identity:String,entry_owner:OwnedEntry,entry_before:Json.Value,
    result:G.Engine & J.State & Result<&2,&2,String,J.Receipt>) -> IO(R.Registry):
  Fixture{label,path,position,source_state,current_state,gate,sequence,repeats} = fixture
  (G.Engine{world,registry},journal,status) = result
  output(label,before,identity,entry_owner,entry_before,journal,status_value(status),WC.encode(world,identity),registry)
def current_ready(+fixture:Fixture,+context:P.Context,+identity:String,+before:List<&2,U32>,registry:R.Registry,world:C.World,
    +captured:J.Source,+captured_binding:B.Binding,result:QueryResult) -> IO(R.Registry):
  Fixture{label,path,+position,source_state,current_state,+gate,+sequence,repeats} = fixture
  Queried{owner,current,entry_after} = result
  +old_position = {C.Position{"minecraft:the_nether",144,7,176} : C.Position}
  +old_chunk = {J.Chunk{"minecraft:the_nether",9,11} : J.Chunk}
  +effect_position = Bool.pick(C.Position,String.eq(gate,"effect-position"),C.Position{"minecraft:overworld",13,8,12},position)
  journal = J.install(J.View{sequence,[J.DirtyChunk{old_chunk,sequence}],
    Some{J.Receipt{old_position,J.Source{old_position,captured_binding,2n},old_chunk,sequence}}})
  observed(fixture,before,identity,owner,entry_after,dirty_repeat(repeats,G.Engine{world,registry},context,
    source_gate(captured,gate),current_gate(current,gate),effect_position,journal))
def captured_ready(+fixture:Fixture,+context:P.Context,+identity:String,+before:List<&2,U32>,registry:R.Registry,world:C.World,
    current_binding:B.Binding,+captured_binding:B.Binding,result:QueryResult) -> IO(R.Registry):
  Fixture{label,path,position,source_state,current_state,gate,sequence,repeats} = fixture
  Queried{owner,captured,entry_before} = result
  current_ready(fixture,context,identity,before,registry,world,captured,captured_binding,query(replace(owner,current_binding,gate)))
def loaded(+fixture:Fixture,+context:P.Context,+identity:String,+before:List<&2,U32>,registry:R.Registry,
    value:Result<&2,&1,String,WC.Loaded>) -> IO(R.Registry):
  Fixture{label,path,+position,source_state,current_state,gate,sequence,repeats} = fixture
  P.Context{+catalog} = context
  match value:
    case Fail{message}: IO.die(R.Registry,2,message)
    case Done{WC.Loaded{world,peer}}:
      do IO<R.Registry>:
        +captured_binding : B.Binding <- need(B.Binding,binding(B.classify(catalog,source_state)))
        current_binding : B.Binding <- need(B.Binding,binding(B.classify(catalog,current_state)))
        captured_ready(fixture,context,identity,before,registry,world,current_binding,captured_binding,query(entry(position,captured_binding)))
def run_case(fixture:Fixture,+context:P.Context,+identity:String,registry:R.Registry) -> IO(R.Registry):
  Fixture{label,+path,position,source_state,current_state,gate,sequence,repeats} = fixture
  do IO<R.Registry>:
    +bytes : List<&2,U32> <- raw(path)
    loaded(fixture,context,identity,bytes,registry,WC.decode(bytes,35723,identity))
def number_result(value:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match value:
    case None{}: Fail{"fixture number"}
    case Some{x}: Done{x}
def number(value:String) -> Result<&2,&2,String,U32>: number_result(U32.read(value))
def nat_result(value:Maybe<&2,Nat>) -> Result<&2,&2,String,Nat>:
  match value:
    case None{}: Fail{"fixture natural"}
    case Some{x}: Done{x}
def fixture(parts:List<&2,String>) -> Result<&2,&2,String,Fixture>:
  match parts:
    case label <> path <> x <> y <> z <> source <> current <> gate <> sequence <> repeats <> Nil{}:
      do Result<&2,&2,String,Fixture>:
        px : U32 <- number(x)
        py : U32 <- number(y)
        pz : U32 <- number(z)
        source_id : U32 <- number(source)
        current_id : U32 <- number(current)
        seq : Nat <- nat_result(Nat.read(sequence))
        count : Nat <- nat_result(Nat.read(repeats))
        return Fixture{label,path,C.Position{"minecraft:overworld",px,py,pz},source_id,current_id,gate,seq,count}
    case _: Fail{"fixture columns"}
def cases(values:List<&2,String>,+context:P.Context,+identity:String,registry:R.Registry) -> IO(R.Registry):
  match values:
    case Nil{}: IO.pure(R.Registry,registry)
    case +head <> rest:
      match head:
        case SNil{}: cases(rest,context,identity,registry)
        case _:
          do IO<R.Registry>:
            value : Fixture <- need(Fixture,fixture(String.split(head,'|')))
            next : R.Registry <- run_case(value,context,identity,registry)
            cases(rest,context,identity,next)
def journal_inspected(label:String,result:J.State & J.View) -> IO(J.State):
  (kept,view) = result
  do IO<J.State>:
    IO.print(Json.encode(Json.JObject{[Json.JMember{"label",text(label)},Json.JMember{"journal",view_value(view)}]}))
    return kept
def journal_output(label:String,owner:J.State) -> IO(J.State):
  journal_inspected(label,J.inspect(owner))
def journal_saved4(result:J.State & J.Snapshot) -> IO(Unit):
  (owner,saved) = result
  do IO<Unit>:
    final : J.State <- journal_output("save-current",J.save_completed(owner,Done{J.FullCookingSaveCommitted{saved}}))
    return Unit{}
def journal_marked4(saved:J.Snapshot,+position:C.Position,result:J.State & J.Receipt) -> IO(Unit):
  (owner,receipt) = result
  do IO<Unit>:
    four : J.State <- journal_output("save-covered-prefix",J.save_completed(owner,Done{J.FullCookingSaveCommitted{saved}}))
    four : J.State <- journal_output("save-future-refused",J.save_completed(four,Done{J.FullCookingSaveCommitted{J.Snapshot{5n,[J.DirtyChunk{J.chunk(position),5n}]}}}))
    four : J.State <- journal_output("save-invalid-chunk-refused",J.save_completed(four,Done{J.FullCookingSaveCommitted{J.Snapshot{4n,[J.DirtyChunk{J.chunk(position),5n}]}}}))
    journal_saved4(J.snapshot(four))
def journal_saved3(+source:J.Source,+position:C.Position,result:J.State & J.Snapshot) -> IO(Unit):
  (owner,saved) = result
  journal_marked4(saved,position,J.marked(position,source,owner))
def journal_marked3(+source:J.Source,+position:C.Position,saved:J.Snapshot,result:J.State & J.Receipt) -> IO(Unit):
  (owner,receipt) = result
  do IO<Unit>:
    three : J.State <- journal_output("journal-three",owner)
    three : J.State <- journal_output("save-failed",J.save_completed(three,Fail{"actual writer failed"}))
    three : J.State <- journal_output("save-old",J.save_completed(three,Done{J.FullCookingSaveCommitted{saved}}))
    journal_saved3(source,position,J.snapshot(three))
def journal_marked2(+source:J.Source,+position:C.Position,saved:J.Snapshot,result:J.State & J.Receipt) -> IO(Unit):
  J.Source{p,binding,incarnation} = source
  (owner,receipt) = result
  +other = {C.Position{"minecraft:overworld",28,8,12} : C.Position}
  journal_marked3(source,position,saved,J.marked(other,J.Source{other,binding,incarnation},owner))
def journal_saved1(+source:J.Source,+position:C.Position,result:J.State & J.Snapshot) -> IO(Unit):
  (owner,saved) = result
  journal_marked2(source,position,saved,J.marked(position,source,owner))
def journal_marked1(+source:J.Source,+position:C.Position,result:J.State & J.Receipt) -> IO(Unit):
  (owner,receipt) = result
  journal_saved1(source,position,J.snapshot(owner))
def journal_cases(+source:J.Source,+position:C.Position) -> IO(Unit):
  journal_marked1(source,position,J.marked(position,source,J.new()))
def restored(label:String,result:Result<&2,&1,String,J.State>) -> IO(Unit):
  match result:
    case Fail{message}:
      IO.print(Json.encode(Json.JObject{[Json.JMember{"label",text(label)},Json.JMember{"status",text(message)},Json.JMember{"journal",Json.JNull{}}]}))
    case Done{owner}:
      IO.print(Json.encode(Json.JObject{[Json.JMember{"label",text(label)},Json.JMember{"status",text("done")},Json.JMember{"journal",journal_value(J.inspect(owner))}]}))
def restore_case(+context:P.Context,label:String,+view:J.View,authenticated:Bool) -> IO(Unit):
  match authenticated:
    case False{}: restored(label,J.restore(view))
    case True{}: restored(label,P.restore_journal(context,view))
def restore_cases(values:List<&2,RestoreCase>,+context:P.Context) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case RestoreCase{label,view,authenticated} <> rest:
      do IO<Unit>:
        restore_case(context,label,view,authenticated)
        restore_cases(rest,context)
def recovery(context:P.Context,+binding:B.Binding) -> IO(Unit):
  +position = {C.Position{"minecraft:overworld",12,8,12} : C.Position}
  +target = {J.chunk(position) : J.Chunk}
  +source = {J.Source{position,binding,2n} : J.Source}
  +latest = {J.Receipt{position,source,target,3n} : J.Receipt}
  +chunks = {[J.DirtyChunk{target,3n}] : List<&2,J.DirtyChunk>}
  +view = {J.View{3n,chunks,Some{latest}} : J.View}
  +other = {C.Position{"minecraft:overworld",13,8,12} : C.Position}
  +bad_binding = {forged(binding,"forged-source",True{}) : B.Binding}
  restore_cases([
    RestoreCase{"restore-empty",J.View{0n,[],None{}},False{}},
    RestoreCase{"restore-valid",view,False{}},
    RestoreCase{"restore-clean-latest",J.View{3n,[],Some{latest}},False{}},
    RestoreCase{"restore-future-chunk",J.View{3n,[J.DirtyChunk{target,4n}],Some{latest}},False{}},
    RestoreCase{"restore-duplicate-chunks",J.View{3n,[J.DirtyChunk{target,3n},J.DirtyChunk{target,2n}],Some{latest}},False{}},
    RestoreCase{"restore-missing-last",J.View{3n,chunks,None{}},False{}},
    RestoreCase{"restore-wrong-position",J.View{3n,chunks,Some{J.Receipt{other,source,target,3n}}},False{}},
    RestoreCase{"restore-wrong-chunk",J.View{3n,chunks,Some{J.Receipt{position,source,J.Chunk{"minecraft:overworld",1,0},3n}}},False{}},
    RestoreCase{"restore-wrong-last-sequence",J.View{3n,chunks,Some{J.Receipt{position,source,target,2n}}},False{}},
    RestoreCase{"restore-zero-chunk",J.View{3n,[J.DirtyChunk{target,0n}],Some{latest}},False{}},
    RestoreCase{"restore-invalid-chunk-coordinate",J.View{3n,[J.DirtyChunk{J.Chunk{"minecraft:overworld",134217728,0},3n}],Some{latest}},False{}},
    RestoreCase{"restore-max-incarnation",J.View{3n,chunks,Some{J.Receipt{position,J.Source{position,binding,J.maximum_sequence()},target,3n}}},True{}},
    RestoreCase{"restore-authenticated",view,True{}},
    RestoreCase{"restore-forged-historical-binding",J.View{3n,chunks,Some{J.Receipt{position,J.Source{position,bad_binding,2n},target,3n}}},True{}}
  ],context)
def initialized(+catalog:B.Catalog,+identity:String,+input:String,result:G.Engine & Result<&2,&2,String,P.Context>) -> IO(Unit):
  (G.Engine{world,registry},status) = result
  do IO<Unit>:
    +context : P.Context <- need(P.Context,status)
    bytes : List<&2,U32> <- raw(input)
    value : String <- need(String,U.decode(4194304n,bytes))
    final : R.Registry <- cases(String.split(value,'\n'),context,identity,registry)
    +source_binding : B.Binding <- need(B.Binding,binding(B.classify(catalog,6884)))
    +position : C.Position = C.Position{"minecraft:overworld",12,8,12}
    journal_cases(J.Source{position,source_binding,2n},position)
    recovery(context,source_binding)
def bindings_loaded(+input:String,registry:R.Registry,+identity:String,bytes:List<&2,U32>) -> IO(Unit):
  do IO<Unit>:
    +catalog : B.Catalog <- need(B.Catalog,BL.parse(identity,35723,1048576n,bytes))
    initialized(catalog,identity,input,P.initialize(G.Engine{C.new(35723),registry},catalog))
def identity_loaded(binding_path:String,input:String,result:R.Registry & Result<&2,&2,String,String>) -> IO(Unit):
  (registry,status) = result
  do IO<Unit>:
    identity : String <- need(String,status)
    bytes : List<&2,U32> <- raw(binding_path)
    bindings_loaded(input,registry,identity,bytes)
def registry_loaded(binding_path:String,input:String,value:Result<&2,&1,R.Error,R.Registry>) -> IO(Unit):
  match value:
    case Fail{error}: IO.die(Unit,2,R.error_text(error))
    case Done{registry}: identity_loaded(binding_path,input,R.Registry.identity(registry))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> registry <> bindings <> input <> Nil{}:
      do IO<Unit>:
        value : Result<&2,&1,R.Error,R.Registry> <- R.Registry.load(registry)
        registry_loaded(bindings,input,value)
    case _: IO.die(Unit,2,"expected REGISTRY BINDINGS CASES")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
