import Base
import ./json.bend as J
import ./world_generation_settings.bend as WG

# The 26.3 router has eight named density inputs. Expressions remain the
# original registry JSON until the density compiler resolves them; an inline
# expression is never silently replaced with a reference or a zero constant.
type Router is Data:
  Router{chunk_surface_level:J.Value,continents:J.Value,depth:J.Value,erosion:J.Value,
    final_density:J.Value,ridges:J.Value,temperature:J.Value,vegetation:J.Value}

type Settings is Data:
  Settings{key:String,min_y:U32,height:U32,sea_level:U32,legacy_random_source:Bool,
    default_block:String,default_fluid:String,material_rule:J.Value,router:Router,
    aquifers:Maybe<&2,J.Value>,spawn_target:J.Value,debug_functions:J.Value,disable_mob_generation:Bool}

def expression_type(value:Maybe<&2,J.Value>) -> Bool:
  match value:
    case Some{J.JString{kind}}: WG.identifier(kind)
    case _: False{}

# Reuse the production JSON number automaton directly. JNumber.raw is a
# lexeme, so surrounding whitespace is not part of this contract. Validation
# does not need the general parser's formatted offset/error reporting path.
def number_tail(text:String,state:Maybe<&2,U32>) -> Bool:
  match text state:
    case SNil{} Some{current}: J.accepting(current)
    case SCon{Chr{code},rest} Some{current}: number_tail(rest,J.number_next(current,code))
    case _ None{}: False{}

def number_body(raw:String) -> Bool:
  match raw:
    case SNil{}: False{}
    case SCon{Chr{+code},rest}:
      (U32.is_eq(code,45) || J.digit(code)) && number_tail(rest,Some{J.initial_number(code)})

def number_valid(+raw:String) -> Bool:
  J.within(16384n,raw) && number_body(raw)

def expression_valid(value:J.Value) -> Bool:
  match value:
    case J.JString{id}: WG.identifier(id)
    case J.JNumber{raw}: number_valid(raw)
    case J.JObject{fields}: expression_type(J.member(J.JObject{fields},"type"))
    case _: False{}

def router_valid(router:Router) -> Bool:
  match router:
    case Router{surface,continents,depth,erosion,density,ridges,temperature,vegetation}:
      expression_valid(surface) && expression_valid(continents) && expression_valid(depth) &&
        expression_valid(erosion) && expression_valid(density) && expression_valid(ridges) &&
        expression_valid(temperature) && expression_valid(vegetation)

def valid(settings:Settings) -> Bool:
  match settings:
    case Settings{key,+min_y,+height,sea,legacy,block,fluid,material,router,aquifers,spawn,debug,mobs}:
      WG.identifier(key) && U32.is_eq(U32.and(min_y,15),0) &&
        U32.is_eq(U32.and(height,15),0) && U32.is_lt(0,height) && U32.is_le(height,2147483647) &&
        WG.signed_le(min_y,U32.sub(U32.add(min_y,height),1)) &&
        WG.identifier(block) && WG.identifier(fluid) && expression_valid(material) && router_valid(router)

def validated(settings:Settings,valid:Bool) -> Result<&2,&2,String,Settings>:
  match valid:
    case True{}: Done{settings}
    case False{}: Fail{"invalid noise settings geometry, identifier or router expression"}

def validate(+settings:Settings) -> Result<&2,&2,String,Settings>:
  validated(settings,valid(settings))
