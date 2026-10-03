import Base
import ../src/block_resources.bend as R
import ../src/client_render.bend as C
import ../src/block_model.bend as B
import ../src/block_bake.bend as K
import ../src/json.bend as J
import ../src/png.bend as P
import ./block_model.bend as T

def string(value:Maybe<&2,J.Value>,fallback:String) -> String:
  match value:
    case Some{J.JString{s}}: s
    case _: fallback
def maybe_integer(value:Maybe<&2,U32>,fallback:U32) -> U32:
  match value:
    case Some{v}: v
    case _: fallback
def integer(value:Maybe<&2,J.Value>,fallback:U32) -> U32:
  match value:
    case Some{v}: maybe_integer(J.as_u32(v),fallback)
    case _: fallback
def strings(values:List<&2,J.Value>) -> List<&2,String>:
  match values:
    case J.JString{s} <> tail: s <> strings(tail)
    case _: []
def names(value:Maybe<&2,J.Value>) -> List<&2,String>:
  match value:
    case Some{J.JArray{values}}: strings(values)
    case _: []
def layer(value:J.Value) -> K.Layer:
  match value:
    case J.JString{"Cutout"}: K.Cutout{}
    case J.JString{"Translucent"}: K.Translucent{}
    case _: K.Solid{}
def layers(values:List<&2,J.Member>,map:Map<&2,K.Layer>) -> Map<&2,K.Layer>:
  match values:
    case Nil{}: map
    case J.JMember{key,value} <> tail: layers(tail,Map.set(&2,K.Layer,map,key,layer(value)))
def policy(value:Maybe<&2,J.Value>) -> R.Policy:
  match value:
    case Some{J.JObject{values}}: R.StaticNormalized{layers(values,MTip{})}
    case _: R.StaticNormalized{MTip{}}
def limits(+value:J.Value) -> R.Limits:
  R.Limits{integer(J.member(value,"models"),256),integer(J.member(value,"depth"),32),integer(J.member(value,"text"),1048576),integer(J.member(value,"png"),8388608),integer(J.member(value,"bytes"),16777216),integer(J.member(value,"sprites"),256),integer(J.member(value,"pixels"),1048576),integer(J.member(value,"side"),256),integer(J.member(value,"json"),255)}
def limits_value(value:Maybe<&2,J.Value>) -> R.Limits:
  match value:
    case Some{v}: limits(v)
    case _: R.defaults()
def layer_text(value:K.Layer) -> J.Value:
  match value:
    case K.Solid{}: T.text("Solid")
    case K.Cutout{}: T.text("Cutout")
    case K.Translucent{}: T.text("Translucent")
def text_list(values:List<&2,String>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> tail: T.text(value) <> text_list(tail)
def numbers(values:List<&2,U32>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> tail: T.number(value) <> numbers(tail)
def source_fields(names:List<&2,String>,+models:Map<&2,B.Model>) -> List<&2,J.Member>:
  match names:
    case Nil{}: []
    case +id <> tail: J.JMember{id,T.model(B.map_value(B.Model,Map.get(B.Model,B.empty_model(),models,id)))} <> source_fields(tail,models)
def query_names(names:List<&2,String>,map:Map<&2,Unit>) -> List<&2,String>:
  match names:
    case Nil{}: R.sorted(Map.keys(&2,Unit,map))
    case name <> tail: query_names(tail,Map.set(&2,Unit,map,B.strip_slot(name),Unit{}))
def resolved_one(+model:B.Resolved) -> J.Value:
  T.resolved(model,J.JArray{text_list(query_names(R.root_slots(model),MTip{}))})
def resolved_fields(names:List<&2,String>,+models:Map<&2,B.Resolved>) -> List<&2,J.Member>:
  match names:
    case Nil{}: []
    case +id <> tail: J.JMember{id,resolved_one(B.map_value(B.Resolved,Map.get(B.Resolved,B.Resolved{"",None{},[],False{},True{},B.Side{},B.Display{MTip{}},MTip{},[]},models,id)))} <> resolved_fields(tail,models)
def maybe_metadata(value:Maybe<&2,J.Value>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{v}: v
def sprite_info(value:K.Sprite) -> J.Value:
  K.Sprite{slot,u0,v0,u1,v1,layer,animated} = value
  T.object([J.JMember{"slot",T.number(slot)},J.JMember{"uv",J.JArray{[T.bits(u0),T.bits(v0),T.bits(u1),T.bits(v1)]}},J.JMember{"layer",layer_text(layer)},J.JMember{"animated",J.JBool{animated}}])
def texture_info(info:R.SpriteInfo,texture:C.Texture,context:K.Context) -> J.Value:
  R.SpriteInfo{+id,slot,+width,+height,layer,meta} = info
  C.Texture{w,h,side,image} = texture
  K.Context{sprites,missing} = context
  +sprite : K.Sprite = B.map_value(K.Sprite,Map.get(K.Sprite,K.Sprite{0,0.0,0.0,0.0,0.0,K.Solid{},True{}},sprites,id))
  T.object([J.JMember{"id",T.text(id)},J.JMember{"slot",T.number(slot)},J.JMember{"width",T.number(width)},J.JMember{"height",T.number(height)},J.JMember{"side",T.number(side)},J.JMember{"layer",layer_text(layer)},J.JMember{"metadata",maybe_metadata(meta)},J.JMember{"context",sprite_info(sprite)},J.JMember{"pixels",J.JArray{numbers(C.pixels_of(image,width,height))}}])
def texture_infos(infos:List<&2,R.SpriteInfo>,textures:List<&2,C.Texture>,+context:K.Context) -> List<&2,J.Value>:
  match infos textures:
    case info <> rest texture <> tail: texture_info(info,texture,context) <> texture_infos(rest,tail,context)
    case _ _: []
def usage(value:R.Usage) -> J.Value:
  R.Usage{models,sprites,text,png,pixels} = value
  T.object([J.JMember{"models",T.number(models)},J.JMember{"sprites",T.number(sprites)},J.JMember{"text",T.number(text)},J.JMember{"png",T.number(png)},J.JMember{"pixels",T.number(pixels)}])
def loaded(value:R.Loaded) -> J.Value:
  R.Loaded{C.Assets{textures},R.Catalog{roots,+source,+models,sprites,context,counts}} = value
  T.object([J.JMember{"status",T.text("ok")},J.JMember{"roots",J.JArray{text_list(roots)}},J.JMember{"source",T.object(source_fields(R.sorted(Map.keys(&2,B.Model,source)),source))},J.JMember{"models",T.object(resolved_fields(R.sorted(Map.keys(&2,B.Resolved,models)),models))},J.JMember{"sprites",J.JArray{texture_infos(sprites,textures,context)}},J.JMember{"usage",usage(counts)}])
def report(value:Result<&2,&1,R.Error,R.Loaded>) -> String:
  match value:
    case Fail{R.Error{code,resource,message}}: J.encode(T.object([J.JMember{"status",T.text("error")},J.JMember{"code",T.text(code)},J.JMember{"resource",T.text(resource)},J.JMember{"message",T.text(message)}]))
    case Done{value}: J.encode(loaded(value))
def pause(value:Maybe<&2,J.Value>) -> IO(Unit):
  match value:
    case Some{J.JBool{True{}}}: IO.sleep(3000)
    case _: IO.pure(Unit,Unit{})
def config(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{+value}:
      do IO<Unit>:
        result : Result<&2,&1,R.Error,R.Loaded> <- R.load(string(J.member(value,"path"),""),names(J.member(value,"roots")),policy(J.member(value,"layers")),limits_value(J.member(value,"limits")))
        IO.print(report(result))
        pause(J.member(value,"pause"))
def cases(values:List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> tail:
      do IO<Unit>:
        config(J.parse(value))
        cases(tail)
def arguments(values:List<String>) -> IO(Unit):
  match values:
    case exe <> tail: cases(tail)
    case _: IO.die(Unit,1,"expected resource configs")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
