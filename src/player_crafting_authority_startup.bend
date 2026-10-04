import Base
import ./player_crafting_authority_load.bend as L
import ./crafting_recipe_decoder.bend as D
import ./json.bend as J
import ./hash.bend as Hash
import ./unicode.bend as Unicode

# Pinned generated registry facts contain observed initialized component maps,
# remainders, resolved tags and ordered recipe IDs. Recipe source stays in the
# actual installed JAR and still goes through Bend's owned ZIP/recipe decoder.
type Facts is Data:
  Facts{metadata:J.Value,ordered_ids:List<&2,String>}

def facts_digest() -> String:
  "9105c1fa3a9eefbab94d21626e1d5be1ad69c9765e19b608e257e458b9e853d1"

def identifiers(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,String>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        id:String <- D.text(value)
        tail:List<&2,String> <- identifiers(rest)
        return id <> tail

def facts(+value:J.Value) -> Result<&2,&2,String,Facts>:
  do Result<&2,&2,String,Facts>:
    raw:J.Value <- D.field(value,"ordered_recipe_ids")
    values:List<&2,J.Value> <- D.array(raw)
    ids:List<&2,String> <- identifiers(values)
    return Facts{value,ids}

def parsed(result:Result<&2,&2,String,J.Value>) -> Result<&2,&2,String,Facts>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: facts(value)

def decoded(result:Result<&1,&1,U32 & String,List<&2,U32>>) -> Result<&2,&2,String,Facts>:
  match result:
    case Fail{Tuple{code,message}}: Fail{"crafting registry facts read: " ++ message}
    case Done{+bytes}:
      do Result<&2,&2,String,Facts>:
        D.guard(Nat.is_le(List.length(&2,U32,bytes),U32.to_nat(8388608)),"crafting registry facts exceed byte budget")
        digest:Hash.Digest <- Hash.digest(U32.to_nat(8388608),bytes)
        D.guard(String.eq(Hash.Digest.hex(digest),facts_digest()),"pinned crafting registry facts digest mismatch")
        text:String <- Unicode.decode(U32.to_nat(8388608),bytes)
        parsed(J.parse_bounded(text,U32.to_nat(8388608),64))

def loaded(result:Result<&2,&2,String,Facts>,jar:String,item_table:String,limits:L.Limits) -> IO(Result<&2,&2,String,L.Service>):
  match result:
    case Fail{message}: IO.pure(Result<&2,&2,String,L.Service>,Fail{message})
    case Done{Facts{metadata,ids}}: L.service(jar,ids,item_table,metadata,limits)

def closed(read:File & Result<&1,&1,U32 & String,List<&2,U32>>,jar:String,item_table:String,limits:L.Limits) -> IO(Result<&2,&2,String,L.Service>):
  (file,result) = read
  do IO<Result<&2,&2,String,L.Service>>:
    File.close(file)
    loaded(decoded(result),jar,item_table,limits)

def opened(result:Result<&1,&1,U32 & String,File>,jar:String,item_table:String,limits:L.Limits) -> IO(Result<&2,&2,String,L.Service>):
  match result:
    case Fail{Tuple{code,message}}: IO.pure(Result<&2,&2,String,L.Service>,Fail{"crafting registry facts open: " ++ message})
    case Done{file}:
      do IO<Result<&2,&2,String,L.Service>>:
        read:File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,8388609)
        closed(read,jar,item_table,limits)

def service(jar:String,item_table:String,facts_path:String,limits:L.Limits) -> IO(Result<&2,&2,String,L.Service>):
  do IO<Result<&2,&2,String,L.Service>>:
    result:Result<&1,&1,U32 & String,File> <- File.open(facts_path,"r")
    opened(result,jar,item_table,limits)
