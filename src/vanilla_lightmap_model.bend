import Base
import ./f64.bend as F

# Values returned by the actual camera EnvironmentAttributeProbe, at the same
# partial tick as this publication. Dimension/day/weather interpolation belongs
# to that authority; these mandatory colors are not guessed from a dimension ID.
type Color is Data:
  Color{red:F32,green:F32,blue:F32}
type Environment is Data:
  Environment{block_tint:Color,sky_factor:F32,sky_color:Color,ambient:Color,night_color:Color}
type Uniforms is Data:
  Uniforms{sky_factor:F32,block_factor:F32,night_vision:F32,darkness:F32,boss:F32,brightness:F32,
    block_tint:Color,sky_color:Color,ambient:Color,night_color:Color}
type Player is Data:
  Player{tick_count:U32,darkness_blend:F32,night_duration:Maybe<&2,U32>,water_vision:F32,conduit:Bool}
type Options is Data:
  Options{gamma:F.F64,darkness_scale:F.F64,hide_flash:Bool}
type Interpolation is Data:
  Interpolation{previous:F32,current:F32}
type Transitions is Data:
  Transitions{end_flash:Maybe<&2,Interpolation>,boss_fog:Bool,boss:Interpolation}
type Inputs is Data:
  Inputs{environment:Environment,player:Player,options:Options,transitions:Transitions,partial:F32}
type Presence is Data:
  Absent{}
  Ready{inputs:Inputs}
type Texture is Data:
  InitialWhite{}
  Evaluated{uniforms:Uniforms}
type Publication is Data:
  Publication{needs_update:Bool,texture:Texture}
type Error is Data:
  Refused{message:String}

def white() -> Color: Color{1.0,1.0,1.0}
def initial_uniforms() -> Uniforms:
  Uniforms{0.0,0.0,0.0,0.0,0.0,0.0,white(),white(),white(),white()}
