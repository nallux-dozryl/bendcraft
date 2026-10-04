import Base
import ./json.bend as J
import ./worldgen_noise_settings.bend as NS

# This metadata decoder preserves every 26.3 vanilla noise-settings field.
# Density/aquifer/material expressions are handed intact to their respective
# compilers. It does not claim to have evaluated those expressions.
def field_result(key:String,result:Maybe<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  match result:
    case None{}: Fail{"missing noise-settings field: " ++ key}
    case Some{item}: Done{item}

def field(value:J.Value,+key:String) -> Result<&2,&2,String,J.Value>:
  field_result(key,J.member(value,key))

def string(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{text}: Done{text}
    case _: Fail{"noise-settings string required"}

def boolean(value:J.Value) -> Result<&2,&2,String,Bool>:
  match value:
    case J.JBool{flag}: Done{flag}
    case _: Fail{"noise-settings boolean required"}

def integer_range(word:U32,valid:Bool) -> Result<&2,&2,String,U32>:
  match valid:
    case True{}: Done{word}
    case False{}: Fail{"noise-settings integer outside signed32"}

# Canonical integer tokens are the metadata boundary currently admitted.
# Noncanonical numeric coercions are refused, never truncated or wrapped.
def magnitude(value:Maybe<&2,U32>,negative:Bool) -> Result<&2,&2,String,U32>:
  match value negative:
    case Some{+word} True{}:
      integer_range(U32.sub(0,word),U32.is_le(word,2147483648))
    case Some{+word} False{}: integer_range(word,U32.is_le(word,2147483647))
    case _ _: Fail{"noise-settings integer required"}

def integer(value:J.Value) -> Result<&2,&2,String,U32>:
  match value:
    case J.JNumber{SCon{Chr{45},rest}}: magnitude(J.u32_lexeme(rest),True{})
    case J.JNumber{raw}: magnitude(J.u32_lexeme(raw),False{})
    case _: Fail{"noise-settings integer required"}

def object(value:J.Value) -> Result<&2,&2,String,J.Value>:
  match value:
    case J.JObject{members}: Done{J.JObject{members}}
    case _: Fail{"noise-settings object required"}

def list(value:J.Value) -> Result<&2,&2,String,J.Value>:
  match value:
    case J.JArray{items}: Done{J.JArray{items}}
    case _: Fail{"noise-settings array required"}

def aquifer_object(result:Result<&2,&2,String,J.Value>) -> Result<&2,&2,String,Maybe<&2,J.Value>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: Done{Some{value}}

def aquifers(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,Maybe<&2,J.Value>>:
  match value:
    case None{}: Done{None{}}
    case Some{item}: aquifer_object(object(item))

def debug_functions(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  match value:
    case None{}: Done{J.JArray{[]}}
    case Some{item}: list(item)

def read_router(value:J.Value) -> Result<&2,&2,String,NS.Router>:
  do Result<&2,&2,String,NS.Router>:
    +router : J.Value <- object(value)
    surface : J.Value <- field(router,"chunk_surface_level")
    continents : J.Value <- field(router,"continents")
    depth : J.Value <- field(router,"depth")
    erosion : J.Value <- field(router,"erosion")
    density : J.Value <- field(router,"final_density")
    ridges : J.Value <- field(router,"ridges")
    temperature : J.Value <- field(router,"temperature")
    vegetation : J.Value <- field(router,"vegetation")
    return NS.Router{surface,continents,depth,erosion,density,ridges,temperature,vegetation}

def read(key:String,value:J.Value) -> Result<&2,&2,String,NS.Settings>:
  do Result<&2,&2,String,NS.Settings>:
    +root : J.Value <- object(value)
    shape_value : J.Value <- field(root,"noise")
    +shape : J.Value <- object(shape_value)
    bottom_value : J.Value <- field(shape,"min_y")
    bottom : U32 <- integer(bottom_value)
    height_value : J.Value <- field(shape,"height")
    height : U32 <- integer(height_value)
    sea_value : J.Value <- field(root,"sea_level")
    sea : U32 <- integer(sea_value)
    legacy_value : J.Value <- field(root,"legacy_random_source")
    legacy : Bool <- boolean(legacy_value)
    block_value : J.Value <- field(root,"default_block")
    block : String <- string(block_value)
    fluid_value : J.Value <- field(root,"default_fluid")
    fluid : String <- string(fluid_value)
    material : J.Value <- field(root,"material_rule")
    router_value : J.Value <- field(root,"noise_router")
    router : NS.Router <- read_router(router_value)
    aquifers : Maybe<&2,J.Value> <- aquifers(J.member(root,"aquifers"))
    spawn_value : J.Value <- field(root,"spawn_target")
    spawn : J.Value <- list(spawn_value)
    debug : J.Value <- debug_functions(J.member(root,"debug_functions"))
    mobs_value : J.Value <- field(root,"disable_mob_generation")
    mobs : Bool <- boolean(mobs_value)
    NS.validate(NS.Settings{key,bottom,height,sea,legacy,block,fluid,material,router,aquifers,spawn,debug,mobs})
