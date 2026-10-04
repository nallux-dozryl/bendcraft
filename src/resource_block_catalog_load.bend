import Base
import ./resource_block_catalog.bend as C
import ./registry.bend as G
import ./blockstate_model.bend as S
import ./block_model.bend as B
import ./block_resources.bend as BR
import ./client_render.bend as R
import ./archive.bend as A
import ./json.bend as J

type Loaded is Type:
  Loaded{assets:R.Assets,catalog:C.Catalog}
type Prepared is Data:
  Prepared{blocks:List<&2,C.Block>,registry_identity:String}
type Source is Data:
  Source{plan:C.Plan,blockstate_bytes:U32}
type Config is Data:
  Config{jar:String,policy:BR.Policy,limits:C.Limits}

def collect_lookup(value:G.Registry & Result<&2,&2,C.Error,C.Block>,out:List<&2,C.Block>,next:G.Registry -> List<&2,C.Block> -> G.Registry & Result<&2,&2,C.Error,List<&2,C.Block>>) -> G.Registry & Result<&2,&2,C.Error,List<&2,C.Block>>:
  (registry,result) = value
  match result:
    case Fail{error}: (registry,Fail{error})
    case Done{block}: next(registry)(block <> out)

def request_admitted(+name:String,mode:C.Mode,seen:Map<&2,Unit>) -> Result<&2,&2,C.Error,Unit>:
  do Result<&2,&2,C.Error,Unit>:
    C.mode_guard(mode,name)
    C.require(Bool.not(S.map_present(Unit,Map.has(&2,Unit,seen,name))),"DuplicateBlock",name,"duplicate catalog request")

def collect_admitted(result:Result<&2,&2,C.Error,Unit>,name:String,mode:C.Mode,out:List<&2,C.Block>,registry:G.Registry,next:G.Registry -> List<&2,C.Block> -> G.Registry & Result<&2,&2,C.Error,List<&2,C.Block>>) -> G.Registry & Result<&2,&2,C.Error,List<&2,C.Block>>:
  match result:
    case Fail{error}: (registry,Fail{error})
    case Done{Unit{}}: collect_lookup(C.looked_up(G.Registry.block(registry,name),mode),out,next)

def collect(fuel:Nat,requests:List<&2,C.Request>,+seen:Map<&2,Unit>,out:List<&2,C.Block>,registry:G.Registry) -> G.Registry & Result<&2,&2,C.Error,List<&2,C.Block>>:
  match fuel requests:
    case _ Nil{}: (registry,Done{List.reverse(&2,C.Block,out)})
    case 0n _: (registry,Fail{C.Error{"RequestWorkBudget","catalog","invalid request traversal bound"}})
    case 1n+p C.Request{+name,+mode} <> rest:
      collect_admitted(request_admitted(name,mode,seen),name,mode,out,registry,
        registry => out => collect(p,rest,Map.set(&2,Unit,seen,name,Unit{}),out,registry))

def collected(value:G.Registry & Result<&2,&2,C.Error,List<&2,C.Block>>,identity:String) -> G.Registry & Result<&2,&2,C.Error,Prepared>:
  (registry,result) = value
  match result:
    case Fail{error}: (registry,Fail{error})
    case Done{blocks}: (registry,Done{Prepared{blocks,identity}})

def identified(value:G.Registry & Result<&2,&2,String,String>,+requests:List<&2,C.Request>) -> G.Registry & Result<&2,&2,C.Error,Prepared>:
  (registry,result) = value
  match result:
    case Fail{message}: (registry,Fail{C.Error{"RegistryIdentity","registry",message}})
    case Done{identity}: collected(collect(List.length(&2,C.Request,requests),requests,MTip{},Nil{},registry),identity)

def prepare_guarded(result:Result<&2,&2,C.Error,Unit>,registry:G.Registry,requests:List<&2,C.Request>) -> G.Registry & Result<&2,&2,C.Error,Prepared>:
  match result:
    case Fail{error}: (registry,Fail{error})
    case Done{Unit{}}: identified(G.Registry.identity(registry),requests)

def prepare(registry:G.Registry,+requests:List<&2,C.Request>,limits:C.Limits) -> G.Registry & Result<&2,&2,C.Error,Prepared>:
  prepare_guarded(C.request_guard(requests,limits),registry,requests)

def blockstate_path(name:String) -> String:
  BR.zip_path(B.identifier_split(name,""),"blockstates",".json")

def parsed(value:Result<&2,&2,BR.Error,J.Value>,+block:C.Block,+source:Source,limits:C.Limits) -> Result<&2,&2,C.Error,Source>:
  C.Block{G.Block{protocol,+name,first,count,default_id,properties},mode} = block
  Source{plan,bytes} = source
  do Result<&2,&2,C.Error,Source>:
    json:J.Value <- C.resource_result(J.Value,value)
    definition:S.Definition <- C.state_result(S.Definition,S.decode(json),name)
    next:C.Plan <- C.prepared_block(block,definition,plan,limits)
    Done{Source{next,bytes}}

def read_source(value:A.Archive & Result<&2,&2,A.Error,List<&2,U32>>,+block:C.Block,source:Source,limits:C.Limits) -> IO(A.Archive & Result<&2,&2,C.Error,Source>):
  (archive,result) = value
  match result:
    case Fail{error}:
      C.Block{G.Block{protocol,name,first,count,default_id,properties},mode} = block
      IO.pure(A.Archive & Result<&2,&2,C.Error,Source>,(archive,Fail{C.Error{"Archive",name,A.error_text(error)}}))
    case Done{bytes}:
      C.Block{G.Block{protocol,+name,first,count,default_id,properties},mode} = block
      C.Limits{max_blocks,max_states,max_text,+resources} = limits
      IO.pure(A.Archive & Result<&2,&2,C.Error,Source>,(archive,parsed(BR.parse(bytes,name,resources),block,source,C.Limits{max_blocks,max_states,max_text,resources})))

def source_entry_guarded(result:Result<&2,&2,C.Error,Unit>,entry:A.Entry,block:C.Block,source:Source,archive:A.Archive,limits:C.Limits) -> IO(A.Archive & Result<&2,&2,C.Error,Source>):
  match result:
    case Fail{error}: IO.pure(A.Archive & Result<&2,&2,C.Error,Source>,(archive,Fail{error}))
    case Done{Unit{}}:
      do IO<A.Archive & Result<&2,&2,C.Error,Source>>:
        read:A.Archive & Result<&2,&2,A.Error,List<&2,U32>> <- A.entry_read(archive,entry)
        read_source(read,block,source,limits)

def source_entry(found:Maybe<&2,A.Entry>,+block:C.Block,+source:Source,archive:A.Archive,+limits:C.Limits) -> IO(A.Archive & Result<&2,&2,C.Error,Source>):
  match found:
    case None{}:
      C.Block{G.Block{protocol,+name,first,count,default_id,properties},mode} = block
      IO.pure(A.Archive & Result<&2,&2,C.Error,Source>,(archive,Fail{C.Error{"MissingBlockstate",name,blockstate_path(name)}}))
    case Some{+entry}:
      C.Block{G.Block{protocol,+name,first,count,default_id,properties},mode} = block
      Source{plan,+bytes} = source
      C.Limits{max_blocks,max_states,+max_text,resources} = limits
      +size = BR.entry_size(entry)
      source_entry_guarded(C.require(U32.is_le(bytes,max_text) && U32.is_le(size,U32.sub(max_text,U32.min(bytes,max_text))),"BlockstateByteBudget",name,"aggregate blockstate text exceeds budget"),entry,block,Source{plan,U32.add(bytes,size)},archive,limits)

def invisible_source(block:C.Block,source:Source,limits:C.Limits) -> Result<&2,&2,C.Error,Source>:
  Source{plan,bytes} = source
  do Result<&2,&2,C.Error,Source>:
    next:C.Plan <- C.invisible_block(block,plan,limits)
    Done{Source{next,bytes}}

def source_advanced(value:A.Archive & Result<&2,&2,C.Error,Source>,rest:List<&2,C.Block>,next:List<&2,C.Block> -> A.Archive -> Result<&2,&2,C.Error,Source> -> IO(A.Archive & Result<&2,&2,C.Error,Source>)) -> IO(A.Archive & Result<&2,&2,C.Error,Source>):
  (archive,result) = value
  next(rest)(archive)(result)

def source_one(+block:C.Block,archive:A.Archive,directory:A.Directory,source:Source,+limits:C.Limits) -> IO(A.Archive & Result<&2,&2,C.Error,Source>):
  C.Block{G.Block{protocol,+name,first,count,default_id,properties},mode} = block
  match mode:
    case C.Invisible{}: IO.pure(A.Archive & Result<&2,&2,C.Error,Source>,(archive,invisible_source(block,source,limits)))
    case C.Unsupported{renderer}: IO.pure(A.Archive & Result<&2,&2,C.Error,Source>,(archive,Fail{C.Error{"UnsupportedRenderer",name,renderer}}))
    case C.Model{}: source_entry(A.lookup(directory,blockstate_path(name)),block,source,archive,limits)

def sources_ready(values:List<&2,C.Block>,archive:A.Archive,directory:A.Directory,source:Source,limits:C.Limits,next:List<&2,C.Block> -> A.Archive -> Result<&2,&2,C.Error,Source> -> IO(A.Archive & Result<&2,&2,C.Error,Source>)) -> IO(A.Archive & Result<&2,&2,C.Error,Source>):
  match values:
    case Nil{}: IO.pure(A.Archive & Result<&2,&2,C.Error,Source>,(archive,Done{source}))
    case +block <> rest:
      do IO<A.Archive & Result<&2,&2,C.Error,Source>>:
        read:A.Archive & Result<&2,&2,C.Error,Source> <- source_one(block,archive,directory,source,limits)
        source_advanced(read,rest,next)

def sources_finished(values:List<&2,C.Block>,archive:A.Archive,source:Source) -> IO(A.Archive & Result<&2,&2,C.Error,Source>):
  match values:
    case Nil{}: IO.pure(A.Archive & Result<&2,&2,C.Error,Source>,(archive,Done{source}))
    case _: IO.pure(A.Archive & Result<&2,&2,C.Error,Source>,(archive,Fail{C.Error{"BlockstateWorkBudget","catalog","invalid blockstate traversal bound"}}))

def sources(fuel:Nat,values:List<&2,C.Block>,archive:A.Archive,+directory:A.Directory,result:Result<&2,&2,C.Error,Source>,+limits:C.Limits) -> IO(A.Archive & Result<&2,&2,C.Error,Source>):
  match fuel result:
    case _ Fail{error}: IO.pure(A.Archive & Result<&2,&2,C.Error,Source>,(archive,Fail{error}))
    case 0n Done{source}: sources_finished(values,archive,source)
    case 1n+p Done{source}: sources_ready(values,archive,directory,source,limits,rest => archive => result => sources(p,rest,archive,directory,result,limits))

def resources_loaded(result:Result<&2,&1,BR.Error,BR.Loaded>,identity:String,entries:Map<&2,C.Entry>) -> Result<&2,&1,C.Error,Loaded>:
  match result:
    case Fail{BR.Error{code,name,detail}}: Fail{C.Error{"Resource:" ++ code,name,detail}}
    case Done{BR.Loaded{assets,loaded_catalog}}: Done{Loaded{assets,C.installed(identity,entries,loaded_catalog)}}

def source_after_close(result:Result<&2,&2,C.Error,Source>,config:Config) -> IO(Result<&2,&1,C.Error,Loaded>):
  match result:
    case Fail{error}: IO.pure(Result<&2,&1,C.Error,Loaded>,Fail{error})
    case Done{Source{C.Plan{identity,entries,models,total},bytes}}:
      Config{jar,policy,C.Limits{blocks,states,text,resources}} = config
      do IO<Result<&2,&1,C.Error,Loaded>>:
        loaded:Result<&2,&1,BR.Error,BR.Loaded> <- BR.load(jar,BR.sorted(Map.keys(&2,Unit,models)),policy,resources)
        return resources_loaded(loaded,identity,entries)

def source_closed(value:A.Archive & Result<&2,&2,C.Error,Source>,config:Config) -> IO(Result<&2,&1,C.Error,Loaded>):
  (archive,result) = value
  do IO<Result<&2,&1,C.Error,Loaded>>:
    A.Archive.close(archive)
    source_after_close(result,config)

def archive_directoried(value:A.Archive & A.Directory,+blocks:List<&2,C.Block>,identity:String,+config:Config) -> IO(Result<&2,&1,C.Error,Loaded>):
  (archive,directory) = value
  Config{jar,policy,limits} = config
  do IO<Result<&2,&1,C.Error,Loaded>>:
    value:A.Archive & Result<&2,&2,C.Error,Source> <- sources(List.length(&2,C.Block,blocks),blocks,archive,directory,Done{Source{C.Plan{identity,MTip{},MTip{},0},0}},limits)
    source_closed(value,config)

def archive_opened(result:Result<&2,&1,A.Error,A.Archive>,prepared:Prepared,+config:Config) -> IO(Result<&2,&1,C.Error,Loaded>):
  match result:
    case Fail{error}:
      Config{jar,policy,limits} = config
      IO.pure(Result<&2,&1,C.Error,Loaded>,Fail{C.Error{"ArchiveOpen",jar,A.error_text(error)}})
    case Done{archive}:
      Prepared{blocks,identity} = prepared
      archive_directoried(A.Archive.directory(archive),blocks,identity,config)

def prepared_load(value:G.Registry & Result<&2,&2,C.Error,Prepared>,+config:Config) -> IO(G.Registry & Result<&2,&1,C.Error,Loaded>):
  (registry,result) = value
  match result:
    case Fail{error}: IO.pure(G.Registry & Result<&2,&1,C.Error,Loaded>,(registry,Fail{error}))
    case Done{prepared}:
      Config{jar,policy,limits} = config
      do IO<G.Registry & Result<&2,&1,C.Error,Loaded>>:
        archive:Result<&2,&1,A.Error,A.Archive> <- A.load(jar,A.UTF8Fallback{},A.default_limits())
        loaded:Result<&2,&1,C.Error,Loaded> <- archive_opened(archive,prepared,config)
        return (registry,loaded)

# All models from weighted choices and every multipart dependency are loaded.
# Archive owners close before texture/model loading and before every return.
def load(jar:String,registry:G.Registry,requests:List<&2,C.Request>,policy:BR.Policy,+limits:C.Limits) -> IO(G.Registry & Result<&2,&1,C.Error,Loaded>):
  prepared_load(prepare(registry,requests,limits),Config{jar,policy,limits})
