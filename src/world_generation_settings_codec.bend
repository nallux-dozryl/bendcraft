import Base
import ./world_generation_settings.bend as W
import ./nbt.bend as N
import ./player_codec.bend as P

# This is a bounded Bendex metadata schema, not vanilla level.dat.
def max_bytes() -> U32:
  16384

def limits() -> N.Limits:
  N.Limits{16384,8,4096}

def schema(-A:Data,result:Result<&2,&2,P.Error,A>) -> Result<&2,&2,String,A>:
  match result:
    case Fail{P.SchemaError{field,message}}: Fail{field ++ ": " ++ message}
    case Fail{error}: Fail{"invalid generator settings NBT schema"}
    case Done{value}: Done{value}

def string_tag(value:String) -> N.Value:
  N.StringTag{P.text(value)}

def string_value(value:N.Value) -> Result<&2,&2,String,String>:
  match value:
    case N.StringTag{N.Text{units}}: schema(String,P.ascii_units(units,""))
    case _: Fail{"expected generator settings String tag"}

def fields(value:N.Value,names:List<&2,String>) -> Result<&2,&2,String,List<&2,P.Field>>:
  schema(List<&2,P.Field>,P.fields(value,names))

def int_value(value:N.Value,name:String) -> Result<&2,&2,String,U32>:
  schema(U32,P.int_value(value,name))

def bool_value(value:N.Value,name:String) -> Result<&2,&2,String,Bool>:
  schema(Bool,P.bool_value(value,name))

def seed_value(value:N.Value) -> Result<&2,&2,String,N.Word64>:
  match value:
    case N.Long{bits}: Done{bits}
    case _: Fail{"seed requires Long tag"}

def strings_tag(names:List<&2,String>) -> List<&2,N.Value>:
  match names:
    case Nil{}: []
    case name <> rest: string_tag(name) <> strings_tag(rest)

def strings(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,String>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        name : String <- string_value(value)
        tail : List<&2,String> <- strings(rest)
        return name <> tail

def string_list(value:N.Value) -> Result<&2,&2,String,List<&2,String>>:
  match value:
    case N.ListTag{8,values}: strings(values)
    case _: Fail{"expected String list"}

def assignments_tag(properties:List<&2,W.Assignment>) -> List<&2,N.Value>:
  match properties:
    case Nil{}: []
    case W.Assignment{name,value} <> rest:
      N.Compound{[P.member("name",string_tag(name)),P.member("value",string_tag(value))]} <> assignments_tag(rest)

def assignments(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,W.Assignment>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,W.Assignment>>:
        +fs : List<&2,P.Field> <- fields(value,["name","value"])
        name : String <- string_value(P.field(fs,"name"))
        value : String <- string_value(P.field(fs,"value"))
        tail : List<&2,W.Assignment> <- assignments(rest)
        return W.Assignment{name,value} <> tail

def properties(value:N.Value) -> Result<&2,&2,String,List<&2,W.Assignment>>:
  match value:
    case N.ListTag{10,values}: assignments(values)
    case _: Fail{"properties requires Compound list"}

def layers_tag(layers:List<&2,W.Layer>) -> List<&2,N.Value>:
  match layers:
    case Nil{}: []
    case W.Layer{height,block,properties} <> rest:
      N.Compound{[P.member("height",N.Int{height}),P.member("block",string_tag(block)),
        P.member("properties",N.ListTag{10,assignments_tag(properties)})]} <> layers_tag(rest)

def layer(value:N.Value) -> Result<&2,&2,String,W.Layer>:
  do Result<&2,&2,String,W.Layer>:
    +fs : List<&2,P.Field> <- fields(value,["height","block","properties"])
    height : U32 <- int_value(P.field(fs,"height"),"height")
    block : String <- string_value(P.field(fs,"block"))
    props : List<&2,W.Assignment> <- properties(P.field(fs,"properties"))
    return W.Layer{height,block,props}

def layers(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,W.Layer>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,W.Layer>>:
        head : W.Layer <- layer(value)
        tail : List<&2,W.Layer> <- layers(rest)
        return head <> tail

def layer_list(value:N.Value) -> Result<&2,&2,String,List<&2,W.Layer>>:
  match value:
    case N.ListTag{10,values}: layers(values)
    case _: Fail{"layers requires Compound list"}

def structures_tag(structures:Maybe<&2,List<&2,String>>) -> N.Value:
  match structures:
    case None{}: N.Compound{[P.member("specified",P.bool_tag(False{})),P.member("entries",N.ListTag{8,[]})]}
    case Some{names}: N.Compound{[P.member("specified",P.bool_tag(True{})),P.member("entries",N.ListTag{8,strings_tag(names)})]}

def structures_result(specified:Bool,names:List<&2,String>) -> Result<&2,&2,String,Maybe<&2,List<&2,String>>>:
  match specified names:
    case True{} names: Done{Some{names}}
    case False{} Nil{}: Done{None{}}
    case False{} _: Fail{"unspecified structures must have an empty entries list"}

def structures(value:N.Value) -> Result<&2,&2,String,Maybe<&2,List<&2,String>>>:
  do Result<&2,&2,String,Maybe<&2,List<&2,String>>>:
    +fs : List<&2,P.Field> <- fields(value,["specified","entries"])
    specified : Bool <- bool_value(P.field(fs,"specified"),"specified")
    names : List<&2,String> <- string_list(P.field(fs,"entries"))
    structures_result(specified,names)

def source_tag(source:W.BiomeSource) -> N.Value:
  match source:
    case W.MultiNoisePreset{preset}: N.Compound{[P.member("kind",string_tag("multi_noise_preset")),P.member("id",string_tag(preset))]}
    case W.EndBiomes{}: N.Compound{[P.member("kind",string_tag("the_end")),P.member("id",string_tag(""))]}
    case W.FixedBiome{biome}: N.Compound{[P.member("kind",string_tag("fixed")),P.member("id",string_tag(biome))]}

def source_result(kind:String,id:String) -> Result<&2,&2,String,W.BiomeSource>:
  match kind id:
    case "multi_noise_preset" id: Done{W.MultiNoisePreset{id}}
    case "the_end" "": Done{W.EndBiomes{}}
    case "fixed" id: Done{W.FixedBiome{id}}
    case _ _: Fail{"unsupported biome source metadata"}

def source(value:N.Value) -> Result<&2,&2,String,W.BiomeSource>:
  do Result<&2,&2,String,W.BiomeSource>:
    +fs : List<&2,P.Field> <- fields(value,["kind","id"])
    kind : String <- string_value(P.field(fs,"kind"))
    id : String <- string_value(P.field(fs,"id"))
    source_result(kind,id)

def generator_tag(generator:W.Generator) -> N.Value:
  match generator:
    case W.Flat{profile,biome,layers,features,lakes,structures}:
      N.Compound{[P.member("kind",string_tag("flat")),P.member("payload",N.Compound{[
        P.member("profile",string_tag(profile)),P.member("biome",string_tag(biome)),
        P.member("layers",N.ListTag{10,layers_tag(layers)}),P.member("features",P.bool_tag(features)),
        P.member("lakes",P.bool_tag(lakes)),P.member("structures",structures_tag(structures))]})]}
    case W.Noise{settings,biome_source}:
      N.Compound{[P.member("kind",string_tag("noise")),P.member("payload",N.Compound{[
        P.member("settings",string_tag(settings)),P.member("biome_source",source_tag(biome_source))]})]}

def generator_result(kind:String,value:N.Value) -> Result<&2,&2,String,W.Generator>:
  match kind:
    case "flat":
      do Result<&2,&2,String,W.Generator>:
        +fs : List<&2,P.Field> <- fields(value,["profile","biome","layers","features","lakes","structures"])
        profile : String <- string_value(P.field(fs,"profile"))
        biome : String <- string_value(P.field(fs,"biome"))
        layer_values : List<&2,W.Layer> <- layer_list(P.field(fs,"layers"))
        features : Bool <- bool_value(P.field(fs,"features"),"features")
        lakes : Bool <- bool_value(P.field(fs,"lakes"),"lakes")
        structure_values : Maybe<&2,List<&2,String>> <- structures(P.field(fs,"structures"))
        return W.Flat{profile,biome,layer_values,features,lakes,structure_values}
    case "noise":
      do Result<&2,&2,String,W.Generator>:
        +fs : List<&2,P.Field> <- fields(value,["settings","biome_source"])
        settings : String <- string_value(P.field(fs,"settings"))
        biomes : W.BiomeSource <- source(P.field(fs,"biome_source"))
        return W.Noise{settings,biomes}
    case _: Fail{"unsupported generator metadata kind"}

def generator(value:N.Value) -> Result<&2,&2,String,W.Generator>:
  do Result<&2,&2,String,W.Generator>:
    +fs : List<&2,P.Field> <- fields(value,["kind","payload"])
    kind : String <- string_value(P.field(fs,"kind"))
    generator_result(kind,P.field(fs,"payload"))

def root(settings:W.Settings) -> N.Root:
  match settings:
    case W.Unspecified{}:
      N.Root{P.text("bendex:world-generation-settings"),N.Compound{[
        P.member("format",N.Int{1}),P.member("kind",string_tag("unspecified")),P.member("payload",N.Compound{[]})]}}
    case W.Settings{dimension,min_y,height,seed,generator}:
      N.Root{P.text("bendex:world-generation-settings"),N.Compound{[
        P.member("format",N.Int{1}),P.member("kind",string_tag("settings")),P.member("payload",N.Compound{[
          P.member("dimension",string_tag(dimension)),P.member("min_y",N.Int{min_y}),P.member("height",N.Int{height}),
          P.member("seed",N.Long{seed}),P.member("generator",generator_tag(generator))]})]}}

def settings_result(kind:String,value:N.Value) -> Result<&2,&2,String,W.Settings>:
  match kind:
    case "unspecified":
      do Result<&2,&2,String,W.Settings>:
        fs : List<&2,P.Field> <- fields(value,[])
        return W.Unspecified{}
    case "settings":
      do Result<&2,&2,String,W.Settings>:
        +fs : List<&2,P.Field> <- fields(value,["dimension","min_y","height","seed","generator"])
        dimension : String <- string_value(P.field(fs,"dimension"))
        min_y : U32 <- int_value(P.field(fs,"min_y"),"min_y")
        height : U32 <- int_value(P.field(fs,"height"),"height")
        seed : N.Word64 <- seed_value(P.field(fs,"seed"))
        gen : W.Generator <- generator(P.field(fs,"generator"))
        W.validate(W.Settings{dimension,min_y,height,seed,gen})
    case _: Fail{"unsupported generator settings kind"}

def decoded(root:N.Root) -> Result<&2,&2,String,W.Settings>:
  N.Root{name,value} = root
  do Result<&2,&2,String,W.Settings>:
    name : String <- schema(String,P.read_text(name))
    W.require(String.eq(name,"bendex:world-generation-settings"),"unexpected generator settings root")
    +fs : List<&2,P.Field> <- fields(value,["format","kind","payload"])
    version : U32 <- int_value(P.field(fs,"format"),"format")
    W.require(U32.is_eq(version,1),"unsupported generator settings version")
    kind : String <- string_value(P.field(fs,"kind"))
    settings_result(kind,P.field(fs,"payload"))

def encode(settings:W.Settings) -> Result<&2,&2,String,List<&2,U32>>:
  do Result<&2,&2,String,List<&2,U32>>:
    settings : W.Settings <- W.validate(settings)
    N.encode_with(limits(),root(settings))

def decode(bytes:List<&2,U32>) -> Result<&2,&2,String,W.Settings>:
  do Result<&2,&2,String,W.Settings>:
    value : N.Root <- N.decode_with(limits(),bytes)
    decoded(value)
