import Base
import ./worldgen_density_ast.bend as A
import ./worldgen_density_number.bend as Number
import ./worldgen_noise_settings.bend as NS
import ./worldgen_noise_settings_codec.bend as NC
import ./worldgen_density_noise.bend as DN
import ./worldgen_blended_noise.bend as BL
import ./world_generation_settings.bend as WG
import ./json.bend as J
import ./f64.bend as F

def identifier_checked(text:String,valid:Bool) -> Result<&2,&2,String,String>:
  match valid:
    case False{}: Fail{"density resource identifier required"}
    case True{}: Done{text}

def identifier(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{+text}: identifier_checked(text,WG.identifier(text))
    case _: Fail{"density resource identifier required"}

def double(value:J.Value) -> Result<&2,&2,String,F.F64>:
  match value:
    case J.JNumber{raw}: Number.read(raw)
    case _: Fail{"density binary64 number required"}

def float_range(value:F32,valid:Bool) -> Result<&2,&2,String,F32>:
  match valid:
    case True{}: Done{value}
    case False{}: Fail{"density float outside actual noise-value codec range"}

def float_read(result:Maybe<&2,F32>) -> Result<&2,&2,String,F32>:
  match result:
    case None{}: Fail{"density float token could not be decoded"}
    case Some{+value}: float_range(value,F32.is_ge(value,F32.neg(1000000.0)) && F32.is_le(value,1000000.0))

def float_checked(raw:String,valid:Bool) -> Result<&2,&2,String,F32>:
  match valid:
    case False{}: Fail{"density float is not a bounded JSON number token"}
    case True{}: float_read(F32.read(raw))

# The actual density constant/threshold codec is FLOAT, not a double narrowed
# after decoding. Native F32.read uses strtof directly; IEEE boundary parity is
# checked separately from structural ownership and resource contracts.
def float(value:J.Value) -> Result<&2,&2,String,F32>:
  match value:
    case J.JNumber{+raw}: float_checked(raw,NS.number_valid(raw) && J.within(128n,raw))
    case _: Fail{"density float number required"}

def axis(value:J.Value) -> Result<&2,&2,String,A.Axis>:
  match value:
    case J.JString{"x"}: Done{A.X{}}
    case J.JString{"y"}: Done{A.Y{}}
    case J.JString{"z"}: Done{A.Z{}}
    case _: Fail{"density gradient axis must be x, y or z"}

def tiling(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,Unit>:
  match value:
    case None{}: Done{Unit{}}
    case _: Fail{"explicit gradient tiling requires the loaded tiling-mode implementation"}

def gradient_checked(form:A.Form,valid:Bool) -> Result<&2,&2,String,A.Form>:
  match valid:
    case True{}: Done{form}
    case False{}: Fail{"density gradient coordinates must differ"}

def gradient(+root:J.Value) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    axis_value:J.Value <- NC.field(root,"axis")
    direction:A.Axis <- axis(axis_value)
    tiling_ok:Unit <- tiling(J.member(root,"tiling"))
    bottom_value:J.Value <- NC.field(root,"from_coordinate")
    +bottom:U32 <- NC.integer(bottom_value)
    top_value:J.Value <- NC.field(root,"to_coordinate")
    +top:U32 <- NC.integer(top_value)
    from_value:J.Value <- NC.field(root,"from_value")
    from:F32 <- float(from_value)
    to_value:J.Value <- NC.field(root,"to_value")
    to:F32 <- float(to_value)
    gradient_checked(A.Gradient{direction,bottom,top,from,to},U32.is_ne(bottom,top))

def unary(operation:A.Unary,root:J.Value) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    input:J.Value <- NC.field(root,"input")
    return A.Unary{operation,input}

def binary(operation:A.Binary,+root:J.Value) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    left:J.Value <- NC.field(root,"left")
    right:J.Value <- NC.field(root,"right")
    return A.Binary{operation,left,right}

def clamp(+root:J.Value) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    input:J.Value <- NC.field(root,"input")
    low_value:J.Value <- NC.field(root,"min")
    low:F32 <- float(low_value)
    high_value:J.Value <- NC.field(root,"max")
    high:F32 <- float(high_value)
    return A.Clamp{input,low,high}

def lerp(+root:J.Value) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    alpha:J.Value <- NC.field(root,"alpha")
    first:J.Value <- NC.field(root,"first")
    second:J.Value <- NC.field(root,"second")
    return A.Lerp{alpha,first,second}

def range_choice(+root:J.Value) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    input:J.Value <- NC.field(root,"input")
    low_value:J.Value <- NC.field(root,"min_inclusive")
    low:F32 <- float(low_value)
    high_value:J.Value <- NC.field(root,"max_exclusive")
    high:F32 <- float(high_value)
    inside:J.Value <- NC.field(root,"when_in_range")
    outside:J.Value <- NC.field(root,"when_out_of_range")
    return A.RangeChoice{input,low,high,inside,outside}

def cache(root:J.Value) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    input:J.Value <- NC.field(root,"input")
    return A.Cache{input}

def base_checked(config:BL.Config,valid:Bool) -> Result<&2,&2,String,A.Form>:
  match valid:
    case True{}: Done{A.BaseNoise{config}}
    case False{}: Fail{"old blended noise configuration outside actual codec range"}

def base(+root:J.Value) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    xz_value:J.Value <- NC.field(root,"xz_scale")
    xz:F.F64 <- double(xz_value)
    y_value:J.Value <- NC.field(root,"y_scale")
    y:F.F64 <- double(y_value)
    xz_factor_value:J.Value <- NC.field(root,"xz_factor")
    xz_factor:F.F64 <- double(xz_factor_value)
    y_factor_value:J.Value <- NC.field(root,"y_factor")
    y_factor:F.F64 <- double(y_factor_value)
    smear_value:J.Value <- NC.field(root,"smear_scale_multiplier")
    smear:F.F64 <- double(smear_value)
    +config:BL.Config = BL.Config{xz,y,xz_factor,y_factor,smear}
    base_checked(config,BL.config_valid(config))

def default_shift(value:Maybe<&2,J.Value>) -> J.Value:
  match value:
    case Some{value}: value
    case None{}: J.JNumber{"0"}

def noise(+root:J.Value) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    name_value:J.Value <- NC.field(root,"noise")
    name:String <- identifier(name_value)
    xz_value:J.Value <- NC.field(root,"xz_scale")
    xz:F.F64 <- double(xz_value)
    y_value:J.Value <- NC.field(root,"y_scale")
    y:F.F64 <- double(y_value)
    return A.Noise{name,xz,y,default_shift(J.member(root,"shift_x")),
      default_shift(J.member(root,"shift_y")),default_shift(J.member(root,"shift_z"))}

def shift(root:J.Value,is_a:Bool) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    name_value:J.Value <- NC.field(root,"noise")
    +name:String <- identifier(name_value)
    return Bool.pick(A.Form,is_a,A.ShiftA{name},A.ShiftB{name})

def constant(root:J.Value) -> Result<&2,&2,String,A.Form>:
  do Result<&2,&2,String,A.Form>:
    value:J.Value <- NC.field(root,"value")
    number:F32 <- float(value)
    return A.Constant{number}

def object(kind:String,root:J.Value) -> Result<&2,&2,String,A.Form>:
  match kind:
    case "minecraft:constant": constant(root)
    case "minecraft:abs": unary(A.Abs{},root)
    case "minecraft:square": unary(A.Square{},root)
    case "minecraft:cube": unary(A.Cube{},root)
    case "minecraft:half_negative": unary(A.HalfNegative{},root)
    case "minecraft:quarter_negative": unary(A.QuarterNegative{},root)
    case "minecraft:squeeze": unary(A.Squeeze{},root)
    case "minecraft:negate": unary(A.Negate{},root)
    case "minecraft:add": binary(A.Add{},root)
    case "minecraft:sub": binary(A.Subtract{},root)
    case "minecraft:mul": binary(A.Multiply{},root)
    case "minecraft:div": binary(A.Divide{},root)
    case "minecraft:min": binary(A.Minimum{},root)
    case "minecraft:max": binary(A.Maximum{},root)
    case "minecraft:gradient": gradient(root)
    case "minecraft:clamp": clamp(root)
    case "minecraft:lerp": lerp(root)
    case "minecraft:range_choice": range_choice(root)
    case "minecraft:cache": cache(root)
    case "minecraft:old_blended_noise": base(root)
    case "minecraft:noise": noise(root)
    case "minecraft:shift_a": shift(root,True{})
    case "minecraft:shift_b": shift(root,False{})
    case _: Done{A.Unsupported{kind,root}}

def read(value:J.Value) -> Result<&2,&2,String,A.Form>:
  match value:
    case J.JString{key}:
      do Result<&2,&2,String,A.Form>:
        name:String <- identifier(J.JString{key})
        return A.Reference{name}
    case J.JNumber{raw}:
      do Result<&2,&2,String,A.Form>:
        value:F32 <- float(J.JNumber{raw})
        return A.Constant{value}
    case J.JObject{+fields}:
      do Result<&2,&2,String,A.Form>:
        kind_value:J.Value <- NC.field(J.JObject{fields},"type")
        kind:String <- identifier(kind_value)
        object(kind,J.JObject{fields})
    case _: Fail{"density expression must be a number, resource reference or typed object"}

def modifiers(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,F.F64>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,F.F64>>:
        value:F.F64 <- double(head)
        tail:List<&2,F.F64> <- modifiers(rest)
        return value <> tail

def modifier_field(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,List<&2,F.F64>>:
  match value:
    case None{}: Done{[]}
    case Some{J.JArray{values}}: modifiers(values)
    case _: Fail{"normal noise amplitude modifiers must be an array"}

def normalization(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,DN.Normalization>:
  match value:
    case None{}: Done{DN.Enabled{}}
    case Some{J.JBool{True{}}}: Done{DN.Enabled{}}
    case Some{J.JBool{False{}}}: Done{DN.Disabled{}}
    case Some{J.JString{"legacy"}}: Done{DN.Legacy{}}
    case _: Fail{"normal noise normalization must be boolean or legacy"}

def noise_config_checked(config:DN.Config,valid:Bool) -> Result<&2,&2,String,DN.Config>:
  match valid:
    case True{}: Done{config}
    case False{}: Fail{"normal noise parameters outside actual codec range"}

def noise_config(key:String,+root:J.Value) -> Result<&2,&2,String,DN.Config>:
  do Result<&2,&2,String,DN.Config>:
    amplitude_value:J.Value <- NC.field(root,"base_amplitude")
    amplitude:F.F64 <- double(amplitude_value)
    octave_value:J.Value <- NC.field(root,"base_octave")
    octave:U32 <- NC.integer(octave_value)
    count_value:J.Value <- NC.field(root,"octave_count")
    count:U32 <- NC.integer(count_value)
    mode:DN.Normalization <- normalization(J.member(root,"normalize"))
    amplitudes:List<&2,F.F64> <- modifier_field(J.member(root,"amplitude_modifiers"))
    +config:DN.Config = DN.Config{key,amplitude,octave,count,mode,amplitudes}
    noise_config_checked(config,DN.config_valid(config))
