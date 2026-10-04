import Base
import ../src/slab_collision.bend as K
import ../src/registry.bend as B
import ../src/unicode.bend as U
import ../src/json.bend as J
import ../src/f64.bend as F
import ../src/geometry.bend as A

type State is Type:
  State{registry:B.Registry,catalog:K.Catalog}

def error_name(error:K.Error) -> String:
  match error:
    case K.IdentityMismatch{provided}: "IdentityMismatch"
    case K.StateCountMismatch{provided}: "StateCountMismatch"
    case K.IntegrityMismatch{}: "IntegrityMismatch"
    case K.InvalidState{state}: "InvalidState"
    case K.UnsupportedState{state}: "UnsupportedState"
    case K.CatalogCorrupt{}: "CatalogCorrupt"
    case K.SchemaError{row,message}: "SchemaError"
    case K.TextError{message}: "TextError"
    case K.ByteLimit{bytes}: "ByteLimit"
    case K.ReadError{code,message}: "ReadError"
    case K.RegistryError{message}: "RegistryError"

def words(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: U32.show(value)
    case value <> rest: U32.show(value) ++ "\t" ++ words(rest)

def kind_text(kind:K.SlabType) -> String:
  match kind:
    case K.TopSlab{}: "top"
    case K.BottomSlab{}: "bottom"
    case K.DoubleSlab{}: "double"

def water_text(water:Bool) -> String:
  match water:
    case False{}: "0"
    case True{}: "1"

def box_words(box:A.Collider) -> String:
  match box:
    case A.EmptyCollider{}: "empty"
    case A.BoxCollider{A.AABB{F.F64{ah,al},F.F64{bh,bl},F.F64{ch,cl},F.F64{dh,dl},F.F64{eh,el},F.F64{fh,fl}}}:
      words([ah,al,bh,bl,ch,cl,dh,dl,eh,el,fh,fl])

def sample_text(sample:K.Sample) -> String:
  K.Sample{id,kind,water,box} = sample
  "ok\t" ++ U32.show(id) ++ "\t" ++ kind_text(kind) ++ "\t" ++ water_text(water) ++ "\t" ++ box_words(box)

def queried(registry:B.Registry,result:K.Catalog & Result<&2,&2,K.Error,K.Sample>) -> State & String:
  (catalog,status) = result
  match status:
    case Fail{error}: (State{registry,catalog},"error\t" ++ error_name(error))
    case Done{sample}: (State{registry,catalog},sample_text(sample))

def query(state:State,identity:String,id:U32) -> State & String:
  State{registry,catalog} = state
  queried(registry,K.Catalog.query(catalog,identity,id))

def candidate(state:State,result:Result<&2,&1,K.Error,K.Catalog>,name:String) -> State & String:
  match state result:
    case _ Fail{error}: (state,"error\t" ++ error_name(error))
    case State{registry,old} Done{catalog}: (State{registry,catalog},"ok\t" ++ name)

def replacing(registry:B.Registry,result:K.Catalog & Result<&2,&2,K.Error,Unit>) -> State & String:
  (catalog,status) = result
  match status:
    case Fail{error}: (State{registry,catalog},"error\t" ++ error_name(error))
    case Done{unit}: (State{registry,catalog},"ok\treplace")

def text_bound(catalog:K.Catalog,result:B.Registry & Result<&2,&1,K.Error,K.Catalog>) -> State & String:
  (registry,status) = result
  candidate(State{registry,catalog},status,"bind")

def textual_value(mode:String,state:State,identity:String,count:U32,text:String) -> State & String:
  match mode state:
    case "replace" State{registry,catalog}: replacing(registry,K.Catalog.replace(catalog,text))
    case "parse" _: candidate(state,K.Catalog.parse(identity,count,text),"parse")
    case "bind" State{registry,catalog}: text_bound(catalog,K.Catalog.bind(registry,text))
    case _ _: (state,"error\tFixtureError")

def textual(state:State,mode:String,identity:String,count:U32,result:Result<&2,&2,String,String>) -> State & String:
  match result:
    case Fail{message}: (state,"error\tTextError")
    case Done{text}: textual_value(mode,state,identity,count,text)

def text_read(state:State,mode:String,identity:String,count:U32,result:Result<&2,&2,K.Error,List<&2,U32>>) -> State & String:
  match result:
    case Fail{error}: (state,"error\t" ++ error_name(error))
    case Done{bytes}: textual(state,mode,identity,count,U.decode(K.byte_limit(),bytes))

def raw_closed(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = result
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)

def raw_file(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    read : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,262144)
    raw_closed(read)

def text_operation(state:State,mode:String,identity:String,count:U32,path:String) -> IO(State & String):
  do IO<State & String>:
    bytes : List<&2,U32> <- raw_file(path)
    return textual(state,mode,identity,count,U.decode(262144n,bytes))

def load_candidate(catalog:K.Catalog,result:B.Registry & Result<&2,&1,K.Error,K.Catalog>) -> State & String:
  (registry,status) = result
  candidate(State{registry,catalog},status,"load")

def load_operation(state:State,path:String) -> IO(State & String):
  State{registry,catalog} = state
  do IO<State & String>:
    loaded : B.Registry & Result<&2,&1,K.Error,K.Catalog> <- K.Catalog.load(registry,path)
    return load_candidate(catalog,loaded)

def foreign_identity(state:State,name:String,result:B.Registry & Result<&2,&2,String,String>) -> State & String:
  (registry,status) = result
  match status:
    case Fail{message}: (state,"error\tRegistryError")
    case Done{identity}: (state,"error\t" ++ name ++ "\t" ++ identity)

def foreign_catalog(state:State,result:B.Registry & Result<&2,&1,K.Error,K.Catalog>) -> State & String:
  (registry,status) = result
  match status:
    case Fail{error}: foreign_identity(state,error_name(error),B.Registry.identity(registry))
    case Done{catalog}: (state,"error\tUnexpectedForeignCatalog")

def foreign_loaded(state:State,path:String,result:Result<&2,&1,B.Error,B.Registry>) -> IO(State & String):
  match result:
    case Fail{error}: IO.pure(State & String,(state,"error\tRegistryError"))
    case Done{registry}:
      do IO<State & String>:
        result : B.Registry & Result<&2,&1,K.Error,K.Catalog> <- K.Catalog.load(registry,path)
        return foreign_catalog(state,result)

def foreign_operation(state:State,registry_path:String,catalog_path:String) -> IO(State & String):
  do IO<State & String>:
    registry : Result<&2,&1,B.Error,B.Registry> <- B.Registry.load(registry_path)
    foreign_loaded(state,catalog_path,registry)

def little_words(bytes:List<&2,U32>,acc:List<&2,U32>) -> List<&2,U32>:
  match bytes:
    case Nil{}: List.reverse(&2,U32,acc)
    case a <> b <> c <> d <> rest:
      little_words(rest,U32.or(a,U32.or(U32.shln(b,8n),U32.or(U32.shln(c,16n),U32.shln(d,24n)))) <> acc)
    case _: Nil{}

def decode_words(state:State,identity:String,count:U32,path:String) -> IO(State & String):
  do IO<State & String>:
    bytes : List<&2,U32> <- raw_file(path)
    return candidate(state,K.Catalog.decode(identity,count,little_words(bytes,Nil{})),"decode")

def inspected_block(catalog:K.Catalog,identity:String,result:B.Registry & Result<&2,&2,B.Error,B.Block>) -> State & String:
  (registry,status) = result
  match status:
    case Fail{error}: (State{registry,catalog},"error\tRegistryError")
    case Done{B.Block{protocol,name,first,count,default_id,props}}:
      (State{registry,catalog},"ok\tregistry\t" ++ identity ++ "\t" ++ name ++ "\t" ++ U32.show(first))

def inspected(catalog:K.Catalog,result:B.Registry & Result<&2,&2,String,String>) -> State & String:
  (registry,status) = result
  match status:
    case Fail{message}: (State{registry,catalog},"error\tRegistryError")
    case Done{identity}: inspected_block(catalog,identity,B.Registry.block(registry,"minecraft:oak_slab"))

def inspect(state:State) -> State & String:
  State{registry,catalog} = state
  inspected(catalog,B.Registry.identity(registry))

# Explicit malformed-owner fixtures, outside Catalog integrity admission.
def forged_fields(name:String,entries:Array<K.Entry>,count:U32,states:U32,identity:String) -> K.Catalog:
  match name:
    case "zero-count": K.Catalog{entries,0,states,identity}
    case "short-count": K.Catalog{entries,605,states,identity}
    case "large-count": K.Catalog{entries,607,states,identity}
    case "max-count": K.Catalog{entries,4294967295,states,identity}
    case "wrong-states": K.Catalog{entries,count,0,identity}
    case "wrong-identity": K.Catalog{entries,count,states,"wrong"}
    case "short-array": K.Catalog{[K.zero_entry() : K.Entry*1n],count,states,identity}
    case "outside-state": K.Catalog{Array.set(K.Entry,entries,303,K.Entry{4294967295,K.TopSlab{},False{}}),count,states,identity}
    case _: K.Catalog{entries,count,states,identity}

def forged(name:String,catalog:K.Catalog) -> K.Catalog:
  K.Catalog{entries,count,states,identity} = catalog
  forged_fields(name,entries,count,states,identity)

def forge(state:State,name:String) -> State & String:
  State{registry,catalog} = state
  (State{registry,forged(name,catalog)},"ok\tforge")

def u32_value(value:Maybe<&2,U32>) -> U32:
  match value:
    case None{}: 4294967295
    case Some{word}: word

def u32(text:String) -> U32:
  u32_value(J.u32_lexeme(text))

def execute(state:State,fields:List<&2,String>) -> IO(State & String):
  match fields:
    case "state" <> id <> Nil{}: IO.pure(State & String,query(state,K.pinned_identity(),u32(id)))
    case "query" <> id <> identity <> Nil{}: IO.pure(State & String,query(state,identity,u32(id)))
    case "replace" <> path <> Nil{}: text_operation(state,"replace",K.pinned_identity(),K.pinned_states(),path)
    case "parse" <> identity <> count <> path <> Nil{}: text_operation(state,"parse",identity,u32(count),path)
    case "bind" <> path <> Nil{}: text_operation(state,"bind",K.pinned_identity(),K.pinned_states(),path)
    case "load" <> path <> Nil{}: load_operation(state,path)
    case "foreign" <> registry <> catalog <> Nil{}: foreign_operation(state,registry,catalog)
    case "decode" <> identity <> count <> path <> Nil{}: decode_words(state,identity,u32(count),path)
    case "inspect" <> Nil{}: IO.pure(State & String,inspect(state))
    case "forge" <> name <> Nil{}: IO.pure(State & String,forge(state,name))
    case "invalid-scalar" <> Nil{}:
      IO.pure(State & String,candidate(state,K.Catalog.parse(K.pinned_identity(),K.pinned_states(),SCon{Chr{55296},SNil{}}),"parse"))
    case _: IO.pure(State & String,(state,"error\tFixtureError"))

def processed(result:State & String,next:State -> IO(Unit)) -> IO(Unit):
  (state,response) = result
  do IO<Unit>:
    IO.print(response)
    next(state)

def process(lines:List<&2,String>,state:State) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit,Unit{})
    case SNil{} <> Nil{}: IO.pure(Unit,Unit{})
    case line <> rest:
      do IO<Unit>:
        result : State & String <- execute(state,String.split(line,'\t'))
        processed(result,next => process(rest,next))

def requests(state:State,result:Result<&2,&2,B.Error,String>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,2,B.error_text(error))
    case Done{text}: process(String.split(text,'\n'),state)

def catalog_loaded(path:String,result:B.Registry & Result<&2,&1,K.Error,K.Catalog>) -> IO(Unit):
  (registry,status) = result
  match status:
    case Fail{error}: IO.die(Unit,2,K.error_text(error))
    case Done{catalog}:
      do IO<Unit>:
        text : Result<&2,&2,B.Error,String> <- B.read_text(path)
        requests(State{registry,catalog},text)

def registry_loaded(catalog_path:String,requests_path:String,result:Result<&2,&1,B.Error,B.Registry>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,2,B.error_text(error))
    case Done{registry}:
      do IO<Unit>:
        result : B.Registry & Result<&2,&1,K.Error,K.Catalog> <- K.Catalog.load(registry,catalog_path)
        catalog_loaded(requests_path,result)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case registry_path <> catalog_path <> requests_path <> Nil{}:
      do IO<Unit>:
        registry : Result<&2,&1,B.Error,B.Registry> <- B.Registry.load(registry_path)
        registry_loaded(catalog_path,requests_path,registry)
    case _: IO.die(Unit,2,"expected REGISTRY CATALOG REQUESTS paths")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(List.tail(&1,String,args))
