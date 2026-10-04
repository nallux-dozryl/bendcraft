import Base
import ../src/local_player_cooking_storage.bend as S
import ../src/player_inventory_codec.bend as I
import ../src/core.bend as C
import ../src/nbt.bend as N
import ../src/player_codec.bend as P
import ../src/cooking_block_entity_codec.bend as CB
import ../src/cooking_block_entity_codec_items.bend as Items
import ../src/cooking_block_entity_codec_nbt.bend as Text

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
  encoded_equal(expected,S.encode(S.Saved{owner,[]}))

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
      S.Body{C.Position{"minecraft:the_end",0,2147483647,4294967295},second} <> Nil{}}}:
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
    check(projection_refused(S.projection(N.Compound{[P.member("format",N.Int{2}),P.member("player",N.ByteArray{[]}),P.member("bodies",N.ListTag{10,[]})]})),"unsupported cooking format refuses")
    check(projection_refused(S.projection(N.Compound{[P.member("format",N.Int{1}),P.member("player",N.ByteArray{[]}),P.member("bodies",N.ListTag{3,[]})]})),"wrong cooking list element type refuses")
    check(merge_known(N.encode_with(S.nbt_limits(),known())),"physical root UTF16 duplicate extras types and raw bits retained")
    check(refused(S.with_details(S.nbt_limits(),[10,0],Some{details()})),"malformed known body refuses extras merge")
    check(refused(S.merged_root(S.nbt_limits(),details(),Done{N.Root{N.Text{[]},N.Int{0}}})),"noncompound known body refuses extras merge")
