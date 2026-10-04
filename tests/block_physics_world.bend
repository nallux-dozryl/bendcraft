import Base
import ../src/block_physics_world.bend as P
import ../src/block_physics.bend as K
import ../src/client_world.bend as W
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/f64.bend as F
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/world_codec.bend as WC
import ../src/section_map.bend as SM
import ../src/section.bend as S
import ../src/schedule.bend as Q
import ../src/json.bend as J

# Standalone lookup instrument. Fixtures install/forge owners explicitly;
# production lookup executes only P.query_cell/query_exact/query_cells.
type State is Type:
  State{world:W.State,catalog:K.Catalog,baseline:String}

def number(text:String) -> U32:
  Maybe.default(&2,U32,J.u32_lexeme(text),4294967295)

def words(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: U32.show(value)
    case value <> rest: U32.show(value) ++ "," ++ words(rest)

def wide(value:F.F64) -> List<&2,U32>:
  F.F64{hi,lo} = value
  [hi,lo]

def vector(value:M.Vec3) -> List<&2,U32>:
  M.Vec3{x,y,z} = value
  List.append(&2,U32,wide(x),List.append(&2,U32,wide(y),wide(z)))

def body_text(body:M.Body) -> String:
  M.Body{position,A.AABB{x,y,z,hx,hy,hz},velocity,width,height,ground,horizontal,vertical,below} = body
  words(vector(position)) ++ "," ++ words(wide(x)) ++ "," ++ words(wide(y)) ++ "," ++ words(wide(z)) ++ "," ++ words(wide(hx)) ++ "," ++ words(wide(hy)) ++ "," ++ words(wide(hz)) ++ "," ++ words(vector(velocity)) ++ "," ++ words([F32.bits(width),F32.bits(height),Bool.to_u32(ground),Bool.to_u32(horizontal),Bool.to_u32(vertical),Bool.to_u32(below)])

def bounds_text(bounds:W.Bounds) -> String:
  W.Bounds{x,y,z,width,height,depth} = bounds
  words([x,y,z,width,height,depth])

def palette_text(palette:W.Palette) -> String:
  W.Palette{air,stone,dirt,planks} = palette
  words([air,stone,dirt,planks])

def optional_palette(value:Maybe<&2,W.Palette>) -> String:
  match value:
    case None{}: "none"
    case Some{palette}: palette_text(palette)

def raw_text(blocks:List<&2,W.RawBlock>) -> String:
  match blocks:
    case Nil{}: ""
    case W.RawBlock{W.Cell{x,y,z,boundary},state,material} <> rest:
      words([x,y,z,boundary,state,material]) ++ ";" ++ raw_text(rest)

def cache_text(value:Maybe<&2,W.SnapshotCache>) -> String:
  match value:
    case None{}: "none"
    case Some{W.SnapshotCache{revision,region,palette,blocks}}:
      Nat.show(revision) ++ ":" ++ bounds_text(region) ++ ":" ++ palette_text(palette) ++ ":" ++ raw_text(blocks)

def view_text(view:W.View) -> String:
  W.View{body,yaw,pitch,palette,region,cache} = view
  body_text(body) ++ "|" ++ words([F32.bits(yaw),F32.bits(pitch)]) ++ "|" ++ optional_palette(palette) ++ "|" ++ bounds_text(region) ++ "|" ++ cache_text(cache)

def checked_view_valid(catalog:K.Catalog,baseline:String,engine:G.Engine,view:W.View,valid:Bool) -> State:
  match valid:
    case True{}: State{W.attach(engine,view),catalog,baseline}
    case False{}: State{W.attach(engine,view),catalog,"VIEW-MISMATCH"}

def checked_view(catalog:K.Catalog,+baseline:String,result:G.Engine & W.View) -> State:
  (engine,+view) = result
  checked_view_valid(catalog,baseline,engine,view,String.eq(view_text(view),baseline))

def checked_state(world:W.State,catalog:K.Catalog,baseline:String) -> State:
  checked_view(catalog,baseline,W.take(world))

def error_name(error:P.Error) -> String:
  match error:
    case P.UnknownDimension{name}: "UnknownDimension"
    case P.InvalidCoordinate{axis}: "InvalidCoordinate:" ++ U32.show(axis)
    case P.RegistryStateCount{count}: "RegistryStateCount"
    case P.CoreStateCount{count}: "CoreStateCount"
    case P.RegistryIdentityError{message}: "RegistryIdentityError"
    case P.ForeignRegistry{identity}: "ForeignRegistry"
    case P.WorldError{C.MissingSection{key}}: "MissingSection"
    case P.WorldError{cause}: "WorldError"
    case P.PrimitiveError{K.CatalogCorrupt{}}: "CatalogCorrupt"
    case P.PrimitiveError{K.InvalidState{state}}: "InvalidState"
    case P.PrimitiveError{cause}: "PrimitiveError"
    case P.BatchLimit{}: "BatchLimit"

def observation_text(result:Result<&2,&2,P.Error,P.Observation>) -> String:
  match result:
    case Fail{error}: "error\t" ++ error_name(error)
    case Done{P.Observation{state,K.Sample{K.Factors{a,b,c},K.WideFactors{F.F64{ah,al},F.F64{bh,bl},F.F64{ch,cl}}}}}:
      "ok\t" ++ U32.show(state) ++ "\t" ++ String.join(String.split(words([F32.bits(a),F32.bits(b),F32.bits(c),ah,al,bh,bl,ch,cl]),Chr{44}),"\t")

def result_single(+id:String,baseline:String,result:W.State & K.Catalog & Result<&2,&2,P.Error,P.Observation>) -> IO(State):
  (world,catalog,status) = result
  do IO<State>:
    IO.print(id ++ "\t" ++ observation_text(status))
    return checked_state(world,catalog,baseline)

def print_observations(values:List<&2,Result<&2,&2,P.Error,P.Observation>>,+id:String,+index:U32) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(id ++ ":" ++ U32.show(index) ++ "\t" ++ observation_text(value))
        print_observations(rest,id,U32.inc(index))

def result_batch(+id:String,baseline:String,result:W.State & K.Catalog & Result<&2,&2,P.Error,List<&2,Result<&2,&2,P.Error,P.Observation>>>) -> IO(State):
  (world,catalog,status) = result
  match status:
    case Fail{error}:
      do IO<State>:
        IO.print(id ++ "\t" ++ "error\t" ++ error_name(error))
        return checked_state(world,catalog,baseline)
    case Done{+values}:
      do IO<State>:
        IO.print(id ++ "\tok\tbatch\t" ++ Nat.show(List.length(&2,Result<&2,&2,P.Error,P.Observation>,values)))
        print_observations(values,id,0)
        return checked_state(world,catalog,baseline)

def positions_line(acc:List<&2,C.Position>,fields:List<&2,String>,finish:List<&2,C.Position> -> List<&2,C.Position>) -> List<&2,C.Position>:
  match fields:
    case dimension <> x <> y <> z <> Nil{}: finish(C.Position{dimension,number(x),number(y),number(z)} <> acc)
    case _: finish(acc)

def positions(lines:List<&2,String>,acc:List<&2,C.Position>) -> List<&2,C.Position>:
  match lines:
    case Nil{}: List.reverse(&2,C.Position,acc)
    case line <> rest: positions_line(acc,String.split(line,Chr{9}),values => positions(rest,values))

def batch_loaded(id:String,state:State,result:Result<&2,&2,B.Error,String>) -> IO(State):
  match state result:
    case _ Fail{cause}: IO.die(State,2,B.error_text(cause))
    case State{world,catalog,baseline} Done{text}: result_batch(id,baseline,P.query_cells(world,catalog,positions(String.split(text,Chr{10}),[])))

def batch_file(id:String,state:State,path:String) -> IO(State):
  do IO<State>:
    loaded : Result<&2,&2,B.Error,String> <- B.read_text(path)
    batch_loaded(id,state,loaded)

def repeat_cells(n:Nat,+cell:C.Position) -> List<&2,C.Position>:
  match n:
    case 0n: []
    case 1n+rest: cell <> repeat_cells(rest,cell)

def write_closed(result:File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    IO.pass(Unit,status)

def write_file(path:String,bytes:List<&2,U32>) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"w"))
    result : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
    write_closed(result)

def checkpoint_encoded(id:String,path:String,registry:B.Registry,view:W.View,catalog:K.Catalog,baseline:String,result:C.World & Result<&2,&2,String,List<&2,U32>>) -> IO(State):
  (world,status) = result
  match status:
    case Fail{message}: IO.die(State,2,message)
    case Done{bytes}:
      do IO<State>:
        write_file(path,bytes)
        IO.print(id ++ "\tok\tcheckpoint")
        return checked_state(W.attach(G.Engine{world,registry},view),catalog,baseline)

def checkpoint_taken(id:String,path:String,catalog:K.Catalog,baseline:String,result:G.Engine & W.View) -> IO(State):
  (G.Engine{world,registry},view) = result
  checkpoint_encoded(id,path,registry,view,catalog,baseline,WC.encode(world,K.pinned_identity()))

def checkpoint(id:String,state:State,path:String) -> IO(State):
  State{world,catalog,baseline} = state
  checkpoint_taken(id,path,catalog,baseline,W.take(world))

def range_text(range:K.Range) -> String:
  K.Range{first,count,K.Factors{a,b,c}} = range
  words([first,count,F32.bits(a),F32.bits(b),F32.bits(c)])

def catalog_read(acc:String,result:Array<K.Range> & K.Range,finish:Array<K.Range> -> String -> Array<K.Range> & String) -> Array<K.Range> & String:
  (array,range) = result
  finish(array,acc ++ range_text(range) ++ ";")

def catalog_go(fuel:Nat,+index:U32,array:Array<K.Range>,acc:String) -> Array<K.Range> & String:
  match fuel:
    case 0n: (array,acc)
    case 1n+rest: catalog_read(acc,Array.get(K.Range,array,index),kept => text => catalog_go(rest,U32.inc(index),kept,text))

def catalog_sized(+count:U32,+states:U32,+identity:String,sized:Array<K.Range> & U32) -> K.Catalog & String:
  (array,+capacity) = sized
  W.paired(Array<K.Range>,String,K.Catalog & String,catalog_go(U32.to_nat(capacity),0,array,""),kept => text => (K.Catalog{kept,count,states,identity},words([count,states,capacity]) ++ ":" ++ identity ++ ":" ++ text))

def catalog_show(catalog:K.Catalog) -> K.Catalog & String:
  K.Catalog{array,count,states,identity} = catalog
  catalog_sized(count,states,identity,Array.size(K.Range,array))

def inspect_shown(+id:String,world:W.State,+baseline:String,result:K.Catalog & String) -> IO(State):
  (catalog,text) = result
  do IO<State>:
    IO.print(id ++ "\tok\tcatalog\t" ++ text)
    IO.print(id ++ "\tok\tview\t" ++ baseline)
    return checked_state(world,catalog,baseline)

def inspect(id:String,state:State) -> IO(State):
  State{world,catalog,baseline} = state
  inspect_shown(id,world,baseline,catalog_show(catalog))

def counts_taken(id:String,catalog:K.Catalog,baseline:String,result:G.Engine & W.View) -> IO(State):
  (G.Engine{C.World{tick,time,paused,daylight,revision,+core_count,sections,pending,events},B.Registry{blocks,names,+block_count,+registry_count}},view) = result
  do IO<State>:
    IO.print(id ++ "\tok\tcounts\t" ++ words([core_count,registry_count,block_count]))
    return checked_state(W.attach(G.Engine{C.World{tick,time,paused,daylight,revision,core_count,sections,pending,events},B.Registry{blocks,names,block_count,registry_count}},view),catalog,baseline)

def forge_catalog(catalog:K.Catalog,mode:String,value:U32) -> K.Catalog:
  K.Catalog{array,count,states,identity} = catalog
  match mode:
    case "count": K.Catalog{array,value,states,identity}
    case "states": K.Catalog{array,count,value,identity}
    case "identity": K.Catalog{array,count,states,"wrong"}
    case "short": K.Catalog{[K.Range{0,1,K.Factors{0.6,1.0,1.0}}:K.Range*1n],count,states,identity}
    case _: K.Catalog{array,count,states,identity}

def changed_core_count(id:String,catalog:K.Catalog,baseline:String,value:U32,result:G.Engine & W.View) -> IO(State):
  (G.Engine{C.World{tick,time,paused,daylight,revision,old,sections,pending,events},registry},view) = result
  do IO<State>:
    IO.print(id ++ "\tok\tcore-count")
    return checked_state(W.attach(G.Engine{C.World{tick,time,paused,daylight,revision,value,sections,pending,events},registry},view),catalog,baseline)

def changed_registry_count(id:String,catalog:K.Catalog,baseline:String,value:U32,result:G.Engine & W.View) -> IO(State):
  (G.Engine{world,B.Registry{blocks,names,count,old}},view) = result
  do IO<State>:
    IO.print(id ++ "\tok\tregistry-count")
    return checked_state(W.attach(G.Engine{world,B.Registry{blocks,names,count,value}},view),catalog,baseline)

def changed_block_count(id:String,catalog:K.Catalog,baseline:String,value:U32,result:G.Engine & W.View) -> IO(State):
  (G.Engine{world,B.Registry{blocks,names,old,states}},view) = result
  do IO<State>:
    IO.print(id ++ "\tok\tblock-count")
    return checked_state(W.attach(G.Engine{world,B.Registry{blocks,names,value,states}},view),catalog,baseline)

def changed_view_gate(id:String,catalog:K.Catalog,engine:G.Engine,+view:W.View) -> IO(State):
  do IO<State>:
    IO.print(id ++ "\tok\tview-mode")
    return State{W.attach(engine,view),catalog,view_text(view)}

def changed_view(id:String,catalog:K.Catalog,mode:String,result:G.Engine & W.View) -> IO(State):
  (engine,W.View{body,yaw,pitch,palette,region,cache}) = result
  changed_view_gate(id,catalog,engine,W.View{body,yaw,pitch,None{},region,None{}})

def changed_registry(id:String,catalog:K.Catalog,baseline:String,replacement:B.Registry,result:G.Engine & W.View) -> IO(State):
  (G.Engine{world,old},view) = result
  do IO<State>:
    IO.print(id ++ "\tok\tregistry")
    return checked_state(W.attach(G.Engine{world,replacement},view),catalog,baseline)

def registry_loaded(id:String,state:State,result:Result<&2,&1,B.Error,B.Registry>) -> IO(State):
  match state result:
    case _ Fail{cause}: IO.die(State,2,B.error_text(cause))
    case State{world,catalog,baseline} Done{registry}: changed_registry(id,catalog,baseline,registry,W.take(world))

def registry_file(id:String,state:State,path:String) -> IO(State):
  do IO<State>:
    registry : Result<&2,&1,B.Error,B.Registry> <- B.Registry.load(path)
    registry_loaded(id,state,registry)

def restored_catalog(id:String,world:W.State,baseline:String,result:K.Catalog & Result<&2,&2,K.Error,Unit>) -> IO(State):
  (catalog,status) = result
  match status:
    case Fail{cause}: IO.die(State,2,K.error_text(cause))
    case Done{unit}:
      do IO<State>:
        IO.print(id ++ "\tok\trestore-catalog")
        return checked_state(world,catalog,baseline)

def restore_text(id:String,state:State,result:Result<&2,&2,B.Error,String>) -> IO(State):
  match state result:
    case _ Fail{cause}: IO.die(State,2,B.error_text(cause))
    case State{world,catalog,baseline} Done{text}: restored_catalog(id,world,baseline,K.Catalog.replace(catalog,text))

def restore_file(id:String,state:State,path:String) -> IO(State):
  do IO<State>:
    text : Result<&2,&2,B.Error,String> <- B.read_text(path)
    restore_text(id,state,text)

def forged_section(id:String,key:String,fill:U32,catalog:K.Catalog,baseline:String,result:G.Engine & W.View) -> IO(State):
  (G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},view) = result
  do IO<State>:
    IO.print(id ++ "\tok\tsection")
    return checked_state(W.attach(G.Engine{C.World{tick,time,paused,daylight,revision,count,SM.set(sections,key,S.Section.new(fill)),pending,events},registry},view),catalog,baseline)

def edit_admitted(id:String,registry:B.Registry,view:W.View,catalog:K.Catalog,baseline:String,result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(State):
  (world,status) = result
  match status:
    case Fail{cause}: IO.die(State,2,W.error_text(cause))
    case Done{unit}:
      do IO<State>:
        IO.print(id ++ "\tok\tcore-edit")
        return checked_state(W.attach(G.Engine{C.advance(1n,world),registry},view),catalog,baseline)

def edit_taken(id:String,state:U32,catalog:K.Catalog,baseline:String,result:G.Engine & W.View) -> IO(State):
  (G.Engine{world,registry},view) = result
  edit_admitted(id,registry,view,catalog,baseline,C.admit(world,C.Developer{},Q.Stamp{43n,7,9n},C.BlockSet{C.Position{"minecraft:overworld",0,0,0},state}))

def operation(fields:List<&2,String>,state:State) -> IO(State):
  match fields state:
    case id <> "cell" <> dimension <> x <> y <> z <> Nil{} State{world,catalog,baseline}:
      result_single(id,baseline,P.query_cell(world,catalog,C.Position{dimension,number(x),number(y),number(z)}))
    case id <> "exact" <> dimension <> xh <> xl <> yh <> yl <> zh <> zl <> Nil{} State{world,catalog,baseline}:
      result_single(id,baseline,P.query_exact(world,catalog,dimension,M.Vec3{F.F64{number(xh),number(xl)},F.F64{number(yh),number(yl)},F.F64{number(zh),number(zl)}}))
    case id <> "batch" <> path <> Nil{} _: batch_file(id,state,path)
    case id <> "repeat" <> size <> dimension <> x <> y <> z <> Nil{} State{world,catalog,baseline}:
      result_batch(id,baseline,P.query_cells(world,catalog,repeat_cells(U32.to_nat(number(size)),C.Position{dimension,number(x),number(y),number(z)})))
    case id <> "checkpoint" <> path <> Nil{} _: checkpoint(id,state,path)
    case id <> "inspect" <> Nil{} _: inspect(id,state)
    case id <> "counts" <> Nil{} State{world,catalog,baseline}: counts_taken(id,catalog,baseline,W.take(world))
    case id <> "forge-catalog" <> mode <> value <> Nil{} State{world,catalog,baseline}:
      do IO<State>:
        IO.print(id ++ "\tok\tforge-catalog")
        return checked_state(world,forge_catalog(catalog,mode,number(value)),baseline)
    case id <> "core-count" <> value <> Nil{} State{world,catalog,baseline}: changed_core_count(id,catalog,baseline,number(value),W.take(world))
    case id <> "registry-count" <> value <> Nil{} State{world,catalog,baseline}: changed_registry_count(id,catalog,baseline,number(value),W.take(world))
    case id <> "block-count" <> value <> Nil{} State{world,catalog,baseline}: changed_block_count(id,catalog,baseline,number(value),W.take(world))
    case id <> "view-mode" <> mode <> Nil{} State{world,catalog,baseline}: changed_view(id,catalog,mode,W.take(world))
    case id <> "registry" <> path <> Nil{} _: registry_file(id,state,path)
    case id <> "restore-catalog" <> path <> Nil{} _: restore_file(id,state,path)
    case id <> "section" <> key <> fill <> Nil{} State{world,catalog,baseline}: forged_section(id,key,number(fill),catalog,baseline,W.take(world))
    case id <> "edit" <> value <> Nil{} State{world,catalog,baseline}: edit_taken(id,number(value),catalog,baseline,W.take(world))
    case "" <> Nil{} _: IO.pure(State,state)
    case _ _ : IO.die(State,2,"invalid controlled request")

def operations(lines:List<&2,String>,state:State) -> IO(State):
  match lines:
    case Nil{}: IO.pure(State,state)
    case line <> rest:
      do IO<State>:
        next : State <- operation(String.split(line,Chr{9}),state)
        operations(rest,next)

def raw_closed(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = result
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)

def raw_file(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,4194304)
    raw_closed(result)

def instrument_view() -> W.View:
  +palette : W.Palette = W.Palette{0,1,10,15}
  +region : W.Bounds = W.Bounds{4294967264,4294967280,16,7,8,9}
  W.View{M.Body{M.Vec3{F.F64{2147483648,0},F.from_f32(3.5),F.from_f32(F32.neg(2.5))},A.AABB{F.from_f32(F32.neg(0.5)),F.from_f32(3.5),F.from_f32(F32.neg(3.0)),F.from_f32(0.5),F.from_f32(5.5),F.from_f32(F32.neg(2.0))},M.Vec3{F.from_f32(0.25),F.F64{2147483648,0},F.from_f32(0.125)},1.0,2.0,False{},True{},True{},False{}},F32.neg(0.0),0.25,Some{palette},region,Some{W.SnapshotCache{987n,region,palette,[W.RawBlock{W.Cell{4294967295,4294967294,4294967293,4},257,9}]}}}

def final_report(state:State) -> IO(Unit):
  State{world,catalog,baseline} = state
  IO.print("final\tok\tview-retained\t" ++ U32.show(Bool.to_u32(Bool.not(String.eq(baseline,"VIEW-MISMATCH")))))

def loaded_requests(state:State,result:Result<&2,&2,B.Error,String>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,2,B.error_text(cause))
    case Done{text}:
      do IO<Unit>:
        after : State <- operations(String.split(text,Chr{10}),state)
        final_report(after)

def loaded_world(registry:B.Registry,catalog:K.Catalog,requests:String,result:Result<&2,&1,String,WC.Loaded>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{WC.Loaded{world,peer}}:
      do IO<Unit>:
        +view : W.View = instrument_view()
        text : Result<&2,&2,B.Error,String> <- B.read_text(requests)
        loaded_requests(State{W.attach(G.Engine{world,registry},view),catalog,view_text(view)},text)

def loaded_catalog(world:String,requests:String,result:B.Registry & Result<&2,&1,K.Error,K.Catalog>) -> IO(Unit):
  (registry,status) = result
  match status:
    case Fail{cause}: IO.die(Unit,2,K.error_text(cause))
    case Done{catalog}:
      do IO<Unit>:
        bytes : List<&2,U32> <- raw_file(world)
        loaded_world(registry,catalog,requests,WC.decode(bytes,K.pinned_states(),K.pinned_identity()))

def loaded_registry(catalog:String,world:String,requests:String,result:Result<&2,&1,B.Error,B.Registry>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,2,B.error_text(cause))
    case Done{registry}:
      do IO<Unit>:
        paired : B.Registry & Result<&2,&1,K.Error,K.Catalog> <- K.Catalog.load(registry,catalog)
        loaded_catalog(world,requests,paired)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case registry <> catalog <> world <> requests <> Nil{}:
      do IO<Unit>:
        loaded : Result<&2,&1,B.Error,B.Registry> <- B.Registry.load(registry)
        loaded_registry(catalog,world,requests,loaded)
    case _: IO.die(Unit,2,"expected REGISTRY CATALOG WORLD_NBT REQUESTS after --")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(List.tail(&1,String,args))
