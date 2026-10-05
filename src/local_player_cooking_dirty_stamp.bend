import Base
import ./core.bend as C
import ./cooking_world_bindings.bend as B
import ./cooking_world_store.bend as S
import ./cooking_effect_publication_journal.bend as J
import ./cooking_effect_publication.bend as Publication

# This cache contains metadata only. Every physical entity and its arrays are
# returned in the same Entry list; no World or entity snapshot is cloned.
type Cache is Data:
  Cache{sources:List<&2,J.Source>}

def counted(position:C.Position,binding:B.Binding,result:Map<&2,Nat> & Nat) -> J.Source:
  (incarnations,incarnation) = result
  J.Source{position,binding,incarnation}

def captured_cons(entry:S.Entry,source:J.Source,
    result:List<&1,S.Entry> & List<&2,J.Source>) -> List<&1,S.Entry> & List<&2,J.Source>:
  (entries,sources) = result
  (entry <> entries,source <> sources)

# The missing-key zero is the existing Sidecar incarnation policy. The source
# keeps the full Entry binding, including its state before a LIT partner write.
def captured(entries:List<&1,S.Entry>,+incarnations:Map<&2,Nat>) ->
    List<&1,S.Entry> & List<&2,J.Source>:
  match entries:
    case Nil{}: ([],[])
    case S.Entry{+position,+binding,entity} <> rest:
      captured_cons(S.Entry{position,binding,entity},
        counted(position,binding,Map.get(Nat,0n,incarnations,B.key(position))),
        captured(rest,incarnations))

def validated_source(result:Result<&2,&2,String,Unit>,
    next:Unit -> Result<&2,&2,String,Unit>) -> Result<&2,&2,String,Unit>:
  match result:
    case Fail{message}: Fail{message}
    case Done{unit}: next(unit)

def unique_source(catalog:B.Catalog,source:J.Source,key:String,result:Set() & Bool,
    next:Set() -> Result<&2,&2,String,Unit>) -> Result<&2,&2,String,Unit>:
  (seen,duplicate) = result
  match duplicate:
    case True{}: Fail{"cooking-dirty-stamp:duplicate-source-position"}
    case False{}:
      validated_source(Publication.validate_source(catalog,source),
        unit => next(Set.add(seen,key)))

def canonical(sources:List<&2,J.Source>,+catalog:B.Catalog,seen:Set()) -> Result<&2,&2,String,Unit>:
  match sources:
    case Nil{}: Done{Unit{}}
    case +source <> rest:
      J.Source{position,binding,incarnation} = source
      +key = B.key(position)
      unique_source(catalog,source,key,Set.has(seen,key),
        seen => canonical(rest,catalog,seen))

def cache_validated(cache:Cache,result:Result<&2,&2,String,Unit>) -> Result<&2,&2,String,Cache>:
  match result:
    case Fail{message}: Fail{message}
    case Done{unit}: Done{cache}

def prepare(catalog:B.Catalog,result:List<&1,S.Entry> & List<&2,J.Source>) ->
    List<&1,S.Entry> & Result<&2,&2,String,Cache>:
  (entries,+sources) = result
  (entries,cache_validated(Cache{sources},canonical(sources,catalog,Set.new())))

# Caller supplies the actual map after observing unacknowledged OwnerReset
# markers from start_tick. The cache must never derive an incarnation from a
# post-commit Entry or from an external supplier.
def capture(catalog:B.Catalog,incarnations:Map<&2,Nat>,entries:List<&1,S.Entry>) ->
    List<&1,S.Entry> & Result<&2,&2,String,Cache>:
  prepare(catalog,captured(entries,incarnations))

def dirty_checked(source:J.Source,position:C.Position,allowed:Bool) -> S.Effect:
  match allowed:
    case False{}: S.Dirty{position}
    case True{}: S.OwnedDirty{source}

def dirty_effect(+position:C.Position,+source:J.Source) -> S.Effect:
  J.Source{captured,binding,incarnation} = source
  dirty_checked(source,position,B.equal_position(captured,position))

# Only the new effects of one actual commit_entry reach this function. The
# caller's ordered cache has already been aligned with that Entry and Plan.
# Existing OwnedDirty and every non-Dirty effect are retained exactly.
def effect(+source:J.Source,value:S.Effect) -> S.Effect:
  match value:
    case S.Dirty{position}: dirty_effect(position,source)
    case other: other

def effects(values:List<&2,S.Effect>,+source:J.Source) -> List<&2,S.Effect>:
  match values:
    case Nil{}: []
    case head <> rest: effect(source,head) <> effects(rest,source)

def committed(source:J.Source,result:S.Entry & List<&2,S.Effect>) -> S.Entry & List<&2,S.Effect>:
  (entry,more) = result
  (entry,effects(more,source))
