import Base
import ./client_world.bend as W
import ./client_render.bend as R
import ./world_mesh.bend as WM
import ./mesh_render.bend as M
import ./block_bake.bend as K
import ./block_model.bend as B
import ./movement.bend as MV
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as Reg

# The measured 26.3 air/full-cube domain. No contextual shape inference.
type Class is Data:
  Air{}
  FullCube{}
type Visibility is Data:
  Visibility{cell:W.Cell,state:U32,visible:U32}
type Sample is Data:
  Sample{snapshot:R.Snapshot,raw:List<&2,W.RawBlock>,visibility:List<&2,Visibility>,
    origin:MV.Vec3,palette:W.Palette,neighbor_reads:U32}
type Limits is Data:
  Limits{mesh:WM.Limits,max_neighbor_reads:U32}
type Error is Data:
  Error{code:String,cell:W.Cell,state:U32,detail:String}
type Collected is Data:
  Collected{reversed:List<&2,Visibility>,reads:U32}
type DirectionResult is Data:
  DirectionResult{visible:U32,reads:U32}

def defaults() -> Limits:
  Limits{WM.defaults(),24576}
def empty_cell() -> W.Cell:
  W.Cell{0,0,0,0}
def directions() -> List<&2,B.Direction>:
  [B.Down{},B.Up{},B.North{},B.South{},B.West{},B.East{}]
def direction_bit(direction:B.Direction) -> U32:
  match direction:
    case B.Down{}: 1
    case B.Up{}: 2
    case B.North{}: 4
    case B.South{}: 8
    case B.West{}: 16
    case B.East{}: 32

# U32 arithmetic preserves BlockPos.relative's signed Java int wraparound.
# boundary is region metadata, not part of a raw cell's identity.
def neighbor(cell:W.Cell,direction:B.Direction) -> W.Cell:
  W.Cell{x,y,z,boundary} = cell
  match direction:
    case B.Down{}: W.Cell{x,U32.sub(y,1),z,0}
    case B.Up{}: W.Cell{x,U32.inc(y),z,0}
    case B.North{}: W.Cell{x,y,U32.sub(z,1),0}
    case B.South{}: W.Cell{x,y,U32.inc(z),0}
    case B.West{}: W.Cell{U32.sub(x,1),y,z,0}
    case B.East{}: W.Cell{U32.inc(x),y,z,0}

def same_cell(a:W.Cell,b:W.Cell) -> Bool:
  match a b:
    case W.Cell{x,y,z,boundary} W.Cell{bx,by,bz,bb}:
      U32.is_eq(x,bx) && U32.is_eq(y,by) && U32.is_eq(z,bz)

def palette_valid(palette:W.Palette) -> Bool:
  W.Palette{+air,+stone,+dirt,+planks} = palette
  U32.is_ne(air,stone) && U32.is_ne(air,dirt) && U32.is_ne(air,planks) &&
    U32.is_ne(stone,dirt) && U32.is_ne(stone,planks) && U32.is_ne(dirt,planks)

def classify(+state:U32,palette:W.Palette,cell:W.Cell) -> Result<&2,&2,Error,Class>:
  W.Palette{air,stone,dirt,planks} = palette
  W.choose(Result<&2,&2,Error,Class>,Done{Air{}},
    W.choose(Result<&2,&2,Error,Class>,Done{FullCube{}},
      Fail{Error{"UnsupportedState",cell,state,"unmeasured-occlusion-state"}},
      U32.is_eq(state,stone) || U32.is_eq(state,dirt) || U32.is_eq(state,planks)),U32.is_eq(state,air))

# Adjacent Shapes.block() is the first Java short circuit; all measured
# solid states use it. The measured air shape is Shapes.empty().
def visible_classes(current:Class,adjacent:Class) -> Bool:
  match adjacent:
    case FullCube{}: False{}
    case Air{}: True{}

law adjacent_full_cube_hides:
  for current:Class
  {visible_classes(current,FullCube{}) == False{} : Bool}
def adjacent_full_cube_hides(current):
  {==}

def should_render_face(current:U32,adjacent:U32,+palette:W.Palette,+cell:W.Cell) -> Result<&2,&2,Error,Bool>:
  do Result<&2,&2,Error,Bool>:
    own : Class <- classify(current,palette,cell)
    other : Class <- classify(adjacent,palette,cell)
    Done{visible_classes(own,other)}

def group_visible(group:Maybe<&2,B.Direction>,+visible:U32) -> Bool:
  match group:
    case None{}: True{}
    case Some{direction}: U32.is_ne(U32.and(visible,direction_bit(direction)),0)

law ungrouped_face_is_retained:
  for visible:U32
  {group_visible(None{},visible) == True{} : Bool}
def ungrouped_face_is_retained(visible):
  {==}

def retain_quad(visible:Bool,+quad:M.Quad,+reversed:List<&2,M.Quad>) -> List<&2,M.Quad>:
  match visible:
    case True{}: quad <> reversed
    case False{}: reversed

law retained_quad_is_exact:
  for +quad:M.Quad
  for +reversed:List<&2,M.Quad>
  {retain_quad(True{},quad,reversed) == quad <> reversed : List<&2,M.Quad>}
def retained_quad_is_exact(quad,reversed):
  {==}

def has_cell(values:List<&2,W.RawBlock>,+cell:W.Cell) -> Bool:
  match values:
    case Nil{}: False{}
    case W.RawBlock{other,state,material} <> tail: same_cell(cell,other) || has_cell(tail,cell)

def same_block(a:R.Block,b:R.Block) -> Bool:
  match a b:
    case R.Block{x,y,z,state,material} R.Block{bx,by,bz,bs,bm}:
      U32.is_eq(F32.bits(x),F32.bits(bx)) && U32.is_eq(F32.bits(y),F32.bits(by)) &&
        U32.is_eq(F32.bits(z),F32.bits(bz)) && U32.is_eq(state,bs) && U32.is_eq(material,bm)

def raw_material(raw:W.RawBlock,palette:W.Palette) -> Bool:
  W.RawBlock{cell,+state,+material} = raw
  W.Palette{air,stone,dirt,planks} = palette
  (U32.is_eq(state,stone) && U32.is_eq(material,0)) ||
    (U32.is_eq(state,dirt) && U32.is_eq(material,1)) ||
    (U32.is_eq(state,planks) && U32.is_eq(material,2))

def alignment(raw:List<&2,W.RawBlock>,blocks:List<&2,R.Block>,masks:List<&2,Visibility>,+origin:MV.Vec3,+palette:W.Palette) -> Bool:
  match raw blocks masks:
    case Nil{} Nil{} Nil{}: True{}
    case W.RawBlock{+point,+current,+material} <> +tail block <> rest Visibility{cell,state,visible} <> remaining:
      +head = {W.RawBlock{point,current,material} : W.RawBlock}
      same_cell(point,cell) && U32.is_eq(current,state) && U32.is_le(visible,63) &&
        U32.is_le(W.boundary(point),3) && raw_material(head,palette) &&
        Bool.not(has_cell(tail,point)) && same_block(block,W.relative_block(head,origin)) &&
        alignment(tail,rest,remaining,origin,palette)
    case _ _ _: False{}

def reads_match(raw:List<&2,W.RawBlock>,+reads:U32) -> Bool:
  match raw:
    case Nil{}: U32.is_eq(reads,0)
    case head <> tail: U32.is_ge(reads,6) && reads_match(tail,U32.sub(reads,6))

def sample_valid(value:Sample,+max_blocks:U32) -> Bool:
  Sample{R.Snapshot{tick,revision,+blocks,camera},+raw,+masks,+origin,+palette,reads} = value
  WM.fits(W.RawBlock,raw,max_blocks) && WM.fits(R.Block,blocks,max_blocks) &&
    WM.fits(Visibility,masks,max_blocks) && palette_valid(palette) &&
    W.finite_relative_origin(origin) && reads_match(raw,reads) && alignment(raw,blocks,masks,origin,palette)

def baked_flags(values:List<&2,K.Baked>,+visible:U32) -> List<&2,Bool>:
  match values:
    case Nil{}: []
    case K.Baked{a,b,c,d,direction,cf,sprite,texture,index,emission,override,layer,force,animated,ds,ns} <> tail:
      group_visible(cf,visible) <> baked_flags(tail,visible)

def binding_flags(binding:Maybe<&2,WM.Binding>,visible:U32) -> List<&2,Bool>:
  match binding:
    case None{}: []
    case Some{WM.Binding{state,baked,appearance}}: baked_flags(baked,visible)

def flags(values:List<&2,Visibility>,+bindings:List<&2,WM.Binding>) -> List<&2,Bool>:
  match values:
    case Nil{}: []
    case Visibility{cell,state,visible} <> tail:
      List.append(&2,Bool,binding_flags(WM.lookup(bindings,state),visible),flags(tail,bindings))

def filter_quads(values:List<&2,Bool>,quads:List<&2,M.Quad>,reversed:List<&2,M.Quad>) -> Result<&2,&2,Error,List<&2,M.Quad>>:
  match values quads:
    case Nil{} Nil{}: Done{List.reverse(&2,M.Quad,reversed)}
    case visible <> tail quad <> rest: filter_quads(tail,rest,retain_quad(visible,quad,reversed))
    case _ _: Fail{Error{"QuadAlignment",empty_cell(),0,"model-and-scene-count"}}

def filtered(result:Result<&2,&2,WM.Error,M.Scene>,masks:List<&2,Visibility>,bindings:List<&2,WM.Binding>) -> Result<&2,&2,Error,M.Scene>:
  match result:
    case Fail{WM.Error{code,state}}: Fail{Error{"Mesh:" ++ code,empty_cell(),state,""}}
    case Done{M.Scene{camera,quads,settings}}:
      do Result<&2,&2,Error,M.Scene>:
        retained : List<&2,M.Quad> <- filter_quads(flags(masks,bindings),quads,[])
        Done{M.Scene{camera,retained,settings}}

def produce_checked(valid:Bool,value:Sample,+bindings:List<&2,WM.Binding>,textures:U32,frame:WM.Frame,limits:WM.Limits) -> Result<&2,&2,Error,M.Scene>:
  match valid:
    case False{}: Fail{Error{"SampleAlignment",empty_cell(),0,"raw-relative-mask-mismatch"}}
    case True{}:
      Sample{snapshot,raw,masks,origin,palette,reads} = value
      filtered(WM.produce(snapshot,bindings,textures,frame,limits),masks,bindings)

def produce(+value:Sample,bindings:List<&2,WM.Binding>,textures:U32,frame:WM.Frame,+limits:WM.Limits) -> Result<&2,&2,Error,M.Scene>:
  WM.Limits{max_blocks,max_bindings,max_quads,max_translucent,max_tints} = limits
  produce_checked(sample_valid(value,max_blocks),value,bindings,textures,frame,limits)

def face_status(result:Result<&2,&2,Error,Bool>,world:C.World,direction:B.Direction,+visible:U32,reads:U32) -> C.World & Result<&2,&2,Error,DirectionResult>:
  match result:
    case Fail{error}: (world,Fail{error})
    case Done{render}:
      (world,Done{DirectionResult{W.choose(U32,U32.or(visible,direction_bit(direction)),visible,render),U32.inc(reads)}})

def read_direction_status(result:C.World & Result<&2,&2,C.Error,U32>,+cell:W.Cell,current:U32,direction:B.Direction,palette:W.Palette,visible:U32,+reads:U32) -> C.World & Result<&2,&2,Error,DirectionResult>:
  (world,status) = result
  match status:
    case Fail{error}: (world,Fail{Error{"NeighborRead",cell,0,W.error_text(error)}})
    case Done{adjacent}: face_status(should_render_face(current,adjacent,palette,cell),world,direction,visible,reads)

def collect_directions(values:List<&2,B.Direction>,+cell:W.Cell,+current:U32,+palette:W.Palette,world:C.World,result:Result<&2,&2,Error,DirectionResult>) -> C.World & Result<&2,&2,Error,DirectionResult>:
  match values result:
    case _ Fail{error}: (world,Fail{error})
    case Nil{} Done{acc}: (world,Done{acc})
    case +direction <> tail Done{DirectionResult{visible,reads}}:
      +point = neighbor(cell,direction)
      W.paired(C.World,Result<&2,&2,Error,DirectionResult>,C.World & Result<&2,&2,Error,DirectionResult>,
        read_direction_status(C.read_block(world,W.position(point)),point,current,direction,palette,visible,reads),
        next => status => collect_directions(tail,cell,current,palette,next,status))

def add_visibility(result:Result<&2,&2,Error,DirectionResult>,cell:W.Cell,state:U32,reversed:List<&2,Visibility>) -> Result<&2,&2,Error,Collected>:
  match result:
    case Fail{error}: Fail{error}
    case Done{DirectionResult{visible,reads}}: Done{Collected{Visibility{cell,state,visible} <> reversed,reads}}

def collect_blocks(values:List<&2,W.RawBlock>,+palette:W.Palette,world:C.World,result:Result<&2,&2,Error,Collected>) -> C.World & Result<&2,&2,Error,Collected>:
  match values result:
    case _ Fail{error}: (world,Fail{error})
    case Nil{} Done{acc}: (world,Done{acc})
    case W.RawBlock{+cell,+state,material} <> tail Done{Collected{+reversed,reads}}:
      W.paired(C.World,Result<&2,&2,Error,DirectionResult>,C.World & Result<&2,&2,Error,Collected>,
        collect_directions(directions(),cell,state,palette,world,Done{DirectionResult{0,reads}}),
        next => status => collect_blocks(tail,palette,next,add_visibility(status,cell,state,reversed)))

def collected(result:C.World & Result<&2,&2,Error,Collected>,registry:Reg.Registry,+view:W.View,+snapshot:R.Snapshot,+raw:List<&2,W.RawBlock>,+palette:W.Palette) -> W.State & Result<&2,&2,Error,Sample>:
  (world,status) = result
  match status:
    case Fail{error}: (W.attach(G.Engine{world,registry},view),Fail{error})
    case Done{Collected{reversed,reads}}:
      W.View{body,yaw,pitch,colors,region,cache} = view
      (W.attach(G.Engine{world,registry},view),Done{Sample{snapshot,raw,List.reverse(&2,Visibility,reversed),W.eye_position(body),palette,reads}})

def zero_masks(raw:List<&2,W.RawBlock>) -> List<&2,Visibility>:
  match raw:
    case Nil{}: []
    case W.RawBlock{cell,state,material} <> tail: Visibility{cell,state,0} <> zero_masks(tail)

def raw_alignment(+snapshot:R.Snapshot,+raw:List<&2,W.RawBlock>,+origin:MV.Vec3,+palette:W.Palette) -> Bool:
  R.Snapshot{tick,revision,blocks,camera} = snapshot
  palette_valid(palette) && alignment(raw,blocks,zero_masks(raw),origin,palette)

def raw_checked(valid:Bool,state:W.State,+snapshot:R.Snapshot,+raw:List<&2,W.RawBlock>,+palette:W.Palette) -> W.State & Result<&2,&2,Error,Sample>:
  match valid:
    case False{}: (state,Fail{Error{"SnapshotAlignment",empty_cell(),0,"invalid-raw-cache"}})
    case True{}:
      W.State{G.Engine{world,registry},body,yaw,pitch,colors,region,cache} = state
      collected(collect_blocks(raw,palette,world,Done{Collected{[],0}}),registry,
        W.View{body,yaw,pitch,colors,region,cache},snapshot,raw,palette)

def collect_checked(error:String,state:W.State,+snapshot:R.Snapshot,+raw:List<&2,W.RawBlock>,+palette:W.Palette) -> W.State & Result<&2,&2,Error,Sample>:
  match error:
    case "":
      W.State{engine,+body,yaw,pitch,colors,region,cache} = state
      raw_checked(raw_alignment(snapshot,raw,W.eye_position(body),palette),
        W.State{engine,body,yaw,pitch,colors,region,cache},snapshot,raw,palette)
    case error: (state,Fail{Error{error,empty_cell(),0,"configured-before-neighbor-reads"}})

def cache_ready(cache:Maybe<&2,List<&2,W.RawBlock>>,state:W.State,snapshot:R.Snapshot,palette:W.Palette,limits:Limits) -> W.State & Result<&2,&2,Error,Sample>:
  match cache:
    case None{}: (state,Fail{Error{"SnapshotCache",empty_cell(),0,"relative-snapshot-did-not-return-raw-cells"}})
    case Some{+raw}:
      Limits{WM.Limits{max_blocks,max_bindings,max_quads,max_translucent,max_tints},max_reads} = limits
      collect_checked(W.choose(String,"BlockLimit",W.choose(String,"NeighborReadLimit","",
        Bool.not(WM.fits(W.RawBlock,raw,U32.div(max_reads,6)))),Bool.not(WM.fits(W.RawBlock,raw,max_blocks))),state,snapshot,raw,palette)

def snapshot_cells(+snapshot:R.Snapshot,state:W.State,limits:Limits) -> W.State & Result<&2,&2,Error,Sample>:
  match snapshot state:
    case R.Snapshot{tick,revision,blocks,camera} W.State{engine,body,yaw,pitch,palette,+region,+cache}:
      match palette:
        case None{}: (W.State{engine,body,yaw,pitch,palette,region,cache},Fail{Error{"Palette",empty_cell(),0,"unavailable"}})
        case Some{+actual}:
          cache_ready(W.cached_blocks(cache,revision,region,actual),W.State{engine,body,yaw,pitch,palette,region,cache},snapshot,actual,limits)

def snapshot_ready(result:W.State & Result<&2,&2,String,R.Snapshot>,limits:Limits) -> W.State & Result<&2,&2,Error,Sample>:
  (state,status) = result
  match status:
    case Fail{error}: (state,Fail{Error{"Snapshot",empty_cell(),0,error}})
    case Done{snapshot}: snapshot_cells(snapshot,state,limits)

def palette_match(valid:Bool,state:W.State,limits:Limits) -> W.State & Result<&2,&2,Error,Sample>:
  match valid:
    case False{}: (state,Fail{Error{"Palette",empty_cell(),0,"registry-palette-mismatch"}})
    case True{}: snapshot_ready(W.relative_snapshot(state,4,4),limits)

def palette_checked(result:Reg.Registry & Result<&2,&2,String,W.Palette>,world:C.World,+view:W.View,limits:Limits) -> W.State & Result<&2,&2,Error,Sample>:
  (registry,status) = result
  match status view:
    case Fail{error} _: (W.attach(G.Engine{world,registry},view),Fail{Error{"Palette",empty_cell(),0,error}})
    case Done{actual} W.View{body,yaw,pitch,None{},region,cache}: (W.attach(G.Engine{world,registry},view),Fail{Error{"Palette",empty_cell(),0,"unavailable"}})
    case Done{+actual} W.View{body,yaw,pitch,Some{palette},region,cache}:
      palette_match(W.same_palette(actual,palette) && palette_valid(actual),W.attach(G.Engine{world,registry},view),limits)

def sample_checked(valid:Bool,state:W.State,limits:Limits) -> W.State & Result<&2,&2,Error,Sample>:
  match valid:
    case False{}: (state,Fail{Error{"LimitsOrRegion",empty_cell(),0,"unsupported-configured-domain"}})
    case True{}:
      W.State{G.Engine{world,registry},body,yaw,pitch,palette,region,cache} = state
      palette_checked(W.palette_air(W.supported_block(Reg.Registry.block(registry,"minecraft:air"))),world,
        W.View{body,yaw,pitch,palette,region,cache},limits)

def sample(state:W.State,+limits:Limits) -> W.State & Result<&2,&2,Error,Sample>:
  W.State{engine,body,yaw,pitch,palette,+region,cache} = state
  Limits{mesh,max_reads} = limits
  sample_checked(WM.limits_valid(mesh) && U32.is_le(max_reads,24576) && W.bounds_valid(region),
    W.State{engine,body,yaw,pitch,palette,region,cache},limits)

def mesh_ready(result:W.State & Result<&2,&2,Error,Sample>,bindings:List<&2,WM.Binding>,textures:U32,frame:WM.Frame,limits:WM.Limits) -> W.State & Result<&2,&2,Error,M.Scene>:
  (state,status) = result
  match status:
    case Fail{error}: (state,Fail{error})
    case Done{value}: (state,produce(value,bindings,textures,frame,limits))

def snapshot_mesh(state:W.State,bindings:List<&2,WM.Binding>,textures:U32,frame:WM.Frame,+limits:Limits) -> W.State & Result<&2,&2,Error,M.Scene>:
  Limits{mesh,max_reads} = limits
  mesh_ready(sample(state,limits),bindings,textures,frame,mesh)
