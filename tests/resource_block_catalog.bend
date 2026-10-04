import Base
import ../src/resource_block_catalog.bend as C
import ../src/resource_block_catalog_load.bend as CL
import ../src/resource_block_catalog_profile.bend as P
import ../src/registry.bend as G
import ../src/blockstate_model.bend as S
import ../src/block_resources.bend as BR
import ../src/block_bake.bend as K
import ../src/world_mesh.bend as WM
import ../src/client_render.bend as R
import ../src/json.bend as J

# Native IO observer: all catalog/registry/dispatch/resource/bake behavior is
# supplied by unchanged production imports. Helpers only decode test commands
# and serialize production values; no model/registry algorithm is reproduced.
def text(value:String) -> J.Value:
  J.JString{value}
def number(value:U32) -> J.Value:
  J.JNumber{U32.show(value)}
def obj(value:List<&2,J.Member>) -> J.Value:
  J.JObject{value}
def string(value:Maybe<&2,J.Value>,fallback:String) -> String:
  match value:
    case Some{J.JString{value}}: value
    case _: fallback
def integer_value(value:Maybe<&2,U32>,fallback:U32) -> U32:
  match value:
    case Some{value}: value
    case _: fallback
def integer(value:Maybe<&2,J.Value>,fallback:U32) -> U32:
  match value:
    case Some{value}: integer_value(J.as_u32(value),fallback)
    case _: fallback
def boolean(value:Maybe<&2,J.Value>) -> Bool:
  match value:
    case Some{J.JBool{value}}: value
    case _: False{}
def values(value:Maybe<&2,J.Value>) -> List<&2,J.Value>:
  match value:
    case Some{J.JArray{values}}: values
    case _: []
def members(value:Maybe<&2,J.Value>) -> List<&2,J.Member>:
  match value:
    case Some{J.JObject{values}}: values
    case _: []
def string_values(values:List<&2,String>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: text(value) <> string_values(rest)
def strings(values:List<&2,String>) -> J.Value:
  J.JArray{string_values(values)}
def assignments(values:List<&2,G.Assignment>) -> List<&2,J.Member>:
  match values:
    case Nil{}: []
    case G.Assignment{name,value} <> rest: J.JMember{name,text(value)} <> assignments(rest)
def identity(value:G.Resolved) -> J.Value:
  G.Resolved{protocol,name,state,properties} = value
  obj([J.JMember{"block_protocol_id",number(protocol)},J.JMember{"identifier",text(name)},
    J.JMember{"id",number(state)},J.JMember{"properties",obj(assignments(properties))}])
def variant(value:S.Variant) -> J.Value:
  S.Variant{model,x,y,z,lock} = value
  obj([J.JMember{"model",text(model)},J.JMember{"x",number(x)},J.JMember{"y",number(y)},
    J.JMember{"z",number(z)},J.JMember{"uvlock",J.JBool{lock}}])
def variants(values:List<&2,S.Variant>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: variant(value) <> variants(rest)
def weighted(values:List<&2,S.Weighted>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case S.Weighted{value,weight} <> rest: obj([J.JMember{"variant",variant(value)},J.JMember{"weight",number(weight)}]) <> weighted(rest)
def choice(value:S.Choice) -> J.Value:
  match value:
    case S.Single{value}: obj([J.JMember{"kind",text("single")},J.JMember{"variant",variant(value)}])
    case S.WeightedChoice{values,total}: obj([J.JMember{"kind",text("weighted")},J.JMember{"total",number(total)},J.JMember{"entries",J.JArray{weighted(values)}}])
def parts(values:List<&2,S.SelectedPart>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case S.SelectedPart{index,value} <> rest: obj([J.JMember{"index",number(index)},J.JMember{"choice",choice(value)}]) <> parts(rest)
def root(value:S.Root) -> J.Value:
  match value:
    case S.VariantRoot{value}: obj([J.JMember{"kind",text("variant")},J.JMember{"choice",choice(value)}])
    case S.MultipartRoot{values,names}: obj([J.JMember{"kind",text("multipart")},J.JMember{"parts",J.JArray{parts(values)}}])
def maybe_root(value:Maybe<&2,S.Root>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{value}: root(value)
def dependencies(value:Maybe<&2,S.Root>) -> J.Value:
  match value:
    case None{}: strings([])
    case Some{value}: strings(S.dependencies(value))
def mode(value:C.Mode) -> J.Value:
  match value:
    case C.Model{}: text("model")
    case C.Invisible{}: text("invisible")
    case C.Unsupported{renderer}: obj([J.JMember{"unsupported",text(renderer)}])
def entry(+value:C.Entry) -> J.Value:
  C.Entry{found,kind,+compiled} = value
  obj([J.JMember{"identity",identity(found)},J.JMember{"mode",mode(kind)},
    J.JMember{"root",maybe_root(compiled)},J.JMember{"dependencies",dependencies(compiled)}])
def error(value:C.Error) -> List<&2,J.Member>:
  C.Error{code,resource,detail} = value
  [J.JMember{"status",text("error")},J.JMember{"code",text(code)},
    J.JMember{"resource",text(resource)},J.JMember{"detail",text(detail)}]
def layer(value:K.Layer) -> J.Value:
  match value:
    case K.Solid{}: text("solid")
    case K.Cutout{}: text("cutout")
    case K.Translucent{}: text("translucent")
def quad(value:K.Baked) -> J.Value:
  K.Baked{a,b,c,d,direction,cullface,sprite,texture,tint,light,shade,kind,force,animated,normal,nether} = value
  obj([J.JMember{"sprite",text(sprite)},J.JMember{"texture",number(texture)},
    J.JMember{"layer",layer(kind)},J.JMember{"tintindex",number(tint)},
    J.JMember{"force_translucent",J.JBool{force}},J.JMember{"animated",J.JBool{animated}}])
def quads(values:List<&2,K.Baked>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: quad(value) <> quads(rest)
def bound(value:Result<&2,&2,C.Error,C.Bound>) -> J.Value:
  match value:
    case Fail{value}: obj(error(value))
    case Done{C.Bound{found,selected,WM.Binding{state,+baked,appearance}}}:
      obj([J.JMember{"status",text("ok")},J.JMember{"identity",identity(found)},
        J.JMember{"variants",J.JArray{variants(selected)}},J.JMember{"state",number(state)},
        J.JMember{"quad_count",J.JNumber{Nat.show(List.length(&2,K.Baked,baked))}},
        J.JMember{"quads",J.JArray{quads(baked)}}])
def tickets(values:List<&2,J.Member>,out:Map<&2,U32>) -> Map<&2,U32>:
  match values:
    case Nil{}: out
    case J.JMember{name,value} <> rest: tickets(rest,Map.set(&2,U32,out,name,integer(Some{value},0)))
def ticket(value:Maybe<&2,J.Value>) -> Maybe<&2,U32>:
  match value:
    case Some{value}: J.as_u32(value)
    case _: None{}
def selection_first(first:Bool,+query:J.Value,value:C.Entry) -> C.Selection:
  match first:
    case True{}: C.first_selection(value)
    case False{}: C.Selection{ticket(J.member(query,"ticket")),tickets(members(J.member(query,"parts")),MTip{})}
def selection(+query:J.Value,value:C.Entry) -> C.Selection:
  selection_first(boolean(J.member(query,"first")),query,value)
def query_found(value:Result<&2,&2,C.Error,C.Entry>,+catalog:C.Catalog,+query:J.Value,+state:U32) -> J.Value:
  match value:
    case Fail{value}: obj(J.JMember{"state",number(state)} <> error(value))
    case Done{+found}:
      obj([J.JMember{"state",number(state)},J.JMember{"lookup",entry(found)},
        J.JMember{"bound",bound(C.bind(catalog,state,selection(query,found),WM.appearance()))}])
def query_values(values:List<&2,J.Value>,+catalog:C.Catalog) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case +value <> rest:
      +state = integer(J.member(value,"state"),0)
      query_found(C.lookup(catalog,state),catalog,value,state) <> query_values(rest,catalog)
def request_mode(+name:String,kind:String,renderer:String) -> C.Request:
  match kind:
    case "model": C.Request{name,C.Model{}}
    case "invisible": C.Request{name,C.Invisible{}}
    case "unsupported": C.Request{name,C.Unsupported{renderer}}
    case _: C.Request{name,P.vanilla_mode(name)}
def request(+value:J.Value) -> C.Request:
  request_mode(string(J.member(value,"name"),""),string(J.member(value,"mode"),"profile"),string(J.member(value,"renderer"),"custom"))
def request_values(values:List<&2,J.Value>) -> List<&2,C.Request>:
  match values:
    case Nil{}: []
    case value <> rest: request(value) <> request_values(rest)
def requests(value:Maybe<&2,J.Value>) -> List<&2,C.Request>:
  match value:
    case Some{J.JArray{values}}: request_values(values)
    case _: P.static_requests()
def layer_value(value:J.Value) -> K.Layer:
  match value:
    case J.JString{"cutout"}: K.Cutout{}
    case J.JString{"translucent"}: K.Translucent{}
    case _: K.Solid{}
def layers(values:List<&2,J.Member>,out:Map<&2,K.Layer>) -> Map<&2,K.Layer>:
  match values:
    case Nil{}: out
    case J.JMember{name,value} <> rest: layers(rest,Map.set(&2,K.Layer,out,name,layer_value(value)))
def policy(value:Maybe<&2,J.Value>) -> BR.Policy:
  match value:
    case Some{J.JObject{values}}: BR.StaticNormalized{layers(values,MTip{})}
    case _: P.static_policy()
def resource_limits(+value:J.Value) -> BR.Limits:
  BR.Limits{integer(J.member(value,"models"),256),integer(J.member(value,"depth"),32),
    integer(J.member(value,"text"),1048576),integer(J.member(value,"png"),8388608),
    integer(J.member(value,"bytes"),16777216),integer(J.member(value,"sprites"),256),
    integer(J.member(value,"pixels"),1048576),integer(J.member(value,"side"),256),integer(J.member(value,"json"),255)}
def resources(value:Maybe<&2,J.Value>) -> BR.Limits:
  match value:
    case Some{value}: resource_limits(value)
    case _: BR.defaults()
def limits(+value:J.Value) -> C.Limits:
  C.Limits{integer(J.member(value,"max_blocks"),256),integer(J.member(value,"max_states"),65535),
    integer(J.member(value,"max_state_text"),1048576),resources(J.member(value,"resources"))}
def registry_decoded(result:Result<&2,&2,G.Error,G.Resolved>) -> J.Value:
  match result:
    case Done{value}: identity(value)
    case Fail{value}: obj([J.JMember{"registry_error",text(G.error_text(value))}])
def registry_after(value:G.Registry & Result<&2,&2,G.Error,G.Resolved>) -> J.Value:
  (registry,result) = value
  registry_decoded(result)
def numbers(values:List<&2,U32>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: number(value) <> numbers(rest)
def sprite(info:BR.SpriteInfo,texture:R.Texture) -> J.Value:
  BR.SpriteInfo{name,slot,width,height,kind,metadata} = info
  R.Texture{+w,+h,side,image} = texture
  obj([J.JMember{"id",text(name)},J.JMember{"slot",number(slot)},J.JMember{"width",number(width)},
    J.JMember{"height",number(height)},J.JMember{"layer",layer(kind)},
    J.JMember{"texture_width",number(w)},J.JMember{"texture_height",number(h)},J.JMember{"side",number(side)},
    J.JMember{"pixels",J.JArray{numbers(R.pixels_of(image,w,h))}}])
def sprites(values:List<&2,BR.SpriteInfo>,textures:List<&2,R.Texture>) -> List<&2,J.Value>:
  match values textures:
    case Nil{} Nil{}: []
    case value <> rest texture <> tail: sprite(value,texture) <> sprites(rest,tail)
    case _ _: [obj([J.JMember{"error",text("SpriteAssetCountMismatch")}])]
def usage(value:BR.Usage) -> J.Value:
  BR.Usage{models,sprites,text,png,pixels} = value
  obj([J.JMember{"models",number(models)},J.JMember{"sprites",number(sprites)},J.JMember{"text",number(text)},
    J.JMember{"png",number(png)},J.JMember{"pixels",number(pixels)}])
def loaded_fields(+catalog:C.Catalog,+config:J.Value,after:J.Value,textures:List<&2,R.Texture>) -> List<&2,J.Member>:
  C.Catalog{registry,entries,BR.Catalog{roots,source,models,infos,context,counts}} = catalog
  [J.JMember{"status",text("ok")},J.JMember{"registry_identity",text(registry)},J.JMember{"registry_after",after},
    J.JMember{"model_roots",strings(roots)},J.JMember{"sprites",J.JArray{sprites(infos,textures)}},J.JMember{"usage",usage(counts)},
    J.JMember{"queries",J.JArray{query_values(values(J.member(config,"queries")),catalog)}}]
def load_report_result(result:Result<&2,&1,C.Error,CL.Loaded>,+config:J.Value,after:J.Value) -> J.Value:
  match result:
    case Fail{value}: obj(J.JMember{"registry_after",after} <> error(value))
    case Done{CL.Loaded{R.Assets{textures},catalog}}: obj(loaded_fields(catalog,config,after,textures))
def load_report(value:G.Registry & Result<&2,&1,C.Error,CL.Loaded>,+config:J.Value) -> J.Value:
  (registry,result) = value
  load_report_result(result,config,registry_after(G.Registry.decode(registry,0)))
def registry_loaded(result:Result<&2,&1,G.Error,G.Registry>,+config:J.Value) -> IO(J.Value):
  match result:
    case Fail{value}: IO.pure(J.Value,obj([J.JMember{"status",text("registry_error")},J.JMember{"detail",text(G.error_text(value))}]))
    case Done{registry}:
      do IO<J.Value>:
        result:G.Registry & Result<&2,&1,C.Error,CL.Loaded> <- CL.load(string(J.member(config,"jar"),""),registry,
          requests(J.member(config,"requests")),policy(J.member(config,"layers")),limits(config))
        return load_report(result,config)

# A pure generic path also exercises catalog planning and root selection under
# arbitrary registry names. Synthetic archives in the Python driver separately
# exercise the same names through the real IO loader and geometry assembler.
def generic_block() -> C.Block:
  C.Block{G.Block{0,"test:signal",0,2,0,[G.Property{"lit",["false","true"],2,1}]},C.Model{}}
def generic_variant() -> S.Definition:
  S.Definition{Some{[S.Selector{"lit=false",S.Single{S.Variant{"test:block/off",0,0,0,False{}}}},
    S.Selector{"lit=true",S.Single{S.Variant{"test:block/on",0,90,0,True{}}}}]},None{}}
def generic_parts() -> S.Definition:
  S.Definition{None{},Some{[S.Part{None{},S.Single{S.Variant{"test:block/base",0,0,0,False{}}}},
    S.Part{Some{S.KeyValues{[S.Test{"lit",[S.Term{"true",False{}}]}]}},
      S.WeightedChoice{[S.Weighted{S.Variant{"test:block/on",0,90,0,True{}},1},
        S.Weighted{S.Variant{"test:block/alternate",0,180,0,False{}},3}],4}}]}}
def selected_report(result:Result<&2,&2,C.Error,List<&2,S.Variant>>) -> J.Value:
  match result:
    case Fail{value}: obj(error(value))
    case Done{values}: obj([J.JMember{"status",text("ok")},J.JMember{"variants",J.JArray{variants(values)}}])
def pure_found(result:Result<&2,&2,C.Error,C.Entry>,+query:J.Value,+state:U32) -> J.Value:
  match result:
    case Fail{value}: obj(J.JMember{"state",number(state)} <> error(value))
    case Done{+value}: obj([J.JMember{"state",number(state)},J.JMember{"lookup",entry(value)},
      J.JMember{"selected",selected_report(C.selected(value,selection(query,value)))}])
def pure_queries(values:List<&2,J.Value>,+catalog:C.Catalog) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case +value <> rest:
      +state = integer(J.member(value,"state"),0)
      pure_found(C.lookup(catalog,state),value,state) <> pure_queries(rest,catalog)
def plan_report(result:Result<&2,&2,C.Error,C.Plan>,+queries:List<&2,J.Value>) -> J.Value:
  match result:
    case Fail{value}: obj(error(value))
    case Done{C.Plan{registry,entries,models,count}}:
      +catalog:C.Catalog = C.Catalog{registry,entries,BR.Catalog{[],MTip{},MTip{},[],K.Context{MTip{},None{}},BR.empty_usage()}}
      obj([J.JMember{"status",text("ok")},J.JMember{"states",number(count)},
        J.JMember{"models",strings(BR.sorted(Map.keys(&2,Unit,models)))},
        J.JMember{"queries",J.JArray{pure_queries(queries,catalog)}}])
def forged(+config:J.Value) -> J.Value:
  +catalog:C.Catalog = C.Catalog{"synthetic-registry-identity",Map.set(&2,C.Entry,MTip{},"0",
    C.Entry{G.Resolved{0,"test:forged",1,[]},C.Model{},Some{S.VariantRoot{S.Single{S.Variant{"test:block/off",0,0,0,False{}}}}}}),
    BR.Catalog{[],MTip{},MTip{},[],K.Context{MTip{},None{}},BR.empty_usage()}}
  obj([J.JMember{"status",text("ok")},J.JMember{"queries",J.JArray{pure_queries(values(J.member(config,"queries")),catalog)}}])
def generic_regular(+config:J.Value) -> J.Value:
  definition = S.choose_value(S.Definition,generic_parts(),generic_variant(),String.eq(string(J.member(config,"kind"),"variant"),"multipart"))
  plan_report(C.prepared_block(generic_block(),definition,C.Plan{"synthetic-registry-identity",MTip{},MTip{},0},C.defaults()),values(J.member(config,"queries")))
def generic_kind(kind:String,+config:J.Value) -> J.Value:
  match kind:
    case "forged": forged(config)
    case _: generic_regular(config)
def generic(+config:J.Value) -> J.Value:
  generic_kind(string(J.member(config,"kind"),"variant"),config)
def dispatch(kind:String,+value:J.Value) -> IO(Unit):
  match kind:
    case "pure": IO.print(J.encode(generic(value)))
    case _:
      do IO<Unit>:
        registry:Result<&2,&1,G.Error,G.Registry> <- G.Registry.load(string(J.member(value,"registry"),"generated/reference_blocks.tsv"))
        report:J.Value <- registry_loaded(registry,value)
        IO.print(J.encode(report))
def config(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{value}: IO.die(Unit,1,value)
    case Done{+value}: dispatch(string(J.member(value,"mode"),"io"),value)
def configs(values:List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        config(J.parse(value))
        configs(rest)
def arguments(values:List<String>) -> IO(Unit):
  match values:
    case exe <> rest: configs(rest)
    case _: IO.die(Unit,1,"expected catalog test configs")
def main() -> IO(Unit):
  do IO<Unit>:
    args:List<String> <- IO.args()
    arguments(args)
