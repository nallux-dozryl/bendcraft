import Base
import ./cooking_world_bindings.bend as B
import ./cooking_recipe.bend as K
import ./campfire_authority.bend as C
import ./hash.bend as H
import ./unicode.bend as U

def guard(ok:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match ok:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}
def number(value:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match value:
    case None{}: Fail{"cooking-world:invalid-number"}
    case Some{x}: Done{x}
def boolean(+text:String) -> Result<&2,&2,String,Bool>:
  do Result<&2,&2,String,Bool>:
    guard(String.eq(text,"true") || String.eq(text,"false"),"cooking-world:invalid-lit")
    return String.eq(text,"true")
def campfire(damage:U32) -> Result<&2,&2,String,B.Family>:
  match damage:
    case 1: Done{B.Campfire{C.Ordinary{}}}
    case 2: Done{B.Campfire{C.Soul{}}}
    case _: Fail{"cooking-world:unsupported-campfire-damage-kind"}
def family_go(+name:String,damage:U32,a:Bool,b:Bool,c:Bool,d:Bool) -> Result<&2,&2,String,B.Family>:
  match a b c d:
    case True{} _ _ _: Done{B.Furnace{K.Smelting{}}}
    case False{} True{} _ _: Done{B.Furnace{K.Blasting{}}}
    case False{} False{} True{} _: Done{B.Furnace{K.Smoking{}}}
    case False{} False{} False{} True{}: campfire(damage)
    case _ _ _ _: Fail{"cooking-world:unsupported-cooking-family"}
def family(+name:String,damage:U32) -> Result<&2,&2,String,B.Family>:
  family_go(name,damage,String.eq(name,"smelting"),String.eq(name,"blasting"),String.eq(name,"smoking"),String.eq(name,"campfire"))
def row(parts:List<&2,String>,+count:U32) -> Result<&2,&2,String,B.Binding>:
  match parts:
    case state <> block <> kind <> lit <> dark <> bright <> damage <> Nil{}:
      do Result<&2,&2,String,B.Binding>:
        +id : U32 <- number(U32.read(state))
        +unlit : U32 <- number(U32.read(dark))
        +light : U32 <- number(U32.read(bright))
        +hit : Bool <- boolean(lit)
        amount : U32 <- number(U32.read(damage))
        kind_value : B.Family <- family(kind,amount)
        guard(U32.is_lt(id,count) && U32.is_lt(unlit,count) && U32.is_lt(light,count),"cooking-world:binding-outside-registry")
        guard(U32.is_eq(id,Bool.pick(U32,hit,light,unlit)),"cooking-world:inconsistent-lit-state")
        return B.Binding{id,block,kind_value,hit,unlit,light}
    case _: Fail{"cooking-world:invalid-binding-row"}
def add_found(result:Map<&2,Maybe<&2,B.Binding>> & Maybe<&2,B.Binding>,+value:B.Binding) -> Result<&2,&2,String,Map<&2,Maybe<&2,B.Binding>>>:
  (kept,previous) = result
  B.Binding{+id,block,kind,lit,dark,bright} = value
  do Result<&2,&2,String,Map<&2,Maybe<&2,B.Binding>>>:
    guard(Maybe.is_none(&2,B.Binding,previous),"cooking-world:duplicate-binding")
    return Map.set(&2,Maybe<&2,B.Binding>,kept,U32.show(id),Some{value})
def add(+value:B.Binding,+entries:Map<&2,Maybe<&2,B.Binding>>) -> Result<&2,&2,String,Map<&2,Maybe<&2,B.Binding>>>:
  B.Binding{+id,block,kind,lit,dark,bright} = value
  add_found(Map.get(Maybe<&2,B.Binding>,None{},entries,U32.show(id)),value)
def rows(values:List<&2,String>,+count:U32,entries:Map<&2,Maybe<&2,B.Binding>>) -> Result<&2,&2,String,Map<&2,Maybe<&2,B.Binding>>>:
  match values:
    case Nil{}: Done{entries}
    case +head <> tail:
      do Result<&2,&2,String,Map<&2,Maybe<&2,B.Binding>>>:
        value : B.Binding <- row(String.split(head,'\t'),count)
        next : Map<&2,Maybe<&2,B.Binding>> <- add(value,entries)
        rows(tail,count,next)
def header(+identity:String,+count:U32,parts:List<&2,String>,lines:List<&2,String>) -> Result<&2,&2,String,B.Catalog>:
  match parts:
    case marker <> pin <> actual <> states <> Nil{}:
      do Result<&2,&2,String,B.Catalog>:
        number_count : U32 <- number(U32.read(states))
        guard(String.eq(marker,"pin") && String.eq(pin,"26.3") && String.eq(actual,identity) && U32.is_eq(number_count,count),"cooking-world:registry-identity-mismatch")
        entries : Map<&2,Maybe<&2,B.Binding>> <- rows(lines,count,MTip{})
        return B.Catalog{identity,count,entries}
    case _: Fail{"cooking-world:invalid-binding-header"}
def decode(identity:String,count:U32,lines:List<&2,String>) -> Result<&2,&2,String,B.Catalog>:
  match lines:
    case Nil{}: Fail{"cooking-world:missing-binding-header"}
    case head <> rest: header(identity,count,String.split(head,'\t'),rest)
def nonempty_cons(+head:String,+tail:List<&2,String>) -> List<&2,String>:
  Bool.pick(List<&2,String>,String.eq(head,""),tail,head <> tail)
def nonempty(values:List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: []
    case head <> tail: nonempty_cons(head,nonempty(tail))
# Integrity authenticates exhaustive classification; absent in-range rows are
# ordinary blocks only for this pinned manifest, not caller-selected fixtures.
def parse(identity:String,count:U32,+limit:Nat,+bytes:List<&2,U32>) -> Result<&2,&2,String,B.Catalog>:
  do Result<&2,&2,String,B.Catalog>:
    digest : H.Digest <- H.digest(limit,bytes)
    guard(String.eq(H.Digest.hex(digest),"7f083e1ae13c83a20a576fcf1fd4b6f5c505b1e203eff691ffa2eacedcb8b290"),"cooking-world:manifest-integrity-mismatch")
    text : String <- U.decode(limit,bytes)
    decode(identity,count,nonempty(String.split(text,'\n')))
