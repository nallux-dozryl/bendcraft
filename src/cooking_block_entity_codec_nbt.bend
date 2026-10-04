import Base
import ./nbt.bend as N
import ./f64.bend as F
import ./cooking_recipe_number.bend as Number
import ./crafting_recipe.bend as R
import ./u32_decimal.bend as Decimal

def units(value:String) -> List<&2,U32>:
  match value:
    case SNil{}: []
    case SCon{Chr{code},rest}: code <> units(rest)
def text(value:String) -> N.Text: N.Text{units(value)}
def member(name:String,value:N.Value) -> N.Member: N.Member{text(name),value}
def words_equal(a:List<&2,U32>,b:List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && words_equal(xs,ys)
    case _ _: False{}
def text_equal(a:N.Text,b:N.Text) -> Bool:
  N.Text{x} = a
  N.Text{y} = b
  words_equal(x,y)
def selected(head:N.Value,tail:Maybe<&2,N.Value>,matches:Bool) -> Maybe<&2,N.Value>:
  match tail matches:
    case Some{value} _: Some{value}
    case None{} True{}: Some{head}
    case None{} False{}: None{}
# CompoundTag/NbtIo use the last physical occurrence of each UTF-16 key.
def find(values:List<&2,N.Member>,+name:N.Text) -> Maybe<&2,N.Value>:
  match values:
    case Nil{}: None{}
    case N.Member{key,value} <> rest: selected(value,find(rest,name),text_equal(key,name))
def field(value:N.Value,name:String) -> Maybe<&2,N.Value>:
  match value:
    case N.Compound{members}: find(members,text(name))
    case _: None{}
def guard(test:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match test:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}
def ascii(units:List<&2,U32>,acc:String) -> Result<&2,&2,String,String>:
  match units:
    case Nil{}: Done{String.reverse(acc)}
    case +unit <> rest:
      do Result<&2,&2,String,String>:
        guard(U32.is_le(unit,127),"registry text requires ASCII")
        ascii(rest,SCon{Chr{unit},acc})
def string(value:N.Value) -> Result<&2,&2,String,String>:
  match value:
    case N.StringTag{N.Text{units}}: ascii(units,"")
    case _: Fail{"expected registry String tag"}
def signed_width(+bits:U32,+width:U32) -> U32:
  R.choose(U32,bits,U32.or(bits,U32.shln(4294967295,U32.to_nat(width))),U32.is_zero(U32.and(bits,U32.shln(1,U32.to_nat(U32.sub(width,1))))))
def raw_float(value:U32) -> F32:
  U32{word} = value
  F32{word}
# FloatTag.valueOf caches either signed zero as its positive ZERO object.
def float_bits(+value:U32) -> F32:
  R.choose(F32,0.0,raw_float(value),U32.is_eq(value,2147483648))
def double_int_result(value:Result<&2,&2,F.F64ConversionError,U32>) -> U32:
  match value:
    case Done{bits}: bits
    case Fail{error}: 0
def double_int_in_range(+value:F.F64,round_down:Bool) -> U32:
  match round_down:
    case True{}: double_int_result(F.floor_i32(value))
    case False{}: double_int_result(F.trunc_i32(value))
def double_int_range(+value:F.F64,round_down:Bool,low:Bool,high:Bool) -> U32:
  match low high:
    case True{} _: 2147483648
    case _ True{}: 2147483647
    case _ _: double_int_in_range(value,round_down)
def double_int(+value:F.F64,round_down:Bool) -> U32:
  double_int_range(value,round_down,F.is_le(value,F.from_i32(2147483648)),F.is_ge(value,F.from_i32(2147483647)))
def int_tag(value:N.Value,round_down:Bool) -> Maybe<&2,U32>:
  match value:
    case N.Byte{bits}: Some{signed_width(bits,8)}
    case N.Short{bits}: Some{signed_width(bits,16)}
    case N.Int{bits}: Some{bits}
    case N.Long{N.Word64{hi,lo}}: Some{lo}
    case N.Float{+bits}: Some{R.choose(U32,Number.floor(float_bits(bits)),Number.java_int(float_bits(bits)),round_down)}
    case N.Double{N.Word64{hi,lo}}: Some{double_int(F.from_bits(hi,lo),round_down)}
    case _: None{}
def fallback(value:Maybe<&2,U32>,missing:U32) -> U32:
  match value:
    case None{}: missing
    case Some{bits}: bits
def int_optional(value:Maybe<&2,N.Value>,missing:U32,round_down:Bool) -> U32:
  match value:
    case None{}: missing
    case Some{tag}: fallback(int_tag(tag,round_down),missing)
def long_ready(again:Unit -> F32,negative:Bool,value:F.Wide,+shift:U32,ready:Bool) -> F32:
  match ready:
    case True{}: F.narrow_float_round(negative,U32.shln(U32.add(126,U32.sub(63,shift)),23n),F.shift_jam(37,value))
    case False{}: again(Unit{})
def long_normalized(fuel:Nat,+negative:Bool,+value:F.Wide,+shift:U32) -> F32:
  match fuel:
    case 0n: 0.0
    case 1n+rest:
      F.Wide{+hi,lo} = value
      long_ready(u => long_normalized(rest,negative,F.wide_shl(value),U32.add(shift,1)),negative,value,shift,U32.is_ge(hi,2147483648))
def long_float_nonzero(+hi:U32,+lo:U32,zero:Bool) -> F32:
  match zero:
    case True{}: 0.0
    case False{}:
      +negative = U32.is_ge(hi,2147483648)
      +magnitude = R.choose(F.Wide,F.wide_sub(F.Wide{0,0},F.Wide{hi,lo}),F.Wide{hi,lo},negative)
      long_normalized(64n,negative,magnitude,0)
# Integer→float rounds once using 24 retained bits and guard/round/sticky.
def long_float(+hi:U32,+lo:U32) -> F32: long_float_nonzero(hi,lo,U32.is_zero(U32.or(hi,lo)))
def double_float(+hi:U32,+lo:U32) -> F32:
  R.choose(F32,0.0,F.to_f32(F.from_bits(hi,lo)),U32.is_zero(U32.or(U32.and(hi,2147483647),lo)))
def float_tag(value:N.Value) -> Maybe<&2,F32>:
  match value:
    case N.Byte{bits}: Some{Number.signed_float(signed_width(bits,8))}
    case N.Short{bits}: Some{Number.signed_float(signed_width(bits,16))}
    case N.Int{bits}: Some{Number.signed_float(bits)}
    case N.Long{N.Word64{hi,lo}}: Some{long_float(hi,lo)}
    case N.Float{bits}: Some{float_bits(bits)}
    case N.Double{N.Word64{hi,lo}}: Some{double_float(hi,lo)}
    case _: None{}
# NbtOps boolean codecs compare Number.doubleValue() with 0.0, including NaN.
def bool_tag(value:N.Value) -> Maybe<&2,Bool>:
  match value:
    case N.Byte{bits}: Some{U32.is_ne(bits,0)}
    case N.Short{bits}: Some{U32.is_ne(bits,0)}
    case N.Int{bits}: Some{U32.is_ne(bits,0)}
    case N.Long{N.Word64{hi,lo}}: Some{U32.is_ne(U32.or(hi,lo),0)}
    case N.Float{bits}: Some{F32.is_ne(float_bits(bits),0.0)}
    case N.Double{N.Word64{hi,lo}}: Some{F.is_ne(F.from_bits(hi,lo),F.from_u32(0))}
    case _: None{}
def float_fallback(value:Maybe<&2,F32>,missing:F32) -> F32:
  match value:
    case None{}: missing
    case Some{number}: number
def float_optional(value:Maybe<&2,N.Value>,missing:F32) -> F32:
  match value:
    case None{}: missing
    case Some{tag}: float_fallback(float_tag(tag),missing)
def signed_text(+bits:U32) -> String:
  R.choose(String,Decimal.show(bits),"-" ++ Decimal.show(U32.sub(0,bits)),U32.is_lt(bits,2147483648))
def canonical_float(+value:F32) -> U32:
  R.choose(U32,R.choose(U32,0,F32.bits(value),F32.is_eq(value,0.0)),2143289344,F32.is_eq(value,value))
