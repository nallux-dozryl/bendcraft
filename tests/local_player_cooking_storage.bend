import Base
import ../src/local_player_cooking_storage.bend as S
import ../src/player_inventory_codec.bend as I
import ../src/core.bend as C
import ../src/nbt.bend as N
import ../src/player_codec.bend as P
import ../src/cooking_block_entity_codec.bend as CB
import ../src/cooking_block_entity_codec_items.bend as Items
import ../src/cooking_block_entity_codec_nbt.bend as Text
import ../src/cooking_world_store.bend as Store
import ../src/cooking_effect_recovery.bend as Effects
import ../src/cooking_effect_entities_model.bend as Entities
import ../src/local_player_effect_entities_codec.bend as EntityCodec
import ../src/random.bend as Random
import ../src/local_player_cooking_publication_codec.bend as Publication
import ../src/cooking_effect_publication_journal.bend as Journal
import ../src/cooking_world_bindings.bend as Bindings
import ../src/cooking_recipe.bend as Recipe

def bytes_equal(a:List<&2,U32>,b:List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && bytes_equal(xs,ys)
    case _ _: False{}

def status_equal(expected:Result<&2,&2,String,List<&2,U32>>,actual:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match expected actual:
    case Done{before} Done{after}: bytes_equal(before,after)
    case _ _: False{}

def encoding_status(result:S.Saved & Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,List<&2,U32>>:
  (owner,actual) = result
  actual

def encoded_equal(expected:Result<&2,&2,String,List<&2,U32>>,result:S.Saved & Result<&2,&2,String,List<&2,U32>>) -> Bool:
  status_equal(expected,encoding_status(result))

def legacy_encoded(result:I.Saved & Result<&2,&2,String,List<&2,U32>>) -> Bool:
  (owner,expected) = result
  encoded_equal(expected,S.encode(S.Saved{owner,[],[],None{},None{}}))

def legacy_initial(result:Result<&2,&1,String,I.Saved>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{owner}: legacy_encoded(I.encode(owner))

def bodies() -> List<&2,S.Body>:
  [S.Body{C.Position{"minecraft:overworld",4294967295,2147483648,0},[1,2,3]},
   S.Body{C.Position{"minecraft:the_end",0,2147483647,4294967295},[255,0]}]

def projection_valid(result:Result<&2,&2,String,S.Projection>) -> Bool:
  match result:
    case Done{S.Projection{player,
      S.Body{C.Position{"minecraft:overworld",4294967295,2147483648,0},first} <>
      S.Body{C.Position{"minecraft:the_end",0,2147483647,4294967295},second} <> Nil{},Nil{},None{},None{}}}:
      bytes_equal(player,[7,8]) && bytes_equal(first,[1,2,3]) && bytes_equal(second,[255,0])
    case _: False{}

def wrapper_root(result:Result<&2,&2,String,N.Root>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{N.Root{name,value}}: projection_valid(S.projection(value))

def wrapper_bytes(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: wrapper_root(N.decode_with(S.nbt_limits(),bytes))

def projection_refused(result:Result<&2,&2,String,S.Projection>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{value}: False{}

def duplicate_root(root:N.Root) -> Bool:
  N.Root{name,value} = root
  projection_refused(S.projection(value))

def extras() -> List<&2,N.Member>:
  [N.Member{P.text("Lock"),N.StringTag{N.Text{[65,0,55296]}}},
   N.Member{P.text("Lock"),N.Int{4294967295}},
   N.Member{N.Text{[56320,0,120]},N.Float{2147483648}}]

def details() -> CB.Details:
  CB.Details{N.Text{[55296,0,97]},extras(),[],Items.Admission{[],[]},0}

def known() -> N.Root:
  N.Root{N.Text{[]},N.Compound{[
    P.member("Items",N.ListTag{10,[]}),P.member("lit_time_remaining",N.Int{7})]}}

def merged_valid(result:Result<&2,&2,String,N.Root>) -> Bool:
  match result:
    case Done{N.Root{N.Text{55296 <> 0 <> 97 <> Nil{}},N.Compound{
      N.Member{items,N.ListTag{10,Nil{}}} <>
      N.Member{timer,N.Int{7}} <>
      N.Member{lock1,N.StringTag{N.Text{65 <> 0 <> 55296 <> Nil{}}}} <>
      N.Member{lock2,N.Int{4294967295}} <>
      N.Member{N.Text{56320 <> 0 <> 120 <> Nil{}},N.Float{2147483648}} <> Nil{}}}}:
      Text.text_equal(items,P.text("Items")) && Text.text_equal(timer,P.text("lit_time_remaining")) &&
      Text.text_equal(lock1,P.text("Lock")) && Text.text_equal(lock2,P.text("Lock"))
    case _: False{}

def merged_bytes(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: merged_valid(N.decode_with(S.nbt_limits(),bytes))

def merge_known(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: merged_bytes(S.with_details(S.nbt_limits(),bytes,Some{details()}))

def refused(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{bytes}: False{}

def empty_payload(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Done{bytes}: bytes_equal(bytes,[7,8])
    case _: False{}

def pending() -> List<&2,Store.Effect>:
  [Store.OwnerReset{C.Position{"minecraft:overworld",1,2,3}},
   Store.Dirty{C.Position{"minecraft:the_end",4294967295,0,2147483648}}]

def recovery_projection(result:Result<&2,&2,String,S.Projection>) -> Bool:
  match result:
    case Done{S.Projection{player,Nil{},
      Store.OwnerReset{C.Position{"minecraft:overworld",1,2,3}} <>
      Store.Dirty{C.Position{"minecraft:the_end",4294967295,0,2147483648}} <> Nil{},None{},None{}}}:
      bytes_equal(player,[7,8])
    case _: False{}

def recovery_decoded(result:Result<&2,&2,String,N.Root>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{N.Root{name,value}}: recovery_projection(S.projection(value))

def recovery_bytes(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: recovery_decoded(N.decode_with(S.nbt_limits(),bytes))

def empty_recovery(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: duplicate_root(S.recovery_root([7,8],[],bytes))

def entity_view() -> Entities.View:
  Entities.View{Random.Xoroshiro{Random.Bits64{4294967295,0},Random.Bits64{2147483648,4294967295}},
    Random.Bits64{3735928559,4275878552},99,Nat.add(4294967295n,1n),[]}

def entity_clocks() -> List<&2,Random.Bits64>:
  [Random.Bits64{2147483648,4294967295},Random.Bits64{4294967295,0}]

def entity_projection(result:Result<&2,&2,String,S.Projection>) -> Bool:
  match result:
    case Done{S.Projection{player,Nil{},Nil{},Some{S.EntityRecovery{
        Entities.View{Random.Xoroshiro{Random.Bits64{4294967295,0},Random.Bits64{2147483648,4294967295}},
          Random.Bits64{3735928559,4275878552},99,order,Nil{}},
        Random.Bits64{2147483648,4294967295} <> Random.Bits64{4294967295,0} <> Nil{}}},None{}}}:
      bytes_equal(player,[7,8]) && Nat.is_eq(order,Nat.add(4294967295n,1n))
    case _: False{}

def entity_decoded(result:Result<&2,&2,String,N.Root>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{N.Root{name,value}}: entity_projection(S.projection(value))

def entity_bytes(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: entity_decoded(N.decode_with(S.nbt_limits(),bytes))

def wrong_clock_fields(effects:List<&2,U32>,records:List<&2,U32>) -> Bool:
  projection_refused(S.projection(N.Compound{[
    P.member("format",N.Int{3}),P.member("player",N.ByteArray{[7,8]}),
    P.member("bodies",N.ListTag{10,[]}),P.member("effects",N.ByteArray{effects}),
    P.member("entities",N.ByteArray{records}),P.member("clock_inputs",N.Int{0})]}))

def wrong_clock_records(effects:List<&2,U32>,result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{records}: wrong_clock_fields(effects,records)

def wrong_clock_effects(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{effects}: wrong_clock_records(effects,EntityCodec.encode(S.nbt_limits(),entity_view()))

def duplicate_entity_clock(root:N.Root) -> Bool:
  N.Root{name,value} = root
  match value:
    case N.Compound{members}:
      projection_refused(S.projection(N.Compound{P.member("clock_inputs",N.LongArray{[]}) <> members}))
    case _: False{}

def duplicate_clock_records(effects:List<&2,U32>,result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{records}: duplicate_entity_clock(S.entity_root([7,8],[],effects,records,entity_clocks()))

def duplicate_clock_effects(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{effects}: duplicate_clock_records(effects,EntityCodec.encode(S.nbt_limits(),entity_view()))

def publication_position() -> C.Position: C.Position{"minecraft:overworld",4294967295,64,2}
def publication_source() -> Journal.Source:
  Journal.Source{publication_position(),Bindings.Binding{80,"minecraft:furnace",Bindings.Furnace{Recipe.Smelting{}},False{},80,81},2n}
def publication_recovery() -> Publication.Recovery:
  Publication.Recovery{MLeaf{Bindings.key(publication_position()),2n},
    Journal.View{3n,[Journal.DirtyChunk{Journal.chunk(publication_position()),3n}],
      Some{Journal.Receipt{publication_position(),publication_source(),Journal.chunk(publication_position()),3n}}}}
def publication_pending() -> List<&2,Store.Effect>:
  [Store.OwnerReset{publication_position()},Store.OwnedDirty{publication_source()}]
def projection_publication_roundtrip(+before:List<&2,U32>,result:Result<&2,&2,String,S.Projection>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{S.Projection{player,bodies,pending,entities,Some{publisher}}}:
      status_equal(Done{before},S.payload_publication(bodies,pending,entities,Some{publisher},player))
    case _: False{}
def publication_decoded(+before:List<&2,U32>,result:Result<&2,&2,String,N.Root>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{N.Root{name,value}}: projection_publication_roundtrip(before,S.projection(value))
def publication_roundtrip(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{+bytes}: publication_decoded(bytes,N.decode_with(S.nbt_limits(),bytes))
def owned_effects_wrong_version(result:Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: duplicate_root(S.recovery_root([7,8],[],bytes))
def unbound_clocks_refused(result:Result<&2,&2,String,Maybe<&2,S.EntityRecovery>>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{entity}: False{}

def check(valid:Bool,name:String) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit,1,"failed " ++ name)
    case True{}: IO.print("ok " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    check(legacy_initial(I.initial(Unit{})),"actual empty inventory codec payload remains byte-identical")
    check(empty_payload(S.payload([],[7,8])),"empty cooking payload preserves player bytes")
    check(wrapper_bytes(S.payload(bodies(),[7,8])),"physical wrapper retains dimensions coordinate bits body order and bytes")
    check(duplicate_root(S.root([7,8],[S.Body{C.Position{"minecraft:overworld",1,2,3},[1]},S.Body{C.Position{"minecraft:overworld",1,2,3},[2]}])),"duplicate body positions refuse complete projection")
    check(projection_refused(S.projection(N.Compound{[P.member("format",N.Int{4}),P.member("player",N.ByteArray{[]}),P.member("bodies",N.ListTag{10,[]})]})),"unsupported cooking format refuses")
    check(projection_refused(S.projection(N.Compound{[P.member("format",N.Int{1}),P.member("player",N.ByteArray{[]}),P.member("bodies",N.ListTag{3,[]})]})),"wrong cooking list element type refuses")
    check(merge_known(N.encode_with(S.nbt_limits(),known())),"physical root UTF16 duplicate extras types and raw bits retained")
    check(refused(S.with_details(S.nbt_limits(),[10,0],Some{details()})),"malformed known body refuses extras merge")
    check(refused(S.merged_root(S.nbt_limits(),details(),Done{N.Root{N.Text{[]},N.Int{0}}})),"noncompound known body refuses extras merge")
    check(recovery_bytes(S.payload_pending([],pending(),[7,8])),"pending effects retain order coordinates and player payload in format2")
    check(empty_recovery(Effects.encode(S.nbt_limits(),[])),"empty recovery payload refuses noncanonical format2")
    check(projection_refused(S.projection(N.Compound{[P.member("format",N.Int{2}),P.member("player",N.ByteArray{[]}),P.member("bodies",N.ListTag{10,[]}),P.member("effects",N.Int{0})]})),"recovery effects require complete ByteArray")
    check(entity_bytes(S.payload_entities([],[],Some{S.EntityRecovery{entity_view(),entity_clocks()}},[7,8])),"format3 retains empty entity owner RNG cursors and ordered raw clock inputs")
    check(status_equal(S.payload_pending([],pending(),[7,8]),S.payload_entities([],pending(),None{},[7,8])),"absent entity owner preserves format2 bytes exactly")
    check(wrong_clock_effects(Effects.encode(S.nbt_limits(),[])),"entity clock inputs require complete LongArray")
    check(duplicate_clock_effects(Effects.encode(S.nbt_limits(),[])),"duplicate entity recovery clock field refuses")
    check(status_equal(S.payload_entities([],pending(),None{},[7,8]),S.payload_publication([],pending(),None{},None{},[7,8])),"absent publication preserves legacy recovery bytes exactly")
    check(publication_roundtrip(S.payload_publication([],publication_pending(),None{},Some{publication_recovery()},[7,8])),"format4 retains complete publication and pending producer with unbound entities")
    check(publication_roundtrip(S.payload_publication(bodies(),publication_pending(),Some{S.EntityRecovery{entity_view(),entity_clocks()}},Some{publication_recovery()},[7,8])),"format4 retains publication together with full entity clock recovery")
    check(refused(S.payload_publication([],publication_pending(),None{},None{},[7,8])),"owned pending effects require publication recovery when encoding")
    check(owned_effects_wrong_version(Effects.encode(S.nbt_limits(),publication_pending())),"owned pending effects refuse legacy wrapper when decoding")
    check(unbound_clocks_refused(S.publication_entity_read([],entity_clocks())),"format4 unbound entity owner refuses orphan clock inputs")
