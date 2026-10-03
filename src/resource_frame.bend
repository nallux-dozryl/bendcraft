import Base
import ./block_resources.bend as BR
import ./block_model.bend as B
import ./block_bake.bend as K
import ./world_mesh.bend as WM
import ./mesh_render.bend as M
import ./client_render.bend as R

# The caller maps its actual registry palette into this lightweight Data value.
# This module deliberately selects three named models at zero transform;
# it does not implement blockstate variant/multipart/weighted selection.
type Palette is Data:
  Palette{air:U32,stone:U32,dirt:U32,planks:U32}
type Info is Data:
  Info{bindings:List<&2,WM.Binding>,texture_count:U32,palette:Palette,catalog:BR.Catalog}
type Assets is Type:
  Assets{resources:R.Assets,bindings:List<&2,WM.Binding>,texture_count:U32,
    palette:Palette,catalog:BR.Catalog}

def palette_valid(value:Palette) -> Bool:
  Palette{+air,+stone,+dirt,+planks} = value
  U32.is_ne(air,stone) && U32.is_ne(air,dirt) && U32.is_ne(air,planks) &&
    U32.is_ne(stone,dirt) && U32.is_ne(stone,planks) && U32.is_ne(dirt,planks)

def model_ids() -> List<&2,String>:
  ["minecraft:block/stone","minecraft:block/dirt","minecraft:block/oak_planks"]

def policy() -> BR.Policy:
  BR.StaticNormalized{Map.set(&2,K.Layer,
    Map.set(&2,K.Layer,Map.set(&2,K.Layer,MTip{},"minecraft:block/stone",K.Solid{}),
      "minecraft:block/dirt",K.Solid{}),"minecraft:block/oak_planks",K.Solid{})}

def resources_error(value:BR.Error) -> String:
  BR.Error{code,resource,message} = value
  "Resource:" ++ code ++ ":" ++ resource ++ ":" ++ message

def model_result(value:Result<&2,&2,BR.Error,B.Resolved>) -> Result<&2,&2,String,B.Resolved>:
  match value:
    case Done{model}: Done{model}
    case Fail{error}: Fail{resources_error(error)}

def bake_result(value:Result<&2,&2,K.Error,List<&2,K.Baked>>) -> Result<&2,&2,String,List<&2,K.Baked>>:
  match value:
    case Done{quads}: Done{quads}
    case Fail{K.Unsupported{code}}: Fail{"Bake:Unsupported:" ++ code}
    case Fail{K.Invalid{code}}: Fail{"Bake:Invalid:" ++ code}
    case Fail{K.MissingMaterial{reference}}: Fail{"Bake:MissingMaterial:" ++ reference}

def binding(+catalog:BR.Catalog,state:U32,id:String) -> Result<&2,&2,String,WM.Binding>:
  BR.Catalog{roots,source,models,sprites,context,usage} = catalog
  do Result<&2,&2,String,WM.Binding>:
    model : B.Resolved <- model_result(BR.model(catalog,id))
    quads : List<&2,K.Baked> <- bake_result(K.bake(model,K.State{0,0,0,False{}},context))
    Done{WM.Binding{state,quads,WM.appearance()}}

def bindings(palette:Palette,+catalog:BR.Catalog) -> Result<&2,&2,String,List<&2,WM.Binding>>:
  Palette{air,stone,dirt,planks} = palette
  do Result<&2,&2,String,List<&2,WM.Binding>>:
    s : WM.Binding <- binding(catalog,stone,"minecraft:block/stone")
    d : WM.Binding <- binding(catalog,dirt,"minecraft:block/dirt")
    p : WM.Binding <- binding(catalog,planks,"minecraft:block/oak_planks")
    Done{[s,d,p]}

def count(catalog:BR.Catalog) -> U32:
  BR.Catalog{roots,source,models,sprites,context,usage} = catalog
  U32.from_nat(List.length(&2,BR.SpriteInfo,sprites))

# BR has already closed the archive. Image trees are owned managed values, with
# no retained file or GPU handles; consuming their owner releases references.
def close_resources(resources:R.Assets) -> IO(Unit):
  R.Assets{textures} = resources
  IO.pure(Unit,Unit{})

def bindings_ready(result:Result<&2,&2,String,List<&2,WM.Binding>>,resources:R.Assets,
    +catalog:BR.Catalog,palette:Palette) -> IO(Result<&2,&1,String,Assets>):
  match result:
    case Done{bindings}: IO.pure(Result<&2,&1,String,Assets>,Done{Assets{resources,bindings,count(catalog),palette,catalog}})
    case Fail{message}:
      do IO<Result<&2,&1,String,Assets>>:
        close_resources(resources)
        return Fail{message}

def loaded(result:Result<&2,&1,BR.Error,BR.Loaded>,+palette:Palette) -> IO(Result<&2,&1,String,Assets>):
  match result:
    case Fail{error}: IO.pure(Result<&2,&1,String,Assets>,Fail{resources_error(error)})
    case Done{BR.Loaded{resources,+catalog}}:
      bindings_ready(bindings(palette,catalog),resources,catalog,palette)

def load_valid(valid:Bool,jar:String,palette:Palette) -> IO(Result<&2,&1,String,Assets>):
  match valid:
    case False{}: IO.pure(Result<&2,&1,String,Assets>,Fail{"Palette:DuplicateState"})
    case True{}:
      do IO<Result<&2,&1,String,Assets>>:
        result : Result<&2,&1,BR.Error,BR.Loaded> <- BR.load(jar,model_ids(),policy(),BR.defaults())
        loaded(result,palette)

def load(jar:String,+palette:Palette) -> IO(Result<&2,&1,String,Assets>):
  load_valid(palette_valid(palette),jar,palette)

def mesh_result(value:Result<&2,&2,M.Error,Image>) -> Result<&2,&2,String,Image>:
  match value:
    case Done{image}: Done{image}
    case Fail{M.Error{code}}: Fail{"Render:" ++ code}

def rendered(value:R.Assets & Result<&2,&2,M.Error,Image>,bindings:List<&2,WM.Binding>,
    textures:U32,palette:Palette,catalog:BR.Catalog) -> Assets & Result<&2,&2,String,Image>:
  (resources,status) = value
  (Assets{resources,bindings,textures,palette,catalog},mesh_result(status))

def produced(value:Result<&2,&2,WM.Error,M.Scene>,assets:Assets,width:U32,height:U32) -> Assets & Result<&2,&2,String,Image>:
  match value:
    case Fail{WM.Error{code,state}}: (assets,Fail{"WorldMesh:" ++ code ++ ":" ++ U32.show(state)})
    case Done{scene}:
      Assets{resources,bindings,textures,palette,catalog} = assets
      rendered(M.render(scene,resources,width,height),bindings,textures,palette,catalog)

def draw(snapshot:R.Snapshot,assets:Assets,+width:U32,+height:U32) -> Assets & Result<&2,&2,String,Image>:
  Assets{resources,+bindings,+textures,palette,catalog} = assets
  produced(WM.produce(snapshot,bindings,textures,WM.frame(width,height),WM.defaults()),
    Assets{resources,bindings,textures,palette,catalog},width,height)

def info(assets:Assets) -> Assets & Info:
  Assets{resources,+bindings,+textures,+palette,+catalog} = assets
  (Assets{resources,bindings,textures,palette,catalog},Info{bindings,textures,palette,catalog})

def close_assets(assets:Assets) -> IO(Unit):
  Assets{resources,bindings,textures,palette,catalog} = assets
  close_resources(resources)
