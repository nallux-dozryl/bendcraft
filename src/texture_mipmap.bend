import Base

# Pinned 26.3 CPU MipmapGenerator. Pixels are row-major straight ARGB words.
type Strategy is Data:
  Auto{}
  Mean{}
  Cutout{}
  StrictCutout{}
  DarkCutout{}
type Transparency is Data:
  Transparency{transparent:Bool,translucent:Bool}
type Config is Data:
  Config{path:String,target_level:U32,strategy:Strategy,bias:F32,transparency:Transparency}
type Limits is Data:
  Limits{max_dimension:U32,max_levels:U32,max_capacity:U32,max_work_pixels:U32,max_path_codepoints:U32}
type Level is Type:
  Level{width:U32,height:U32,pixels:Array<U32>}
type Chain is Type:
  Chain{levels:List<&1,Level>}
type Dimension is Data:
  Dimension{width:U32,height:U32,capacity:U32}
type Summary is Data:
  Summary{effective:Strategy,early_return:Bool,base_preconditioned:Bool,original_levels:U32,dimensions:List<&2,Dimension>}
type Error is Data:
  Error{code:String,level:U32}
type Usage is Data:
  Usage{capacity:U32,logical:U32}
type Lookup is Data:
  Value{value:U32}
  Pair{left:Lookup,right:Lookup}
type Tables is Data:
  Tables{linear:Lookup,inverse:Lookup}

def choose(-A:Type,yes:A,no:A,value:Bool) -> A:
  match value:
    case True{}: yes
    case False{}: no
def paired(-A:Type,-B:Type,-C:Type,value:A & B,f:A -> B -> C) -> C:
  (a,b) = value
  f(a)(b)
def defaults() -> Limits:
  Limits{8192,16,4194304,1048576,4096}
def strategy_name(value:Strategy) -> String:
  match value:
    case Auto{}: "auto"
    case Mean{}: "mean"
    case Cutout{}: "cutout"
    case StrictCutout{}: "strict_cutout"
    case DarkCutout{}: "dark_cutout"
def effective(value:Strategy,tr:Transparency) -> Strategy:
  match value tr:
    case Auto{} Transparency{transparent,translucent}: choose(Strategy,Cutout{},Mean{},transparent)
    case _ _: value
def cutout(value:Strategy) -> Bool:
  match value:
    case Mean{}: False{}
    case Auto{}: False{}
    case _: True{}
def cutoff(value:Strategy) -> F32:
  match value:
    case StrictCutout{}: 0.3
    case _: 0.5
def alpha(value:U32) -> U32:
  U32.shrn(value,24n)
def channel(value:U32,shift:Nat) -> U32:
  U32.and(U32.shrn(value,shift),255)
def argb(a:U32,r:U32,g:U32,b:U32) -> U32:
  U32.or(U32.shln(a,24n),U32.or(U32.shln(r,16n),U32.or(U32.shln(g,8n),b)))
def set_alpha(value:U32,a:U32) -> U32:
  U32.or(U32.and(value,16777215),U32.shln(a,24n))
def invoke(f:Unit -> U32) -> U32:
  f(Unit{})
def lookup(value:Lookup,+index:U32,+bit:U32) -> U32:
  match value:
    case Value{v}: v
    case Pair{a,b}: invoke(choose(Unit -> U32,unit => lookup(a,index,U32.shr(bit)),unit => lookup(b,index,U32.shr(bit)),U32.is_eq(U32.and(index,bit),0)))
def linear(value:Tables,index:U32) -> U32:
  Tables{tree,other} = value
  lookup(tree,index,128)
def inverse(value:Tables,index:U32) -> U32:
  Tables{other,tree} = value
  lookup(tree,index,512)
def mean_channel(+t:Tables,a:U32,b:U32,c:U32,d:U32) -> U32:
  inverse(t,U32.div((linear(t,a) + linear(t,b) + linear(t,c) + linear(t,d) : U32),4))
def mean(+t:Tables,+a:U32,+b:U32,+c:U32,+d:U32) -> U32:
  argb(U32.div((alpha(a) + alpha(b) + alpha(c) + alpha(d) : U32),4),mean_channel(t,channel(a,16n),channel(b,16n),channel(c,16n),channel(d,16n)),mean_channel(t,channel(a,8n),channel(b,8n),channel(c,8n),channel(d,8n)),mean_channel(t,channel(a,0n),channel(b,0n),channel(c,0n),channel(d,0n)))
def linear_float(t:Tables,value:U32) -> F32:
  F32.div(U32.to_f32(linear(t,value)),1023.0)
def dark_term(t:Tables,+pixel:U32,shift:Nat) -> F32:
  choose(F32,0.0,linear_float(t,channel(pixel,shift)),U32.is_eq(alpha(pixel),0))
def dark_channel(+t:Tables,a:U32,b:U32,c:U32,d:U32,+shift:Nat) -> U32:
  +sum = F32.add(F32.add(F32.add(F32.add(0.0,dark_term(t,a,shift)),dark_term(t,b,shift)),dark_term(t,c,shift)),dark_term(t,d,shift))
  inverse(t,F32.to_u32(F32.mul(F32.div(sum,4.0),1023.0)))
def dark(+t:Tables,+a:U32,+b:U32,+c:U32,+d:U32) -> U32:
  argb(dark_channel(t,a,b,c,d,24n),dark_channel(t,a,b,c,d,16n),dark_channel(t,a,b,c,d,8n),dark_channel(t,a,b,c,d,0n))
def blend(t:Tables,strategy:Strategy,a:U32,b:U32,c:U32,d:U32) -> U32:
  match strategy:
    case DarkCutout{}: dark(t,a,b,c,d)
    case _: mean(t,a,b,c,d)
def array_depth(fuel:Nat,+needed:U32,+capacity:U32) -> Nat:
  match fuel:
    case 0n: 0n
    case 1n+p: choose(Nat,0n,1n+array_depth(p,needed,U32.mul(capacity,2)),U32.is_ge(capacity,needed))
def new_pixels(w:U32,h:U32,value:U32) -> Array<U32>:
  Array.new(U32,array_depth(24n,U32.mul(w,h),1),value)
def rounded_capacity(fuel:Nat,+needed:U32,+capacity:U32) -> U32:
  match fuel:
    case 0n: capacity
    case 1n+p: choose(U32,capacity,rounded_capacity(p,needed,U32.mul(capacity,2)),U32.is_ge(capacity,needed))
def inspect_array(fuel:Nat,pixels:Array<U32>) -> Array<U32> & U32:
  match fuel:
    case 0n: (pixels,0)
    case 1n+ +p:
      match pixels:
        case ALeaf{x}: (ALeaf{x},1)
        case ANode{left,right}:
          paired(Array<U32>,U32,Array<U32> & U32,inspect_array(p,left),left => +a => paired(Array<U32>,U32,Array<U32> & U32,inspect_array(p,right),right => b => (ANode{left,right},choose(U32,U32.mul(a,2),0,U32.is_eq(a,b)&&U32.is_gt(a,0)))))
def inspect_level(value:Level) -> Level & Dimension:
  Level{+w,+h,pixels} = value
  paired(Array<U32>,U32,Level & Dimension,inspect_array(25n,pixels),pixels => capacity => (Level{w,h,pixels},Dimension{w,h,capacity}))
def inspect_levels(values:List<&1,Level>) -> List<&1,Level> & List<&2,Dimension>:
  match values:
    case Nil{}: ([],[])
    case head <> rest:
      paired(Level,Dimension,List<&1,Level> & List<&2,Dimension>,inspect_level(head),head => info => paired(List<&1,Level>,List<&2,Dimension>,List<&1,Level> & List<&2,Dimension>,inspect_levels(rest),rest => infos => (head<>rest,info<>infos)))
def guard(allowed:Bool,code:String,index:U32) -> Result<&2,&2,Error,Unit>:
  match allowed:
    case True{}: Done{Unit{}}
    case False{}: Fail{Error{code,index}}
def validate_dimensions(values:List<&2,Dimension>,+limits:Limits,+index:U32,+capacity:U32,+logical:U32) -> Result<&2,&2,Error,Usage>:
  match values limits:
    case Nil{} _: Done{Usage{capacity,logical}}
    case Dimension{+w,+h,+size} <> rest Limits{+maximum,levels,+budget,+work,path}:
      do Result<&2,&2,Error,Usage>:
        guard(U32.is_gt(w,0)&&U32.is_gt(h,0)&&U32.is_le(w,maximum)&&U32.is_le(h,maximum),"DimensionRange",index)
        guard(U32.is_gt(size,0),"BufferShape",index)
        guard(U32.is_le(U32.mul(w,h),size),"BufferLength",index)
        guard(U32.is_le(size,U32.sub(budget,capacity)),"CapacityLimit",index)
        guard(U32.is_le(U32.mul(w,h),U32.sub(work,logical)),"WorkLimit",index)
        validate_dimensions(rest,limits,U32.add(index,1),U32.add(capacity,size),U32.add(logical,U32.mul(w,h)))

law zero_alpha_word:
  {set_alpha(4294967295,0) == 16777215 : U32}
def zero_alpha_word():
  {==}

# The tables below are actual untouched 26.3 ARGB class readouts, not a runtime
# gamma approximation. Their source provenance and complete values are compared
# against fresh actual Java receivers by the reference/native suites.

# Actual table SHA256 (canonical JSON): d3113a5d4cbd13e12d25e4d5b000aec411666f2d7b694907fd67d347a52f7512
def linear_table() -> Lookup:
  Pair{Pair{Pair{Pair{Pair{Pair{Pair{Pair{Value{0},Value{0}},Pair{Value{1},Value{1}}},Pair{Pair{Value{1},Value{2}},Pair{Value{2},Value{2}}}},Pair{Pair{Pair{Value{2},Value{3}},Pair{Value{3},Value{3}}},Pair{Pair{Value{4},Value{4}},Pair{Value{4},Value{5}}}}},Pair{Pair{Pair{Pair{Value{5},Value{6}},Pair{Value{6},Value{7}}},Pair{Pair{Value{7},Value{8}},Pair{Value{8},Value{9}}}},Pair{Pair{Pair{Value{9},Value{10}},Pair{Value{11},Value{11}}},Pair{Pair{Value{12},Value{13}},Pair{Value{13},Value{14}}}}}},Pair{Pair{Pair{Pair{Pair{Value{15},Value{16}},Pair{Value{16},Value{17}}},Pair{Pair{Value{18},Value{19}},Pair{Value{20},Value{21}}}},Pair{Pair{Pair{Value{22},Value{23}},Pair{Value{24},Value{25}}},Pair{Pair{Value{26},Value{27}},Pair{Value{28},Value{29}}}}},Pair{Pair{Pair{Pair{Value{30},Value{31}},Pair{Value{33},Value{34}}},Pair{Pair{Value{35},Value{36}},Pair{Value{38},Value{39}}}},Pair{Pair{Pair{Value{40},Value{42}},Pair{Value{43},Value{45}}},Pair{Pair{Value{46},Value{48}},Pair{Value{49},Value{51}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Value{52},Value{54}},Pair{Value{56},Value{57}}},Pair{Pair{Value{59},Value{61}},Pair{Value{63},Value{64}}}},Pair{Pair{Pair{Value{66},Value{68}},Pair{Value{70},Value{72}}},Pair{Pair{Value{74},Value{76}},Pair{Value{78},Value{80}}}}},Pair{Pair{Pair{Pair{Value{82},Value{84}},Pair{Value{86},Value{88}}},Pair{Pair{Value{91},Value{93}},Pair{Value{95},Value{97}}}},Pair{Pair{Pair{Value{100},Value{102}},Pair{Value{105},Value{107}}},Pair{Pair{Value{109},Value{112}},Pair{Value{115},Value{117}}}}}},Pair{Pair{Pair{Pair{Pair{Value{120},Value{122}},Pair{Value{125},Value{128}}},Pair{Pair{Value{130},Value{133}},Pair{Value{136},Value{139}}}},Pair{Pair{Pair{Value{142},Value{145}},Pair{Value{147},Value{150}}},Pair{Pair{Value{153},Value{156}},Pair{Value{160},Value{163}}}}},Pair{Pair{Pair{Pair{Value{166},Value{169}},Pair{Value{172},Value{175}}},Pair{Pair{Value{179},Value{182}},Pair{Value{185},Value{189}}}},Pair{Pair{Pair{Value{192},Value{196}},Pair{Value{199},Value{203}}},Pair{Pair{Value{206},Value{210}},Pair{Value{213},Value{217}}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Pair{Value{221},Value{225}},Pair{Value{228},Value{232}}},Pair{Pair{Value{236},Value{240}},Pair{Value{244},Value{248}}}},Pair{Pair{Pair{Value{252},Value{256}},Pair{Value{260},Value{264}}},Pair{Pair{Value{268},Value{272}},Pair{Value{277},Value{281}}}}},Pair{Pair{Pair{Pair{Value{285},Value{290}},Pair{Value{294},Value{298}}},Pair{Pair{Value{303},Value{307}},Pair{Value{312},Value{317}}}},Pair{Pair{Pair{Value{321},Value{326}},Pair{Value{331},Value{335}}},Pair{Pair{Value{340},Value{345}},Pair{Value{350},Value{355}}}}}},Pair{Pair{Pair{Pair{Pair{Value{360},Value{365}},Pair{Value{370},Value{375}}},Pair{Pair{Value{380},Value{385}},Pair{Value{390},Value{395}}}},Pair{Pair{Pair{Value{401},Value{406}},Pair{Value{411},Value{417}}},Pair{Pair{Value{422},Value{427}},Pair{Value{433},Value{439}}}}},Pair{Pair{Pair{Pair{Value{444},Value{450}},Pair{Value{455},Value{461}}},Pair{Pair{Value{467},Value{473}},Pair{Value{479},Value{484}}}},Pair{Pair{Pair{Value{490},Value{496}},Pair{Value{502},Value{508}}},Pair{Pair{Value{514},Value{521}},Pair{Value{527},Value{533}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Value{539},Value{546}},Pair{Value{552},Value{558}}},Pair{Pair{Value{565},Value{571}},Pair{Value{578},Value{584}}}},Pair{Pair{Pair{Value{591},Value{598}},Pair{Value{604},Value{611}}},Pair{Pair{Value{618},Value{625}},Pair{Value{631},Value{638}}}}},Pair{Pair{Pair{Pair{Value{645},Value{652}},Pair{Value{659},Value{666}}},Pair{Pair{Value{674},Value{681}},Pair{Value{688},Value{695}}}},Pair{Pair{Pair{Value{702},Value{710}},Pair{Value{717},Value{725}}},Pair{Pair{Value{732},Value{740}},Pair{Value{747},Value{755}}}}}},Pair{Pair{Pair{Pair{Pair{Value{763},Value{770}},Pair{Value{778},Value{786}}},Pair{Pair{Value{794},Value{802}},Pair{Value{809},Value{817}}}},Pair{Pair{Pair{Value{826},Value{834}},Pair{Value{842},Value{850}}},Pair{Pair{Value{858},Value{866}},Pair{Value{875},Value{883}}}}},Pair{Pair{Pair{Pair{Value{891},Value{900}},Pair{Value{908},Value{917}}},Pair{Pair{Value{925},Value{934}},Pair{Value{943},Value{952}}}},Pair{Pair{Pair{Value{960},Value{969}},Pair{Value{978},Value{987}}},Pair{Pair{Value{996},Value{1005}},Pair{Value{1014},Value{1023}}}}}}}}}

# Actual table SHA256 (canonical JSON): 9c47e13bf0858c594ac47cca540e47f7a21ab326fd4317668c76933282de47d9
def inverse_table() -> Lookup:
  Pair{Pair{Pair{Pair{Pair{Pair{Pair{Pair{Pair{Pair{Value{0},Value{3}},Pair{Value{6},Value{10}}},Pair{Pair{Value{13},Value{15}},Pair{Value{18},Value{20}}}},Pair{Pair{Pair{Value{22},Value{23}},Pair{Value{25},Value{27}}},Pair{Pair{Value{28},Value{30}},Pair{Value{31},Value{32}}}}},Pair{Pair{Pair{Pair{Value{34},Value{35}},Pair{Value{36},Value{37}}},Pair{Pair{Value{38},Value{39}},Pair{Value{40},Value{41}}}},Pair{Pair{Pair{Value{42},Value{43}},Pair{Value{44},Value{45}}},Pair{Pair{Value{46},Value{47}},Pair{Value{48},Value{49}}}}}},Pair{Pair{Pair{Pair{Pair{Value{49},Value{50}},Pair{Value{51},Value{52}}},Pair{Pair{Value{53},Value{53}},Pair{Value{54},Value{55}}}},Pair{Pair{Pair{Value{56},Value{56}},Pair{Value{57},Value{58}}},Pair{Pair{Value{58},Value{59}},Pair{Value{60},Value{61}}}}},Pair{Pair{Pair{Pair{Value{61},Value{62}},Pair{Value{62},Value{63}}},Pair{Pair{Value{64},Value{64}},Pair{Value{65},Value{66}}}},Pair{Pair{Pair{Value{66},Value{67}},Pair{Value{67},Value{68}}},Pair{Pair{Value{68},Value{69}},Pair{Value{70},Value{70}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Value{71},Value{71}},Pair{Value{72},Value{72}}},Pair{Pair{Value{73},Value{73}},Pair{Value{74},Value{74}}}},Pair{Pair{Pair{Value{75},Value{76}},Pair{Value{76},Value{77}}},Pair{Pair{Value{77},Value{78}},Pair{Value{78},Value{79}}}}},Pair{Pair{Pair{Pair{Value{79},Value{79}},Pair{Value{80},Value{80}}},Pair{Pair{Value{81},Value{81}},Pair{Value{82},Value{82}}}},Pair{Pair{Pair{Value{83},Value{83}},Pair{Value{84},Value{84}}},Pair{Pair{Value{85},Value{85}},Pair{Value{85},Value{86}}}}}},Pair{Pair{Pair{Pair{Pair{Value{86},Value{87}},Pair{Value{87},Value{88}}},Pair{Pair{Value{88},Value{88}},Pair{Value{89},Value{89}}}},Pair{Pair{Pair{Value{90},Value{90}},Pair{Value{91},Value{91}}},Pair{Pair{Value{91},Value{92}},Pair{Value{92},Value{93}}}}},Pair{Pair{Pair{Pair{Value{93},Value{93}},Pair{Value{94},Value{94}}},Pair{Pair{Value{95},Value{95}},Pair{Value{95},Value{96}}}},Pair{Pair{Pair{Value{96},Value{97}},Pair{Value{97},Value{97}}},Pair{Pair{Value{98},Value{98}},Pair{Value{98},Value{99}}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Pair{Value{99},Value{99}},Pair{Value{100},Value{100}}},Pair{Pair{Value{101},Value{101}},Pair{Value{101},Value{102}}}},Pair{Pair{Pair{Value{102},Value{102}},Pair{Value{103},Value{103}}},Pair{Pair{Value{103},Value{104}},Pair{Value{104},Value{104}}}}},Pair{Pair{Pair{Pair{Value{105},Value{105}},Pair{Value{106},Value{106}}},Pair{Pair{Value{106},Value{107}},Pair{Value{107},Value{107}}}},Pair{Pair{Pair{Value{108},Value{108}},Pair{Value{108},Value{109}}},Pair{Pair{Value{109},Value{109}},Pair{Value{110},Value{110}}}}}},Pair{Pair{Pair{Pair{Pair{Value{110},Value{110}},Pair{Value{111},Value{111}}},Pair{Pair{Value{111},Value{112}},Pair{Value{112},Value{112}}}},Pair{Pair{Pair{Value{113},Value{113}},Pair{Value{113},Value{114}}},Pair{Pair{Value{114},Value{114}},Pair{Value{115},Value{115}}}}},Pair{Pair{Pair{Pair{Value{115},Value{115}},Pair{Value{116},Value{116}}},Pair{Pair{Value{116},Value{117}},Pair{Value{117},Value{117}}}},Pair{Pair{Pair{Value{118},Value{118}},Pair{Value{118},Value{118}}},Pair{Pair{Value{119},Value{119}},Pair{Value{119},Value{120}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Value{120},Value{120}},Pair{Value{121},Value{121}}},Pair{Pair{Value{121},Value{121}},Pair{Value{122},Value{122}}}},Pair{Pair{Pair{Value{122},Value{123}},Pair{Value{123},Value{123}}},Pair{Pair{Value{123},Value{124}},Pair{Value{124},Value{124}}}}},Pair{Pair{Pair{Pair{Value{125},Value{125}},Pair{Value{125},Value{125}}},Pair{Pair{Value{126},Value{126}},Pair{Value{126},Value{126}}}},Pair{Pair{Pair{Value{127},Value{127}},Pair{Value{127},Value{128}}},Pair{Pair{Value{128},Value{128}},Pair{Value{128},Value{129}}}}}},Pair{Pair{Pair{Pair{Pair{Value{129},Value{129}},Pair{Value{129},Value{130}}},Pair{Pair{Value{130},Value{130}},Pair{Value{130},Value{131}}}},Pair{Pair{Pair{Value{131},Value{131}},Pair{Value{131},Value{132}}},Pair{Pair{Value{132},Value{132}},Pair{Value{133},Value{133}}}}},Pair{Pair{Pair{Pair{Value{133},Value{133}},Pair{Value{134},Value{134}}},Pair{Pair{Value{134},Value{134}},Pair{Value{135},Value{135}}}},Pair{Pair{Pair{Value{135},Value{135}},Pair{Value{136},Value{136}}},Pair{Pair{Value{136},Value{136}},Pair{Value{137},Value{137}}}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Pair{Pair{Value{137},Value{137}},Pair{Value{138},Value{138}}},Pair{Pair{Value{138},Value{138}},Pair{Value{138},Value{139}}}},Pair{Pair{Pair{Value{139},Value{139}},Pair{Value{139},Value{140}}},Pair{Pair{Value{140},Value{140}},Pair{Value{140},Value{141}}}}},Pair{Pair{Pair{Pair{Value{141},Value{141}},Pair{Value{141},Value{142}}},Pair{Pair{Value{142},Value{142}},Pair{Value{142},Value{143}}}},Pair{Pair{Pair{Value{143},Value{143}},Pair{Value{143},Value{143}}},Pair{Pair{Value{144},Value{144}},Pair{Value{144},Value{144}}}}}},Pair{Pair{Pair{Pair{Pair{Value{145},Value{145}},Pair{Value{145},Value{145}}},Pair{Pair{Value{146},Value{146}},Pair{Value{146},Value{146}}}},Pair{Pair{Pair{Value{146},Value{147}},Pair{Value{147},Value{147}}},Pair{Pair{Value{147},Value{148}},Pair{Value{148},Value{148}}}}},Pair{Pair{Pair{Pair{Value{148},Value{148}},Pair{Value{149},Value{149}}},Pair{Pair{Value{149},Value{149}},Pair{Value{150},Value{150}}}},Pair{Pair{Pair{Value{150},Value{150}},Pair{Value{150},Value{151}}},Pair{Pair{Value{151},Value{151}},Pair{Value{151},Value{152}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Value{152},Value{152}},Pair{Value{152},Value{152}}},Pair{Pair{Value{153},Value{153}},Pair{Value{153},Value{153}}}},Pair{Pair{Pair{Value{153},Value{154}},Pair{Value{154},Value{154}}},Pair{Pair{Value{154},Value{155}},Pair{Value{155},Value{155}}}}},Pair{Pair{Pair{Pair{Value{155},Value{155}},Pair{Value{156},Value{156}}},Pair{Pair{Value{156},Value{156}},Pair{Value{156},Value{157}}}},Pair{Pair{Pair{Value{157},Value{157}},Pair{Value{157},Value{157}}},Pair{Pair{Value{158},Value{158}},Pair{Value{158},Value{158}}}}}},Pair{Pair{Pair{Pair{Pair{Value{158},Value{159}},Pair{Value{159},Value{159}}},Pair{Pair{Value{159},Value{159}},Pair{Value{160},Value{160}}}},Pair{Pair{Pair{Value{160},Value{160}},Pair{Value{160},Value{161}}},Pair{Pair{Value{161},Value{161}},Pair{Value{161},Value{161}}}}},Pair{Pair{Pair{Pair{Value{162},Value{162}},Pair{Value{162},Value{162}}},Pair{Pair{Value{162},Value{163}},Pair{Value{163},Value{163}}}},Pair{Pair{Pair{Value{163},Value{163}},Pair{Value{164},Value{164}}},Pair{Pair{Value{164},Value{164}},Pair{Value{164},Value{165}}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Pair{Value{165},Value{165}},Pair{Value{165},Value{165}}},Pair{Pair{Value{166},Value{166}},Pair{Value{166},Value{166}}}},Pair{Pair{Pair{Value{166},Value{167}},Pair{Value{167},Value{167}}},Pair{Pair{Value{167},Value{167}},Pair{Value{168},Value{168}}}}},Pair{Pair{Pair{Pair{Value{168},Value{168}},Pair{Value{168},Value{168}}},Pair{Pair{Value{169},Value{169}},Pair{Value{169},Value{169}}}},Pair{Pair{Pair{Value{169},Value{170}},Pair{Value{170},Value{170}}},Pair{Pair{Value{170},Value{170}},Pair{Value{171},Value{171}}}}}},Pair{Pair{Pair{Pair{Pair{Value{171},Value{171}},Pair{Value{171},Value{171}}},Pair{Pair{Value{172},Value{172}},Pair{Value{172},Value{172}}}},Pair{Pair{Pair{Value{172},Value{173}},Pair{Value{173},Value{173}}},Pair{Pair{Value{173},Value{173}},Pair{Value{173},Value{174}}}}},Pair{Pair{Pair{Pair{Value{174},Value{174}},Pair{Value{174},Value{174}}},Pair{Pair{Value{175},Value{175}},Pair{Value{175},Value{175}}}},Pair{Pair{Pair{Value{175},Value{175}},Pair{Value{176},Value{176}}},Pair{Pair{Value{176},Value{176}},Pair{Value{176},Value{177}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Value{177},Value{177}},Pair{Value{177},Value{177}}},Pair{Pair{Value{177},Value{178}},Pair{Value{178},Value{178}}}},Pair{Pair{Pair{Value{178},Value{178}},Pair{Value{178},Value{179}}},Pair{Pair{Value{179},Value{179}},Pair{Value{179},Value{179}}}}},Pair{Pair{Pair{Pair{Value{179},Value{180}},Pair{Value{180},Value{180}}},Pair{Pair{Value{180},Value{180}},Pair{Value{181},Value{181}}}},Pair{Pair{Pair{Value{181},Value{181}},Pair{Value{181},Value{181}}},Pair{Pair{Value{182},Value{182}},Pair{Value{182},Value{182}}}}}},Pair{Pair{Pair{Pair{Pair{Value{182},Value{182}},Pair{Value{183},Value{183}}},Pair{Pair{Value{183},Value{183}},Pair{Value{183},Value{183}}}},Pair{Pair{Pair{Value{184},Value{184}},Pair{Value{184},Value{184}}},Pair{Pair{Value{184},Value{184}},Pair{Value{185},Value{185}}}}},Pair{Pair{Pair{Pair{Value{185},Value{185}},Pair{Value{185},Value{185}}},Pair{Pair{Value{186},Value{186}},Pair{Value{186},Value{186}}}},Pair{Pair{Pair{Value{186},Value{186}},Pair{Value{187},Value{187}}},Pair{Pair{Value{187},Value{187}},Pair{Value{187},Value{187}}}}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Pair{Pair{Pair{Value{188},Value{188}},Pair{Value{188},Value{188}}},Pair{Pair{Value{188},Value{188}},Pair{Value{189},Value{189}}}},Pair{Pair{Pair{Value{189},Value{189}},Pair{Value{189},Value{189}}},Pair{Pair{Value{190},Value{190}},Pair{Value{190},Value{190}}}}},Pair{Pair{Pair{Pair{Value{190},Value{190}},Pair{Value{191},Value{191}}},Pair{Pair{Value{191},Value{191}},Pair{Value{191},Value{191}}}},Pair{Pair{Pair{Value{191},Value{192}},Pair{Value{192},Value{192}}},Pair{Pair{Value{192},Value{192}},Pair{Value{192},Value{193}}}}}},Pair{Pair{Pair{Pair{Pair{Value{193},Value{193}},Pair{Value{193},Value{193}}},Pair{Pair{Value{193},Value{194}},Pair{Value{194},Value{194}}}},Pair{Pair{Pair{Value{194},Value{194}},Pair{Value{194},Value{194}}},Pair{Pair{Value{195},Value{195}},Pair{Value{195},Value{195}}}}},Pair{Pair{Pair{Pair{Value{195},Value{195}},Pair{Value{196},Value{196}}},Pair{Pair{Value{196},Value{196}},Pair{Value{196},Value{196}}}},Pair{Pair{Pair{Value{197},Value{197}},Pair{Value{197},Value{197}}},Pair{Pair{Value{197},Value{197}},Pair{Value{197},Value{198}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Value{198},Value{198}},Pair{Value{198},Value{198}}},Pair{Pair{Value{198},Value{199}},Pair{Value{199},Value{199}}}},Pair{Pair{Pair{Value{199},Value{199}},Pair{Value{199},Value{199}}},Pair{Pair{Value{200},Value{200}},Pair{Value{200},Value{200}}}}},Pair{Pair{Pair{Pair{Value{200},Value{200}},Pair{Value{200},Value{201}}},Pair{Pair{Value{201},Value{201}},Pair{Value{201},Value{201}}}},Pair{Pair{Pair{Value{201},Value{202}},Pair{Value{202},Value{202}}},Pair{Pair{Value{202},Value{202}},Pair{Value{202},Value{202}}}}}},Pair{Pair{Pair{Pair{Pair{Value{203},Value{203}},Pair{Value{203},Value{203}}},Pair{Pair{Value{203},Value{203}},Pair{Value{203},Value{204}}}},Pair{Pair{Pair{Value{204},Value{204}},Pair{Value{204},Value{204}}},Pair{Pair{Value{204},Value{204}},Pair{Value{205},Value{205}}}}},Pair{Pair{Pair{Pair{Value{205},Value{205}},Pair{Value{205},Value{205}}},Pair{Pair{Value{206},Value{206}},Pair{Value{206},Value{206}}}},Pair{Pair{Pair{Value{206},Value{206}},Pair{Value{206},Value{207}}},Pair{Pair{Value{207},Value{207}},Pair{Value{207},Value{207}}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Pair{Value{207},Value{207}},Pair{Value{208},Value{208}}},Pair{Pair{Value{208},Value{208}},Pair{Value{208},Value{208}}}},Pair{Pair{Pair{Value{208},Value{209}},Pair{Value{209},Value{209}}},Pair{Pair{Value{209},Value{209}},Pair{Value{209},Value{209}}}}},Pair{Pair{Pair{Pair{Value{210},Value{210}},Pair{Value{210},Value{210}}},Pair{Pair{Value{210},Value{210}},Pair{Value{210},Value{211}}}},Pair{Pair{Pair{Value{211},Value{211}},Pair{Value{211},Value{211}}},Pair{Pair{Value{211},Value{211}},Pair{Value{212},Value{212}}}}}},Pair{Pair{Pair{Pair{Pair{Value{212},Value{212}},Pair{Value{212},Value{212}}},Pair{Pair{Value{212},Value{212}},Pair{Value{213},Value{213}}}},Pair{Pair{Pair{Value{213},Value{213}},Pair{Value{213},Value{213}}},Pair{Pair{Value{213},Value{214}},Pair{Value{214},Value{214}}}}},Pair{Pair{Pair{Pair{Value{214},Value{214}},Pair{Value{214},Value{214}}},Pair{Pair{Value{215},Value{215}},Pair{Value{215},Value{215}}}},Pair{Pair{Pair{Value{215},Value{215}},Pair{Value{215},Value{216}}},Pair{Pair{Value{216},Value{216}},Pair{Value{216},Value{216}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Value{216},Value{216}},Pair{Value{216},Value{217}}},Pair{Pair{Value{217},Value{217}},Pair{Value{217},Value{217}}}},Pair{Pair{Pair{Value{217},Value{217}},Pair{Value{218},Value{218}}},Pair{Pair{Value{218},Value{218}},Pair{Value{218},Value{218}}}}},Pair{Pair{Pair{Pair{Value{218},Value{219}},Pair{Value{219},Value{219}}},Pair{Pair{Value{219},Value{219}},Pair{Value{219},Value{219}}}},Pair{Pair{Pair{Value{219},Value{220}},Pair{Value{220},Value{220}}},Pair{Pair{Value{220},Value{220}},Pair{Value{220},Value{220}}}}}},Pair{Pair{Pair{Pair{Pair{Value{221},Value{221}},Pair{Value{221},Value{221}}},Pair{Pair{Value{221},Value{221}},Pair{Value{221},Value{221}}}},Pair{Pair{Pair{Value{222},Value{222}},Pair{Value{222},Value{222}}},Pair{Pair{Value{222},Value{222}},Pair{Value{222},Value{222}}}}},Pair{Pair{Pair{Pair{Value{223},Value{223}},Pair{Value{223},Value{223}}},Pair{Pair{Value{223},Value{223}},Pair{Value{223},Value{224}}}},Pair{Pair{Pair{Value{224},Value{224}},Pair{Value{224},Value{224}}},Pair{Pair{Value{224},Value{224}},Pair{Value{224},Value{225}}}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Pair{Pair{Value{225},Value{225}},Pair{Value{225},Value{225}}},Pair{Pair{Value{225},Value{225}},Pair{Value{225},Value{226}}}},Pair{Pair{Pair{Value{226},Value{226}},Pair{Value{226},Value{226}}},Pair{Pair{Value{226},Value{226}},Pair{Value{227},Value{227}}}}},Pair{Pair{Pair{Pair{Value{227},Value{227}},Pair{Value{227},Value{227}}},Pair{Pair{Value{227},Value{227}},Pair{Value{228},Value{228}}}},Pair{Pair{Pair{Value{228},Value{228}},Pair{Value{228},Value{228}}},Pair{Pair{Value{228},Value{228}},Pair{Value{229},Value{229}}}}}},Pair{Pair{Pair{Pair{Pair{Value{229},Value{229}},Pair{Value{229},Value{229}}},Pair{Pair{Value{229},Value{229}},Pair{Value{230},Value{230}}}},Pair{Pair{Pair{Value{230},Value{230}},Pair{Value{230},Value{230}}},Pair{Pair{Value{230},Value{230}},Pair{Value{231},Value{231}}}}},Pair{Pair{Pair{Pair{Value{231},Value{231}},Pair{Value{231},Value{231}}},Pair{Pair{Value{231},Value{231}},Pair{Value{232},Value{232}}}},Pair{Pair{Pair{Value{232},Value{232}},Pair{Value{232},Value{232}}},Pair{Pair{Value{232},Value{232}},Pair{Value{233},Value{233}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Value{233},Value{233}},Pair{Value{233},Value{233}}},Pair{Pair{Value{233},Value{233}},Pair{Value{234},Value{234}}}},Pair{Pair{Pair{Value{234},Value{234}},Pair{Value{234},Value{234}}},Pair{Pair{Value{234},Value{234}},Pair{Value{235},Value{235}}}}},Pair{Pair{Pair{Pair{Value{235},Value{235}},Pair{Value{235},Value{235}}},Pair{Pair{Value{235},Value{235}},Pair{Value{236},Value{236}}}},Pair{Pair{Pair{Value{236},Value{236}},Pair{Value{236},Value{236}}},Pair{Pair{Value{236},Value{236}},Pair{Value{236},Value{237}}}}}},Pair{Pair{Pair{Pair{Pair{Value{237},Value{237}},Pair{Value{237},Value{237}}},Pair{Pair{Value{237},Value{237}},Pair{Value{237},Value{238}}}},Pair{Pair{Pair{Value{238},Value{238}},Pair{Value{238},Value{238}}},Pair{Pair{Value{238},Value{238}},Pair{Value{238},Value{239}}}}},Pair{Pair{Pair{Pair{Value{239},Value{239}},Pair{Value{239},Value{239}}},Pair{Pair{Value{239},Value{239}},Pair{Value{239},Value{239}}}},Pair{Pair{Pair{Value{240},Value{240}},Pair{Value{240},Value{240}}},Pair{Pair{Value{240},Value{240}},Pair{Value{240},Value{240}}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Pair{Value{241},Value{241}},Pair{Value{241},Value{241}}},Pair{Pair{Value{241},Value{241}},Pair{Value{241},Value{241}}}},Pair{Pair{Pair{Value{241},Value{242}},Pair{Value{242},Value{242}}},Pair{Pair{Value{242},Value{242}},Pair{Value{242},Value{242}}}}},Pair{Pair{Pair{Pair{Value{242},Value{243}},Pair{Value{243},Value{243}}},Pair{Pair{Value{243},Value{243}},Pair{Value{243},Value{243}}}},Pair{Pair{Pair{Value{243},Value{243}},Pair{Value{244},Value{244}}},Pair{Pair{Value{244},Value{244}},Pair{Value{244},Value{244}}}}}},Pair{Pair{Pair{Pair{Pair{Value{244},Value{244}},Pair{Value{245},Value{245}}},Pair{Pair{Value{245},Value{245}},Pair{Value{245},Value{245}}}},Pair{Pair{Pair{Value{245},Value{245}},Pair{Value{245},Value{246}}},Pair{Pair{Value{246},Value{246}},Pair{Value{246},Value{246}}}}},Pair{Pair{Pair{Pair{Value{246},Value{246}},Pair{Value{246},Value{246}}},Pair{Pair{Value{247},Value{247}},Pair{Value{247},Value{247}}}},Pair{Pair{Pair{Value{247},Value{247}},Pair{Value{247},Value{247}}},Pair{Pair{Value{248},Value{248}},Pair{Value{248},Value{248}}}}}}},Pair{Pair{Pair{Pair{Pair{Pair{Value{248},Value{248}},Pair{Value{248},Value{248}}},Pair{Pair{Value{248},Value{249}},Pair{Value{249},Value{249}}}},Pair{Pair{Pair{Value{249},Value{249}},Pair{Value{249},Value{249}}},Pair{Pair{Value{249},Value{249}},Pair{Value{250},Value{250}}}}},Pair{Pair{Pair{Pair{Value{250},Value{250}},Pair{Value{250},Value{250}}},Pair{Pair{Value{250},Value{250}},Pair{Value{250},Value{251}}}},Pair{Pair{Pair{Value{251},Value{251}},Pair{Value{251},Value{251}}},Pair{Pair{Value{251},Value{251}},Pair{Value{251},Value{251}}}}}},Pair{Pair{Pair{Pair{Pair{Value{252},Value{252}},Pair{Value{252},Value{252}}},Pair{Pair{Value{252},Value{252}},Pair{Value{252},Value{252}}}},Pair{Pair{Pair{Value{252},Value{253}},Pair{Value{253},Value{253}}},Pair{Pair{Value{253},Value{253}},Pair{Value{253},Value{253}}}}},Pair{Pair{Pair{Pair{Value{253},Value{253}},Pair{Value{254},Value{254}}},Pair{Pair{Value{254},Value{254}},Pair{Value{254},Value{254}}}},Pair{Pair{Pair{Value{254},Value{254}},Pair{Value{254},Value{255}}},Pair{Pair{Value{255},Value{255}},Pair{Value{255},Value{255}}}}}}}}}}}

def tables() -> Tables:
  Tables{linear_table(),inverse_table()}

type Quad is Data:
  Quad{a:U32,b:U32,c:U32,d:U32}
type AlphaQuad is Data:
  AlphaQuad{a:F32,b:F32,c:F32,d:F32}
type Queue is Data:
  Queue{front:List<&2,U32>,back:List<&2,U32>}
type Popped is Data:
  Popped{index:U32,queue:Queue}
type Flood is Type:
  Flood{colors:Array<U32>,distance:Array<U32>,queue:Queue}

def reverse(values:List<&2,U32>,acc:List<&2,U32>) -> List<&2,U32>:
  match values:
    case Nil{}: acc
    case h <> rest: reverse(rest,h<>acc)
def pop_front(values:List<&2,U32>,back:List<&2,U32>) -> Maybe<&2,Popped>:
  match values:
    case Nil{}: None{}
    case h <> rest: Some{Popped{h,Queue{rest,back}}}
def pop(value:Queue) -> Maybe<&2,Popped>:
  match value:
    case Queue{Nil{},back}: pop_front(reverse(back,[]),[])
    case Queue{h<>rest,back}: Some{Popped{h,Queue{rest,back}}}
def enqueue(value:Queue,index:U32) -> Queue:
  Queue{front,back} = value
  Queue{front,index<>back}
def quad(pixels:Array<U32>,+index:U32,+w:U32) -> Array<U32> & Quad:
  paired(Array<U32>,U32,Array<U32> & Quad,Array.get(U32,pixels,index),pixels => a => paired(Array<U32>,U32,Array<U32> & Quad,Array.get(U32,pixels,U32.add(index,1)),pixels => b => paired(Array<U32>,U32,Array<U32> & Quad,Array.get(U32,pixels,U32.add(index,w)),pixels => c => paired(Array<U32>,U32,Array<U32> & Quad,Array.get(U32,pixels,U32.add(U32.add(index,w),1)),pixels => d => (pixels,Quad{a,b,c,d})))))
def seed_if(pixels:Array<U32>,colors:Array<U32>,distance:Array<U32>,queue:Queue,+index:U32,+pixel:U32,opaque:Bool) -> Array<U32> & Flood:
  match opaque:
    case False{}: (pixels,Flood{colors,distance,queue})
    case True{}: (pixels,Flood{Array.set(U32,colors,index,pixel),Array.set(U32,distance,index,0),enqueue(queue,index)})
def seed(fuel:Nat,pixels:Array<U32>,state:Flood,+w:U32,+h:U32,+at:U32) -> Array<U32> & Flood:
  match fuel:
    case 0n: (pixels,state)
    case 1n+p:
      Flood{colors,distance,queue} = state
      +index = U32.add(U32.div(at,h),U32.mul(U32.mod(at,h),w))
      paired(Array<U32>,U32,Array<U32> & Flood,Array.get(U32,pixels,index),pixels => +pixel => paired(Array<U32>,Flood,Array<U32> & Flood,seed_if(pixels,colors,distance,queue,index,pixel,U32.is_gt(alpha(pixel),0)),pixels => state => seed(p,pixels,state,w,h,U32.add(at,1))))
def visit_if(colors:Array<U32>,distance:Array<U32>,queue:Queue,+index:U32,pixel:U32,+next:U32,update:Bool) -> Flood:
  match update:
    case False{}: Flood{colors,distance,queue}
    case True{}: Flood{Array.set(U32,colors,index,pixel),Array.set(U32,distance,index,next),enqueue(queue,index)}
def visit(state:Flood,+index:U32,pixel:U32,+next:U32,inside:Bool) -> Flood:
  match state inside:
    case Flood{colors,distance,queue} False{}: Flood{colors,distance,queue}
    case Flood{colors,distance,queue} True{}:
      paired(Array<U32>,U32,Flood,Array.get(U32,distance,index),distance => found => visit_if(colors,distance,queue,index,pixel,next,U32.is_gt(found,next)))
def neighbors(state:Flood,+index:U32,+pixel:U32,+next:U32,+w:U32,+h:U32) -> Flood:
  +x = U32.mod(index,w)
  +y = U32.div(index,w)
  right = visit(state,U32.add(index,1),pixel,next,U32.is_lt(U32.add(x,1),w))
  left = visit(right,U32.sub(index,1),pixel,next,U32.is_gt(x,0))
  down = visit(left,U32.add(index,w),pixel,next,U32.is_lt(U32.add(y,1),h))
  visit(down,U32.sub(index,w),pixel,next,U32.is_gt(y,0))
def flood_step(f:Flood -> Flood,colors:Array<U32>,distance:Array<U32>,+w:U32,+h:U32,value:Maybe<&2,Popped>) -> Flood:
  match value:
    case None{}: Flood{colors,distance,Queue{[],[]}}
    case Some{Popped{+index,queue}}:
      paired(Array<U32>,U32,Flood,Array.get(U32,colors,index),colors => pixel => paired(Array<U32>,U32,Flood,Array.get(U32,distance,index),distance => found => f(neighbors(Flood{colors,distance,queue},index,pixel,U32.add(found,1),w,h))))
def flood(fuel:Nat,state:Flood,+w:U32,+h:U32) -> Flood:
  match fuel:
    case 0n: state
    case 1n+p:
      Flood{colors,distance,+queue} = state
      flood_step(state => flood(p,state,w,h),colors,distance,w,h,pop(queue))
def fill_from_colors(fuel:Nat,pixels:Array<U32>,colors:Array<U32>,+index:U32) -> Array<U32>:
  match fuel:
    case 0n: pixels
    case 1n+p:
      paired(Array<U32>,U32,Array<U32>,Array.get(U32,pixels,index),pixels => +pixel => paired(Array<U32>,U32,Array<U32>,Array.get(U32,colors,index),colors => color => fill_from_colors(p,Array.set(U32,pixels,index,choose(U32,set_alpha(color,0),pixel,U32.is_eq(alpha(pixel),0))),colors,U32.add(index,1))))
def solidify_finish(+w:U32,+h:U32,pixels:Array<U32>,value:Flood) -> Level:
  Flood{colors,distance,queue} = value
  Level{w,h,fill_from_colors(U32.to_nat(U32.mul(w,h)),pixels,colors,0)}
def solidify(value:Level) -> Level:
  Level{+w,+h,pixels} = value
  paired(Array<U32>,Flood,Level,seed(U32.to_nat(U32.mul(w,h)),pixels,Flood{new_pixels(w,h,0),new_pixels(w,h,2147483647),Queue{[],[]}},w,h,0),pixels => state => solidify_finish(w,h,pixels,flood(U32.to_nat(U32.mul(w,h)),state,w,h)))
def dark_min(fuel:Nat,pixels:Array<U32>,+w:U32,+h:U32,+at:U32,+minimum:U32,+selected:U32) -> Array<U32> & U32:
  match fuel:
    case 0n: (pixels,selected)
    case 1n+p:
      index = U32.add(U32.div(at,h),U32.mul(U32.mod(at,h),w))
      paired(Array<U32>,U32,Array<U32> & U32,Array.get(U32,pixels,index),pixels => +pixel => (
        +sum = (channel(pixel,16n) + channel(pixel,8n) + channel(pixel,0n) : U32)
        +update = U32.is_gt(alpha(pixel),0)&&U32.is_lt(sum,minimum)
        dark_min(p,pixels,w,h,U32.add(at,1),choose(U32,sum,minimum,update),choose(U32,pixel,selected,update))))
def fill_dark(fuel:Nat,pixels:Array<U32>,+index:U32,+color:U32) -> Array<U32>:
  match fuel:
    case 0n: pixels
    case 1n+p:
      paired(Array<U32>,U32,Array<U32>,Array.get(U32,pixels,index),pixels => +pixel => fill_dark(p,Array.set(U32,pixels,index,choose(U32,color,pixel,U32.is_eq(alpha(pixel),0))),U32.add(index,1),color))
def dark_color(+value:U32) -> U32:
  argb(0,U32.div(U32.mul(3,channel(value,16n)),4),U32.div(U32.mul(3,channel(value,8n)),4),U32.div(U32.mul(3,channel(value,0n)),4))
def dark_fill(value:Level) -> Level:
  Level{+w,+h,pixels} = value
  paired(Array<U32>,U32,Level,dark_min(U32.to_nat(U32.mul(w,h)),pixels,w,h,0,2147483647,4294967295),pixels => color => Level{w,h,fill_dark(U32.to_nat(U32.mul(w,h)),pixels,0,dark_color(color))})
def precondition(value:Level,strategy:Strategy) -> Level:
  match strategy:
    case Cutout{}: solidify(value)
    case StrictCutout{}: solidify(value)
    case DarkCutout{}: dark_fill(value)
    case _: value

def clamp(+value:F32) -> F32:
  choose(F32,1.0,choose(F32,0.0,value,F32.is_lt(value,0.0)),F32.is_gt(value,1.0))
def alpha_float(pixel:U32,scale:F32) -> F32:
  clamp(F32.mul(F32.div(U32.to_f32(alpha(pixel)),255.0),scale))
def alpha_quad(value:Quad,+scale:F32) -> AlphaQuad:
  Quad{a,b,c,d} = value
  AlphaQuad{alpha_float(a,scale),alpha_float(b,scale),alpha_float(c,scale),alpha_float(d,scale)}
def bilinear(value:AlphaQuad,+x:F32,+y:F32) -> F32:
  AlphaQuad{a,b,c,d} = value
  F32.add(F32.add(F32.add(F32.mul(F32.mul(a,F32.sub(1.0,x)),F32.sub(1.0,y)),F32.mul(F32.mul(b,x),F32.sub(1.0,y))),F32.mul(F32.mul(c,F32.sub(1.0,x)),y)),F32.mul(F32.mul(d,x),y))
def samples(fuel:Nat,+value:AlphaQuad,+cut:F32,+index:U32,count:U32) -> U32:
  match fuel:
    case 0n: count
    case 1n+p:
      x = F32.div(F32.add(U32.to_f32(U32.mod(index,4)),0.5),4.0)
      y = F32.div(F32.add(U32.to_f32(U32.div(index,4)),0.5),4.0)
      samples(p,value,cut,U32.add(index,1),U32.add(count,choose(U32,1,0,F32.is_gt(bilinear(value,x,y),cut))))
def coverage_pixels(fuel:Nat,pixels:Array<U32>,+w:U32,+cut:F32,+scale:F32,+index:U32,total:F32) -> Array<U32> & F32:
  match fuel:
    case 0n: (pixels,total)
    case 1n+p:
      at = U32.add(U32.mod(index,U32.sub(w,1)),U32.mul(U32.div(index,U32.sub(w,1)),w))
      paired(Array<U32>,Quad,Array<U32> & F32,quad(pixels,at,w),pixels => q => coverage_pixels(p,pixels,w,cut,scale,U32.add(index,1),F32.add(total,F32.div(U32.to_f32(samples(16n,alpha_quad(q,scale),cut,0,0)),16.0))))
def coverage(value:Level,cut:F32,scale:F32) -> Level & F32:
  Level{+w,+h,pixels} = value
  +cells = U32.mul(U32.sub(w,1),U32.sub(h,1))
  paired(Array<U32>,F32,Level & F32,coverage_pixels(U32.to_nat(cells),pixels,w,cut,scale,0,0.0),pixels => count => (Level{w,h,pixels},F32.div(count,U32.to_f32(cells))))
def magnitude(+value:F32) -> F32:
  choose(F32,F32.sub(0.0,value),value,F32.is_lt(value,0.0))
def search_if(f:Level -> Level & F32,value:Level,best:F32,again:Bool) -> Level & F32:
  match again:
    case True{}: f(value)
    case False{}: (value,best)
def search(fuel:Nat,value:Level,+target:F32,+cut:F32,+low:F32,+high:F32,+candidate:F32,+best:F32,+error:F32) -> Level & F32:
  match fuel:
    case 0n: (value,best)
    case 1n+p:
      paired(Level,F32,Level & F32,coverage(value,cut,candidate),value => +found => (
        +next_error = magnitude(F32.sub(found,target))
        +closer = F32.is_lt(next_error,error)
        +next_best = choose(F32,candidate,best,closer)
        +lower = F32.is_lt(found,target)
        +upper = F32.is_gt(found,target)
        +next_low = choose(F32,candidate,low,lower)
        +next_high = choose(F32,candidate,high,upper)
        search_if(value => search(p,value,target,cut,next_low,next_high,F32.mul(F32.add(next_low,next_high),0.5),next_best,choose(F32,next_error,error,closer)),value,next_best,lower||upper)))
def alpha_word(value:F32,not_nan:Bool) -> U32:
  match not_nan:
    case False{}: 0
    case True{}: F32.to_u32(F32.mul(value,255.0))
def scaled_alpha(+pixel:U32,best:F32,bias:F32) -> U32:
  +value = clamp(F32.add(F32.add(F32.mul(F32.div(U32.to_f32(alpha(pixel)),255.0),best),bias),0.025))
  set_alpha(pixel,alpha_word(value,F32.is_eq(value,value)))
def scale_pixels(fuel:Nat,pixels:Array<U32>,+index:U32,+best:F32,+bias:F32) -> Array<U32>:
  match fuel:
    case 0n: pixels
    case 1n+p:
      paired(Array<U32>,U32,Array<U32>,Array.get(U32,pixels,index),pixels => pixel => scale_pixels(p,Array.set(U32,pixels,index,scaled_alpha(pixel,best,bias)),U32.add(index,1),best,bias))
def scale_finish(value:Level,best:F32,bias:F32) -> Level:
  Level{+w,+h,pixels} = value
  Level{w,h,scale_pixels(U32.to_nat(U32.mul(w,h)),pixels,0,best,bias)}
def scale(value:Level,target:F32,cut:F32,+bias:F32) -> Level:
  paired(Level,F32,Level,search(5n,value,target,cut,0.0,4.0,1.0,1.0,3.4028235e38),value => best => scale_finish(value,best,bias))

type Plan is Data:
  Plan{effective:Strategy,early_return:Bool,precondition:Bool,original_levels:U32}
type Next is Type:
  Next{previous:Level,next:Level,remaining:List<&1,Level>}
def blend_quad(t:Tables,strategy:Strategy,value:Quad) -> U32:
  Quad{a,b,c,d} = value
  blend(t,strategy,a,b,c,d)
def down_pixels(fuel:Nat,input:Array<U32>,output:Array<U32>,+source_width:U32,+width:U32,+height:U32,+at:U32,+t:Tables,+strategy:Strategy) -> Array<U32> & Array<U32>:
  match fuel:
    case 0n: (input,output)
    case 1n+p:
      +x = U32.div(at,height)
      +y = U32.mod(at,height)
      source = U32.add(U32.mul(x,2),U32.mul(U32.mul(y,2),source_width))
      index = U32.add(x,U32.mul(y,width))
      paired(Array<U32>,Quad,Array<U32> & Array<U32>,quad(input,source,source_width),input => q => down_pixels(p,input,Array.set(U32,output,index,blend_quad(t,strategy,q)),source_width,width,height,U32.add(at,1),t,strategy))
def downsample(value:Level,t:Tables,strategy:Strategy) -> Level & Level:
  Level{+w,+h,pixels} = value
  +width = U32.shr(w)
  +height = U32.shr(h)
  paired(Array<U32>,Array<U32>,Level & Level,down_pixels(U32.to_nat(U32.mul(width,height)),pixels,new_pixels(width,height,0),w,width,height,0,t,strategy),pixels => next => (Level{w,h,pixels},Level{width,height,next}))
def next_pair(value:Level & Level,remaining:List<&1,Level>) -> Next:
  (previous,next) = value
  Next{previous,next,remaining}
def next_level(previous:Level,remaining:List<&1,Level>,t:Tables,strategy:Strategy) -> Next:
  match remaining:
    case Nil{}: next_pair(downsample(previous,t,strategy),[])
    case next <> rest: Next{previous,next,rest}
def maybe_scale(value:Level,strategy:Strategy,target:F32,bias:F32) -> Level:
  match strategy:
    case Mean{}: value
    case Auto{}: value
    case _: scale(value,target,cutoff(strategy),bias)
def reverse_levels(values:List<&1,Level>,acc:List<&1,Level>) -> List<&1,Level>:
  match values:
    case Nil{}: acc
    case h <> rest: reverse_levels(rest,h<>acc)
def append_levels(values:List<&1,Level>,tail:List<&1,Level>) -> List<&1,Level>:
  match values:
    case Nil{}: tail
    case h <> rest: h <> append_levels(rest,tail)
def grow_next(f:Level -> List<&1,Level> -> List<&1,Level> -> List<&1,Level>,value:Next,acc:List<&1,Level>,+strategy:Strategy,target:F32,bias:F32) -> List<&1,Level>:
  Next{previous,next,remaining} = value
  f(maybe_scale(next,strategy,target,bias))(remaining)(previous<>acc)
def grow(fuel:Nat,previous:Level,remaining:List<&1,Level>,acc:List<&1,Level>,+t:Tables,+strategy:Strategy,+target:F32,+bias:F32) -> List<&1,Level>:
  match fuel:
    case 0n: append_levels(reverse_levels(previous<>acc,[]),remaining)
    case 1n+p: grow_next(next => rest => acc => grow(p,next,rest,acc,t,strategy,target,bias),next_level(previous,remaining,t,strategy),acc,strategy,target,bias)
def maybe_precondition(value:Level,strategy:Strategy,enabled:Bool) -> Level:
  match enabled:
    case False{}: value
    case True{}: precondition(value,strategy)
def base_coverage(value:Level,+strategy:Strategy) -> Level & F32:
  match strategy:
    case Mean{}: (value,0.0)
    case Auto{}: (value,0.0)
    case _: coverage(value,cutoff(strategy),1.0)
def process(values:List<&1,Level>,+plan:Plan,+config:Config) -> List<&1,Level>:
  match values plan:
    case Nil{} _: []
    case first <> rest Plan{+strategy,True{},+pre,count}: maybe_precondition(first,strategy,pre) <> rest
    case first <> rest Plan{+strategy,False{},+pre,count}:
      Config{path,+target,requested,+bias,tr} = config
      paired(Level,F32,List<&1,Level>,base_coverage(maybe_precondition(first,strategy,pre),strategy),first => coverage => grow(U32.to_nat(target),first,rest,[],tables(),strategy,coverage,bias))
def last_dimension(values:List<&2,Dimension>,last:Dimension) -> Dimension:
  match values:
    case Nil{}: last
    case h <> rest: last_dimension(rest,h)
def first_dimension(values:List<&2,Dimension>) -> Dimension:
  match values:
    case Nil{}: Dimension{0,0,0}
    case h <> rest: h
def dimension_width(value:Dimension) -> U32:
  Dimension{w,h,c} = value
  w
def dimension_height(value:Dimension) -> U32:
  Dimension{w,h,c} = value
  h
def validates_generated(fuel:Nat,+w:U32,+h:U32,+index:U32,+limits:Limits,+capacity:U32,+logical:U32) -> Result<&2,&2,Error,Unit>:
  match fuel:
    case 0n: Done{Unit{}}
    case 1n+p:
      Limits{maximum,levels,+budget,+work,path} = limits
      +nw = U32.shr(w)
      +nh = U32.shr(h)
      +size = rounded_capacity(24n,U32.mul(nw,nh),1)
      do Result<&2,&2,Error,Unit>:
        guard(U32.is_gt(nw,0)&&U32.is_gt(nh,0),"ZeroGeneratedDimension",index)
        guard(U32.is_le(size,U32.sub(budget,capacity)),"CapacityLimit",index)
        guard(U32.is_le(U32.mul(nw,nh),U32.sub(work,logical)),"WorkLimit",index)
        validates_generated(p,nw,nh,U32.add(index,1),limits,U32.add(capacity,size),U32.add(logical,U32.mul(nw,nh)))
def extra_capacity(value:Strategy,size:U32,pre:Bool) -> U32:
  match value pre:
    case Cutout{} True{}: U32.mul(size,2)
    case StrictCutout{} True{}: U32.mul(size,2)
    case _ _: 0
def plan_usage(+dimensions:List<&2,Dimension>,+limits:Limits,+config:Config,value:Usage) -> Result<&2,&2,Error,Plan>:
  Limits{dimension,levels,+budget,work,pathlimit} = limits
  Config{+path,+target,+requested,bias,tr} = config
  Usage{+capacity,+logical} = value
  +count = U32.from_nat(List.length(&2,Dimension,dimensions))
  +strategy = effective(requested,tr)
  +pre = U32.is_eq(count,1)&&Bool.not(String.starts_with(path,"item/"))&&cutout(strategy)
  +early = U32.is_ge(count,U32.add(target,1))
  +first = first_dimension(dimensions)
  +last = last_dimension(dimensions,Dimension{0,0,0})
  fw = dimension_width(first)
  fh = dimension_height(first)
  lw = dimension_width(last)
  lh = dimension_height(last)
  +extra = extra_capacity(strategy,rounded_capacity(24n,U32.mul(fw,fh),1),pre)
  do Result<&2,&2,Error,Plan>:
    guard(U32.is_le(extra,U32.sub(budget,capacity)),"CapacityLimit",0)
    validates_generated(U32.to_nat(choose(U32,0,U32.sub(U32.add(target,1),count),early)),lw,lh,count,limits,U32.add(capacity,extra),logical)
    Done{Plan{strategy,early,pre,count}}
def validate(+dimensions:List<&2,Dimension>,+config:Config,+limits:Limits) -> Result<&2,&2,Error,Plan>:
  Config{+path,+target,strategy,bias,tr} = config
  Limits{+maximum,+levels,+budget,+work,+pathlimit} = limits
  do Result<&2,&2,Error,Plan>:
    guard(U32.is_gt(maximum,0)&&U32.is_le(maximum,16384)&&U32.is_gt(levels,0)&&U32.is_le(levels,16)&&U32.is_le(budget,16777216)&&U32.is_le(work,16777216)&&U32.is_le(pathlimit,65536),"LimitsRange",0)
    guard(U32.is_lt(target,levels),"LevelRange",target)
    guard(Nat.is_le(String.length(path),U32.to_nat(pathlimit)),"PathLimit",0)
    guard(Nat.is_ge(List.length(&2,Dimension,dimensions),1n)&&Nat.is_le(List.length(&2,Dimension,dimensions),U32.to_nat(levels)),"LevelCount",0)
    usage : Usage <- validate_dimensions(dimensions,limits,0,0,0)
    plan_usage(dimensions,limits,config,usage)
def finish(values:List<&1,Level>,plan:Plan) -> Chain & Result<&2,&2,Error,Summary>:
  Plan{strategy,early,pre,count} = plan
  paired(List<&1,Level>,List<&2,Dimension>,Chain & Result<&2,&2,Error,Summary>,inspect_levels(values),values => dimensions => (Chain{values},Done{Summary{strategy,early,pre,count,dimensions}}))
def admitted(values:List<&1,Level>,+config:Config,result:Result<&2,&2,Error,Plan>) -> Chain & Result<&2,&2,Error,Summary>:
  match result:
    case Fail{e}: (Chain{values},Fail{e})
    case Done{+plan}: finish(process(values,plan,config),plan)
def generate(value:Chain,+config:Config,+limits:Limits) -> Chain & Result<&2,&2,Error,Summary>:
  Chain{values} = value
  paired(List<&1,Level>,List<&2,Dimension>,Chain & Result<&2,&2,Error,Summary>,inspect_levels(values),values => dimensions => admitted(values,config,validate(dimensions,config,limits)))

# Caller-visible diagnostics copy scalar Data words while retaining every array.
def compute_transparency_pixels(fuel:Nat,pixels:Array<U32>,+index:U32,+transparent:Bool,+translucent:Bool) -> Array<U32> & Transparency:
  match fuel:
    case 0n: (pixels,Transparency{transparent,translucent})
    case 1n+p:
      paired(Array<U32>,U32,Array<U32> & Transparency,Array.get(U32,pixels,index),pixels => pixel => (
        +a = alpha(pixel)
        compute_transparency_pixels(p,pixels,U32.add(index,1),transparent||U32.is_eq(a,0),translucent||(U32.is_gt(a,0)&&U32.is_lt(a,255)))))
def compute_transparency_unchecked(value:Level) -> Level & Transparency:
  Level{+w,+h,pixels} = value
  paired(Array<U32>,Transparency,Level & Transparency,compute_transparency_pixels(U32.to_nat(U32.mul(w,h)),pixels,0,False{},False{}),pixels => transparency => (Level{w,h,pixels},transparency))
def compute_admitted(value:Level,result:Result<&2,&2,Error,Plan>) -> Level & Result<&2,&2,Error,Transparency>:
  match result:
    case Fail{e}: (value,Fail{e})
    case Done{plan}: paired(Level,Transparency,Level & Result<&2,&2,Error,Transparency>,compute_transparency_unchecked(value),value => transparency => (value,Done{transparency}))
def compute_transparency(value:Level,+limits:Limits) -> Level & Result<&2,&2,Error,Transparency>:
  paired(Level,Dimension,Level & Result<&2,&2,Error,Transparency>,inspect_level(value),value => dimension => compute_admitted(value,validate([dimension],Config{"",0,Mean{},0.0,Transparency{False{},False{}}},limits)))
def close_levels(values:List<&1,Level>) -> Unit:
  match values:
    case Nil{}: Unit{}
    case Level{w,h,pixels} <> rest: close_levels(rest)
def close_chain(value:Chain) -> Unit:
  Chain{values} = value
  close_levels(values)

law black_mean:
  {mean(tables(),0,0,0,0) == 0 : U32}
def black_mean():
  {==}
law white_mean:
  {mean(tables(),4294967295,4294967295,4294967295,4294967295) == 4294967295 : U32}
def white_mean():
  {==}
