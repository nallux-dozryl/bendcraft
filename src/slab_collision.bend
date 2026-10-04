import Base
import ./f64.bend as F
import ./geometry.bend as A
import ./registry.bend as B
import ./json.bend as J
import ./unicode.bend as U
import ./hash.bend as H

# Only normally constructed, official registered SlabBlock collision getters.
# Shape derives from admitted TYPE; no arbitrary Collider is stored in the catalog.
type SlabType is Data:
  TopSlab{}
  BottomSlab{}
  DoubleSlab{}
type Entry is Data:
  Entry{state_id:U32,slab_type:SlabType,waterlogged:Bool}
type Sample is Data:
  Sample{state_id:U32,slab_type:SlabType,waterlogged:Bool,collision:A.Collider}
type Catalog is Type:
  Catalog{entries:Array<Entry>,count:U32,state_count:U32,identity:String}
type Error is Data:
  IdentityMismatch{provided:String}
  StateCountMismatch{provided:U32}
  IntegrityMismatch{}
  InvalidState{state:U32}
  UnsupportedState{state:U32}
  CatalogCorrupt{}
  SchemaError{row:U32,message:String}
  TextError{message:String}
  ByteLimit{bytes:Nat}
  ReadError{code:U32,message:String}
  RegistryError{message:String}
type Builder is Type:
  Builder{entries:Array<Entry>,loaded:U32,last:U32}

def pinned_identity() -> String:
  "4f75fa335a12e34cf74be71ff6a0ee530b13233212423f5463bb26a2fe4f3cfc"

def pinned_states() -> U32:
  35723

def pinned_sha256() -> String:
  "e36cb6c6bd59dea0b4bd6300eb96ff61bf689ef006029bc9b954b042cc630856"

def byte_limit() -> Nat:
  16384n

def error_text(error:Error) -> String:
  match error:
    case IdentityMismatch{provided}: "identity:" ++ provided
    case StateCountMismatch{provided}: "state-count:" ++ U32.show(provided)
    case IntegrityMismatch{}: "integrity"
    case InvalidState{state}: "invalid-state:" ++ U32.show(state)
    case UnsupportedState{state}: "unsupported-state:" ++ U32.show(state)
    case CatalogCorrupt{}: "catalog-corrupt"
    case SchemaError{row,message}: "schema:" ++ U32.show(row) ++ ":" ++ message
    case TextError{message}: "text:" ++ message
    case ByteLimit{bytes}: "byte-limit:" ++ Nat.show(bytes)
    case ReadError{code,message}: "read:" ++ U32.show(code) ++ ":" ++ message
    case RegistryError{message}: "registry:" ++ message

def pinned_slabs() -> U32:
  606

def collision(slab_type:SlabType) -> A.Collider:
  match slab_type:
    case TopSlab{}: A.BoxCollider{A.AABB{F.F64{0,0},F.F64{1071644672,0},F.F64{0,0},F.F64{1072693248,0},F.F64{1072693248,0},F.F64{1072693248,0}}}
    case BottomSlab{}: A.BoxCollider{A.AABB{F.F64{0,0},F.F64{0,0},F.F64{0,0},F.F64{1072693248,0},F.F64{1071644672,0},F.F64{1072693248,0}}}
    case DoubleSlab{}: A.BoxCollider{A.AABB{F.F64{0,0},F.F64{0,0},F.F64{0,0},F.F64{1072693248,0},F.F64{1072693248,0},F.F64{1072693248,0}}}

def sample(entry:Entry) -> Sample:
  match entry:
    case Entry{id,+kind,waterlogged}: Sample{id,kind,waterlogged,collision(kind)}

def zero_entry() -> Entry:
  Entry{0,BottomSlab{},False{}}

def number_result(row:U32,name:String,value:Maybe<&2,U32>) -> Result<&2,&2,Error,U32>:
  match value:
    case None{}: Fail{SchemaError{row,"invalid U32 " ++ name}}
    case Some{value}: Done{value}

def number(row:U32,name:String,text:String) -> Result<&2,&2,Error,U32>:
  number_result(row,name,J.u32_lexeme(text))

def kind(row:U32,text:String) -> Result<&2,&2,Error,SlabType>:
  match text:
    case "top": Done{TopSlab{}}
    case "bottom": Done{BottomSlab{}}
    case "double": Done{DoubleSlab{}}
    case _: Fail{SchemaError{row,"unknown slab type"}}

def water(row:U32,text:String) -> Result<&2,&2,Error,Bool>:
  match text:
    case "0": Done{False{}}
    case "1": Done{True{}}
    case _: Fail{SchemaError{row,"invalid waterlogged bit"}}

def row_checked(row:U32,id:U32,kind:SlabType,water:Bool,valid:Bool) -> Result<&2,&2,Error,Entry>:
  match valid:
    case False{}: Fail{SchemaError{row,"state outside official registry"}}
    case True{}: Done{Entry{id,kind,water}}

def row_fields(+row:U32,fields:List<&2,String>) -> Result<&2,&2,Error,Entry>:
  match fields:
    case id <> slab_type <> waterlogged <> Nil{}:
      do Result<&2,&2,Error,Entry>:
        +state : U32 <- number(row,"state ID",id)
        slab : SlabType <- kind(row,slab_type)
        wet : Bool <- water(row,waterlogged)
        row_checked(row,state,slab,wet,U32.is_lt(state,pinned_states()))
    case _: Fail{SchemaError{row,"expected three TSV fields"}}

def build_row.checked(row:U32,entries:Array<Entry>,+loaded:U32,entry:Entry,valid:Bool) -> Result<&2,&1,Error,Builder>:
  match entry valid:
    case _ False{}: Fail{SchemaError{row,"unordered/duplicate state or capacity exceeded"}}
    case Entry{+id,slab_type,waterlogged} True{}:
      Done{Builder{Array.set(Entry,entries,loaded,Entry{id,slab_type,waterlogged}),U32.inc(loaded),id}}

def build_row(+row:U32,builder:Builder,result:Result<&2,&2,Error,Entry>) -> Result<&2,&1,Error,Builder>:
  match builder result:
    case _ Fail{error}: Fail{error}
    case Builder{entries,+loaded,last} Done{+entry}:
      Entry{id,slab_type,waterlogged} = entry
      build_row.checked(row,entries,loaded,entry,U32.is_lt(loaded,pinned_slabs()) && (U32.is_eq(loaded,0) || U32.is_gt(id,last)))

def finish_checked(entries:Array<Entry>,loaded:U32,valid:Bool) -> Result<&2,&1,Error,Catalog>:
  match valid:
    case False{}: Fail{SchemaError{0,"incomplete pinned slab coverage"}}
    case True{}: Done{Catalog{entries,loaded,pinned_states(),pinned_identity()}}

def finish(result:Result<&2,&1,Error,Builder>) -> Result<&2,&1,Error,Catalog>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Builder{entries,+loaded,last}}:
      finish_checked(entries,loaded,U32.is_eq(loaded,pinned_slabs()))

def schema_rows(lines:List<&2,String>,+row:U32,builder:Result<&2,&1,Error,Builder>) -> Result<&2,&1,Error,Catalog>:
  match lines builder:
    case _ Fail{error}: Fail{error}
    case Nil{} _: finish(builder)
    case SNil{} <> Nil{} _: finish(builder)
    case line <> rest Done{built}:
      schema_rows(rest,U32.inc(row),build_row(row,built,row_fields(row,String.split(line,'\t'))))

def schema_header(lines:List<&2,String>,valid:Bool) -> Result<&2,&1,Error,Catalog>:
  match valid:
    case False{}: Fail{SchemaError{1,"invalid pinned catalog header"}}
    case True{}: schema_rows(lines,3,Done{Builder{[zero_entry() : Entry*1024n],0,0}})

def schema_lines(lines:List<&2,String>) -> Result<&2,&1,Error,Catalog>:
  match lines:
    case first <> fields <> rest:
      schema_header(rest,String.eq(first,"BendSlabCollision\t1\t26.3\t" ++ pinned_identity() ++ "\t35723\t606") && String.eq(fields,"state_id\tslab_type\twaterlogged"))
    case _: Fail{SchemaError{1,"missing catalog headers"}}

def parsed_hash.checked(text:String,valid:Bool) -> Result<&2,&1,Error,Catalog>:
  match valid:
    case False{}: Fail{IntegrityMismatch{}}
    case True{}: schema_lines(String.split(text,'\n'))

def parsed_hash(text:String,result:Result<&2,&2,String,H.Digest>) -> Result<&2,&1,Error,Catalog>:
  match result:
    case Fail{message}: Fail{TextError{message}}
    case Done{digest}:
      parsed_hash.checked(text,String.eq(H.Digest.hex(digest),pinned_sha256()))

def parsed_encoded(text:String,result:Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&1,Error,Catalog>:
  match result:
    case Fail{message}: Fail{TextError{message}}
    case Done{bytes}: parsed_hash(text,H.digest(byte_limit(),bytes))

def parse_count(+text:String,count:U32,valid:Bool) -> Result<&2,&1,Error,Catalog>:
  match valid:
    case False{}: Fail{StateCountMismatch{count}}
    case True{}: parsed_encoded(text,U.encode(byte_limit(),text))

def parse_identity(identity:String,+count:U32,text:String,valid:Bool) -> Result<&2,&1,Error,Catalog>:
  match valid:
    case False{}: Fail{IdentityMismatch{identity}}
    case True{}: parse_count(text,count,U32.is_eq(count,pinned_states()))

def Catalog.parse(+identity:String,count:U32,text:String) -> Result<&2,&1,Error,Catalog>:
  parse_identity(identity,count,text,String.eq(identity,pinned_identity()))

def decoded_text(identity:String,count:U32,result:Result<&2,&2,String,String>) -> Result<&2,&1,Error,Catalog>:
  match result:
    case Fail{message}: Fail{TextError{message}}
    case Done{text}: Catalog.parse(identity,count,text)

def decode_sized(identity:String,count:U32,bytes:List<&2,U32>,size:Nat,valid:Bool) -> Result<&2,&1,Error,Catalog>:
  match valid:
    case False{}: Fail{ByteLimit{size}}
    case True{}: decoded_text(identity,count,U.decode(byte_limit(),bytes))

def Catalog.decode(identity:String,count:U32,+bytes:List<&2,U32>) -> Result<&2,&1,Error,Catalog>:
  +size = List.length(&2,U32,bytes)
  decode_sized(identity,count,bytes,size,Nat.is_le(size,byte_limit()))

def query_search.choose(count:U32,states:U32,identity:String,state:U32,entries:Array<Entry>,entry:Entry,next_left:Array<Entry> -> Catalog & Result<&2,&2,Error,Sample>,next_right:Array<Entry> -> Catalog & Result<&2,&2,Error,Sample>,valid:Bool,order:Cmp) -> Catalog & Result<&2,&2,Error,Sample>:
  match valid order:
    case False{} _: (Catalog{entries,count,states,identity},Fail{CatalogCorrupt{}})
    case True{} EQ{}: (Catalog{entries,count,states,identity},Done{sample(entry)})
    case True{} LT{}: next_left(entries)
    case True{} GT{}: next_right(entries)

def query_search.read(+count:U32,+states:U32,+identity:String,+state:U32,+mid:U32,read:Array<Entry> & Entry,next_left:Array<Entry> -> Catalog & Result<&2,&2,Error,Sample>,next_right:Array<Entry> -> Catalog & Result<&2,&2,Error,Sample>) -> Catalog & Result<&2,&2,Error,Sample>:
  (entries,+entry) = read
  Entry{+id,kind,water} = entry
  query_search.choose(count,states,identity,state,entries,entry,next_left,next_right,U32.is_lt(id,states),U32.cmp(state,id))

def query_search.bounds(+low:U32,+high:U32,count:U32,states:U32,identity:String,state:U32,entries:Array<Entry>,more:Bool,next_left:Array<Entry> -> Catalog & Result<&2,&2,Error,Sample>,next_right:Array<Entry> -> Catalog & Result<&2,&2,Error,Sample>) -> Catalog & Result<&2,&2,Error,Sample>:
  match more:
    case False{}: (Catalog{entries,count,states,identity},Fail{UnsupportedState{state}})
    case True{}:
      +mid = U32.div(U32.add(low,high),2)
      query_search.read(count,states,identity,state,mid,Array.get(Entry,entries,mid),next_left,next_right)

def query_search(+fuel:Nat,+low:U32,+high:U32,+count:U32,+states:U32,+identity:String,+state:U32,entries:Array<Entry>) -> Catalog & Result<&2,&2,Error,Sample>:
  match fuel:
    case 0n: (Catalog{entries,count,states,identity},Fail{CatalogCorrupt{}})
    case 1n+rest:
      query_search.bounds(low,high,count,states,identity,state,entries,U32.is_lt(low,high),remaining => query_search(rest,low,U32.div(U32.add(low,high),2),count,states,identity,state,remaining),remaining => query_search(rest,U32.inc(U32.div(U32.add(low,high),2)),high,count,states,identity,state,remaining))

def query_metadata.checked(+count:U32,states:U32,identity:String,state:U32,entries:Array<Entry>,valid:Bool) -> Catalog & Result<&2,&2,Error,Sample>:
  match valid:
    case False{}: (Catalog{entries,count,states,identity},Fail{CatalogCorrupt{}})
    case True{}: query_search(11n,0,count,count,states,identity,state,entries)

def query_metadata.sized(+count:U32,+states:U32,+identity:String,state:U32,sized:Array<Entry> & U32) -> Catalog & Result<&2,&2,Error,Sample>:
  (entries,capacity) = sized
  query_metadata.checked(count,states,identity,state,entries,U32.is_eq(count,pinned_slabs()) && U32.is_le(count,capacity) && U32.is_eq(states,pinned_states()) && String.eq(identity,pinned_identity()))

def query_metadata(catalog:Catalog,state:U32) -> Catalog & Result<&2,&2,Error,Sample>:
  match catalog:
    case Catalog{entries,count,states,identity}: query_metadata.sized(count,states,identity,state,Array.size(Entry,entries))

def query_bounds(catalog:Catalog,state:U32,valid:Bool) -> Catalog & Result<&2,&2,Error,Sample>:
  match valid:
    case False{}: (catalog,Fail{InvalidState{state}})
    case True{}: query_metadata(catalog,state)

def query_identity(catalog:Catalog,identity:String,+state:U32,valid:Bool) -> Catalog & Result<&2,&2,Error,Sample>:
  match valid:
    case False{}: (catalog,Fail{IdentityMismatch{identity}})
    case True{}: query_bounds(catalog,state,U32.is_lt(state,pinned_states()))

def Catalog.query(catalog:Catalog,+identity:String,state:U32) -> Catalog & Result<&2,&2,Error,Sample>:
  query_identity(catalog,identity,state,String.eq(identity,pinned_identity()))

def replace_result(catalog:Catalog,result:Result<&2,&1,Error,Catalog>) -> Catalog & Result<&2,&2,Error,Unit>:
  match result:
    case Fail{error}: (catalog,Fail{error})
    case Done{replacement}: (replacement,Done{Unit{}})

def Catalog.replace(catalog:Catalog,text:String) -> Catalog & Result<&2,&2,Error,Unit>:
  replace_result(catalog,Catalog.parse(pinned_identity(),pinned_states(),text))

def Catalog.bind.count(text:String,identity:String,registry:B.Registry) -> B.Registry & Result<&2,&1,Error,Catalog>:
  match registry:
    case B.Registry{blocks,names,count,+states}:
      (B.Registry{blocks,names,count,states},Catalog.parse(identity,states,text))

def bind_sized(text:String,result:B.Registry & Result<&2,&2,String,String>) -> B.Registry & Result<&2,&1,Error,Catalog>:
  (registry,status) = result
  match status:
    case Fail{message}: (registry,Fail{RegistryError{message}})
    case Done{identity}: Catalog.bind.count(text,identity,registry)

def Catalog.bind(registry:B.Registry,text:String) -> B.Registry & Result<&2,&1,Error,Catalog>:
  bind_sized(text,B.Registry.identity(registry))

def read_tail(bytes:List<&2,U32>,result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Result<&2,&2,Error,List<&2,U32>>):
  (file,status) = result
  match status:
    case Fail{(code,message)}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        File.close(file)
        return Fail{ReadError{code,message}}
    case Done{Nil{}}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        File.close(file)
        return Done{bytes}
    case Done{_}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        File.close(file)
        return Fail{ByteLimit{16385n}}

def read_bytes(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Result<&2,&2,Error,List<&2,U32>>):
  (file,status) = result
  match status:
    case Fail{(code,message)}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        File.close(file)
        return Fail{ReadError{code,message}}
    case Done{bytes}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        tail : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,1)
        read_tail(bytes,tail)

def read_open(result:Result<&1,&1,U32 & String,File>) -> IO(Result<&2,&2,Error,List<&2,U32>>):
  match result:
    case Fail{(code,message)}: IO.pure(Result<&2,&2,Error,List<&2,U32>>,Fail{ReadError{code,message}})
    case Done{file}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        read : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,16384)
        read_bytes(read)

def read_file(path:String) -> IO(Result<&2,&2,Error,List<&2,U32>>):
  do IO<Result<&2,&2,Error,List<&2,U32>>>:
    opened : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
    read_open(opened)

def loaded_text(registry:B.Registry,result:Result<&2,&2,String,String>) -> B.Registry & Result<&2,&1,Error,Catalog>:
  match result:
    case Fail{message}: (registry,Fail{TextError{message}})
    case Done{text}: Catalog.bind(registry,text)

def loaded_bytes(registry:B.Registry,result:Result<&2,&2,Error,List<&2,U32>>) -> B.Registry & Result<&2,&1,Error,Catalog>:
  match result:
    case Fail{error}: (registry,Fail{error})
    case Done{bytes}: loaded_text(registry,U.decode(byte_limit(),bytes))

def Catalog.load(registry:B.Registry,path:String) -> IO(B.Registry & Result<&2,&1,Error,Catalog>):
  do IO<B.Registry & Result<&2,&1,Error,Catalog>>:
    bytes : Result<&2,&2,Error,List<&2,U32>> <- read_file(path)
    return loaded_bytes(registry,bytes)

law wrong_identity_query_retains_owner:
  for catalog:Catalog
  for state:U32
  {Catalog.query(catalog,"",state) == (catalog,Fail{IdentityMismatch{""}}) : Catalog & Result<&2,&2,Error,Sample>}

def wrong_identity_query_retains_owner(catalog,state):
  {==}

law maximum_state_query_retains_owner:
  for catalog:Catalog
  {Catalog.query(catalog,pinned_identity(),4294967295) == (catalog,Fail{InvalidState{4294967295}}) : Catalog & Result<&2,&2,Error,Sample>}

def maximum_state_query_retains_owner(catalog):
  {==}

law replacement_failure_retains_owner:
  for catalog:Catalog
  for error:Error
  {replace_result(catalog,Fail{error}) == (catalog,Fail{error}) : Catalog & Result<&2,&2,Error,Unit>}

def replacement_failure_retains_owner(catalog,error):
  {==}
