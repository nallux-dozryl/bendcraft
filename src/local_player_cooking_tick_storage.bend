import Base
import ./local_player_effect_tick_recovery.bend as Q
import ./local_player_effect_tick_recovery_codec.bend as Codec
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./local_player_effect_entities_codec.bend as Raw
import ./random.bend as R
import ./nbt.bend as N
import ./entity_section_membership_model.bend as M
import ./entity_membership_codec.bend as Membership

# The format5 component has one entity image, inside Q.Recovery. Constructor
# clock inputs are the real remaining ordered source, independent of all RNGs.
# CS will own the outer player/body/effect/publication schema and old versions.
type Stored is Data:
  Stored{recovery:Q.Recovery,clock_inputs:List<&2,R.Bits64>,membership:Maybe<&2,M.View>}
type Payload is Data:
  Payload{entities:List<&2,U32>,clock_inputs:List<&2,N.Word64>}
type Restored is Type:
  Restored{tick:T.State,clock_inputs:List<&2,R.Bits64>,membership:Maybe<&2,M.View>}

def legacy(view:E.View,clock_inputs:List<&2,R.Bits64>) -> Stored:
  Stored{Q.legacy(view),clock_inputs,None{}}
def inspected(+clock_inputs:List<&2,R.Bits64>,+membership:Maybe<&2,M.View>,result:T.State & Q.Recovery) -> T.State & Stored:
  (state,recovery) = result
  (state,Stored{recovery,clock_inputs,membership})
def inspect(state:T.State,clock_inputs:List<&2,R.Bits64>,membership:Maybe<&2,M.View>) -> T.State & Stored:
  inspected(clock_inputs,membership,Q.inspect(state))
def clocks_value(values:List<&2,R.Bits64>) -> List<&2,N.Word64>:
  match values:
    case Nil{}: []
    case R.Bits64{hi,lo} <> rest: N.Word64{hi,lo} <> clocks_value(rest)
def clocks_read(values:List<&2,N.Word64>) -> List<&2,R.Bits64>:
  match values:
    case Nil{}: []
    case N.Word64{hi,lo} <> rest: R.Bits64{hi,lo} <> clocks_read(rest)
def encoded(clock_inputs:List<&2,R.Bits64>,value:Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,Payload>:
  match value:
    case Fail{message}: Fail{message}
    case Done{bytes}: Done{Payload{bytes,clocks_value(clock_inputs)}}
def membership_encoded(limits:N.Limits,value:Maybe<&2,M.View>) -> Result<&2,&2,String,N.Value>:
  match value:
    case None{}: Done{N.ListTag{7,[]}}
    case Some{view}:
      Result.map(&2,&2,String,List<&2,U32>,N.Value,bytes => N.ListTag{7,[N.ByteArray{bytes}]},Membership.encode(limits,view))
def membership_decoded(limits:N.Limits,value:N.Value) -> Result<&2,&2,String,Maybe<&2,M.View>>:
  match value:
    case N.ListTag{7,Nil{}}: Done{None{}}
    case N.ListTag{7,N.ByteArray{bytes} <> Nil{}}:
      Result.map(&2,&2,String,M.View,Maybe<&2,M.View>,view => Some{view},Membership.decode(limits,bytes))
    case _: Fail{"local-player-cooking-tick-storage:membership availability schema"}
def envelope_root(recovery:List<&2,U32>,membership:N.Value) -> N.Root:
  N.Root{Raw.text("bendex:local-player-cooking-tick-storage"),N.Compound{[Raw.member("format",N.Int{1}),
    Raw.member("recovery",N.ByteArray{recovery}),Raw.member("membership",membership)]}}
def encode(+limits:N.Limits,value:Stored) -> Result<&2,&2,String,Payload>:
  Stored{recovery,clocks,membership} = value
  do Result<&2,&2,String,Payload>:
    bytes : List<&2,U32> <- Codec.encode(limits,recovery)
    manager : N.Value <- membership_encoded(limits,membership)
    envelope : List<&2,U32> <- N.encode_with(limits,envelope_root(bytes,manager))
    return Payload{envelope,clocks_value(clocks)}
def envelope_read(+limits:N.Limits,+clock_inputs:List<&2,N.Word64>,value:N.Root) -> Result<&2,&2,String,Stored>:
  match value:
    case N.Root{name,N.Compound{N.Member{a,N.Int{1}} <> N.Member{b,N.ByteArray{bytes}} <> N.Member{c,manager} <> Nil{}}}:
      do Result<&2,&2,String,Stored>:
        Raw.guard(Raw.name(name,"bendex:local-player-cooking-tick-storage") && Raw.name(a,"format") &&
          Raw.name(b,"recovery") && Raw.name(c,"membership"),"tick storage envelope schema")
        recovery : Q.Recovery <- Codec.decode(limits,bytes)
        membership : Maybe<&2,M.View> <- membership_decoded(limits,manager)
        return Stored{recovery,clocks_read(clock_inputs),membership}
    case _: Fail{"local-player-cooking-tick-storage:envelope schema"}
def decode(+limits:N.Limits,entities:List<&2,U32>,clock_inputs:List<&2,N.Word64>) -> Result<&2,&2,String,Stored>:
  Result.bind(&2,&2,String,N.Root,Stored,N.decode_with(limits,entities),root => envelope_read(limits,clock_inputs,root))
def clocks_field(value:N.Value) -> Result<&2,&2,String,List<&2,N.Word64>>:
  match value:
    case N.LongArray{words}: Done{words}
    case _: Fail{"local-player-cooking-tick-storage:clock_inputs require LongArray"}
def decode_fields(limits:N.Limits,entities:List<&2,U32>,clocks:N.Value) -> Result<&2,&2,String,Stored>:
  do Result<&2,&2,String,Stored>:
    words : List<&2,N.Word64> <- clocks_field(clocks)
    decode(limits,entities,words)
def payload_value(value:Payload) -> N.Value:
  Payload{bytes,clocks} = value
  N.Compound{[Raw.member("entities",N.ByteArray{bytes}),Raw.member("clock_inputs",N.LongArray{clocks})]}
def payload_read(limits:N.Limits,value:N.Value) -> Result<&2,&2,String,Stored>:
  match value:
    case N.Compound{N.Member{a,N.ByteArray{bytes}} <> N.Member{b,N.LongArray{clocks}} <> Nil{}}:
      do Result<&2,&2,String,Stored>:
        Raw.guard(Raw.name(a,"entities") && Raw.name(b,"clock_inputs"),"tick storage component schema")
        decode(limits,bytes,clocks)
    case _: Fail{"local-player-cooking-tick-storage:component schema"}
def restored(clock_inputs:List<&2,R.Bits64>,membership:Maybe<&2,M.View>,value:Result<&2,&1,String,T.State>) -> Result<&2,&1,String,Restored>:
  match value:
    case Fail{message}: Fail{message}
    case Done{state}: Done{Restored{state,clock_inputs,membership}}
def restore(value:Stored) -> Result<&2,&1,String,Restored>:
  Stored{recovery,clock_inputs,membership} = value
  restored(clock_inputs,membership,Q.restore(recovery))

law constructor_clock_words_are_lossless:
  for +values:List<&2,R.Bits64>
  {clocks_read(clocks_value(values)) == values : List<&2,R.Bits64>}
def constructor_clock_words_are_lossless(values):
  match values:
    case Nil{}: {==}
    case R.Bits64{+hi,+lo} <> +rest:
      %constructor_clock_words_are_lossless(rest) :
        {R.Bits64{hi,lo} <> clocks_read(clocks_value(rest)) == R.Bits64{hi,lo} <> _ : List<&2,R.Bits64>}
      {==}
