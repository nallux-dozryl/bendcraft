import Base
import ./archive.bend as A
import ./json.bend as J
import ./resource_json.bend as Q
import ./block_model.bend as B
import ./block_bake.bend as K
import ./client_render.bend as R
import ./png.bend as P

type Error is Data:
  Error{code:String,resource:String,message:String}
type Policy is Data:
  StaticNormalized{layers:Map<&2,K.Layer>}
type Limits is Data:
  Limits{max_models:U32,max_parent_depth:U32,max_text_bytes:U32,max_png_bytes:U32,
    max_total_bytes:U32,max_sprites:U32,max_pixels:U32,max_side:U32,json_depth:U32}
type Usage is Data:
  Usage{models:U32,sprites:U32,text_bytes:U32,png_bytes:U32,pixels:U32}
type SpriteInfo is Data:
  SpriteInfo{id:String,slot:U32,width:U32,height:U32,layer:K.Layer,metadata:Maybe<&2,J.Value>}
type Catalog is Data:
  Catalog{roots:List<&2,String>,source_models:Map<&2,B.Model>,models:Map<&2,B.Resolved>,
    sprites:List<&2,SpriteInfo>,context:K.Context,usage:Usage}
type Loaded is Type:
  Loaded{assets:R.Assets,catalog:Catalog}
type Task is Data:
  Task{id:String,depth:U32,ancestors:List<&2,String>}
type ModelWork is Data:
  ModelWork{pending:List<&2,Task>,models:Map<&2,B.Model>,usage:Usage}
type Plan is Data:
  Skip{work:ModelWork}
  Fetch{entry:A.Entry,task:Task,work:ModelWork}
type TextureWork is Data:
  TextureWork{textures:List<&2,R.Texture>,sprites:List<&2,SpriteInfo>,context:Map<&2,K.Sprite>,usage:Usage,backing_pixels:U32}
type SpritePlan is Data:
  SpritePlan{entry:A.Entry,layer:K.Layer,usage:Usage}
type ResolvedWork is Data:
  ResolvedWork{source:Map<&2,B.Model>,models:Map<&2,B.Resolved>,names:List<&2,String>,usage:Usage}
type Prepared is Data:
  Prepared{roots:List<&2,String>,layers:Map<&2,K.Layer>}
type Utf8 is Data:
  Utf8{need:U32,code:U32,minimum:U32,reversed:String}

def defaults() -> Limits:
  Limits{256,32,1048576,8388608,16777216,256,1048576,256,255}

def empty_usage() -> Usage:
  Usage{0,0,0,0,0}

def require(allowed:Bool,code:String,resource:String,message:String) -> Result<&2,&2,Error,Unit>:
  match allowed:
    case True{}: Done{Unit{}}
    case False{}: Fail{Error{code,resource,message}}

def sorted(names:List<&2,String>) -> List<&2,String>:
  List.sort(String,a => b => Cmp.is_le(String.order(a,b)),names)

def limits_valid(limits:Limits) -> Bool:
  Limits{models,depth,text,png,total,sprites,pixels,+side,json} = limits
  U32.is_le(models,4096) && U32.is_le(depth,255) && U32.is_le(text,4194304) && U32.is_le(png,33554432) && U32.is_le(total,67108864) && U32.is_le(sprites,4096) && U32.is_le(pixels,1048576) && U32.is_gt(side,0) && U32.is_le(side,1024) && U32.is_le(json,255)

def converted(-X:Data,result:Result<&2,&2,B.Error,X>,+id:String) -> Result<&2,&2,Error,X>:
  match result:
    case Fail{B.Error{code,path}}: Fail{Error{"Model:" ++ code,id,path}}
    case Done{value}: Done{value}

def roots_map(ids:List<&2,String>,map:Map<&2,Unit>) -> Result<&2,&2,Error,Map<&2,Unit>>:
  match ids:
    case Nil{}: Done{map}
    case +id <> tail:
      do Result<&2,&2,Error,Map<&2,Unit>>:
        name : String <- converted(String,B.identifier(id,"requested model"),id)
        roots_map(tail,Map.set(&2,Unit,map,name,Unit{}))

def tasks(ids:List<&2,String>) -> List<&2,Task>:
  match ids:
    case Nil{}: []
    case id <> tail: Task{id,0,[]} <> tasks(tail)

def zip_path(parts:B.IdentifierParts,kind:String,suffix:String) -> String:
  B.IdentifierParts{namespace,path} = parts
  "assets/" ++ namespace ++ "/" ++ kind ++ "/" ++ path ++ suffix

def model_path(id:String) -> String:
  zip_path(B.identifier_split(id,""),"models",".json")

def sprite_path(id:String) -> String:
  zip_path(B.identifier_split(id,""),"textures",".png")

def contains(names:List<&2,String>,+id:String) -> Bool:
  match names:
    case Nil{}: False{}
    case name <> tail: String.eq(name,id) || contains(tail,id)

def scalar(+code:U32) -> Bool:
  U32.is_le(code,1114111) && Bool.not(U32.is_ge(code,55296) && U32.is_le(code,57343))

def utf_char(valid:Bool,code:U32,reversed:String) -> Result<&2,&2,String,Utf8>:
  match valid:
    case False{}: Fail{"overlong or invalid Unicode scalar"}
    case True{}: Done{Utf8{0,0,0,SCon{Chr{code},reversed}}}

def utf_lead(+byte:U32,+reversed:String) -> Result<&2,&2,String,Utf8>:
  match byte:
    case _: P.choose(Result<&2,&2,String,Utf8>,Done{Utf8{0,0,0,SCon{Chr{byte},reversed}}},
      P.choose(Result<&2,&2,String,Utf8>,Done{Utf8{1,U32.sub(byte,192),128,reversed}},
        P.choose(Result<&2,&2,String,Utf8>,Done{Utf8{2,U32.sub(byte,224),2048,reversed}},
          P.choose(Result<&2,&2,String,Utf8>,Done{Utf8{3,U32.sub(byte,240),65536,reversed}},Fail{"invalid UTF-8 leading byte"},U32.is_ge(byte,240) && U32.is_le(byte,244)),U32.is_ge(byte,224) && U32.is_le(byte,239)),U32.is_ge(byte,194) && U32.is_le(byte,223)),U32.is_lt(byte,128))

def utf_continue(valid:Bool,+need:U32,+code:U32,+minimum:U32,+reversed:String) -> Result<&2,&2,String,Utf8>:
  match valid:
    case False{}: Fail{"invalid UTF-8 continuation byte"}
    case True{}: P.choose(Result<&2,&2,String,Utf8>,utf_char(U32.is_ge(code,minimum) && scalar(code),code,reversed),Done{Utf8{U32.sub(need,1),code,minimum,reversed}},U32.is_eq(need,1))

def utf_byte(state:Utf8,+byte:U32) -> Result<&2,&2,String,Utf8>:
  match state:
    case Utf8{0,code,minimum,reversed}: utf_lead(byte,reversed)
    case Utf8{need,code,minimum,reversed}: utf_continue(U32.is_ge(byte,128) && U32.is_le(byte,191),need,U32.add(U32.mul(code,64),U32.sub(byte,128)),minimum,reversed)

def utf_loop(bytes:List<&2,U32>,result:Result<&2,&2,String,Utf8>) -> Result<&2,&2,String,String>:
  match bytes result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{Utf8{0,code,minimum,reversed}}: Done{String.reverse(reversed)}
    case Nil{} _: Fail{"truncated UTF-8 sequence"}
    case byte <> tail Done{state}: utf_loop(tail,utf_byte(state,byte))

def json_result(result:Result<&2,&2,String,J.Value>,id:String) -> Result<&2,&2,Error,J.Value>:
  match result:
    case Fail{message}: Fail{Error{"JSON",id,message}}
    case Done{value}: Done{value}

def parse_text(text:String,+id:String,limits:Limits) -> Result<&2,&2,Error,J.Value>:
  Limits{m,d,max_text,png,total,sprites,pixels,side,json} = limits
  json_result(Q.parse_with(text,J.Limits{U32.to_nat(max_text),json}),id)

def resource_text(result:Result<&2,&2,String,String>,id:String,limits:Limits) -> Result<&2,&2,Error,J.Value>:
  match result:
    case Fail{message}: Fail{Error{"UTF8",id,message}}
    case Done{value}: parse_text(value,id,limits)

def parse(bytes:List<&2,U32>,id:String,limits:Limits) -> Result<&2,&2,Error,J.Value>:
  resource_text(utf_loop(bytes,Done{Utf8{0,0,0,""}}),id,limits)

def entry_size(entry:A.Entry) -> U32:
  A.Entry{ordinal,name,raw,needed,flags,method,crc,compressed,size,offset,ceiling} = entry
  size

def reserve(+usage:Usage,+size:U32,+id:String,limits:Limits,+png:Bool) -> Result<&2,&2,Error,Usage>:
  Usage{models,sprites,+text,+images,pixels} = usage
  Limits{m,d,max_text,max_png,+total,s,p,side,json} = limits
  do Result<&2,&2,Error,Usage>:
    require(U32.is_le(size,P.choose(U32,max_png,max_text,png)),"EntryBudget",id,"declared resource bytes exceed per-entry budget")
    require(U32.is_le(size,U32.sub(total,U32.min(total,U32.add(text,images)))) && U32.is_le(U32.add(text,images),total),"ByteBudget",id,"aggregate decoded resource bytes exceed budget")
    Done{Usage{models,sprites,P.choose(U32,text,U32.add(text,size),png),P.choose(U32,U32.add(images,size),images,png),pixels}}

def found_entry(found:Maybe<&2,A.Entry>,+id:String) -> Result<&2,&2,Error,A.Entry>:
  match found:
    case None{}: Fail{Error{"MissingResource",id,"exact ZIP entry was not found"}}
    case Some{entry}: Done{entry}

def archive_result(result:Result<&2,&2,A.Error,List<&2,U32>>,id:String) -> Result<&2,&2,Error,List<&2,U32>>:
  match result:
    case Done{bytes}: Done{bytes}
    case Fail{error}: Fail{Error{"Archive",id,A.error_text(error)}}

def parent_tasks(parent:Maybe<&2,String>,+id:String,depth:U32,ancestors:List<&2,String>,pending:List<&2,Task>) -> List<&2,Task>:
  match parent:
    case None{}: pending
    case Some{parent}: Task{parent,U32.inc(depth),id <> ancestors} <> pending

def plan_seen(seen:Bool,+task:Task,+work:ModelWork,+directory:A.Directory,+limits:Limits) -> Result<&2,&2,Error,Plan>:
  match seen:
    case True{}: Done{Skip{work}}
    case False{}:
      Task{+id,depth,ancestors} = task
      ModelWork{pending,+models,+usage} = work
      Usage{count,sprites,text,png,pixels} = usage
      Limits{max,parents,t,p,total,s,pix,side,json} = limits
      do Result<&2,&2,Error,Plan>:
        require(U32.is_lt(count,max),"ModelBudget",id,"model closure exceeds budget")
        +entry : A.Entry <- found_entry(A.lookup(directory,model_path(id)),id)
        charged : Usage <- reserve(usage,entry_size(entry),id,limits,False{})
        Done{Fetch{entry,task,ModelWork{pending,models,charged}}}

def model_seen(work:ModelWork,id:String) -> Bool:
  ModelWork{pending,models,usage} = work
  B.map_has(B.Model,Map.has(&2,B.Model,models,id))

def model_plan(+task:Task,+work:ModelWork,directory:A.Directory,+limits:Limits) -> Result<&2,&2,Error,Plan>:
  Task{+id,+depth,+ancestors} = task
  Limits{max,parents,t,p,total,s,pix,side,json} = limits
  do Result<&2,&2,Error,Plan>:
    require(Bool.not(contains(ancestors,id)),"ParentCycle",id,"recursive parent chain")
    require(U32.is_le(depth,parents),"ParentDepth",id,"parent depth exceeds budget")
    plan_seen(model_seen(work,id),task,work,directory,limits)

def insert_model(+model:B.Model,task:Task,work:ModelWork) -> ModelWork:
  B.Model{parent,es,ao,gui,display,textures} = model
  Task{+id,depth,ancestors} = task
  ModelWork{pending,models,Usage{count,sprites,text,png,pixels}} = work
  ModelWork{parent_tasks(parent,id,depth,ancestors,pending),Map.set(&2,B.Model,models,id,model),Usage{U32.inc(count),sprites,text,png,pixels}}

def model_decoded(result:Result<&2,&2,Error,J.Value>,+task:Task,work:ModelWork) -> Result<&2,&2,Error,ModelWork>:
  Task{+id,depth,ancestors} = task
  do Result<&2,&2,Error,ModelWork>:
    value : J.Value <- result
    model : B.Model <- converted(B.Model,B.decode(value),id)
    Done{insert_model(model,task,work)}

def model_bytes(result:Result<&2,&2,A.Error,List<&2,U32>>,+id:String,limits:Limits) -> Result<&2,&2,Error,J.Value>:
  do Result<&2,&2,Error,J.Value>:
    data : List<&2,U32> <- archive_result(result,id)
    parse(data,id,limits)

def model_fetch(result:Result<&2,&2,Error,Plan>,archive:A.Archive,limits:Limits,next:A.Archive -> Result<&2,&2,Error,ModelWork> -> IO(A.Archive & Result<&2,&2,Error,ModelWork>)) -> IO(A.Archive & Result<&2,&2,Error,ModelWork>):
  match result:
    case Fail{error}: next(archive,Fail{error})
    case Done{Skip{work}}: next(archive,Done{work})
    case Done{Fetch{entry,+task,work}}:
      Task{+id,depth,ancestors} = task
      do IO<A.Archive & Result<&2,&2,Error,ModelWork>>:
        read : A.Archive & Result<&2,&2,A.Error,List<&2,U32>> <- A.entry_read(archive,entry)
        P.paired(A.Archive,Result<&2,&2,A.Error,List<&2,U32>>,IO(A.Archive & Result<&2,&2,Error,ModelWork>),read,archive => bytes => next(archive,model_decoded(model_bytes(bytes,id,limits),task,work)))

def models_loop(fuel:Nat,+directory:A.Directory,+limits:Limits,archive:A.Archive,result:Result<&2,&2,Error,ModelWork>) -> IO(A.Archive & Result<&2,&2,Error,ModelWork>):
  match fuel result:
    case _ Fail{error}: IO.pure(A.Archive & Result<&2,&2,Error,ModelWork>,(archive,Fail{error}))
    case _ Done{ModelWork{Nil{},models,usage}}: IO.pure(A.Archive & Result<&2,&2,Error,ModelWork>,(archive,result))
    case 0n _: IO.pure(A.Archive & Result<&2,&2,Error,ModelWork>,(archive,Fail{Error{"WorkBudget","models","parent closure work limit"}}))
    case 1n+p Done{ModelWork{task <> pending,models,usage}}: model_fetch(model_plan(task,ModelWork{pending,models,usage},directory,limits),archive,limits,archive => result => models_loop(p,directory,limits,archive,result))

def resolve_models(names:List<&2,String>,+library:B.Library,resolved:Map<&2,B.Resolved>) -> Result<&2,&2,Error,Map<&2,B.Resolved>>:
  match names:
    case Nil{}: Done{resolved}
    case +id <> tail:
      do Result<&2,&2,Error,Map<&2,B.Resolved>>:
        value : B.Resolved <- converted(B.Resolved,B.resolve(library,id),id)
        resolve_models(tail,library,Map.set(&2,B.Resolved,resolved,id,value))

def add_material(status:B.MaterialStatus,id:String,set:Map<&2,Unit>) -> Result<&2,&2,Error,Map<&2,Unit>>:
  match status:
    case B.FoundMaterial{B.Material{sprite,force}}: Done{Map.set(&2,Unit,set,sprite,Unit{})}
    case B.UnresolvedMaterial{B.TextureCycle{slot}}: Fail{Error{"TextureCycle",id,slot}}
    case B.UnresolvedMaterial{B.MissingTexture{slot}}: Fail{Error{"MissingTexture",id,slot}}
    case _: Fail{Error{"MissingTexture",id,"unresolved material"}}

def referenced_slots(names:List<&2,String>,+model:B.Resolved,+id:String,set:Map<&2,Unit>) -> Result<&2,&2,Error,Map<&2,Unit>>:
  match names:
    case Nil{}: Done{set}
    case slot <> tail:
      do Result<&2,&2,Error,Map<&2,Unit>>:
        set : Map<&2,Unit> <- add_material(B.material_status(model,"#" ++ slot),id,set)
        referenced_slots(tail,model,id,set)

def face_slots(faces:List<&2,B.Face>,set:Map<&2,Unit>) -> Map<&2,Unit>:
  match faces:
    case Nil{}: set
    case B.Face{direction,cull,uv,rotation,texture,tint} <> tail: face_slots(tail,Map.set(&2,Unit,set,texture,Unit{}))

def element_slots(elements:List<&2,B.Element>,set:Map<&2,Unit>) -> Map<&2,Unit>:
  match elements:
    case Nil{}: set
    case B.Element{from,to,rotation,faces,emission,shade} <> tail: element_slots(tail,face_slots(faces,set))

def slot_queries(names:List<&2,String>) -> List<&2,String>:
  match names:
    case Nil{}: []
    case name <> tail: ("#" ++ name) <> slot_queries(tail)

def root_slots(model:B.Resolved) -> List<&2,String>:
  B.Resolved{name,parent,elements,present,ao,gui,display,textures,diagnostics} = model
  List.append(&2,String,slot_queries(Map.keys(&2,B.Texture,textures)),Map.keys(&2,Unit,element_slots(elements,MTip{})))

def slot_budget(id:String,+set:Map<&2,Unit>) -> Result<&2,&2,Error,Map<&2,Unit>>:
  do Result<&2,&2,Error,Map<&2,Unit>>:
    require(Nat.is_lt(List.length(&2,String,Map.keys(&2,Unit,set)),1025n),"ReferencedSlotBudget",id,"StaticNormalized supports at most 1024 referenced slot spellings per effective model")
    Done{set}

def unique_slots(names:List<&2,String>,set:Map<&2,Unit>) -> Map<&2,Unit>:
  match names:
    case Nil{}: set
    case name <> tail: unique_slots(tail,Map.set(&2,Unit,set,B.strip_slot(name),Unit{}))

def collect_roots(roots:List<&2,String>,+models:Map<&2,B.Resolved>,set:Map<&2,Unit>) -> Result<&2,&2,Error,Map<&2,Unit>>:
  match roots:
    case Nil{}: Done{set}
    case +id <> tail:
      +model : B.Resolved = B.map_value(B.Resolved,Map.get(B.Resolved,B.Resolved{"",None{},[],False{},True{},B.Side{},B.Display{MTip{}},MTip{},[]},models,id))
      do Result<&2,&2,Error,Map<&2,Unit>>:
        slots : Map<&2,Unit> <- slot_budget(id,unique_slots(root_slots(model),MTip{}))
        set : Map<&2,Unit> <- referenced_slots(sorted(Map.keys(&2,Unit,slots)),model,id,set)
        collect_roots(tail,models,set)

# Populate an indexed owner once; Image construction then performs bounded
# tree reads instead of repeated traversal of the source pixel list.
def fill_pixels(pixels:List<&2,U32>,buffer:Array<U32>,+index:U32,+width:U32,+side:U32) -> Array<U32>:
  match pixels:
    case Nil{}: buffer
    case pixel <> tail: fill_pixels(tail,buffer[U32.add(U32.mul(U32.div(index,width),side),U32.mod(index,width))] <- pixel,U32.inc(index),width,side)

def image_tree(n:Nat,buffer:Array<U32>,+x:U32,+y:U32,+side:U32,+stride:U32) -> Array<U32> & Image:
  match n:
    case 0n: P.paired(Array<U32>,U32,Array<U32> & Image,buffer[U32.add(U32.mul(y,stride),x)],buffer => color => (buffer,Pix{color}))
    case 1n++p:
      +half = U32.div(side,2)
      P.paired(Array<U32>,Image,Array<U32> & Image,image_tree(p,buffer,x,y,half,stride),buffer => tl =>
        P.paired(Array<U32>,Image,Array<U32> & Image,image_tree(p,buffer,U32.add(x,half),y,half,stride),buffer => tr =>
          P.paired(Array<U32>,Image,Array<U32> & Image,image_tree(p,buffer,x,U32.add(y,half),half,stride),buffer => bl =>
            P.paired(Array<U32>,Image,Array<U32> & Image,image_tree(p,buffer,U32.add(x,half),U32.add(y,half),half,stride),buffer => br =>
              (buffer,Qua{tl,tr,bl,br})))))

def texture(decoded:P.Decoded) -> R.Texture:
  P.Decoded{+width,+height,pixels} = decoded
  +side = R.side_for(U32.max(width,height))
  P.paired(Array<U32>,Image,R.Texture,image_tree(P.array_depth(13n,side,1),fill_pixels(pixels,Array.new(U32,P.array_depth(27n,U32.mul(side,side),1),0),0,width,side),0,0,side,side),buffer => image => R.Texture{width,height,side,image})

def policy_keys(names:List<&2,String>,+layers:Map<&2,K.Layer>,+result:Map<&2,K.Layer>) -> Result<&2,&2,Error,Map<&2,K.Layer>>:
  match names:
    case Nil{}: Done{result}
    case +name <> tail:
      do Result<&2,&2,Error,Map<&2,K.Layer>>:
        +id : String <- converted(String,B.identifier(name,"sprite layer policy"),name)
        require(Bool.not(B.map_has(K.Layer,Map.has(&2,K.Layer,result,id))),"LayerCollision",id,"two layer keys normalize to one sprite ID")
        policy_keys(tail,layers,Map.set(&2,K.Layer,result,id,B.map_value(K.Layer,Map.get(K.Layer,K.Solid{},layers,name))))

def policy_layers(policy:Policy) -> Result<&2,&2,Error,Map<&2,K.Layer>>:
  StaticNormalized{+layers} = policy
  do Result<&2,&2,Error,Map<&2,K.Layer>>:
    require(Nat.is_le(List.length(&2,String,Map.keys(&2,K.Layer,layers)),4096n),"LayerBudget","policy","layer map exceeds supported bound")
    policy_keys(sorted(Map.keys(&2,K.Layer,layers)),layers,MTip{})

def layer_for(+layers:Map<&2,K.Layer>,+id:String) -> Result<&2,&2,Error,K.Layer>:
  do Result<&2,&2,Error,K.Layer>:
    require(B.map_has(K.Layer,Map.has(&2,K.Layer,layers,id)),"MissingLayer",id,"StaticNormalized requires a caller-supplied layer for each sprite")
    Done{B.map_value(K.Layer,Map.get(K.Layer,K.Solid{},layers,id))}

def metadata_members(members:List<&2,J.Member>,id:String) -> Result<&2,&2,Error,Unit>:
  match members:
    case Nil{}: Done{Unit{}}
    case J.JMember{"animation",value} <> tail: Fail{Error{"UnsupportedAnimation",id,"StaticNormalized does not select or interpolate animation frames"}}
    case J.JMember{key,value} <> tail: Fail{Error{"UnsupportedMetadata",id,"unsupported sprite metadata key: " ++ key}}

def metadata(value:J.Value,id:String) -> Result<&2,&2,Error,Maybe<&2,J.Value>>:
  match value:
    case J.JObject{+members}:
      do Result<&2,&2,Error,Maybe<&2,J.Value>>:
        metadata_members(members,id)
        Done{Some{J.JObject{members}}}
    case _: Fail{Error{"MetadataObject",id,"sprite metadata must be an object"}}

def png_result(result:Result<&2,&1,P.Error,P.Decoded>,id:String) -> Result<&2,&2,Error,P.Decoded>:
  match result:
    case Fail{P.Error{code}}: Fail{Error{"PNG:" ++ code,id,"PNG decode rejected resource"}}
    case Done{decoded}: Done{decoded}

def decode_png(result:Result<&2,&2,A.Error,List<&2,U32>>,+id:String,limits:Limits,usage:Usage) -> Result<&2,&2,Error,P.Decoded>:
  Limits{m,d,text,png,total,s,+max_pixels,+side,json} = limits
  Usage{models,sprites,t,p,pixels} = usage
  do Result<&2,&2,Error,P.Decoded>:
    bytes : List<&2,U32> <- archive_result(result,id)
    png_result(P.decode(bytes,P.Limits{png,side,side,U32.sub(max_pixels,U32.min(max_pixels,pixels))}),id)

def image_budget(result:Result<&2,&2,Error,P.Decoded>,id:String,limits:Limits,work:TextureWork) -> Result<&2,&2,Error,P.Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+decoded}:
      P.Decoded{w,h,pixels} = decoded
      Limits{m,d,text,png,total,s,+max_pixels,side,json} = limits
      TextureWork{textures,sprites,context,usage,capacity} = work
      +needed = R.side_for(U32.max(w,h))
      do Result<&2,&2,Error,P.Decoded>:
        require(U32.is_le(U32.mul(needed,needed),U32.sub(max_pixels,U32.min(max_pixels,capacity))),"ImageBudget",id,"padded Image backing pixels exceed aggregate budget")
        Done{decoded}

def add_sprite(decoded:P.Decoded,+id:String,+layer:K.Layer,meta:Maybe<&2,J.Value>,work:TextureWork) -> TextureWork:
  P.Decoded{+width,+height,pixels} = decoded
  TextureWork{textures,sprites,context,Usage{models,+slot,text,png,count},capacity} = work
  TextureWork{texture(P.Decoded{width,height,pixels}) <> textures,SpriteInfo{id,slot,width,height,layer,meta} <> sprites,
    Map.set(&2,K.Sprite,context,id,K.Sprite{slot,0.0,0.0,1.0,1.0,layer,False{}}),Usage{models,U32.inc(slot),text,png,U32.add(count,U32.mul(width,height))},U32.add(capacity,U32.mul(R.side_for(U32.max(width,height)),R.side_for(U32.max(width,height))))}

def metadata_done(result:Result<&2,&2,Error,J.Value>,decoded:P.Decoded,+id:String,layer:K.Layer,work:TextureWork) -> Result<&2,&2,Error,TextureWork>:
  do Result<&2,&2,Error,TextureWork>:
    value : J.Value <- result
    meta : Maybe<&2,J.Value> <- metadata(value,id)
    Done{add_sprite(decoded,id,layer,meta,work)}

def metadata_fetch(plan:Result<&2,&2,Error,Usage>,entry:A.Entry,+id:String,decoded:P.Decoded,layer:K.Layer,work:TextureWork,archive:A.Archive,limits:Limits,next:A.Archive -> Result<&2,&2,Error,TextureWork> -> IO(A.Archive & Result<&2,&2,Error,TextureWork>)) -> IO(A.Archive & Result<&2,&2,Error,TextureWork>):
  match plan:
    case Fail{error}: next(archive,Fail{error})
    case Done{usage}:
      TextureWork{textures,sprites,context,old,capacity} = work
      do IO<A.Archive & Result<&2,&2,Error,TextureWork>>:
        read : A.Archive & Result<&2,&2,A.Error,List<&2,U32>> <- A.entry_read(archive,entry)
        P.paired(A.Archive,Result<&2,&2,A.Error,List<&2,U32>>,IO(A.Archive & Result<&2,&2,Error,TextureWork>),read,archive => bytes => next(archive,metadata_done(model_bytes(bytes,id ++ ".png.mcmeta",limits),decoded,id,layer,TextureWork{textures,sprites,context,usage,capacity})))

def metadata_optional(entry:Maybe<&2,A.Entry>,decoded:P.Decoded,+id:String,layer:K.Layer,+work:TextureWork,archive:A.Archive,+limits:Limits,next:A.Archive -> Result<&2,&2,Error,TextureWork> -> IO(A.Archive & Result<&2,&2,Error,TextureWork>)) -> IO(A.Archive & Result<&2,&2,Error,TextureWork>):
  match entry:
    case None{}: next(archive,Done{add_sprite(decoded,id,layer,None{},work)})
    case Some{+entry}:
      TextureWork{textures,sprites,context,usage,capacity} = work
      metadata_fetch(reserve(usage,entry_size(entry),id,limits,False{}),entry,id,decoded,layer,work,archive,limits,next)

def sprite_decoded(result:Result<&2,&2,Error,P.Decoded>,+directory:A.Directory,+id:String,layer:K.Layer,work:TextureWork,archive:A.Archive,limits:Limits,next:A.Archive -> Result<&2,&2,Error,TextureWork> -> IO(A.Archive & Result<&2,&2,Error,TextureWork>)) -> IO(A.Archive & Result<&2,&2,Error,TextureWork>):
  match result:
    case Fail{error}: next(archive,Fail{error})
    case Done{decoded}: metadata_optional(A.lookup(directory,sprite_path(id) ++ ".mcmeta"),decoded,id,layer,work,archive,limits,next)

def sprite_plan(+id:String,+directory:A.Directory,layers:Map<&2,K.Layer>,+usage:Usage,+limits:Limits) -> Result<&2,&2,Error,SpritePlan>:
  Usage{models,count,text,png,pixels} = usage
  Limits{m,d,t,p,total,max,pix,side,json} = limits
  do Result<&2,&2,Error,SpritePlan>:
    require(U32.is_lt(count,max),"SpriteBudget",id,"referenced sprites exceed budget")
    layer : K.Layer <- layer_for(layers,id)
    +entry : A.Entry <- found_entry(A.lookup(directory,sprite_path(id)),id)
    charged : Usage <- reserve(usage,entry_size(entry),id,limits,True{})
    Done{SpritePlan{entry,layer,charged}}

def sprite_read(plan:Result<&2,&2,Error,SpritePlan>,+id:String,+directory:A.Directory,+limits:Limits,+work:TextureWork,archive:A.Archive,next:A.Archive -> Result<&2,&2,Error,TextureWork> -> IO(A.Archive & Result<&2,&2,Error,TextureWork>)) -> IO(A.Archive & Result<&2,&2,Error,TextureWork>):
  match plan:
    case Fail{error}: next(archive,Fail{error})
    case Done{SpritePlan{entry,+layer,+usage}}:
      TextureWork{textures,sprites,context,old,capacity} = work
      do IO<A.Archive & Result<&2,&2,Error,TextureWork>>:
        read : A.Archive & Result<&2,&2,A.Error,List<&2,U32>> <- A.entry_read(archive,entry)
        P.paired(A.Archive,Result<&2,&2,A.Error,List<&2,U32>>,IO(A.Archive & Result<&2,&2,Error,TextureWork>),read,archive => bytes => sprite_decoded(image_budget(decode_png(bytes,id,limits,usage),id,limits,work),directory,id,layer,TextureWork{textures,sprites,context,usage,capacity},archive,limits,next))

def sprites_loop(names:List<&2,String>,+directory:A.Directory,+layers:Map<&2,K.Layer>,+limits:Limits,archive:A.Archive,result:Result<&2,&2,Error,TextureWork>) -> IO(A.Archive & Result<&2,&2,Error,TextureWork>):
  match names result:
    case _ Fail{error}: IO.pure(A.Archive & Result<&2,&2,Error,TextureWork>,(archive,Fail{error}))
    case Nil{} _: IO.pure(A.Archive & Result<&2,&2,Error,TextureWork>,(archive,result))
    case +id <> tail Done{+work}:
      TextureWork{textures,sprites,context,usage,capacity} = work
      sprite_read(sprite_plan(id,directory,layers,usage,limits),id,directory,limits,work,archive,archive => result => sprites_loop(tail,directory,layers,limits,archive,result))

def resolved_work(work:ModelWork,+roots:List<&2,String>) -> Result<&2,&2,Error,ResolvedWork>:
  ModelWork{pending,+models,usage} = work
  do Result<&2,&2,Error,ResolvedWork>:
    +resolved : Map<&2,B.Resolved> <- resolve_models(sorted(Map.keys(&2,B.Model,models)),B.Library{models,B.empty_model()},MTip{})
    sprites : Map<&2,Unit> <- collect_roots(roots,resolved,MTip{})
    Done{ResolvedWork{models,resolved,sorted(Map.keys(&2,Unit,sprites)),usage}}

def close_loaded(archive:A.Archive,result:Result<&2,&2,Error,TextureWork>,roots:List<&2,String>,source:Map<&2,B.Model>,models:Map<&2,B.Resolved>) -> IO(Result<&2,&1,Error,Loaded>):
  match result:
    case Fail{error}:
      do IO<Result<&2,&1,Error,Loaded>>:
        A.Archive.close(archive)
        return Fail{error}
    case Done{TextureWork{textures,sprites,context,usage,capacity}}:
      do IO<Result<&2,&1,Error,Loaded>>:
        A.Archive.close(archive)
        return Done{Loaded{R.Assets{List.reverse(&2,R.Texture,textures)},Catalog{roots,source,models,List.reverse(&2,SpriteInfo,sprites),K.Context{context,None{}},usage}}}

def load_sprites(result:Result<&2,&2,Error,ResolvedWork>,archive:A.Archive,directory:A.Directory,roots:List<&2,String>,layers:Map<&2,K.Layer>,limits:Limits) -> IO(Result<&2,&1,Error,Loaded>):
  match result:
    case Fail{error}: close_loaded(archive,Fail{error},roots,MTip{},MTip{})
    case Done{ResolvedWork{source,models,names,usage}}:
      do IO<Result<&2,&1,Error,Loaded>>:
        loaded : A.Archive & Result<&2,&2,Error,TextureWork> <- sprites_loop(names,directory,layers,limits,archive,Done{TextureWork{[],[],MTip{},usage,0}})
        P.paired(A.Archive,Result<&2,&2,Error,TextureWork>,IO(Result<&2,&1,Error,Loaded>),loaded,archive => result => close_loaded(archive,result,roots,source,models))

def load_models_result(result:Result<&2,&2,Error,ModelWork>,archive:A.Archive,directory:A.Directory,+roots:List<&2,String>,layers:Map<&2,K.Layer>,limits:Limits) -> IO(Result<&2,&1,Error,Loaded>):
  match result:
    case Fail{error}: close_loaded(archive,Fail{error},roots,MTip{},MTip{})
    case Done{work}: load_sprites(resolved_work(work,roots),archive,directory,roots,layers,limits)

def directory_ready(archive:A.Archive,+directory:A.Directory,+roots:List<&2,String>,layers:Map<&2,K.Layer>,+limits:Limits) -> IO(Result<&2,&1,Error,Loaded>):
  Limits{models,depth,text,png,total,sprites,pixels,side,json} = limits
  do IO<Result<&2,&1,Error,Loaded>>:
    loaded : A.Archive & Result<&2,&2,Error,ModelWork> <- models_loop(U32.to_nat(U32.inc(U32.mul(models,2))),directory,limits,archive,Done{ModelWork{tasks(roots),MTip{},empty_usage()}})
    P.paired(A.Archive,Result<&2,&2,Error,ModelWork>,IO(Result<&2,&1,Error,Loaded>),loaded,archive => result => load_models_result(result,archive,directory,roots,layers,limits))

def opened(result:Result<&2,&1,A.Error,A.Archive>,roots:List<&2,String>,layers:Map<&2,K.Layer>,limits:Limits) -> IO(Result<&2,&1,Error,Loaded>):
  match result:
    case Fail{error}: IO.pure(Result<&2,&1,Error,Loaded>,Fail{Error{"ArchiveOpen","archive",A.error_text(error)}})
    case Done{archive}: P.paired(A.Archive,A.Directory,IO(Result<&2,&1,Error,Loaded>),A.Archive.directory(archive),archive => directory => directory_ready(archive,directory,roots,layers,limits))

def prepared(+roots:List<&2,String>,policy:Policy,+limits:Limits) -> Result<&2,&2,Error,Prepared>:
  Limits{models,depth,text,png,total,sprites,pixels,side,json} = limits
  do Result<&2,&2,Error,Prepared>:
    require(limits_valid(limits),"Limits","configuration","limits exceed the supported finite bounds")
    require(Nat.is_le(List.length(&2,String,roots),U32.to_nat(models)),"RootBudget","configuration","requested root count exceeds model budget")
    names : Map<&2,Unit> <- roots_map(roots,MTip{})
    layers : Map<&2,K.Layer> <- policy_layers(policy)
    Done{Prepared{sorted(Map.keys(&2,Unit,names)),layers}}

def load_prepared(result:Result<&2,&2,Error,Prepared>,path:String,+limits:Limits) -> IO(Result<&2,&1,Error,Loaded>):
  match result:
    case Fail{error}: IO.pure(Result<&2,&1,Error,Loaded>,Fail{error})
    case Done{Prepared{roots,layers}}:
      do IO<Result<&2,&1,Error,Loaded>>:
        result : Result<&2,&1,A.Error,A.Archive> <- A.load(path,A.UTF8Fallback{},A.default_limits())
        opened(result,roots,layers,limits)

def load(path:String,roots:List<&2,String>,policy:Policy,+limits:Limits) -> IO(Result<&2,&1,Error,Loaded>):
  load_prepared(prepared(roots,policy,limits),path,limits)

def split(loaded:Loaded) -> R.Assets & Catalog:
  Loaded{assets,catalog} = loaded
  (assets,catalog)

def model_found(found:Bool,+models:Map<&2,B.Resolved>,+id:String) -> Result<&2,&2,Error,B.Resolved>:
  match found:
    case False{}: Fail{Error{"ModelNotLoaded",id,"model was not in the requested closure"}}
    case True{}: Done{B.map_value(B.Resolved,Map.get(B.Resolved,B.Resolved{"",None{},[],False{},True{},B.Side{},B.Display{MTip{}},MTip{},[]},models,id))}

def model(catalog:Catalog,+id:String) -> Result<&2,&2,Error,B.Resolved>:
  Catalog{roots,source,+models,sprites,context,usage} = catalog
  do Result<&2,&2,Error,B.Resolved>:
    +name : String <- converted(String,B.identifier(id,"model lookup"),id)
    model_found(B.map_has(B.Resolved,Map.has(&2,B.Resolved,models,name)),models,name)
