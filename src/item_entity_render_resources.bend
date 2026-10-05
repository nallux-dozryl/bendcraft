import Base
import ./archive.bend as A
import ./json.bend as J
import ./png.bend as P
import ./block_model.bend as B
import ./block_bake.bend as K
import ./block_resources.bend as BR
import ./client_render.bend as R
import ./mesh_render.bend as M
import ./inventory.bend as I
import ./player_item_definitions.bend as Definitions
import ./crafting_recipe_components.bend as C
import ./item_entity_pickup_patch.bend as Patch
import ./item_entity_render_generated.bend as G
import ./item_entity_render_model.bend as D

type Request is Data:
  Request{key:I.ItemKey,seed:U32,item_model:String,model:String}
type Assets is Type:
  Assets{textures:R.Assets,catalog:D.Catalog}
type Error is Data:
  Error{message:String}

def required(-T:Data,value:Maybe<&2,T>,message:String) -> Result<&2,&2,String,T>:
  match value:
    case None{}: Fail{message}
    case Some{answer}: Done{answer}
def members(value:J.Value) -> Result<&2,&2,String,List<&2,J.Member>>:
  match value:
    case J.JObject{values}: Done{values}
    case _: Fail{"render:item components require object"}
def text(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{value}: Done{value}
    case _: Fail{"render:resource identifier requires string"}
def item_model(+effective:J.Value) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    raw : J.Value <- required(J.Value,J.member(effective,"minecraft:item_model"),"render:ITEM_MODEL absent")
    text(raw)
def enchantments(value:Maybe<&2,J.Value>) -> Bool:
  match value:
    case Some{J.JObject{Nil{}}}: False{}
    case None{}: False{}
    case _: True{}
def foil_override(value:Maybe<&2,J.Value>,+effective:J.Value) -> Bool:
  match value:
    case Some{J.JBool{flag}}: flag
    case _:
      enchantments(J.member(effective,"minecraft:enchantments"))
def definition_seed(definition:Definitions.Definition,effective:J.Value) -> U32:
  Definitions.Definition{number,id,description,limit,set,hash,enabled} = definition
  U32.add(number,C.unsigned_default(J.member(effective,"minecraft:damage"),0))
# Exact key/default authentication precedes ITEM_MODEL and seed selection.
def request(+definitions:Definitions.Catalog,+key:I.ItemKey) -> Result<&2,&2,String,Request>:
  I.ItemKey{+id,identity} = key
  do Result<&2,&2,String,Request>:
    definition : Definitions.Definition <- required(Definitions.Definition,Definitions.definition(definitions,id),"render:item not registered")
    +defaults : J.Value <- required(J.Value,Definitions.initialized_defaults(definitions,id),"render:initialized item defaults required")
    +patch : J.Value <- Patch.patch(defaults,key)
    changes : List<&2,C.Change> <- C.decode(patch)
    values : List<&2,J.Member> <- members(defaults)
    +effective : J.Value = J.JObject{C.apply(changes,values)}
    C.guard(Bool.not(foil_override(J.member(effective,"minecraft:enchantment_glint_override"),effective)),"render:foil/glint material provider required")
    name : String <- item_model(effective)
    return Request{key,definition_seed(definition,effective),name,""}
def converted(-T:Data,value:Result<&2,&2,BR.Error,T>) -> Result<&2,&2,String,T>:
  match value:
    case Fail{BR.Error{code,resource,message}}: Fail{code ++ ":" ++ resource ++ ":" ++ message}
    case Done{answer}: Done{answer}
def bake_converted(value:Result<&2,&2,K.Error,List<&2,K.Baked>>) -> Result<&2,&2,String,List<&2,K.Baked>>:
  match value:
    case Fail{K.Unsupported{code}}: Fail{"render:unsupported bake:" ++ code}
    case Fail{K.Invalid{code}}: Fail{"render:invalid bake:" ++ code}
    case Fail{K.MissingMaterial{reference}}: Fail{"render:missing material:" ++ reference}
    case Done{answer}: Done{answer}
def model_converted(-T:Data,value:Result<&2,&2,B.Error,T>) -> Result<&2,&2,String,T>:
  match value:
    case Fail{B.Error{code,path}}: Fail{"render:" ++ code ++ ":" ++ path}
    case Done{answer}: Done{answer}
def direct_model(+value:J.Value) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    +root : J.Value <- required(J.Value,J.member(value,"model"),"render:client item has no model")
    +kind : J.Value <- required(J.Value,J.member(root,"type"),"render:client item has no type")
    +name : String <- text(kind)
    C.guard(String.eq(name,"minecraft:model") || String.eq(name,"model"),"render:client item selector/composite/special model provider required")
    C.guard(Maybe.is_none(&2,J.Value,J.member(root,"tints")),"render:dynamic item tint provider required")
    raw : J.Value <- required(J.Value,J.member(root,"model"),"render:direct model missing identifier")
    name : String <- text(raw)
    model_converted(String,B.identifier(name,"client item model"))
def item_json(value:Result<&2,&2,BR.Error,J.Value>,request:Request) -> Result<&2,&2,String,Request>:
  Request{key,seed,item_model,model} = request
  do Result<&2,&2,String,Request>:
    json : J.Value <- converted(J.Value,value)
    model : String <- direct_model(json)
    return Request{key,seed,item_model,model}
def item_path(name:String) -> String:
  BR.zip_path(B.identifier_split(name,""),"items",".json")
def request_name(request:Request) -> String:
  Request{key,seed,name,model} = request
  name
def item_bytes(+request:Request,pair:A.Archive & Result<&2,&2,A.Error,List<&2,U32>>,limits:BR.Limits,
    next:A.Archive -> Result<&2,&2,String,Request> -> IO(A.Archive & Result<&2,&2,String,Request>)) -> IO(A.Archive & Result<&2,&2,String,Request>):
  (archive,result) = pair
  next(archive)(item_json(BR.model_bytes(result,request_name(request),limits),request))
def read_client_item(found:Result<&2,&2,BR.Error,A.Entry>,request:Request,archive:A.Archive,limits:BR.Limits,
    next:A.Archive -> Result<&2,&2,String,Request> -> IO(A.Archive & Result<&2,&2,String,Request>)) -> IO(A.Archive & Result<&2,&2,String,Request>):
  match found:
    case Fail{BR.Error{code,name,message}}: next(archive)(Fail{code ++ ":" ++ name ++ ":" ++ message})
    case Done{entry}:
      do IO<A.Archive & Result<&2,&2,String,Request>>:
        read : A.Archive & Result<&2,&2,A.Error,List<&2,U32>> <- A.entry_read(archive,entry)
        item_bytes(request,read,limits,next)
def item_read(+request:Request,+directory:A.Directory,+limits:BR.Limits,archive:A.Archive,
    next:A.Archive -> Result<&2,&2,String,Request> -> IO(A.Archive & Result<&2,&2,String,Request>)) -> IO(A.Archive & Result<&2,&2,String,Request>):
  read_client_item(BR.found_entry(A.lookup(directory,item_path(request_name(request))),request_name(request)),request,archive,limits,next)

def texture_at(values:List<&2,R.Texture>,index:Nat) -> Result<&2,&2,String,R.Texture>:
  match values index:
    case head <> rest 0n: Done{head}
    case head <> rest 1n+p: texture_at(rest,p)
    case _ _: Fail{"render:sprite texture slot not loaded"}
def generated_parent(builtin:Bool,model:B.Model,next:String -> Bool) -> Bool:
  match builtin model:
    case True{} _: True{}
    case False{} B.Model{Some{parent},None{},ao,gui,display,textures}: next(parent)
    case _ _: False{}
def generated_chain(left:Nat,+models:Map<&2,B.Model>,+name:String) -> Bool:
  match left:
    case 0n: False{}
    case 1n+rest: generated_parent(String.eq(name,"minecraft:builtin/generated"),B.map_value(B.Model,Map.get(B.Model,B.empty_model(),models,name)),parent => generated_chain(rest,models,parent))
def sprite_name(status:B.MaterialStatus) -> Result<&2,&2,String,String>:
  match status:
    case B.FoundMaterial{B.Material{name,force}}: Done{name}
    case _: Fail{"render:generated layer material not found"}
def generated_sprite(sprite:K.Sprite,textures:List<&2,R.Texture>,slot:String,index:U32) -> Result<&2,&2,String,List<&2,B.Element>>:
  K.Sprite{texture,a,b,c,d,layer,animated} = sprite
  do Result<&2,&2,String,List<&2,B.Element>>:
    C.guard(Bool.not(animated),"render:generated animated sprite requires frame union and animation owner")
    image : R.Texture <- texture_at(textures,U32.to_nat(texture))
    return G.elements(image,slot,index)
def generated_layer(+name:String,+context:K.Context,+textures:List<&2,R.Texture>,slot:String,index:U32) -> Result<&2,&2,String,List<&2,B.Element>>:
  K.Context{+sprites,missing} = context
  do Result<&2,&2,String,List<&2,B.Element>>:
    C.guard(B.map_has(K.Sprite,Map.has(&2,K.Sprite,sprites,name)),"render:generated sprite not loaded")
    sprite : K.Sprite = B.map_value(K.Sprite,Map.get(K.Sprite,K.Sprite{0,0.0,0.0,1.0,1.0,K.Cutout{},False{}},sprites,name))
    generated_sprite(sprite,textures,slot,index)
def generated_found(value:Maybe<&2,B.Material>,name:String,context:K.Context,textures:List<&2,R.Texture>,index:U32,
    next:Unit -> Result<&2,&2,String,List<&2,B.Element>>) -> Result<&2,&2,String,List<&2,B.Element>>:
  match value:
    case None{}: Done{[]}
    case Some{B.Material{sprite,force}}:
      do Result<&2,&2,String,List<&2,B.Element>>:
        head : List<&2,B.Element> <- generated_layer(sprite,context,textures,"#" ++ name,index)
        tail : List<&2,B.Element> <- next(Unit{})
        return List.append(&2,B.Element,head,tail)
def generated_layers(names:List<&2,String>,+resolved:B.Resolved,+context:K.Context,+textures:List<&2,R.Texture>,+index:U32) -> Result<&2,&2,String,List<&2,B.Element>>:
  match names:
    case Nil{}: Done{[]}
    case +name <> rest: generated_found(B.material(resolved,name),name,context,textures,index,unit => generated_layers(rest,resolved,context,textures,U32.inc(index)))
def resolved_generated(resolved:B.Resolved,elements:List<&2,B.Element>) -> B.Resolved:
  B.Resolved{id,parent,old,present,ao,gui,display,textures,diagnostics} = resolved
  B.Resolved{id,parent,elements,True{},ao,gui,display,textures,diagnostics}
def geometry(generated:Bool,+resolved:B.Resolved,context:K.Context,textures:List<&2,R.Texture>) -> Result<&2,&2,String,B.Resolved>:
  match generated:
    case False{}: Done{resolved}
    case True{}:
      do Result<&2,&2,String,B.Resolved>:
        elements : List<&2,B.Element> <- generated_layers(["layer0","layer1","layer2","layer3","layer4"],resolved,context,textures,0)
        return resolved_generated(resolved,elements)
def display_ground(value:B.Resolved) -> B.Transform:
  B.Resolved{id,parent,elements,present,ao,gui,B.Display{transforms},textures,diagnostics} = value
  B.map_value(B.Transform,Map.get(B.Transform,B.identity_transform(),transforms,"ground"))
def ground_position(value:M.Vec3,transform:B.Transform) -> M.Vec3:
  M.Vec3{x,y,z} = value
  B.Transform{rotation,B.Vec3{tx,ty,tz},B.Vec3{sx,sy,sz}} = transform
  M.Vec3{F32.add(F32.mul(sx,F32.sub(x,0.5)),tx),F32.add(F32.mul(sy,F32.sub(y,0.5)),ty),F32.add(F32.mul(sz,F32.sub(z,0.5)),tz)}
def ground_vertex(value:M.Vertex,transform:B.Transform) -> M.Vertex:
  M.Vertex{point,uv} = value
  M.Vertex{ground_position(point,transform),uv}
def ground_quad(value:K.Baked,+transform:B.Transform) -> M.Quad:
  K.Baked{a,b,c,d,direction,cull,sprite,texture,tint,emission,override,layer,force,animated,ds,ns} = value
  M.Quad{ground_vertex(a,transform),ground_vertex(b,transform),ground_vertex(c,transform),ground_vertex(d,transform),M.Material{texture,4294967295,4294967295,1.0,K.mesh_mode(layer,1),M.Clamp{}},M.Back{},0}
def ground_quads(values:List<&2,K.Baked>,+transform:B.Transform) -> List<&2,M.Quad>:
  match values:
    case Nil{}: []
    case head <> rest: ground_quad(head,transform) <> ground_quads(rest,transform)
def bounds_quads(values:List<&2,M.Quad>,low:M.Vec3,high:M.Vec3) -> M.Vec3 & M.Vec3:
  match values:
    case Nil{}: (low,high)
    case M.Quad{M.Vertex{+a,au},M.Vertex{+b,bu},M.Vertex{+c,cu},M.Vertex{+d,du},mat,cull,order} <> rest:
      bounds_quads(rest,M.minimum(low,M.minimum(M.minimum(a,b),M.minimum(c,d))),M.maximum(high,M.maximum(M.maximum(a,b),M.maximum(c,d))))
def bounds(values:List<&2,M.Quad>) -> M.Vec3 & M.Vec3:
  match values:
    case Nil{}: (M.Vec3{0.0,0.0,0.0},M.Vec3{0.0,0.0,0.0})
    case +head <> rest:
      M.Quad{M.Vertex{+a,uv},b,c,d,mat,cull,order} = head
      bounds_quads(head <> rest,a,a)
def block_light(gui:B.GuiLight) -> Bool:
  match gui:
    case B.Side{}: True{}
    case B.Front{}: False{}
def ground_ready(request:Request,resolved:B.Resolved,+quads:List<&2,M.Quad>,bound:M.Vec3 & M.Vec3) -> D.Ground:
  Request{key,seed,item_model,model} = request
  B.Resolved{id,parent,elements,present,ao,gui,display,textures,diagnostics} = resolved
  (low,high) = bound
  D.Ground{key,seed,quads,low,high,block_light(gui)}
def transform_rotation(value:B.Transform) -> B.Vec3:
  B.Transform{rotation,translation,scale} = value
  rotation
# The existing mesh Cutout mode cannot preserve fractional sprite alpha. Until
# the actual vanilla material classification joins this loader, refuse it.
def binary_alpha_node(image:Image) -> Bool:
  match image:
    case Pix{+color}:
      +alpha = U32.shrn(color,24n)
      U32.is_eq(alpha,0) || U32.is_eq(alpha,255)
    case Qua{a,b,c,d}: binary_alpha_node(a) && binary_alpha_node(b) && binary_alpha_node(c) && binary_alpha_node(d)
def binary_alpha_texture(texture:R.Texture) -> Bool:
  R.Texture{w,h,side,image} = texture
  binary_alpha_node(image)
def binary_baked(values:List<&2,K.Baked>,+textures:List<&2,R.Texture>) -> Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case K.Baked{a,b,c,d,direction,cull,sprite,texture,tint,emission,override,layer,force,animated,ds,ns} <> rest:
      do Result<&2,&2,String,Unit>:
        image : R.Texture <- texture_at(textures,U32.to_nat(texture))
        C.guard(binary_alpha_texture(image) || U32.is_eq(K.layer_flag(layer),1),"render:fractional sprite alpha requires vanilla material classifier")
        binary_baked(rest,textures)
def bake_ground(+request:Request,+resolved:B.Resolved,context:K.Context,textures:List<&2,R.Texture>) -> Result<&2,&2,String,D.Ground>:
  +transform = display_ground(resolved)
  do Result<&2,&2,String,D.Ground>:
    C.guard(K.vec_eq(transform_rotation(transform),B.Vec3{0.0,0.0,0.0}),"render:nonzero resource ground rotation requires general display quaternion provider")
    +baked : List<&2,K.Baked> <- bake_converted(K.bake(resolved,K.State{0,0,0,False{}},context))
    binary_baked(baked,textures)
    +quads : List<&2,M.Quad> = ground_quads(baked,transform)
    return ground_ready(request,resolved,quads,bounds(quads))
def ground_request(+request:Request,+catalog:BR.Catalog,+textures:List<&2,R.Texture>) -> Result<&2,&2,String,D.Ground>:
  Request{key,seed,item_model,+model} = request
  BR.Catalog{roots,+source,models,sprites,+context,usage} = catalog
  do Result<&2,&2,String,D.Ground>:
    +resolved : B.Resolved <- converted(B.Resolved,BR.model(catalog,model))
    resolved : B.Resolved <- geometry(generated_chain(List.length(&2,String,Map.keys(&2,B.Model,source)),source,model),resolved,context,textures)
    bake_ground(request,resolved,context,textures)
def grounds(requests:List<&2,Request>,+catalog:BR.Catalog,+textures:List<&2,R.Texture>) -> Result<&2,&2,String,List<&2,D.Ground>>:
  match requests:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,D.Ground>>:
        head : D.Ground <- ground_request(head,catalog,textures)
        tail : List<&2,D.Ground> <- grounds(rest,catalog,textures)
        return head <> tail
def orb_slot_chosen(found:Bool,slot:U32,next:Maybe<&2,U32>) -> Maybe<&2,U32>:
  match found:
    case True{}: Some{slot}
    case False{}: next
def orb_slot(values:List<&2,BR.SpriteInfo>) -> Maybe<&2,U32>:
  match values:
    case Nil{}: None{}
    case BR.SpriteInfo{name,slot,w,h,layer,meta} <> rest: orb_slot_chosen(String.eq(name,"minecraft:entity/experience/experience_orb"),slot,orb_slot(rest))
def loaded_assets(result:Result<&2,&2,String,List<&2,D.Ground>>,textures:R.Assets,count:U32,orb:Maybe<&2,U32>) -> Result<&2,&1,String,Assets>:
  match result:
    case Fail{message}: Fail{message}
    case Done{items}: Done{Assets{textures,D.Catalog{items,count,orb}}}
def finalize(loaded:BR.Loaded,requests:List<&2,Request>) -> Result<&2,&1,String,Assets>:
  BR.Loaded{R.Assets{+textures},+catalog} = loaded
  BR.Catalog{roots,source,models,+sprites,context,BR.Usage{models_count,count,text,png,pixels}} = catalog
  loaded_assets(grounds(requests,catalog,textures),R.Assets{textures},count,orb_slot(sprites))

def all_layers(names:List<&2,String>,map:Map<&2,K.Layer>) -> Map<&2,K.Layer>:
  match names:
    case Nil{}: map
    case name <> rest: all_layers(rest,Map.set(&2,K.Layer,map,name,K.Cutout{}))
def closed_resources(result:Result<&2,&1,BR.Error,BR.Loaded>,requests:List<&2,Request>) -> Result<&2,&1,String,Assets>:
  match result:
    case Fail{BR.Error{code,name,message}}: Fail{code ++ ":" ++ name ++ ":" ++ message}
    case Done{loaded}: finalize(loaded,requests)
def close_textures(archive:A.Archive,result:Result<&2,&2,BR.Error,BR.TextureWork>,roots:List<&2,String>,source:Map<&2,B.Model>,models:Map<&2,B.Resolved>,requests:List<&2,Request>) -> IO(Result<&2,&1,String,Assets>):
  do IO<Result<&2,&1,String,Assets>>:
    loaded : Result<&2,&1,BR.Error,BR.Loaded> <- BR.close_loaded(archive,result,roots,source,models)
    return closed_resources(loaded,requests)
def sprites_ready(result:Result<&2,&2,BR.Error,BR.ResolvedWork>,archive:A.Archive,+directory:A.Directory,+roots:List<&2,String>,+limits:BR.Limits,requests:List<&2,Request>) -> IO(Result<&2,&1,String,Assets>):
  match result:
    case Fail{error}:
      do IO<Result<&2,&1,String,Assets>>:
        A.Archive.close(archive)
        return Fail{"render:resource model closure refused"}
    case Done{BR.ResolvedWork{source,models,+names,usage}}:
      +sprites = List.append(&2,String,names,["minecraft:entity/experience/experience_orb"])
      do IO<Result<&2,&1,String,Assets>>:
        result : A.Archive & Result<&2,&2,BR.Error,BR.TextureWork> <- BR.sprites_loop(sprites,directory,all_layers(sprites,MTip{}),limits,archive,Done{BR.TextureWork{[],[],MTip{},usage,0}})
        P.paired(A.Archive,Result<&2,&2,BR.Error,BR.TextureWork>,IO(Result<&2,&1,String,Assets>),result,archive => result => close_textures(archive,result,roots,source,models,requests))
def models_ready(result:Result<&2,&2,BR.Error,BR.ModelWork>,archive:A.Archive,directory:A.Directory,+roots:List<&2,String>,limits:BR.Limits,requests:List<&2,Request>) -> IO(Result<&2,&1,String,Assets>):
  match result:
    case Fail{error}:
      do IO<Result<&2,&1,String,Assets>>:
        A.Archive.close(archive)
        return Fail{"render:resource model loading refused"}
    case Done{work}: sprites_ready(BR.resolved_work(work,roots),archive,directory,roots,limits,requests)
def roots(values:List<&2,Request>) -> List<&2,String>:
  match values:
    case Nil{}: []
    case Request{key,seed,item,model} <> rest: model <> roots(rest)
def request_roots(values:List<&2,Request>,out:Map<&2,Unit>) -> Map<&2,Unit>:
  match values:
    case Nil{}: out
    case Request{key,seed,item,model} <> rest: request_roots(rest,Map.set(&2,Unit,out,model,Unit{}))
def resources(+requests:List<&2,Request>,archive:A.Archive,+directory:A.Directory,+limits:BR.Limits) -> IO(Result<&2,&1,String,Assets>):
  BR.Limits{+models,depth,text,png,total,sprites,pixels,side,json} = limits
  +names = BR.sorted(Map.keys(&2,Unit,request_roots(requests,MTip{})))
  +builtin : B.Model = B.Model{None{},None{},None{},Some{B.Front{}},None{},MTip{}}
  do IO<Result<&2,&1,String,Assets>>:
    result : A.Archive & Result<&2,&2,BR.Error,BR.ModelWork> <- BR.models_loop(U32.to_nat(U32.inc(U32.mul(models,2))),directory,limits,archive,Done{BR.ModelWork{BR.tasks(names),Map.set(&2,B.Model,MTip{},"minecraft:builtin/generated",builtin),BR.empty_usage()}})
    P.paired(A.Archive,Result<&2,&2,BR.Error,BR.ModelWork>,IO(Result<&2,&1,String,Assets>),result,archive => result => models_ready(result,archive,directory,names,limits,requests))

def request_list(keys:List<&2,I.ItemKey>,+definitions:Definitions.Catalog) -> Result<&2,&2,String,List<&2,Request>>:
  match keys:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,Request>>:
        head : Request <- request(definitions,head)
        tail : List<&2,Request> <- request_list(rest,definitions)
        return head <> tail
def client_item_result(value:Result<&2,&2,String,Request>,archive:A.Archive,
    next:A.Archive -> Request -> IO(Result<&2,&1,String,Assets>)) -> IO(Result<&2,&1,String,Assets>):
  match value:
    case Fail{message}:
      do IO<Result<&2,&1,String,Assets>>:
        A.Archive.close(archive)
        return Fail{message}
    case Done{answer}: next(archive)(answer)
def client_item_pair(pair:A.Archive & Result<&2,&2,String,Request>,next:A.Archive -> Request -> IO(Result<&2,&1,String,Assets>)) -> IO(Result<&2,&1,String,Assets>):
  (archive,result) = pair
  client_item_result(result,archive,next)
def client_items(values:List<&2,Request>,+directory:A.Directory,+limits:BR.Limits,archive:A.Archive,reversed:List<&2,Request>) -> IO(Result<&2,&1,String,Assets>):
  match values:
    case Nil{}: resources(List.reverse(&2,Request,reversed),archive,directory,limits)
    case head <> rest:
      do IO<Result<&2,&1,String,Assets>>:
        result : A.Archive & Result<&2,&2,String,Request> <- item_read(head,directory,limits,archive,archive => result => IO.pure(A.Archive & Result<&2,&2,String,Request>,(archive,result)))
        client_item_pair(result,archive => head => client_items(rest,directory,limits,archive,head <> reversed))
def directory_ready(requests:List<&2,Request>,pair:A.Archive & A.Directory,limits:BR.Limits) -> IO(Result<&2,&1,String,Assets>):
  (archive,directory) = pair
  client_items(requests,directory,limits,archive,[])
def opened(result:Result<&2,&1,A.Error,A.Archive>,requests:List<&2,Request>,limits:BR.Limits) -> IO(Result<&2,&1,String,Assets>):
  match result:
    case Fail{error}: IO.pure(Result<&2,&1,String,Assets>,Fail{"render:archive open refused"})
    case Done{archive}: directory_ready(requests,A.Archive.directory(archive),limits)
def load_ready(result:Result<&2,&2,String,List<&2,Request>>,path:String,limits:BR.Limits) -> IO(Result<&2,&1,String,Assets>):
  match result:
    case Fail{message}: IO.pure(Result<&2,&1,String,Assets>,Fail{message})
    case Done{requests}:
      do IO<Result<&2,&1,String,Assets>>:
        result : Result<&2,&1,A.Error,A.Archive> <- A.load(path,A.UTF8Fallback{},A.default_limits())
        opened(result,requests,limits)
# Generic exact-key requests; caller work budgets never define product item IDs.
def load(path:String,definitions:Definitions.Catalog,keys:List<&2,I.ItemKey>,+limits:BR.Limits) -> IO(Result<&2,&1,String,Assets>):
  load_ready(request_list(keys,definitions),path,limits)
def inspect(assets:Assets) -> Assets & D.Catalog:
  Assets{textures,+catalog} = assets
  (Assets{textures,catalog},catalog)
def rendered(catalog:D.Catalog,pair:R.Assets & Result<&2,&2,M.Error,Image>) -> Assets & Result<&2,&2,M.Error,Image>:
  (textures,result) = pair
  (Assets{textures,catalog},result)

def draw(frame:D.Frame,assets:Assets,camera:R.Camera,settings:M.Settings,width:U32,height:U32) -> Assets & Result<&2,&2,M.Error,Image>:
  D.Frame{draws,quads} = frame
  Assets{textures,+catalog} = assets
  rendered(catalog,M.render(M.Scene{camera,quads,settings},textures,width,height))
