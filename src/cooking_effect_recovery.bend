import Base
import ./core.bend as C
import ./cooking_world_store.bend as S
import ./furnace_authority.bend as F
import ./inventory.bend as I
import ./nbt.bend as N

# Internal recovery framing, not vanilla entity NBT. Raw char words preserve
# complete component identities without UTF normalization or StringTag's
# 65535-byte limit. Limits belong to the existing atomic save caller.
def words(text:String) -> List<&2,U32>:
  match text:
    case SNil{}: []
    case SCon{Chr{word},rest}: word <> words(rest)
def string(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case word <> rest: SCon{Chr{word},string(rest)}
def equal_words(a:List<&2,U32>,b:List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && equal_words(xs,ys)
    case _ _: False{}
def text(value:String) -> N.Text: N.Text{words(value)}
def name(value:N.Text,expected:String) -> Bool:
  N.Text{units} = value
  equal_words(units,words(expected))
def member(key:String,value:N.Value) -> N.Member: N.Member{text(key),value}
def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{"cooking-effects-recovery:" ++ message}
def raw_float(bits:U32) -> F32:
  U32{word} = bits
  F32{word}

def position_value(position:C.Position) -> N.Value:
  C.Position{dimension,x,y,z} = position
  N.Compound{[member("dimension",N.IntArray{words(dimension)}),member("x",N.Int{x}),
    member("y",N.Int{y}),member("z",N.Int{z})]}
def position_read(value:N.Value) -> Result<&2,&2,String,C.Position>:
  match value:
    case N.Compound{N.Member{a,N.IntArray{dimension}} <> N.Member{b,N.Int{x}} <>
        N.Member{c,N.Int{y}} <> N.Member{d,N.Int{z}} <> Nil{}}:
      do Result<&2,&2,String,C.Position>:
        guard(name(a,"dimension") && name(b,"x") && name(c,"y") && name(d,"z"),"position schema")
        return C.Position{string(dimension),x,y,z}
    case _: Fail{"cooking-effects-recovery:position schema"}
def slot_value(value:I.Slot) -> N.Value:
  match value:
    case I.InvEmpty{}: N.Compound{[]}
    case I.InvStack{I.ItemKey{id,components},count}:
      N.Compound{[member("id",N.IntArray{words(id)}),member("components",N.IntArray{words(components)}),member("count",N.Int{count})]}
def slot_read(value:N.Value) -> Result<&2,&2,String,I.Slot>:
  match value:
    case N.Compound{Nil{}}: Done{I.InvEmpty{}}
    case N.Compound{N.Member{a,N.IntArray{id}} <> N.Member{b,N.IntArray{components}} <> N.Member{c,N.Int{count}} <> Nil{}}:
      do Result<&2,&2,String,I.Slot>:
        guard(name(a,"id") && name(b,"components") && name(c,"count"),"item schema")
        return I.InvStack{I.ItemKey{string(id),string(components)},count}
    case _: Fail{"cooking-effects-recovery:item schema"}
def natural_read(raw:String,value:Maybe<&2,Nat>) -> Result<&2,&2,String,Nat>:
  match value:
    case None{}: Fail{"cooking-effects-recovery:notification count"}
    case Some{+count}:
      do Result<&2,&2,String,Nat>:
        guard(String.eq(raw,Nat.show(count)),"noncanonical notification count")
        return count
def count_read(units:List<&2,U32>) -> Result<&2,&2,String,Nat>:
  +raw = string(units)
  natural_read(raw,Nat.read(raw))

def encoded(tag:U32,position:C.Position,payload:N.Value) -> N.Value:
  N.Compound{[member("kind",N.Int{tag}),member("position",position_value(position)),member("payload",payload)]}
def effect_value(value:S.Effect) -> N.Value:
  match value:
    case S.OwnerReset{position}: encoded(0,position,N.Compound{[]})
    case S.Drop{position,slot,item}:
      encoded(1,position,N.Compound{[member("slot",N.Int{slot}),member("item",slot_value(item))]})
    case S.Experience{position,F.XpRequest{id,uses,xp}}:
      encoded(2,position,N.Compound{[member("recipe",N.IntArray{words(id)}),member("uses",N.Int{uses}),member("experience_bits",N.Int{F32.bits(xp)})]})
    case S.Dirty{position}: encoded(3,position,N.Compound{[]})
    case S.BlockUpdate{position,count}: encoded(4,position,N.IntArray{words(Nat.show(count))})
    case S.BlockChange{position,count}: encoded(5,position,N.IntArray{words(Nat.show(count))})
def effect_payload(tag:U32,+position:C.Position,value:N.Value) -> Result<&2,&2,String,S.Effect>:
  match tag value:
    case 0 N.Compound{Nil{}}: Done{S.OwnerReset{position}}
    case 1 N.Compound{N.Member{a,N.Int{slot}} <> N.Member{b,item} <> Nil{}}:
      do Result<&2,&2,String,S.Effect>:
        guard(name(a,"slot") && name(b,"item"),"drop schema")
        value : I.Slot <- slot_read(item)
        return S.Drop{position,slot,value}
    case 2 N.Compound{N.Member{a,N.IntArray{id}} <> N.Member{b,N.Int{uses}} <> N.Member{c,N.Int{xp}} <> Nil{}}:
      do Result<&2,&2,String,S.Effect>:
        guard(name(a,"recipe") && name(b,"uses") && name(c,"experience_bits"),"XP schema")
        return S.Experience{position,F.XpRequest{string(id),uses,raw_float(xp)}}
    case 3 N.Compound{Nil{}}: Done{S.Dirty{position}}
    case 4 N.IntArray{units}:
      Result.map(&2,&2,String,Nat,S.Effect,count => S.BlockUpdate{position,count},count_read(units))
    case 5 N.IntArray{units}:
      Result.map(&2,&2,String,Nat,S.Effect,count => S.BlockChange{position,count},count_read(units))
    case _ _: Fail{"cooking-effects-recovery:effect kind or payload schema"}
def effect_read(value:N.Value) -> Result<&2,&2,String,S.Effect>:
  match value:
    case N.Compound{N.Member{a,N.Int{tag}} <> N.Member{b,point} <> N.Member{c,payload} <> Nil{}}:
      do Result<&2,&2,String,S.Effect>:
        guard(name(a,"kind") && name(b,"position") && name(c,"payload"),"effect schema")
        position : C.Position <- position_read(point)
        effect_payload(tag,position,payload)
    case _: Fail{"cooking-effects-recovery:effect schema"}
def values(effects:List<&2,S.Effect>) -> List<&2,N.Value>:
  match effects:
    case Nil{}: []
    case head <> rest: effect_value(head) <> values(rest)
def effects(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,S.Effect>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,S.Effect>>:
        first : S.Effect <- effect_read(head)
        tail : List<&2,S.Effect> <- effects(rest)
        return first <> tail
def value(effects:List<&2,S.Effect>) -> N.Value: N.ListTag{10,values(effects)}
def read(value:N.Value) -> Result<&2,&2,String,List<&2,S.Effect>>:
  match value:
    case N.ListTag{10,values}: effects(values)
    case _: Fail{"cooking-effects-recovery:effects require Compound list"}
def root(effects:List<&2,S.Effect>) -> N.Root:
  N.Root{text("bendex:cooking-effects"),N.Compound{[member("format",N.Int{1}),member("effects",value(effects))]}}
def root_read(value:N.Root) -> Result<&2,&2,String,List<&2,S.Effect>>:
  match value:
    case N.Root{n,N.Compound{N.Member{a,N.Int{1}} <> N.Member{b,effects} <> Nil{}}}:
      do Result<&2,&2,String,List<&2,S.Effect>>:
        guard(name(n,"bendex:cooking-effects") && name(a,"format") && name(b,"effects"),"root schema")
        read(effects)
    case _: Fail{"cooking-effects-recovery:root schema"}
def encode(limits:N.Limits,effects:List<&2,S.Effect>) -> Result<&2,&2,String,List<&2,U32>>:
  N.encode_with(limits,root(effects))
def decode(limits:N.Limits,bytes:List<&2,U32>) -> Result<&2,&2,String,List<&2,S.Effect>>:
  Result.bind(&2,&2,String,N.Root,List<&2,S.Effect>,N.decode_with(limits,bytes),root_read)
