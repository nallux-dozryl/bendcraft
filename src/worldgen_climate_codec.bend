import Base
import ./worldgen_climate.bend as C
import ./worldgen_biome.bend as B
import ./world_generation_settings.bend as WG
import ./json.bend as J
import ./f64.bend as F

# Decoded Climate.ParameterList boundary: all long words are four exact U32
# numeric tokens per interval. The native Minecraft float codec remains outside
# this interface; no host search or host conversion supplies runtime decisions.
def field_value(key:String,value:Maybe<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  match value:
    case Some{item}: Done{item}
    case None{}: Fail{"missing climate table field: " ++ key}

def field(value:J.Value,+key:String) -> Result<&2,&2,String,J.Value>:
  field_value(key,J.member(value,key))

def word_value(value:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match value:
    case Some{word}: Done{word}
    case None{}: Fail{"climate word must be a canonical U32 integer"}

def word(value:J.Value) -> Result<&2,&2,String,U32>:
  match value:
    case J.JNumber{raw}: word_value(J.u32_lexeme(raw))
    case _: Fail{"climate word must be a canonical U32 integer"}

def interval_words(a:J.Value,b:J.Value,c:J.Value,d:J.Value) -> Result<&2,&2,String,C.Interval>:
  do Result<&2,&2,String,C.Interval>:
    hi_min : U32 <- word(a)
    lo_min : U32 <- word(b)
    hi_max : U32 <- word(c)
    lo_max : U32 <- word(d)
    return C.Interval{F.Word64{hi_min,lo_min},F.Word64{hi_max,lo_max}}

def interval(value:J.Value) -> Result<&2,&2,String,C.Interval>:
  match value:
    case J.JArray{a <> b <> c <> d <> Nil{}}: interval_words(a,b,c,d)
    case _: Fail{"climate interval requires four long words"}

def interval_valid(interval:C.Interval) -> Bool:
  match interval:
    case C.Interval{+min,+max}:
      Bool.not(C.less(max,min)) && Bool.not(C.less(min,F.Word64{4294967295,4294947296})) &&
        Bool.not(C.less(F.Word64{0,20000},max))

def offset_valid(interval:C.Interval) -> Bool:
  match interval:
    case C.Interval{+min,+max}:
      C.word_equal(min,max) && Bool.not(C.less(min,C.zero())) &&
        Bool.not(C.less(F.Word64{0,10000},max))

def space_valid(space:C.Space) -> Bool:
  match space:
    case C.Space{t,h,c,e,d,w,o}:
      interval_valid(t) && interval_valid(h) && interval_valid(c) && interval_valid(e) &&
        interval_valid(d) && interval_valid(w) && offset_valid(o)

def space_checked(+space:C.Space,valid:Bool) -> Result<&2,&2,String,C.Space>:
  match valid:
    case True{}: Done{space}
    case False{}: Fail{"climate intervals or offset outside native codec range"}

def space_fields(t:J.Value,h:J.Value,c:J.Value,e:J.Value,d:J.Value,w:J.Value,o:J.Value) -> Result<&2,&2,String,C.Space>:
  do Result<&2,&2,String,C.Space>:
    temperature : C.Interval <- interval(t)
    humidity : C.Interval <- interval(h)
    continentalness : C.Interval <- interval(c)
    erosion : C.Interval <- interval(e)
    depth : C.Interval <- interval(d)
    weirdness : C.Interval <- interval(w)
    offset : C.Interval <- interval(o)
    +space : C.Space = C.Space{temperature,humidity,continentalness,erosion,depth,weirdness,offset}
    result : C.Space <- space_checked(space,space_valid(space))
    return result

def space(value:J.Value) -> Result<&2,&2,String,C.Space>:
  match value:
    case J.JArray{t <> h <> c <> e <> d <> w <> o <> Nil{}}: space_fields(t,h,c,e,d,w,o)
    case _: Fail{"climate parameter point requires six intervals and offset"}

def biome(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{+name}:
      C.gate(Result<&2,&2,String,String>,WG.identifier(name),u => Done{name},
        u => Fail{"climate biome identifier invalid"})
    case _: Fail{"climate biome identifier required"}

def entry_checked(index:U32,space:C.Space,biome:String,valid:Bool) -> Result<&2,&2,String,C.Entry>:
  match valid:
    case True{}: Done{C.Entry{index,space,biome}}
    case False{}: Fail{"climate table ordinal does not match ordered entry"}

def entry(+value:J.Value,+ordinal:U32) -> Result<&2,&2,String,C.Entry>:
  do Result<&2,&2,String,C.Entry>:
    index_raw : J.Value <- field(value,"index")
    space_raw : J.Value <- field(value,"space")
    biome_raw : J.Value <- field(value,"biome")
    +index : U32 <- word(index_raw)
    decoded_space : C.Space <- space(space_raw)
    decoded_biome : String <- biome(biome_raw)
    decoded : C.Entry <- entry_checked(index,decoded_space,decoded_biome,U32.is_eq(index,ordinal))
    return decoded

def entries(budget:Nat,+ordinal:U32,values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,C.Entry>>:
  match budget values:
    case _ Nil{}: Done{Nil{}}
    case 0n _: Fail{"climate parameter list exceeds entry budget"}
    case 1n+rest value <> tail:
      do Result<&2,&2,String,List<&2,C.Entry>>:
        decoded : C.Entry <- entry(value,ordinal)
        more : List<&2,C.Entry> <- entries(rest,U32.add(ordinal,1),tail)
        return decoded <> more

def entry_array(value:J.Value,budget:Nat) -> Result<&2,&2,String,List<&2,C.Entry>>:
  match value:
    case J.JArray{Nil{}}: Fail{"climate parameter list must be nonempty"}
    case J.JArray{items}: entries(budget,0,items)
    case _: Fail{"climate parameter list must be an array"}

def read_checked(identity:B.LoadedPreset,value:J.Value,budget:Nat,valid:Bool) -> Result<&2,&2,String,C.Loaded>:
  match valid:
    case False{}: Fail{"climate table identity or entry budget invalid"}
    case True{}:
      do Result<&2,&2,String,C.Loaded>:
        loaded : List<&2,C.Entry> <- entry_array(value,budget)
        return C.Loaded{identity,loaded}

def read(+identity:B.LoadedPreset,value:J.Value,+budget:Nat) -> Result<&2,&2,String,C.Loaded>:
  match identity:
    case B.LoadedPreset{+key,+definition}:
      read_checked(B.LoadedPreset{key,definition},value,budget,
        B.preset_matches(key,B.LoadedPreset{key,definition}) && Nat.is_lt(budget,2147483648n))
