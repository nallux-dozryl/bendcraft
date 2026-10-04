import Base
import ./archive.bend as A
import ./unicode.bend as Unicode
import ./crafting_recipe.bend as R
import ./crafting_recipe_decoder.bend as D
import ./json.bend as J
import ./player_item_definitions.bend as Definitions
import ./player_item_catalog.bend as ItemCatalog
import ./crafting_recipe_component_registry.bend as Registry
import ./item_component.bend as Components

# Read original recipe entries through the existing owned Bend ZIP reader.
# Source-pack order and resolved tag/default metadata are explicit caller
# authority; neither the jar central-directory order nor fixture recipes may
# silently become recipe-manager precedence.
type Context is Data:
  Context{items:J.Value,tags:J.Value}

type Limits is Data:
  Limits{archive:A.Limits,max_recipes:U32,max_entry:U32,max_total:U32,max_json_depth:U32}

type Work is Data:
  Work{recipes:List<&2,J.Value>,bytes:U32}

type Service is Data:
  Service{definitions:Definitions.Catalog,recipes:R.Catalog}

def defaults() -> Limits:
  Limits{A.default_limits(),4096,65536,8388608,32}

def resource_path(fields:List<&2,String>) -> String:
  match fields:
    case namespace <> name <> Nil{}: "data/" ++ namespace ++ "/recipe/" ++ name ++ ".json"
    case _: ""

def recipe_path(id:String) -> String:
  resource_path(String.split(id,':'))

def context_catalog(context:Context,recipes:List<&2,J.Value>) -> Result<&2,&2,String,R.Catalog>:
  Context{items,tags} = context
  D.catalog(J.JObject{[J.JMember{"items",items},J.JMember{"tags",tags},J.JMember{"recipes",J.JArray{recipes}}]})

# Complete initialized maps are structural reference inputs. Only the closed
# suspicious-stew profile below receives component semantic admission.
def default_members(values:List<&2,J.Member>,+seen:List<&2,String>) -> Bool:
  match values:
    case Nil{}: True{}
    case J.JMember{+name,value} <> rest:
      Registry.persistent(name) && Bool.not(R.contains(seen,name)) && default_members(rest,name <> seen)

def required_defaults(+value:J.Value) -> Bool:
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:attack_animation")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:attribute_modifiers")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:break_sound")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:enchantments")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:interact_animation")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:item_model")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:item_name")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:lore")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:max_stack_size")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:rarity")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:repair_cost")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:tooltip_display")) &&
  Maybe.is_some(&2,J.Value,J.member(value,"minecraft:use_effects"))

def stew_defaults(result:Result<&2,&2,String,Components.Defaults>) -> Result<&2,&2,String,Unit>:
  match result:
    case Fail{message}: Fail{"invalid initialized suspicious stew defaults: " ++ message}
    case Done{defaults}: Done{Unit{}}

def default_profile(id:String,value:J.Value) -> Result<&2,&2,String,Unit>:
  match id:
    case "minecraft:suspicious_stew": stew_defaults(Components.initialize(value))
    case _: Done{Unit{}}

def default_map(+value:J.Value,+id:String,+limit:U32) -> Result<&2,&2,String,Unit>:
  match value:
    case J.JObject{members}:
      do Result<&2,&2,String,Unit>:
        D.guard(default_members(members,[]) && required_defaults(value),"incomplete or invalid initialized component map")
        +maximum:U32 <- D.number_field(value,"minecraft:max_stack_size")
        D.guard(U32.is_eq(maximum,limit) || (String.eq(id,"minecraft:air") && U32.is_eq(maximum,64) && U32.is_eq(limit,1)),"initialized component stack limit disagrees with item definition")
        default_profile(id,value)
    case _: Fail{"initialized components must be a complete map"}

def default_rows(values:List<&2,J.Value>) -> Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case +value <> rest:
      do Result<&2,&2,String,Unit>:
        id:String <- D.text_field(value,"id")
        limit:U32 <- D.number_field(value,"limit")
        components:J.Value <- D.field(value,"components")
        default_map(components,id,limit)
        default_rows(rest)

def context_parts(+value:J.Value) -> Result<&2,&2,String,Context>:
  do Result<&2,&2,String,Context>:
    +items:J.Value <- D.field(value,"items")
    +tags:J.Value <- D.field(value,"tags")
    rows:List<&2,J.Value> <- D.array(items)
    default_rows(rows)
    return Context{items,tags}

def context(+value:J.Value) -> Result<&2,&2,String,Context>:
  do Result<&2,&2,String,Context>:
    +parsed:Context <- context_parts(value)
    admitted:R.Catalog <- context_catalog(parsed,[])
    return parsed

def definition_matches(value:Maybe<&2,Definitions.Definition>,limit:U32) -> Bool:
  match value:
    case None{}: False{}
    case Some{Definitions.Definition{number,id,description,maximum,set,identity,enabled}}:
      enabled && U32.is_eq(maximum,limit)

def items_match(values:List<&2,R.ItemDefinition>,+definitions:Definitions.Catalog) -> Bool:
  match values:
    case Nil{}: True{}
    case R.ItemDefinition{id,limit,remainder} <> rest:
      definition_matches(Definitions.definition(definitions,id),limit) && items_match(rest,definitions)

def initialized(result:Result<&2,&2,String,R.Catalog>,context:Context,+definitions:Definitions.Catalog) -> Result<&2,&2,String,Context>:
  match result:
    case Fail{message}: Fail{message}
    case Done{R.Catalog{recipes,tags,+items}}:
      do Result<&2,&2,String,Context>:
        D.guard(Nat.is_eq(List.length(&2,R.ItemDefinition,items),U32.to_nat(Definitions.count(definitions))) && items_match(items,definitions),"crafting item metadata disagrees with initialized player definitions")
        return context

def context_with(value:J.Value,definitions:Definitions.Catalog) -> Result<&2,&2,String,Context>:
  do Result<&2,&2,String,Context>:
    +parsed:Context <- context_parts(value)
    initialized(context_catalog(parsed,[]),parsed,definitions)

def request_ids(values:List<&2,String>,+seen:List<&2,String>) -> Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case +id <> rest:
      do Result<&2,&2,String,Unit>:
        D.guard(D.identifier(id),"invalid recipe resource identifier")
        D.guard(Bool.not(R.contains(seen,id)),"duplicate recipe resource request")
        request_ids(rest,id <> seen)

def request_guard(+values:List<&2,String>,limits:Limits) -> Result<&2,&2,String,Unit>:
  Limits{archive,max_recipes,+max_entry,+max_total,+depth} = limits
  do Result<&2,&2,String,Unit>:
    D.guard(Nat.is_le(List.length(&2,String,values),U32.to_nat(max_recipes)),"recipe resource count exceeds budget")
    D.guard(U32.is_gt(max_entry,0) && U32.is_le(max_entry,8388608) && U32.is_le(max_total,67108864) && U32.is_gt(depth,0) && U32.is_le(depth,256),"invalid crafting resource limits")
    request_ids(values,[])

def source_bytes(result:Result<&2,&2,A.Error,List<&2,U32>>,id:String,+work:Work,limits:Limits) -> Result<&2,&2,String,Work>:
  match result:
    case Fail{error}: Fail{A.error_text(error)}
    case Done{+bytes}:
      Work{recipes,+total} = work
      Limits{archive,max_recipes,+max_entry,+max_total,depth} = limits
      do Result<&2,&2,String,Work>:
        D.guard(Nat.is_le(List.length(&2,U32,bytes),U32.to_nat(max_entry)),"recipe entry exceeds byte budget")
        +length:U32 = U32.from_nat(List.length(&2,U32,bytes))
        D.guard(U32.is_le(total,max_total) && U32.is_le(length,U32.sub(max_total,U32.min(total,max_total))),"recipe resources exceed aggregate byte budget")
        text:String <- Unicode.decode(U32.to_nat(max_entry),bytes)
        source:J.Value <- J.parse_bounded(text,U32.to_nat(max_entry),depth)
        return Work{J.JObject{[J.JMember{"id",J.JString{id}},J.JMember{"source",source}]} <> recipes,U32.add(total,length)}

def source_read(read:A.Archive & Result<&2,&2,A.Error,List<&2,U32>>,id:String,work:Work,limits:Limits) -> A.Archive & Result<&2,&2,String,Work>:
  (archive,result) = read
  (archive,source_bytes(result,id,work,limits))

def entry_size(entry:A.Entry) -> U32:
  A.Entry{ordinal,name,raw,needed,flags,method,crc,compressed,size,local,ceiling} = entry
  size

def source_allowed(allowed:Bool,archive:A.Archive,entry:A.Entry,id:String,work:Work,limits:Limits) -> IO(A.Archive & Result<&2,&2,String,Work>):
  match allowed:
    case False{}: IO.pure(A.Archive & Result<&2,&2,String,Work>,(archive,Fail{"recipe entry exceeds byte budget"}))
    case True{}:
      do IO<A.Archive & Result<&2,&2,String,Work>>:
        read:A.Archive & Result<&2,&2,A.Error,List<&2,U32>> <- A.entry_read(archive,entry)
        return source_read(read,id,work,limits)

def source_found(found:Maybe<&2,A.Entry>,archive:A.Archive,id:String,work:Work,+limits:Limits) -> IO(A.Archive & Result<&2,&2,String,Work>):
  match found:
    case None{}: IO.pure(A.Archive & Result<&2,&2,String,Work>,(archive,Fail{"missing recipe resource: " ++ id}))
    case Some{+entry}:
      Limits{archive_limits,max_recipes,max_entry,total,depth} = limits
      source_allowed(U32.is_le(entry_size(entry),max_entry),archive,entry,id,work,limits)

def source_continued(read:A.Archive & Result<&2,&2,String,Work>,body:A.Archive -> Result<&2,&2,String,Work> -> IO(A.Archive & Result<&2,&2,String,Work>)) -> IO(A.Archive & Result<&2,&2,String,Work>):
  (archive,result) = read
  body(archive)(result)

def sources(ids:List<&2,String>,archive:A.Archive,+directory:A.Directory,result:Result<&2,&2,String,Work>,+limits:Limits) -> IO(A.Archive & Result<&2,&2,String,Work>):
  match ids result:
    case _ Fail{message}: IO.pure(A.Archive & Result<&2,&2,String,Work>,(archive,Fail{message}))
    case Nil{} _: IO.pure(A.Archive & Result<&2,&2,String,Work>,(archive,result))
    case +id <> rest Done{work}:
      IO.bind(A.Archive & Result<&2,&2,String,Work>,A.Archive & Result<&2,&2,String,Work>,source_found(A.lookup(directory,recipe_path(id)),archive,id,work,limits),read => source_continued(read,next_archive => next_result => sources(rest,next_archive,directory,next_result,limits)))

def completed(result:Result<&2,&2,String,Work>,context:Context) -> Result<&2,&2,String,R.Catalog>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Work{recipes,bytes}}: context_catalog(context,List.reverse(&2,J.Value,recipes))

def closed(read:A.Archive & Result<&2,&2,String,Work>,context:Context) -> IO(Result<&2,&2,String,R.Catalog>):
  (archive,result) = read
  do IO<Result<&2,&2,String,R.Catalog>>:
    A.Archive.close(archive)
    return completed(result,context)

def directory_opened(read:A.Archive & A.Directory,ids:List<&2,String>,context:Context,limits:Limits) -> IO(Result<&2,&2,String,R.Catalog>):
  (archive,directory) = read
  do IO<Result<&2,&2,String,R.Catalog>>:
    result:A.Archive & Result<&2,&2,String,Work> <- sources(ids,archive,directory,Done{Work{[],0}},limits)
    closed(result,context)

def opened(result:Result<&2,&1,A.Error,A.Archive>,ids:List<&2,String>,context:Context,limits:Limits) -> IO(Result<&2,&2,String,R.Catalog>):
  match result:
    case Fail{error}: IO.pure(Result<&2,&2,String,R.Catalog>,Fail{A.error_text(error)})
    case Done{archive}: directory_opened(A.Archive.directory(archive),ids,context,limits)

def guarded(result:Result<&2,&2,String,Unit>,jar:String,ids:List<&2,String>,context:Context,+limits:Limits) -> IO(Result<&2,&2,String,R.Catalog>):
  match result:
    case Fail{message}: IO.pure(Result<&2,&2,String,R.Catalog>,Fail{message})
    case Done{unit}:
      Limits{archive,count,entry,total,depth} = limits
      do IO<Result<&2,&2,String,R.Catalog>>:
        result:Result<&2,&1,A.Error,A.Archive> <- A.load(jar,A.UTF8Fallback{},archive)
        opened(result,ids,context,limits)

def load(jar:String,+ordered_ids:List<&2,String>,context:Context,+limits:Limits) -> IO(Result<&2,&2,String,R.Catalog>):
  guarded(request_guard(ordered_ids,limits),jar,ordered_ids,context,limits)

# An explicit local extraction/interchange is a bootstrap input, never an
# automatic fallback after failed jar/resource loading. All matching/decoding
# remains Bend; default tables and nested tags must have the recorded source.
def artifact_parsed(result:Result<&2,&2,String,J.Value>) -> Result<&2,&2,String,R.Catalog>:
  match result:
    case Fail{message}: Fail{message}
    case Done{+value}:
      do Result<&2,&2,String,R.Catalog>:
        admitted:Context <- context(value)
        D.catalog(value)

def artifact_decoded(result:Result<&1,&1,U32 & String,List<&2,U32>>,+max_bytes:U32,depth:U32) -> Result<&2,&2,String,R.Catalog>:
  match result:
    case Fail{Tuple{code,message}}: Fail{"crafting catalog read: " ++ message}
    case Done{+bytes}:
      do Result<&2,&2,String,R.Catalog>:
        D.guard(Nat.is_le(List.length(&2,U32,bytes),U32.to_nat(max_bytes)),"crafting catalog exceeds byte budget")
        text:String <- Unicode.decode(U32.to_nat(max_bytes),bytes)
        artifact_parsed(J.parse_bounded(text,U32.to_nat(max_bytes),depth))

def artifact_read(read:File & Result<&1,&1,U32 & String,List<&2,U32>>,max_bytes:U32,depth:U32) -> IO(Result<&2,&2,String,R.Catalog>):
  (file,result) = read
  do IO<Result<&2,&2,String,R.Catalog>>:
    File.close(file)
    return artifact_decoded(result,max_bytes,depth)

def artifact_opened(result:Result<&1,&1,U32 & String,File>,+max_bytes:U32,depth:U32) -> IO(Result<&2,&2,String,R.Catalog>):
  match result:
    case Fail{Tuple{code,message}}: IO.pure(Result<&2,&2,String,R.Catalog>,Fail{"crafting catalog open: " ++ message})
    case Done{file}:
      do IO<Result<&2,&2,String,R.Catalog>>:
        read:File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,U32.add(max_bytes,1))
        artifact_read(read,max_bytes,depth)

def artifact_guarded(allowed:Bool,path:String,+max_bytes:U32,depth:U32) -> IO(Result<&2,&2,String,R.Catalog>):
  match allowed:
    case False{}: IO.pure(Result<&2,&2,String,R.Catalog>,Fail{"invalid crafting catalog limits"})
    case True{}:
      do IO<Result<&2,&2,String,R.Catalog>>:
        result:Result<&1,&1,U32 & String,File> <- File.open(path,"r")
        artifact_opened(result,max_bytes,depth)

def load_artifact(path:String,+max_bytes:U32,+depth:U32) -> IO(Result<&2,&2,String,R.Catalog>):
  artifact_guarded(U32.is_gt(max_bytes,0) && U32.is_le(max_bytes,67108864) && U32.is_gt(depth,0) && U32.is_le(depth,256),path,max_bytes,depth)

def service_recipes(result:Result<&2,&2,String,R.Catalog>,definitions:Definitions.Catalog) -> Result<&2,&2,String,Service>:
  match result:
    case Fail{message}: Fail{message}
    case Done{recipes}: Done{Service{definitions,recipes}}

def service_context(result:Result<&2,&2,String,Context>,jar:String,ids:List<&2,String>,+definitions:Definitions.Catalog,limits:Limits) -> IO(Result<&2,&2,String,Service>):
  match result:
    case Fail{message}: IO.pure(Result<&2,&2,String,Service>,Fail{message})
    case Done{context}:
      do IO<Result<&2,&2,String,Service>>:
        recipes:Result<&2,&2,String,R.Catalog> <- load(jar,ids,context,limits)
        return service_recipes(recipes,definitions)

def service_definitions(result:Result<&2,&2,String,Definitions.Catalog>,jar:String,ids:List<&2,String>,metadata:J.Value,limits:Limits) -> IO(Result<&2,&2,String,Service>):
  match result:
    case Fail{message}: IO.pure(Result<&2,&2,String,Service>,Fail{message})
    case Done{+definitions}: service_context(context_with(metadata,definitions),jar,ids,definitions,limits)

# ItemCatalog.load is the actual initialized player item-definition path.
# The metadata input carries actual observed remainder/default-component data
# and already-resolved item tags; a separate tag loader owns nested references.
def service(jar:String,ordered_ids:List<&2,String>,item_table:String,metadata:J.Value,limits:Limits) -> IO(Result<&2,&2,String,Service>):
  do IO<Result<&2,&2,String,Service>>:
    definitions:Result<&2,&2,String,Definitions.Catalog> <- ItemCatalog.load(item_table)
    service_definitions(definitions,jar,ordered_ids,metadata,limits)
