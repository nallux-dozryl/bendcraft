import Base
import ./json.bend as J
import ./f64.bend as F
import ./worldgen_blended_noise.bend as BL
import ./worldgen_overworld.bend as O
import ./worldgen_density_spline.bend as Spline

type Axis is Data:
  X{}
  Y{}
  Z{}

type Unary is Data:
  Abs{}
  Square{}
  Cube{}
  HalfNegative{}
  QuarterNegative{}
  Squeeze{}
  Negate{}

type Binary is Data:
  Add{}
  Subtract{}
  Multiply{}
  Divide{}
  Minimum{}
  Maximum{}

type NoiseMode is Data:
  Plain{}
  ShiftedXZ{}
  ShiftedXYZ{}

type MinMaxMode is Data:
  ReadLeft{}
  ReadRight{}
  ConstantLeft{value:F32}
  ConstantRight{value:F32}
  BoundedRight{bound:F32}

# Loaded forms retain the original child JSON until registry resolution. A
# function outside the admitted interpreter is represented explicitly.
type Form is Data:
  Constant{value:F32}
  Reference{key:String}
  Unary{operation:Unary,input:J.Value}
  Binary{operation:Binary,left:J.Value,right:J.Value}
  Gradient{axis:Axis,from_coordinate:U32,to_coordinate:U32,from_value:F32,to_value:F32}
  Clamp{input:J.Value,minimum:F32,maximum:F32}
  Lerp{alpha:J.Value,first:J.Value,second:J.Value}
  RangeChoice{input:J.Value,minimum:F32,maximum:F32,inside:J.Value,outside:J.Value}
  Cache{input:J.Value}
  Spline{tree:Spline.Tree<J.Value>}
  BaseNoise{config:BL.Config}
  Noise{key:String,xz_scale:F.F64,y_scale:F.F64,shift_x:J.Value,shift_y:J.Value,shift_z:J.Value}
  ShiftA{key:String}
  ShiftB{key:String}
  BlendAlpha{}
  BlendOffset{}
  BlendDensity{input:J.Value}
  Unsupported{kind:String,original:J.Value}

type Binding is Data:
  Binding{key:String,value:J.Value}

type Registry is Data:
  Registry{densities:List<&2,Binding>,noises:List<&2,Binding>}

# Every child index refers to an earlier node in the compiled finite DAG.
# Registry reference identities are interned once; roots retain their original
# request and complete loaded definitions alongside the saved generation plan.
type Operation is Data:
  OpConstant{value:F32}
  OpUnary{operation:Unary,input:U32}
  OpBinary{operation:Binary,left:U32,right:U32,left_constant:Bool,right_constant:Bool}
  OpGradient{axis:Axis,from_coordinate:U32,to_coordinate:U32,from_value:F32,to_value:F32}
  OpClamp{input:U32,minimum:F32,maximum:F32}
  OpLerp{alpha:U32,first:U32,second:U32}
  OpRangeChoice{input:U32,minimum:F32,maximum:F32,inside:U32,outside:U32}
  OpCache{input:U32}
  OpSpline{tree:Spline.Tree<U32>}
  OpBaseNoise{config:BL.Config}
  OpNoise{key:String,xz_scale:F.F64,y_scale:F.F64,shift_x:U32,shift_y:U32,shift_z:U32,mode:NoiseMode}
  OpShiftA{key:String}
  OpShiftB{key:String}
  OpMinMax{operation:Binary,left:U32,right:U32,mode:MinMaxMode}
  OpBlendAlpha{}
  OpBlendOffset{}
  OpBlendDensity{input:U32}

type Node is Data:
  Node{index:U32,original:J.Value,operation:Operation}

type Program is Data:
  Program{plan:O.Plan,registry:Registry,expression:J.Value,nodes:List<&2,Node>,root:U32}
