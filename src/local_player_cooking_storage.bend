import Base
import ./core.bend as C
import ./nbt.bend as N
import ./player_codec.bend as P
import ./player_inventory_codec.bend as I
import ./player_item_definitions.bend as D
import ./world_generation_settings.bend as WG
import ./extended_persistence.bend as E
import ./cooking_block_entity_codec.bend as CB
import ./cooking_world_store.bend as Store
import ./cooking_effect_recovery.bend as Effects

# The inventory ABI and existing empty-cooking payload remain intact. Cooking
# bodies travel inside the same Core/extension atomic publication, never in a
# separately acknowledged file. Live world discovery admits these bodies.
type Body is Data:
  Body{position:C.Position,bytes:List<&2,U32>}
type Saved is Type:
  Saved{player:I.Saved,bodies:List<&2,Body>,pending:List<&2,Store.Effect>}

def nbt_limits() -> N.Limits:
  N.default_limits()

def limits() -> E.Limits:
  E.Limits{E.core_limits(E.default_limits()),16777216,
    U32.add(E.file_limit(E.default_limits()),16777216)}

def same_position(a:C.Position,b:C.Position) -> Bool:
  C.Position{dimension,x,y,z} = a
  C.Position{other,ox,oy,oz} = b
  String.eq(dimension,other) && U32.is_eq(x,ox) && U32.is_eq(y,oy) && U32.is_eq(z,oz)

def has_position(values:List<&2,Body>,+position:C.Position) -> Bool:
  match values:
    case Nil{}: False{}
    case Body{candidate,bytes} <> rest:
      same_position(position,candidate) || has_position(rest,position)

def unique_bodies(values:List<&2,Body>) -> Bool:
  match values:
    case Nil{}: True{}
    case Body{+position,bytes} <> +rest:
      Bool.not(has_position(rest,position)) && unique_bodies(rest)

def body_value(body:Body) -> N.Value:
  Body{C.Position{dimension,x,y,z},bytes} = body
  N.Compound{[P.member("dimension",N.StringTag{P.text(dimension)}),
    P.member("x",N.Int{x}),P.member("y",N.Int{y}),P.member("z",N.Int{z}),
    P.member("body",N.ByteArray{bytes})]}

def body_values(values:List<&2,Body>) -> List<&2,N.Value>:
  match values:
    case Nil{}: []
    case head <> rest: body_value(head) <> body_values(rest)

def root(player:List<&2,U32>,bodies:List<&2,Body>) -> N.Root:
  N.Root{P.text("bendex:local-player-cooking-record"),N.Compound{[
    P.member("format",N.Int{1}),P.member("player",N.ByteArray{player}),
    P.member("bodies",N.ListTag{10,body_values(bodies)})]}}

def payload(+bodies:List<&2,Body>,player:List<&2,U32>) -> Result<&2,&2,String,List<&2,U32>>:
  match bodies:
    case Nil{}: Done{player}
    case head <> rest:
      do Result<&2,&2,String,List<&2,U32>>:
        I.require(unique_bodies(bodies),"duplicate cooking body position")
        N.encode_with(nbt_limits(),root(player,bodies))

def recovery_root(player:List<&2,U32>,bodies:List<&2,Body>,effects:List<&2,U32>) -> N.Root:
  N.Root{P.text("bendex:local-player-cooking-record"),N.Compound{[
    P.member("format",N.Int{2}),P.member("player",N.ByteArray{player}),
    P.member("bodies",N.ListTag{10,body_values(bodies)}),
    P.member("effects",N.ByteArray{effects})]}}

def payload_pending(+bodies:List<&2,Body>,pending:List<&2,Store.Effect>,player:List<&2,U32>) -> Result<&2,&2,String,List<&2,U32>>:
  match pending:
    case Nil{}: payload(bodies,player)
    case head <> rest:
      do Result<&2,&2,String,List<&2,U32>>:
        I.require(unique_bodies(bodies),"duplicate cooking body position")
        effects : List<&2,U32> <- Effects.encode(nbt_limits(),head <> rest)
        N.encode_with(nbt_limits(),recovery_root(player,bodies,effects))

def encoded(+bodies:List<&2,Body>,+pending:List<&2,Store.Effect>,result:I.Saved & Result<&2,&2,String,List<&2,U32>>) -> Saved & Result<&2,&2,String,List<&2,U32>>:
  (player,status) = result
  (Saved{player,bodies,pending},Result.bind(&2,&2,String,List<&2,U32>,List<&2,U32>,status,
    bytes => payload_pending(bodies,pending,bytes)))

def encode(saved:Saved) -> Saved & Result<&2,&2,String,List<&2,U32>>:
  Saved{player,bodies,pending} = saved
  encoded(bodies,pending,I.encode(player))

def body_decoded(value:N.Value) -> Result<&2,&2,String,Body>:
  do Result<&2,&2,String,Body>:
    +fields : List<&2,P.Field> <- I.schema(List<&2,P.Field>,P.fields(value,["dimension","x","y","z","body"]))
    dimension : String <- I.string_value(P.field(fields,"dimension"))
    x : U32 <- I.schema(U32,P.int_value(P.field(fields,"x"),"x"))
    y : U32 <- I.schema(U32,P.int_value(P.field(fields,"y"),"y"))
    z : U32 <- I.schema(U32,P.int_value(P.field(fields,"z"),"z"))
    bytes : List<&2,U32> <- I.byte_array(P.field(fields,"body"))
    return Body{C.Position{dimension,x,y,z},bytes}

def body_position(body:Body) -> C.Position:
  Body{position,bytes} = body
  position

def body_list(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,Body>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,Body>>:
        +body : Body <- body_decoded(head)
        +tail : List<&2,Body> <- body_list(rest)
        I.require(Bool.not(has_position(tail,body_position(body))),"duplicate cooking body position")
        return body <> tail

def bodies_value(value:N.Value) -> Result<&2,&2,String,List<&2,Body>>:
  match value:
    case N.ListTag{10,values}: body_list(values)
    case _: Fail{"cooking bodies require Compound list"}

def wrap(bodies:List<&2,Body>,pending:List<&2,Store.Effect>,result:Result<&2,&1,String,I.Saved>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{player}: Done{Saved{player,bodies,pending}}

type Projection is Data:
  Projection{player:List<&2,U32>,bodies:List<&2,Body>,pending:List<&2,Store.Effect>}

def projection_legacy(value:N.Value) -> Result<&2,&2,String,Projection>:
  do Result<&2,&2,String,Projection>:
    +fields : List<&2,P.Field> <- I.schema(List<&2,P.Field>,P.fields(value,["format","player","bodies"]))
    format : U32 <- I.schema(U32,P.int_value(P.field(fields,"format"),"format"))
    I.require(U32.is_eq(format,1),"unsupported cooking payload format")
    player : List<&2,U32> <- I.byte_array(P.field(fields,"player"))
    bodies : List<&2,Body> <- bodies_value(P.field(fields,"bodies"))
    return Projection{player,bodies,[]}

def projection_recovery(value:N.Value) -> Result<&2,&2,String,Projection>:
  do Result<&2,&2,String,Projection>:
    +fields : List<&2,P.Field> <- I.schema(List<&2,P.Field>,P.fields(value,["format","player","bodies","effects"]))
    format : U32 <- I.schema(U32,P.int_value(P.field(fields,"format"),"format"))
    I.require(U32.is_eq(format,2),"unsupported cooking recovery payload format")
    player : List<&2,U32> <- I.byte_array(P.field(fields,"player"))
    bodies : List<&2,Body> <- bodies_value(P.field(fields,"bodies"))
    bytes : List<&2,U32> <- I.byte_array(P.field(fields,"effects"))
    +pending : List<&2,Store.Effect> <- Effects.decode(nbt_limits(),bytes)
    I.require(Bool.not(List.is_empty(&2,Store.Effect,pending)),"empty cooking recovery payload")
    return Projection{player,bodies,pending}

def projection_shape(value:N.Value,legacy:Bool) -> Result<&2,&2,String,Projection>:
  match legacy:
    case True{}: projection_legacy(value)
    case False{}: projection_recovery(value)

# Each selected schema still requires exactly its fields and its version.
# This avoids accepting optional, duplicate or unknown wrapper members.
def projection(value:N.Value) -> Result<&2,&2,String,Projection>:
  match value:
    case N.Compound{+members}:
      projection_shape(N.Compound{members},Nat.is_eq(List.length(&2,N.Member,members),3n))
    case _: Fail{"cooking payload requires Compound"}

def projected(definitions:D.Catalog,result:Result<&2,&2,String,Projection>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Projection{player,bodies,pending}}: wrap(bodies,pending,I.decode_with(definitions,1,player))

def cooking_root(definitions:D.Catalog,root:N.Root) -> Result<&2,&1,String,Saved>:
  N.Root{name,value} = root
  projected(definitions,projection(value))

def named(+definitions:D.Catalog,+root:N.Root,result:Result<&2,&2,String,String>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{"bendex:local-player-cooking-record"}: cooking_root(definitions,root)
    case Done{other}: wrap([],[],I.decoded_with(definitions,Done{root}))

def parsed(definitions:D.Catalog,result:Result<&2,&2,String,N.Root>) -> Result<&2,&1,String,Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{+root}:
      N.Root{name,value} = root
      named(definitions,root,I.schema(String,P.read_text(name)))

def decode_with(definitions:D.Catalog,schema:U32,bytes:List<&2,U32>) -> Result<&2,&1,String,Saved>:
  match schema:
    case 1: parsed(definitions,N.decode_with(nbt_limits(),bytes))
    case _: Fail{"unsupported local-player-record schema"}

def initial_with(definitions:D.Catalog,creative:Bool,generation:WG.Settings,unit:Unit) -> Result<&2,&1,String,Saved>:
  wrap([],[],I.initial_with(definitions,creative,generation,unit))

def refuse_core_only(unit:Unit) -> Result<&2,&1,String,Saved>:
  Fail{"Core-only or plain-Player saves require explicit LocalPlayer migration"}

def codec_with(+definitions:D.Catalog,creative:Bool,generation:WG.Settings) -> E.Codec<Saved>:
  E.Codec{"bendex:local-player-record",1,encode,schema => bytes => decode_with(definitions,schema,bytes),
    unit => initial_with(definitions,creative,generation,unit),refuse_core_only}

# The physical cooking encoder supplies known fields; the live sidecar supplies
# the exact unconsumed root name and unknown/base fields from the accepted load.
def merged_root(limits:N.Limits,details:CB.Details,result:Result<&2,&2,String,N.Root>) -> Result<&2,&2,String,List<&2,U32>>:
  CB.Details{name,extras,inputs,admission,discarded} = details
  match result:
    case Fail{message}: Fail{message}
    case Done{N.Root{old,N.Compound{members}}}:
      N.encode_with(limits,N.Root{name,N.Compound{List.append(&2,N.Member,members,extras)}})
    case _: Fail{"cooking body requires Compound root"}

def with_details(+limits:N.Limits,bytes:List<&2,U32>,details:Maybe<&2,CB.Details>) -> Result<&2,&2,String,List<&2,U32>>:
  match details:
    case None{}: Done{bytes}
    case Some{details}: merged_root(limits,details,N.decode_with(limits,bytes))
