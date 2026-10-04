import Base

# Actual 26.3 TextureAtlasSprite scalar constructor/getU/getV contract.
# Inputs use raw Java int words. x/y remain stitch callback region origins.
type Input is Data:
  Input{atlas_width:U32,atlas_height:U32,width:U32,height:U32,x:U32,y:U32,padding:U32}

type Mapping is Data:
  Mapping{input:Input,content_x:U32,content_y:U32,u0:F32,v0:F32,u1:F32,v1:F32}

type UV is Data:
  UV{u:F32,v:F32}

type Corners is Data:
  Corners{a:UV,b:UV,c:UV,d:UV}

type Error is Data:
  Error{code:String}

def choose(-A:Type,yes:A,no:A,value:Bool) -> A:
  match value:
    case True{}: yes
    case False{}: no

def i32_float(+word:U32) -> F32:
  choose(F32,F32.sub(0.0,U32.to_f32((0 - word : U32))),U32.to_f32(word),U32.is_ge(word,2147483648))

# Java performs each int sum BEFORE i2f, then one F32 division. Do not compute
# x/atlas + padding/atlas, narrow individual addends, or use F64 arithmetic.
def raw_mapping(+value:Input) -> Mapping:
  Input{+aw,+ah,w,h,+x,+y,+padding} = value
  +cx = (x + padding : U32)
  +cy = (y + padding : U32)
  Mapping{value,cx,cy,F32.div(i32_float(cx),i32_float(aw)),F32.div(i32_float(cy),i32_float(ah)),F32.div(i32_float((cx + w : U32)),i32_float(aw)),F32.div(i32_float((cy + h : U32)),i32_float(ah))}

def range(+value:U32) -> Bool:
  U32.is_gt(value,0) && U32.is_le(value,536870912)

def guarded(value:Input,code:String,allowed:Bool) -> Result<&2,&2,Error,Input>:
  match allowed:
    case True{}: Done{value}
    case False{}: Fail{Error{code}}

# Admission is caller policy, separate from unchecked Java receiver arithmetic.
# This bound also keeps all padded-extent sums below U32 wraparound.
def derive(+value:Input) -> Result<&2,&2,Error,Mapping>:
  Input{+aw,+ah,+w,+h,+x,+y,+p} = value
  do Result<&2,&2,Error,Mapping>:
    atlas : Input <- guarded(value,"AtlasRange",range(aw) && range(ah))
    frame : Input <- guarded(atlas,"FrameRange",range(w) && range(h))
    origin : Input <- guarded(frame,"OriginRange",U32.is_le(x,536870912) && U32.is_le(y,536870912) && U32.is_le(p,536870912))
    bounded : Input <- guarded(origin,"PaddedBounds",U32.is_le((x + (2 * p : U32) + w : U32),aw) && U32.is_le((y + (2 * p : U32) + h : U32),ah))
    Done{raw_mapping(bounded)}

# getU/getV accept normalized coordinates; there is no division by16 or clamp.
# Each operation rounds separately to F32, matching fsub/fmul/fadd bytecode.
def get_u(value:Mapping,t:F32) -> F32:
  Mapping{input,cx,cy,+u0,v0,u1,v1} = value
  F32.add(u0,F32.mul(F32.sub(u1,u0),t))

def get_v(value:Mapping,t:F32) -> F32:
  Mapping{input,cx,cy,u0,+v0,u1,v1} = value
  F32.add(v0,F32.mul(F32.sub(v1,v0),t))

def map(+value:Mapping,uv:UV) -> UV:
  UV{u,v} = uv
  UV{get_u(value,u),get_v(value,v)}

# Same rectangle order used by unrotated CuboidFace/BlockBake face UVs:
# (u0,v0), (u0,v1), (u1,v1), (u1,v0). No nonexistent shrink adjustment.
def corners(value:Mapping) -> Corners:
  Mapping{input,cx,cy,+u0,+v0,+u1,+v1} = value
  Corners{UV{u0,v0},UV{u0,v1},UV{u1,v1},UV{u1,v0}}

# Mapping t=1 performs the actual subtract/multiply/add sequence. It need not
# be assumed bit-identical to returning the stored endpoint getter.
def mapped_corners(+value:Mapping) -> Corners:
  Corners{map(value,UV{0.0,0.0}),map(value,UV{0.0,1.0}),map(value,UV{1.0,1.0}),map(value,UV{1.0,0.0})}

def mapping_input(value:Mapping) -> Input:
  Mapping{input,cx,cy,u0,v0,u1,v1} = value
  input

def content_origin(value:Mapping) -> U32 & U32:
  Mapping{input,cx,cy,u0,v0,u1,v1} = value
  (cx,cy)

law callback_origin:
  {content_origin(raw_mapping(Input{32,32,16,16,4,6,1})) == (5,7) : U32 & U32}
def callback_origin():
  {==}

law preserves_input:
  for value:Input
  {mapping_input(raw_mapping(value)) == value : Input}
def preserves_input(value):
  match value:
    case Input{aw,ah,w,h,x,y,p}: {==}
