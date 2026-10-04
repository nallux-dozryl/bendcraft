import Base
import ./section_map.bend as M
import ./section.bend as S

# Updates traverse the actual owned trie. Refusals never use pop/set, which
# would normalize an empty bucket or move an existing collision entry.
type Error is Data:
  Existing{}
  Missing{}
  Malformed{}
  SectionRejected{error:S.Section.Error}

def path(depth:Nat,+bits:U32) -> List<&2,Bool>:
  match depth:
    case 0n: []
    case 1n+rest: U32.is_ne(U32.and(bits,1),0) <> path(rest,U32.shr(bits))

# This query observes keys in the real affine bucket and drops their payloads.
# It is the membership specification used by the complete-owner contracts.
def keys(entries:List<&1,M.Entry>) -> List<&2,String>:
  match entries:
    case Nil{}: []
    case M.Entry{key,section} <> tail: key <> keys(tail)

def member(names:List<&2,String>,+key:String) -> Bool:
  match names:
    case Nil{}: False{}
    case name <> tail: String.eq(name,key) || member(tail,key)

def present(route:List<&2,Bool>,sections:M.Sections,key:String) -> Bool:
  match route sections:
    case Nil{} M.Bucket{entries}: member(keys(entries),key)
    case False{} <> rest M.Branch{lo,hi}: present(rest,lo,key)
    case True{} <> rest M.Branch{lo,hi}: present(rest,hi,key)
    case _ _: False{}

def presence_head(head:M.Entry,same:Bool,result:List<&1,M.Entry> & Bool) -> List<&1,M.Entry> & Bool:
  (tail,found) = result
  (head <> tail,same || found)

def contains(entries:List<&1,M.Entry>,+key:String) -> List<&1,M.Entry> & Bool:
  match entries:
    case Nil{}: ([],False{})
    case M.Entry{+candidate,section} <> tail:
      presence_head(M.Entry{candidate,section},String.eq(candidate,key),contains(tail,key))

def created(entries:List<&1,M.Entry>,key:String,fill:U32,exists:Bool) -> M.Sections & Result<&2,&2,Error,Unit>:
  match exists:
    case True{}: (M.Bucket{entries},Fail{Existing{}})
    case False{}: (M.Bucket{M.Entry{key,S.Section.new(fill)} <> entries},Done{Unit{}})

def create_bucket(key:String,fill:U32,result:List<&1,M.Entry> & Bool) -> M.Sections & Result<&2,&2,Error,Unit>:
  (entries,exists) = result
  created(entries,key,fill,exists)

def left(hi:M.Sections,result:M.Sections & Result<&2,&2,Error,Unit>) -> M.Sections & Result<&2,&2,Error,Unit>:
  (lo,status) = result
  (M.Branch{lo,hi},status)

def right(lo:M.Sections,result:M.Sections & Result<&2,&2,Error,Unit>) -> M.Sections & Result<&2,&2,Error,Unit>:
  (hi,status) = result
  (M.Branch{lo,hi},status)

def create_at(route:List<&2,Bool>,sections:M.Sections,+key:String,+fill:U32) -> M.Sections & Result<&2,&2,Error,Unit>:
  match route sections:
    case Nil{} M.EmptySections{}:
      (M.Bucket{[M.Entry{key,S.Section.new(fill)}]},Done{Unit{}})
    case Nil{} M.Bucket{entries}: create_bucket(key,fill,contains(entries,key))
    case False{} <> rest M.Branch{lo,hi}: left(hi,create_at(rest,lo,key,fill))
    case True{} <> rest M.Branch{lo,hi}: right(lo,create_at(rest,hi,key,fill))
    case False{} <> rest M.EmptySections{}: left(M.EmptySections{},create_at(rest,M.EmptySections{},key,fill))
    case True{} <> rest M.EmptySections{}: right(M.EmptySections{},create_at(rest,M.EmptySections{},key,fill))
    case _ other: (other,Fail{Malformed{}})

def create(sections:M.Sections,+key:String,fill:U32) -> M.Sections & Result<&2,&2,Error,Unit>:
  create_at(path(32n,M.hash(key)),sections,key,fill)

def section_status(status:Result<&2,&2,S.Section.Error,Unit>) -> Result<&2,&2,Error,Unit>:
  match status:
    case Done{unit}: Done{unit}
    case Fail{error}: Fail{SectionRejected{error}}

def changed_head(key:String,tail:List<&1,M.Entry>,result:S.Section & Result<&2,&2,S.Section.Error,Unit>) -> List<&1,M.Entry> & Result<&2,&2,Error,Unit>:
  (section,status) = result
  (M.Entry{key,section} <> tail,section_status(status))

def unchanged_head(head:M.Entry,result:List<&1,M.Entry> & Result<&2,&2,Error,Unit>) -> List<&1,M.Entry> & Result<&2,&2,Error,Unit>:
  (tail,status) = result
  (head <> tail,status)

def write_head(candidate:String,section:S.Section,tail:List<&1,M.Entry>,key:String,x:U32,y:U32,z:U32,state:U32,
               same:Bool,continue:List<&1,M.Entry> -> List<&1,M.Entry> & Result<&2,&2,Error,Unit>) -> List<&1,M.Entry> & Result<&2,&2,Error,Unit>:
  match same:
    case True{}: changed_head(candidate,tail,S.Section.set(section,x,y,z,state))
    case False{}: unchanged_head(M.Entry{candidate,section},continue(tail))

def write_bucket(fuel:Nat,entries:List<&1,M.Entry>,+key:String,+x:U32,+y:U32,+z:U32,+state:U32) -> List<&1,M.Entry> & Result<&2,&2,Error,Unit>:
  match fuel entries:
    case 0n other: (other,Fail{Missing{}})
    case _ Nil{}: ([],Fail{Missing{}})
    case 1n+rest M.Entry{+candidate,section} <> tail:
      write_head(candidate,section,tail,key,x,y,z,state,String.eq(candidate,key),
        tail => write_bucket(rest,tail,key,x,y,z,state))

def counted_head(head:M.Entry,result:List<&1,M.Entry> & Nat) -> List<&1,M.Entry> & Nat:
  (tail,count) = result
  (head <> tail,1n+count)

def count(entries:List<&1,M.Entry>) -> List<&1,M.Entry> & Nat:
  match entries:
    case Nil{}: ([],0n)
    case head <> tail: counted_head(head,count(tail))

def leaf(result:List<&1,M.Entry> & Result<&2,&2,Error,Unit>) -> M.Sections & Result<&2,&2,Error,Unit>:
  (entries,status) = result
  (M.Bucket{entries},status)

def write_counted(key:String,x:U32,y:U32,z:U32,state:U32,result:List<&1,M.Entry> & Nat) -> M.Sections & Result<&2,&2,Error,Unit>:
  (entries,fuel) = result
  leaf(write_bucket(fuel,entries,key,x,y,z,state))

# Membership is checked while returning the complete bucket owner. Invalid
# local coordinates then refuse before any Section array can be written.
def write_checked(entries:List<&1,M.Entry>,key:String,x:U32,y:U32,z:U32,state:U32,
                  index:Result<&2,&2,S.Section.Error,U32>) -> M.Sections & Result<&2,&2,Error,Unit>:
  match index:
    case Fail{error}: (M.Bucket{entries},Fail{SectionRejected{error}})
    case Done{value}: write_counted(key,x,y,z,state,count(entries))

def write_present(entries:List<&1,M.Entry>,key:String,+x:U32,+y:U32,+z:U32,state:U32,exists:Bool) -> M.Sections & Result<&2,&2,Error,Unit>:
  match exists:
    case False{}: (M.Bucket{entries},Fail{Missing{}})
    case True{}: write_checked(entries,key,x,y,z,state,S.Section.local_index(x,y,z))

def write_leaf(key:String,x:U32,y:U32,z:U32,state:U32,result:List<&1,M.Entry> & Bool) -> M.Sections & Result<&2,&2,Error,Unit>:
  (entries,exists) = result
  write_present(entries,key,x,y,z,state,exists)

def write_at(route:List<&2,Bool>,sections:M.Sections,+key:String,+x:U32,+y:U32,+z:U32,+state:U32) -> M.Sections & Result<&2,&2,Error,Unit>:
  match route sections:
    case Nil{} M.Bucket{entries}: write_leaf(key,x,y,z,state,contains(entries,key))
    case False{} <> rest M.Branch{lo,hi}: left(hi,write_at(rest,lo,key,x,y,z,state))
    case True{} <> rest M.Branch{lo,hi}: right(lo,write_at(rest,hi,key,x,y,z,state))
    case _ other: (other,Fail{Missing{}})

def write(sections:M.Sections,+key:String,x:U32,y:U32,z:U32,state:U32) -> M.Sections & Result<&2,&2,Error,Unit>:
  write_at(path(32n,M.hash(key)),sections,key,x,y,z,state)
