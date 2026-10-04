import Base
import ./resource_frame.bend as RF
import ./world_visibility.bend as V
import ./client_world.bend as W
import ./world_mesh.bend as WM
import ./mesh_render.bend as M
import ./resource_catalog_world.bend as CW
import ./resource_block_catalog.bend as Catalog

# Keep the immutable draw inputs in one record rather than a wide continuation.
# The sole texture owner remains RF.Assets throughout production and rendering.
type DrawConfig is Data:
  DrawConfig{width:U32,height:U32,mesh:WM.Limits}
type DrawSource is Data:
  DrawSource{sample:V.Sample,info:RF.Info,config:DrawConfig}

def resource_palette(value:W.Palette) -> RF.Palette:
  W.Palette{air,stone,dirt,planks} = value
  RF.Palette{air,stone,dirt,planks}

law resource_palette_fields:
  for +air:U32
  for +stone:U32
  for +dirt:U32
  for +planks:U32
  {resource_palette(W.Palette{air,stone,dirt,planks}) == RF.Palette{air,stone,dirt,planks} : RF.Palette}
def resource_palette_fields(air,stone,dirt,planks):
  {==}

def palette_match(world:W.Palette,resources:RF.Palette) -> Bool:
  match world resources:
    case W.Palette{+air,+stone,+dirt,+planks} RF.Palette{+ra,+rs,+rd,+rp}:
      V.palette_valid(W.Palette{air,stone,dirt,planks}) &&
        RF.palette_valid(RF.Palette{ra,rs,rd,rp}) &&
        U32.is_eq(air,ra) && U32.is_eq(stone,rs) && U32.is_eq(dirt,rd) && U32.is_eq(planks,rp)

def palette_guard(valid:Bool) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{"Palette:Mismatch"}
    case True{}: Done{Unit{}}

law mismatched_palette_rejects:
  {palette_guard(False{}) == Fail{"Palette:Mismatch"} : Result<&2,&2,String,Unit>}
def mismatched_palette_rejects():
  {==}

# Preserve the complete V.Error raw cell words, state and detail in diagnostics.
# These unsigned XYZ words retain signed BlockPos identity without F32 rounding.
def visibility_error(value:V.Error) -> String:
  V.Error{code,W.Cell{x,y,z,boundary},state,detail} = value
  "Visibility:" ++ code ++ ":" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(boundary) ++
    ":" ++ U32.show(state) ++ ":" ++ detail

def scene_result(value:Result<&2,&2,V.Error,M.Scene>) -> Result<&2,&2,String,M.Scene>:
  match value:
    case Fail{error}: Fail{visibility_error(error)}
    case Done{scene}: Done{scene}

def scene_gated(status:Result<&2,&2,String,Unit>,source:DrawSource) -> Result<&2,&2,String,M.Scene>:
  match status:
    case Fail{message}: Fail{message}
    case Done{Unit{}}:
      DrawSource{sample,RF.Info{bindings,textures,palette,catalog},DrawConfig{width,height,limits}} = source
      scene_result(V.produce(sample,bindings,textures,WM.frame(width,height),limits))

law scene_rejection_preserves_error:
  for +message:String
  for source:DrawSource
  {scene_gated(Fail{message},source) == Fail{message} : Result<&2,&2,String,M.Scene>}
def scene_rejection_preserves_error(message,source):
  {==}

def source_palette(value:DrawSource) -> Bool:
  DrawSource{V.Sample{snapshot,raw,masks,origin,palette,reads},RF.Info{bindings,textures,rp,catalog},config} = value
  palette_match(palette,rp)

def scene_source(+source:DrawSource) -> Result<&2,&2,String,M.Scene>:
  scene_gated(palette_guard(source_palette(source)),source)

def scene(sample:V.Sample,info:RF.Info,width:U32,height:U32,limits:WM.Limits) -> Result<&2,&2,String,M.Scene>:
  scene_source(DrawSource{sample,info,DrawConfig{width,height,limits}})

def produced(value:Result<&2,&2,String,M.Scene>,assets:RF.Assets,config:DrawConfig) -> RF.Assets & Result<&2,&2,String,Image>:
  match value:
    case Fail{message}: (assets,Fail{message})
    case Done{scene}:
      RF.Assets{resources,bindings,textures,palette,catalog} = assets
      DrawConfig{width,height,limits} = config
      RF.rendered(M.render(scene,resources,width,height),bindings,textures,palette,catalog)

def informed(value:RF.Assets & RF.Info,sample:V.Sample,+config:DrawConfig) -> RF.Assets & Result<&2,&2,String,Image>:
  (assets,info) = value
  produced(scene_source(DrawSource{sample,info,config}),assets,config)

def draw_config(sample:V.Sample,assets:RF.Assets,config:DrawConfig) -> RF.Assets & Result<&2,&2,String,Image>:
  informed(RF.info(assets),sample,config)

def draw_with(sample:V.Sample,assets:RF.Assets,width:U32,height:U32,limits:WM.Limits) -> RF.Assets & Result<&2,&2,String,Image>:
  draw_config(sample,assets,DrawConfig{width,height,limits})

def draw(sample:V.Sample,assets:RF.Assets,width:U32,height:U32) -> RF.Assets & Result<&2,&2,String,Image>:
  draw_with(sample,assets,width,height,WM.defaults())

# Registry-bound frames carry each cell's admitted selection and appearance.
# Rendering returns the same complete resource owner on either outcome.
def draw_catalog(frame:CW.Frame,assets:CW.Assets,width:U32,height:U32) -> CW.Assets & Result<&2,&2,Catalog.Error,Image>:
  RF.catalog_draw(frame,assets,width,height,WM.defaults())

def sampled(value:W.State & Result<&2,&2,V.Error,V.Sample>,assets:RF.Assets,config:DrawConfig) -> W.State & (RF.Assets & Result<&2,&2,String,Image>):
  (world,status) = value
  match status:
    case Fail{error}: (world,(assets,Fail{visibility_error(error)}))
    case Done{sample}: (world,draw_config(sample,assets,config))

# Sampling may populate the validated raw cache. It does not step simulation.
# Both affine owners are returned even when sampling, admission or render fails.
def snapshot_draw(world:W.State,assets:RF.Assets,width:U32,height:U32,+limits:V.Limits) -> W.State & (RF.Assets & Result<&2,&2,String,Image>):
  V.Limits{mesh,max_reads} = limits
  sampled(V.sample(world,limits),assets,DrawConfig{width,height,mesh})
