import Base
import ./f64.bend as F
import ./registry.bend as B
import ./json.bend as J
import ./unicode.bend as U
import ./hash.bend as H

# Only the pinned Block stored friction/speedFactor/jumpFactor getters.
# Contextual shapes and the entity's application of these factors are separate.
type Factors is Data:
  Factors{friction:F32,speed_factor:F32,jump_factor:F32}
type WideFactors is Data:
  WideFactors{friction:F.F64,speed_factor:F.F64,jump_factor:F.F64}
type Sample is Data:
  Sample{factors:Factors,widened:WideFactors}
type Range is Data:
  Range{first:U32,count:U32,factors:Factors}
type Catalog is Type:
  Catalog{ranges:Array<Range>,range_count:U32,state_count:U32,identity:String}
type Error is Data:
  IdentityMismatch{provided:String}
  StateCountMismatch{provided:U32}
  IntegrityMismatch{}
  InvalidState{state:U32}
  CatalogCorrupt{}
  SchemaError{row:U32,message:String}
  TextError{message:String}
  ByteLimit{bytes:Nat}
  ReadError{code:U32,message:String}
  RegistryError{message:String}
type Builder is Type:
  Builder{ranges:Array<Range>,loaded:U32,next:U32}

def pinned_identity() -> String:
  "4f75fa335a12e34cf74be71ff6a0ee530b13233212423f5463bb26a2fe4f3cfc"

def pinned_states() -> U32:
  35723

def pinned_sha256() -> String:
  "e4a4ad19274a04559ea8aa72a61db792744a54c84d50f0a4a5321aec75fc6e93"

def byte_limit() -> Nat:
  8192n

def error_text(error:Error) -> String:
  match error:
    case IdentityMismatch{provided}: "identity:" ++ provided
    case StateCountMismatch{provided}: "state-count:" ++ U32.show(provided)
    case IntegrityMismatch{}: "integrity"
    case InvalidState{state}: "invalid-state:" ++ U32.show(state)
    case CatalogCorrupt{}: "catalog-corrupt"
    case SchemaError{row,message}: "schema:" ++ U32.show(row) ++ ":" ++ message
    case TextError{message}: "text:" ++ message
    case ByteLimit{bytes}: "byte-limit:" ++ Nat.show(bytes)
    case ReadError{code,message}: "read:" ++ U32.show(code) ++ ":" ++ message
    case RegistryError{message}: "registry:" ++ message

def float_bits(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}

def finite_bits(+value:U32) -> Bool:
  U32.is_ne(U32.and(U32.shrn(value,23n),255),255)

def widened(factors:Factors) -> Sample:
  match factors:
    case Factors{+friction,+speed,+jump}:
      Sample{Factors{friction,speed,jump},WideFactors{F.from_f32(friction),F.from_f32(speed),F.from_f32(jump)}}

def zero_range() -> Range:
  Range{0,0,Factors{0.0,0.0,0.0}}

def number_result(row:U32,name:String,value:Maybe<&2,U32>) -> Result<&2,&2,Error,U32>:
  match value:
    case None{}: Fail{SchemaError{row,"invalid U32 " ++ name}}
    case Some{value}: Done{value}

def number(row:U32,name:String,text:String) -> Result<&2,&2,Error,U32>:
  number_result(row,name,J.u32_lexeme(text))

def row_checked(row:U32,first:U32,count:U32,a:U32,b:U32,c:U32,valid:Bool) -> Result<&2,&2,Error,Range>:
  match valid:
    case False{}: Fail{SchemaError{row,"empty/overflowing interval or nonfinite primitive"}}
    case True{}: Done{Range{first,count,Factors{float_bits(a),float_bits(b),float_bits(c)}}}

def row_fields(+row:U32,fields:List<&2,String>) -> Result<&2,&2,Error,Range>:
  match fields:
    case first <> count <> friction <> speed <> jump <> Nil{}:
      do Result<&2,&2,Error,Range>:
        +start : U32 <- number(row,"first",first)
        +size : U32 <- number(row,"count",count)
        +a : U32 <- number(row,"friction bits",friction)
        +b : U32 <- number(row,"speed bits",speed)
        +c : U32 <- number(row,"jump bits",jump)
        row_checked(row,start,size,a,b,c,U32.is_gt(size,0) && U32.is_le(start,pinned_states()) && U32.is_le(size,U32.sub(pinned_states(),start)) && finite_bits(a) && finite_bits(b) && finite_bits(c))
    case _: Fail{SchemaError{row,"expected five TSV fields"}}

def build_row.checked(row:U32,ranges:Array<Range>,+loaded:U32,next:U32,range:Range,valid:Bool) -> Result<&2,&1,Error,Builder>:
  match range valid:
    case _ False{}: Fail{SchemaError{row,"noncontiguous interval or range capacity exceeded"}}
    case Range{first,+count,factors} True{}:
      Done{Builder{Array.set(Range,ranges,loaded,Range{first,count,factors}),U32.inc(loaded),U32.add(next,count)}}

def build_row(+row:U32,builder:Builder,result:Result<&2,&2,Error,Range>) -> Result<&2,&1,Error,Builder>:
  match builder result:
    case _ Fail{error}: Fail{error}
    case Builder{ranges,+loaded,+next} Done{+range}:
      Range{first,count,factors} = range
      build_row.checked(row,ranges,loaded,next,range,U32.is_lt(loaded,16) && U32.is_eq(first,next))

def finish_checked(ranges:Array<Range>,loaded:U32,valid:Bool) -> Result<&2,&1,Error,Catalog>:
  match valid:
    case False{}: Fail{SchemaError{0,"incomplete pinned state coverage"}}
    case True{}: Done{Catalog{ranges,loaded,pinned_states(),pinned_identity()}}

def finish(result:Result<&2,&1,Error,Builder>) -> Result<&2,&1,Error,Catalog>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Builder{ranges,+loaded,next}}:
      finish_checked(ranges,loaded,U32.is_gt(loaded,0) && U32.is_eq(next,pinned_states()))

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
    case True{}: schema_rows(lines,3,Done{Builder{[zero_range() : Range*16n],0,0}})

def schema_lines(lines:List<&2,String>) -> Result<&2,&1,Error,Catalog>:
  match lines:
    case first <> fields <> rest:
      schema_header(rest,String.eq(first,"BendBlockPrimitives\t1\t26.3\t" ++ pinned_identity() ++ "\t35723") && String.eq(fields,"first_state_id\tstate_count\tfriction_f32_bits\tspeed_factor_f32_bits\tjump_factor_f32_bits"))
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

def query_found(count:U32,states:U32,identity:String,read:Array<Range> & Range) -> Catalog & Result<&2,&2,Error,Sample>:
  (ranges,Range{first,size,factors}) = read
  (Catalog{ranges,count,states,identity},Done{widened(factors)})

def query_search.checked(count:U32,states:U32,identity:String,ranges:Array<Range>,range:Range,next:Array<Range> -> Catalog & Result<&2,&2,Error,Sample>,valid:Bool,contains:Bool) -> Catalog & Result<&2,&2,Error,Sample>:
  match valid contains:
    case False{} _: (Catalog{ranges,count,states,identity},Fail{CatalogCorrupt{}})
    case True{} True{}: query_found(count,states,identity,(ranges,range))
    case True{} False{}: next(ranges)

def query_search.read(count:U32,+states:U32,identity:String,+state:U32,read:Array<Range> & Range,next:Array<Range> -> Catalog & Result<&2,&2,Error,Sample>) -> Catalog & Result<&2,&2,Error,Sample>:
  (ranges,+range) = read
  Range{+first,+size,factors} = range
  query_search.checked(count,states,identity,ranges,range,next,U32.is_gt(size,0) && U32.is_le(first,states) && U32.is_le(size,U32.sub(states,first)),U32.is_ge(state,first) && U32.is_lt(state,U32.add(first,size)))

# At most sixteen exact contiguous ranges; the parsed catalog has fifteen.
# The small linear walk keeps one array owner and needs no state-sized table.
def query_search(fuel:Nat,+index:U32,+count:U32,+states:U32,+identity:String,+state:U32,ranges:Array<Range>) -> Catalog & Result<&2,&2,Error,Sample>:
  match fuel:
    case 0n: (Catalog{ranges,count,states,identity},Fail{CatalogCorrupt{}})
    case 1n+rest:
      query_search.read(count,states,identity,state,Array.get(Range,ranges,index),remaining => query_search(rest,U32.inc(index),count,states,identity,state,remaining))

def query_metadata.checked(+count:U32,states:U32,identity:String,state:U32,ranges:Array<Range>,valid:Bool) -> Catalog & Result<&2,&2,Error,Sample>:
  match valid:
    case False{}: (Catalog{ranges,count,states,identity},Fail{CatalogCorrupt{}})
    case True{}: query_search(U32.to_nat(count),0,count,states,identity,state,ranges)

def query_metadata.sized(+count:U32,+states:U32,+identity:String,state:U32,sized:Array<Range> & U32) -> Catalog & Result<&2,&2,Error,Sample>:
  (ranges,capacity) = sized
  query_metadata.checked(count,states,identity,state,ranges,U32.is_gt(count,0) && U32.is_le(count,16) && U32.is_le(count,capacity) && U32.is_eq(states,pinned_states()) && String.eq(identity,pinned_identity()))

def query_metadata(catalog:Catalog,state:U32) -> Catalog & Result<&2,&2,Error,Sample>:
  match catalog:
    case Catalog{ranges,count,states,identity}: query_metadata.sized(count,states,identity,state,Array.size(Range,ranges))

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
        return Fail{ByteLimit{8193n}}

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
        read : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,8192)
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
