import Base
import ./world_generation_settings.bend as WG
import ./worldgen_noise_settings.bend as NS
import ./json.bend as J
import ./f64.bend as F

# The density compiler must resolve these six actual router expressions before
# climate sampling is available. Humidity uses vegetation, continentalness uses
# continents and weirdness uses ridges, matching NoiseRouter.createClimateSampler.
type Inputs is Data:
  Inputs{temperature:J.Value,humidity:J.Value,continentalness:J.Value,
    erosion:J.Value,depth:J.Value,weirdness:J.Value}

type Quart is Data:
  Quart{x:U32,y:U32,z:U32}

type Block is Data:
  Block{x:U32,y:U32,z:U32}

type Values is Data:
  Values{temperature:F32,humidity:F32,continentalness:F32,erosion:F32,depth:F32,weirdness:F32}

type Target is Data:
  Target{temperature:F.Word64,humidity:F.Word64,continentalness:F.Word64,
    erosion:F.Word64,depth:F.Word64,weirdness:F.Word64}

type LoadedPreset is Data:
  LoadedPreset{key:String,definition:J.Value}

type Plan is Data:
  Fixed{biome:String}
  MultiNoise{preset:String,definition:LoadedPreset,inputs:Inputs}

def inputs(router:NS.Router) -> Inputs:
  match router:
    case NS.Router{surface,continents,depth,erosion,density,ridges,temperature,vegetation}:
      Inputs{temperature,vegetation,continents,erosion,depth,ridges}

# QuartPos.toBlock is Java int arithmetic, including its defined wrap at the
# signed-word boundaries. It does not clamp a generated-world coordinate.
def to_block(quart:Quart) -> Block:
  match quart:
    case Quart{x,y,z}: Block{U32.shln(x,2n),U32.shln(y,2n),U32.shln(z,2n)}

# Climate.quantizeCoord multiplies in float before Java f2l narrowing. The exact
# F32 product is widened only afterward; NaN, infinities and signed64 saturation
# are handled by the shared actual Java-long conversion.
def quantize(value:F32) -> F.Word64:
  F.to_java_long(F.from_f32(F32.mul(value,10000.0)))

def target(values:Values) -> Target:
  match values:
    case Values{temperature,humidity,continents,erosion,depth,weirdness}:
      Target{quantize(temperature),quantize(humidity),quantize(continents),
        quantize(erosion),quantize(depth),quantize(weirdness)}

def preset_member_valid(value:Maybe<&2,J.Value>) -> Bool:
  match value:
    case Some{J.JString{defined}}: WG.identifier(defined)
    case _: False{}

def preset_matches(+preset:String,loaded:LoadedPreset) -> Bool:
  match loaded:
    case LoadedPreset{key,definition}:
      WG.identifier(preset) && String.eq(preset,key) && preset_member_valid(J.member(definition,"preset"))

def prepared_multi(preset:String,definition:LoadedPreset,router:NS.Router,valid:Bool) -> Result<&2,&2,String,Plan>:
  match valid:
    case True{}: Done{MultiNoise{preset,definition,inputs(router)}}
    case False{}: Fail{"multi-noise biome preset identity or loaded definition mismatch"}

def prepare(source:WG.BiomeSource,+router:NS.Router,+definition:LoadedPreset) -> Result<&2,&2,String,Plan>:
  match source:
    case WG.FixedBiome{biome}: Done{Fixed{biome}}
    case WG.MultiNoisePreset{+preset}:
      prepared_multi(preset,definition,router,preset_matches(preset,definition) && NS.router_valid(router))
    case WG.EndBiomes{}: Fail{"End biome producer is unavailable to the Overworld generator"}

# This owner-facing boundary names the actual missing producer. Retaining a
# preset is not a loaded Climate.ParameterList or a compiled density sampler.
def unavailable(plan:Plan,quart:Quart) -> Result<&2,&2,String,String>:
  match plan:
    case Fixed{biome}: Done{biome}
    case MultiNoise{preset,definition,inputs}:
      Fail{"multi-noise biome sampling requires the compiled climate density graph and loaded preset parameter search"}
