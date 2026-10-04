import Base
import ./resource_block_catalog.bend as C
import ./block_resources.bend as BR
import ./world_mesh.bend as WM
import ./mesh_render.bend as M
import ./client_render.bend as R

# Resource ownership is independent of world ownership. The catalog retains the
# registry identity; each instance supplies its own model ticket and appearance.
type Assets is Type:
  Assets{resources:R.Assets,catalog:C.Catalog,texture_count:U32}
type Info is Data:
  Info{catalog:C.Catalog,texture_count:U32}
type Instance is Data:
  Instance{block:R.Block,selection:C.Selection,appearance:WM.Appearance}
type Frame is Data:
  Frame{registry_identity:String,tick:Nat,revision:Nat,
    instances:List<&2,Instance>,camera:R.Camera}

def catalog_identity(value:C.Catalog) -> String:
  C.Catalog{identity,entries,loaded} = value
  identity

def sprite_infos(value:Info) -> List<&2,BR.SpriteInfo>:
  Info{C.Catalog{identity,entries,BR.Catalog{roots,source,models,sprites,context,usage}},textures} = value
  sprites

def count(+catalog:C.Catalog) -> U32:
  U32.from_nat(List.length(&2,BR.SpriteInfo,sprite_infos(Info{catalog,0})))

def info(assets:Assets) -> Assets & Info:
  Assets{resources,+catalog,+textures} = assets
  (Assets{resources,catalog,textures},Info{catalog,textures})

def identity_guard(valid:Bool,declared:String,actual:String) -> Result<&2,&2,C.Error,Unit>:
  match valid:
    case False{}: Fail{C.Error{"RegistryIdentityMismatch","catalog",declared ++ ":" ++ actual}}
    case True{}: Done{Unit{}}

def mesh_error(value:WM.Error) -> C.Error:
  WM.Error{code,state} = value
  C.Error{"WorldMesh:" ++ code,"world",U32.show(state)}

def mesh_result(-A:Data,value:Result<&2,&2,WM.Error,A>) -> Result<&2,&2,C.Error,A>:
  match value:
    case Fail{error}: Fail{mesh_error(error)}
    case Done{result}: Done{result}

def binding_check(value:Result<&2,&2,String,Unit>,state:U32) -> Result<&2,&2,C.Error,Unit>:
  match value:
    case Fail{code}: Fail{C.Error{"WorldMesh:" ++ code,"world",U32.show(state)}}
    case Done{Unit{}}: Done{Unit{}}

def configuration(render:WM.Frame,camera:R.Camera,limits:WM.Limits) -> Result<&2,&2,C.Error,Unit>:
  do Result<&2,&2,C.Error,Unit>:
    C.require(WM.limits_valid(limits),"WorldMesh:Limits","world","")
    C.require(WM.frame_valid(render),"WorldMesh:Frame","world","")
    C.require(WM.relative_camera(camera),"WorldMesh:RelativeCamera","world","")

# max_bindings counts binding operations, including invisible instances. It is
# independent of max_blocks. No state-indexed cache can collapse cell decisions.
def instance_budget(blocks:U32,bindings:U32,+state:U32) -> Result<&2,&2,C.Error,Unit>:
  do Result<&2,&2,C.Error,Unit>:
    C.require(U32.is_gt(blocks,0),"WorldMesh:BlockLimit","world",U32.show(state))
    C.require(U32.is_gt(bindings,0),"WorldMesh:BindingLimit","world",U32.show(state))

def bound_checked(status:Result<&2,&2,C.Error,Unit>,+block:R.Block,binding:WM.Binding,
    acc:WM.Accumulator,textures:U32,limits:WM.Limits) -> Result<&2,&2,C.Error,WM.Accumulator>:
  match status:
    case Fail{error}: Fail{error}
    case Done{Unit{}}:
      mesh_result(WM.Accumulator,WM.bound_block(WM.block_bound(block),block,Some{binding},acc,textures,limits))

def instance_bound(value:Result<&2,&2,C.Error,C.Bound>,+block:R.Block,acc:WM.Accumulator,
    +textures:U32,+limits:WM.Limits) -> Result<&2,&2,C.Error,WM.Accumulator>:
  match value:
    case Fail{error}: Fail{error}
    case Done{C.Bound{identity,variants,+binding}}:
      R.Block{x,y,z,state,material} = block
      WM.Limits{blocks,bindings,quads,layers,tints} = limits
      bound_checked(binding_check(WM.bindings_check(binding <> Nil{},textures,1,quads,tints),state),
        block,binding,acc,textures,limits)

def instance(value:Instance,catalog:C.Catalog,acc:WM.Accumulator,textures:U32,limits:WM.Limits) -> Result<&2,&2,C.Error,WM.Accumulator>:
  Instance{+block,selection,appearance} = value
  R.Block{x,y,z,state,material} = block
  instance_bound(C.bind(catalog,state,selection,appearance),block,acc,textures,limits)

# One shared accumulator preserves instance/model/quad order and charges the
# complete frame's quad/translucent budgets. Only the current binding is checked;
# an unused catalog state cannot introduce a missing tint or geometry failure.
def instances(values:List<&2,Instance>,+catalog:C.Catalog,+textures:U32,+limits:WM.Limits,
    +blocks:U32,+bindings:U32,acc:WM.Accumulator) -> Result<&2,&2,C.Error,WM.Accumulator>:
  match values:
    case Nil{}: Done{acc}
    case +head <> tail:
      Instance{R.Block{x,y,z,state,material},selection,appearance} = head
      do Result<&2,&2,C.Error,WM.Accumulator>:
        instance_budget(blocks,bindings,state)
        next:WM.Accumulator <- instance(head,catalog,acc,textures,limits)
        instances(tail,catalog,textures,limits,U32.sub(blocks,1),U32.sub(bindings,1),next)

def scene_configured(status:Result<&2,&2,C.Error,Unit>,frame:Frame,catalog:C.Catalog,
    textures:U32,render:WM.Frame,+limits:WM.Limits) -> Result<&2,&2,C.Error,M.Scene>:
  match status:
    case Fail{error}: Fail{error}
    case Done{Unit{}}:
      Frame{identity,tick,revision,values,camera} = frame
      WM.Frame{width,height,settings} = render
      WM.Limits{blocks,bindings,quads,layers,tints} = limits
      do Result<&2,&2,C.Error,M.Scene>:
        acc:WM.Accumulator <- instances(values,catalog,textures,limits,blocks,bindings,WM.Accumulator{[],0,0})
        mesh_result(M.Scene,WM.finish(Done{acc},camera,settings))

def scene_gated(status:Result<&2,&2,C.Error,Unit>,+frame:Frame,catalog:C.Catalog,
    textures:U32,+render:WM.Frame,+limits:WM.Limits) -> Result<&2,&2,C.Error,M.Scene>:
  match status:
    case Fail{error}: Fail{error}
    case Done{Unit{}}:
      Frame{identity,tick,revision,values,camera} = frame
      scene_configured(configuration(render,camera,limits),frame,catalog,textures,render,limits)

def scene(+frame:Frame,+catalog:C.Catalog,textures:U32,render:WM.Frame,limits:WM.Limits) -> Result<&2,&2,C.Error,M.Scene>:
  Frame{+declared,tick,revision,values,camera} = frame
  +actual = catalog_identity(catalog)
  scene_gated(identity_guard(String.eq(declared,actual),declared,actual),frame,catalog,textures,render,limits)

def render_result(value:Result<&2,&2,M.Error,Image>) -> Result<&2,&2,C.Error,Image>:
  match value:
    case Fail{M.Error{code}}: Fail{C.Error{"Render:" ++ code,"scene",""}}
    case Done{image}: Done{image}

def rendered(value:R.Assets & Result<&2,&2,M.Error,Image>,catalog:C.Catalog,textures:U32) -> Assets & Result<&2,&2,C.Error,Image>:
  (resources,status) = value
  (Assets{resources,catalog,textures},render_result(status))

def produced(value:Result<&2,&2,C.Error,M.Scene>,assets:Assets,+width:U32,+height:U32) -> Assets & Result<&2,&2,C.Error,Image>:
  match value:
    case Fail{error}: (assets,Fail{error})
    case Done{scene}:
      Assets{resources,catalog,textures} = assets
      rendered(M.render(scene,resources,width,height),catalog,textures)

def draw(frame:Frame,assets:Assets,+width:U32,+height:U32,limits:WM.Limits) -> Assets & Result<&2,&2,C.Error,Image>:
  Assets{resources,+catalog,+textures} = assets
  produced(scene(frame,catalog,textures,WM.frame(width,height),limits),Assets{resources,catalog,textures},width,height)

# CL/BR close their archives before handing out resources. This owner contains
# managed image references, not an open file, socket, GPU buffer or window.
def close_assets(assets:Assets) -> IO(Unit):
  Assets{R.Assets{textures},catalog,count} = assets
  IO.pure(Unit,Unit{})
