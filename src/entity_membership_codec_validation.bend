import Base
import ./entity_section_membership_model.bend as M
import ./entity_section_membership.bend as P
import ./cooking_effect_entities_model.bend as E
import ./random.bend as R

# These indexes authenticate a saved image's own structure, never live loader
# visibility or a second entity owner. Fixed raw-word prefixes are injective
# even when the dimension contains arbitrary Char words or separators.
def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{"entity-membership:" ++ message}
def word_base() -> Nat: Nat.add(4294967295n,1n)
def maximum_order() -> Nat: Nat.add(Nat.mul(65535n,word_base()),4294967295n)
def id_key(dimension:String,id:U32) -> String: SCon{Chr{id},dimension}
def section_key(dimension:String,key:M.SectionKey) -> String:
  M.SectionKey{x,y,z}=key
  SCon{Chr{x},SCon{Chr{y},SCon{Chr{z},dimension}}}
def chunk_key(dimension:String,x:U32,z:U32) -> String:
  SCon{Chr{U32.and(x,4194303)},SCon{Chr{U32.and(z,4194303)},dimension}}
def section_chunk(dimension:String,key:M.SectionKey) -> String:
  M.SectionKey{x,y,z}=key
  chunk_key(dimension,x,z)
def uuid_key(dimension:String,uuid:E.Uuid) -> String:
  E.Uuid{R.Bits64{a,b},R.Bits64{c,d}}=uuid
  SCon{Chr{a},SCon{Chr{b},SCon{Chr{c},SCon{Chr{d},dimension}}}}
def present_result(~A:Data,result:Map<&2,A> & Bool) -> Bool:
  (index,present)=result
  present
def present(~A:Data,index:Map<&2,A>,key:String) -> Bool:
  present_result(A,Map.has(&2,A,index,key))
def section_result(result:Map<&2,Maybe<&2,M.Section>> & Maybe<&2,M.Section>) -> Maybe<&2,M.Section>:
  (index,value)=result
  value
def find_section(index:Map<&2,Maybe<&2,M.Section>>,dimension:String,key:M.SectionKey) -> Maybe<&2,M.Section>:
  section_result(Map.get(Maybe<&2,M.Section>,None{},index,section_key(dimension,key)))
def chunk_result(result:Map<&2,Maybe<&2,M.Chunk>> & Maybe<&2,M.Chunk>) -> Maybe<&2,M.Chunk>:
  (index,value)=result
  value
def find_chunk(index:Map<&2,Maybe<&2,M.Chunk>>,dimension:String,key:M.SectionKey) -> Maybe<&2,M.Chunk>:
  chunk_result(Map.get(Maybe<&2,M.Chunk>,None{},index,section_chunk(dimension,key)))

def members_index(values:List<&2,M.Member>,+ids:Map<&2,Unit>,+uuids:Map<&2,Unit>) -> Result<&2,&2,String,Map<&2,Unit>>:
  match values:
    case Nil{}: Done{ids}
    case M.Member{+dimension,+id,+key,order,box,+uuid} <> rest:
      +identity=id_key(dimension,id)
      +unique=uuid_key(dimension,uuid)
      do Result<&2,&2,String,Map<&2,Unit>>:
        guard(P.key_valid(key),"packed member key")
        guard(Nat.is_le(order,maximum_order()),"member order exceeds native Nat48")
        guard(Bool.not(present(Unit,ids,identity)),"duplicate member identity")
        guard(Bool.not(present(Unit,uuids,unique)),"duplicate dimension UUID")
        members_index(rest,Map.set(&2,Unit,ids,identity,Unit{}),Map.set(&2,Unit,uuids,unique,Unit{}))
def chunks_index(values:List<&2,M.Chunk>,+index:Map<&2,Maybe<&2,M.Chunk>>) -> Result<&2,&2,String,Map<&2,Maybe<&2,M.Chunk>>>:
  match values:
    case Nil{}: Done{index}
    case +value <> rest:
      M.Chunk{+dimension,+x,+z,loaded,visibility}=value
      +identity=chunk_key(dimension,x,z)
      do Result<&2,&2,String,Map<&2,Maybe<&2,M.Chunk>>>:
        guard(Bool.not(present(Maybe<&2,M.Chunk>,index,identity)),"duplicate aliased chunk identity")
        chunks_index(rest,Map.set(&2,Maybe<&2,M.Chunk>,index,identity,Some{value}))
def expected_ids(values:List<&2,M.Member>,+dimension:String,+key:M.SectionKey,+prior:List<&2,U32>) -> List<&2,U32>:
  match values:
    case Nil{}: prior
    case M.Member{d,+id,k,order,box,uuid} <> rest:
      expected_ids(rest,dimension,key,Bool.pick(List<&2,U32>,String.eq(d,dimension) && P.key_eq(k,key),id <> prior,prior))
def equal_ids(a:List<&2,U32>,b:List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case head <> rest other <> tail: U32.is_eq(head,other) && equal_ids(rest,tail)
    case _ _: False{}
def section_chunk_valid(visibility:M.Visibility,value:Maybe<&2,M.Chunk>) -> Bool:
  match value:
    case None{}: False{}
    case Some{M.Chunk{d,x,z,loaded,other}}: P.visibility_eq(visibility,other)
def sections_index(values:List<&2,M.Section>,+members:List<&2,M.Member>,+chunks:Map<&2,Maybe<&2,M.Chunk>>,
    +index:Map<&2,Maybe<&2,M.Section>>) -> Result<&2,&2,String,Map<&2,Maybe<&2,M.Section>>>:
  match values:
    case Nil{}: Done{index}
    case +value <> rest:
      M.Section{+dimension,+key,+visibility,+ids}=value
      +identity=section_key(dimension,key)
      do Result<&2,&2,String,Map<&2,Maybe<&2,M.Section>>>:
        guard(P.key_valid(key),"packed section key")
        guard(Bool.not(List.is_empty(&2,U32,ids)),"empty entity section")
        guard(Bool.not(present(Maybe<&2,M.Section>,index,identity)),"duplicate section identity")
        guard(equal_ids(ids,expected_ids(members,dimension,key,[])),"section member identity or insertion order")
        guard(section_chunk_valid(visibility,find_chunk(chunks,dimension,key)),"section cached chunk visibility")
        sections_index(rest,members,chunks,Map.set(&2,Maybe<&2,M.Section>,index,identity,Some{value}))
def registrations_index(values:List<&2,M.Registration>,+members:Map<&2,Unit>,+index:Map<&2,Unit>) -> Result<&2,&2,String,Map<&2,Unit>>:
  match values:
    case Nil{}: Done{index}
    case M.Registration{dimension,id} <> rest:
      +identity=id_key(dimension,id)
      do Result<&2,&2,String,Map<&2,Unit>>:
        guard(present(Unit,members,identity),"orphan registry identity")
        guard(Bool.not(present(Unit,index,identity)),"duplicate registry identity")
        registrations_index(rest,members,Map.set(&2,Unit,index,identity,Unit{}))
def registries_linked(found:Maybe<&2,M.Section>,tracked:Bool,ticked:Bool) -> Bool:
  match found:
    case None{}: False{}
    case Some{M.Section{dimension,key,+visibility,ids}}:
      P.bool_eq(tracked,P.accessible(visibility)) && P.bool_eq(ticked,P.ticking(visibility))
def members_linked(values:List<&2,M.Member>,+sections:Map<&2,Maybe<&2,M.Section>>,+tracked:Map<&2,Unit>,+ticked:Map<&2,Unit>) -> Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case M.Member{+dimension,+id,key,order,box,uuid} <> rest:
      +identity=id_key(dimension,id)
      do Result<&2,&2,String,Unit>:
        guard(registries_linked(find_section(sections,dimension,key),present(Unit,tracked,identity),present(Unit,ticked,identity)),
          "member section or tracking/ticking registry")
        members_linked(rest,sections,tracked,ticked)

# A valid image may retain unloaded chunk facts and raw exceptional AABB words.
# Neither those words nor internally agreeing flags authenticate live physics.
def validate(view:M.View) -> Result<&2,&2,String,Unit>:
  M.View{+members,+sections,chunks,tracked,ticked}=view
  do Result<&2,&2,String,Unit>:
    +identities : Map<&2,Unit> <- members_index(members,MTip{},MTip{})
    +physical : Map<&2,Maybe<&2,M.Chunk>> <- chunks_index(chunks,MTip{})
    +registered : Map<&2,Maybe<&2,M.Section>> <- sections_index(sections,members,physical,MTip{})
    +observed : Map<&2,Unit> <- registrations_index(tracked,identities,MTip{})
    +scheduled : Map<&2,Unit> <- registrations_index(ticked,identities,MTip{})
    members_linked(members,registered,observed,scheduled)
