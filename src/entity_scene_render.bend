import Base
import ./entity_scene_render_model.bend as A
import ./entity_scene_render_camera.bend as Camera
import ./remote_entity_frame.bend as EF
import ./remote_entity_snapshot_wire.bend as Wire
import ./generic_resource_world_sample.bend as GS
import ./generic_resource_world_sample_frame.bend as GF
import ./resource_block_catalog.bend as C
import ./resource_catalog_world.bend as CW
import ./client_render.bend as R
import ./client_world.bend as W
import ./world_mesh.bend as WM
import ./mesh_render.bend as M
import ./item_entity_render.bend as IR
import ./item_entity_render_model.bend as D
import ./locomotion.bend as L
import ./vanilla_entity_fields.bend as V
import ./movement.bend as MV

def catalog_error(-T:Data,value:Result<&2,&2,C.Error,T>) -> Result<&2,&2,A.Error,T>:
  match value:
    case Fail{C.Error{code,resource,detail}}: Fail{A.Refused{code ++ ":" ++ resource ++ ":" ++ detail}}
    case Done{answer}: Done{answer}
def entity_error(-T:Data,value:Result<&2,&2,D.Error,T>) -> Result<&2,&2,A.Error,T>:
  match value:
    case Fail{D.Refused{message}}: Fail{A.Refused{message}}
    case Fail{D.ScanBudget{}}: Fail{A.Refused{"scene:entity scan budget"}}
    case Fail{D.QuadBudget{}}: Fail{A.Refused{"scene:entity quad budget"}}
    case Done{answer}: Done{answer}
def mesh_error(-T:Data,value:Result<&2,&2,WM.Error,T>) -> Result<&2,&2,A.Error,T>:
  match value:
    case Fail{WM.Error{code,state}}: Fail{A.Refused{"scene:" ++ code}}
    case Done{answer}: Done{answer}
def light_valid(block:U32,sky:U32,rgb:U32) -> Bool:
  U32.is_le(block,15) && U32.is_le(sky,15) && U32.is_eq(U32.shrn(rgb,24n),255)
def entity_lights(values:List<&2,D.Light>) -> Bool:
  match values:
    case Nil{}: True{}
    case D.Light{id,+block,+sky,item,orb} <> rest:
      light_valid(block,sky,item) && light_valid(U32.min(15,U32.add(block,7)),sky,orb) && entity_lights(rest)
def light_id_present(values:List<&2,D.Light>,+wanted:U32) -> Bool:
  match values:
    case Nil{}: False{}
    case D.Light{id,block,sky,item,orb} <> rest: U32.is_eq(id,wanted) || light_id_present(rest,wanted)
def light_ids_unique(values:List<&2,D.Light>) -> Bool:
  match values:
    case Nil{}: True{}
    case D.Light{id,block,sky,item,orb} <> +rest: Bool.not(light_id_present(rest,id)) && light_ids_unique(rest)
def world_light(value:Map<&2,Maybe<&2,A.WorldLight>> & Maybe<&2,A.WorldLight>,+state:U32) -> Result<&2,&2,A.Error,U32>:
  (map,found) = value
  match found:
    case None{}: Fail{A.Refused{"scene:actual world light sample missing"}}
    case Some{A.WorldLight{actual,block,sky,+rgb}}:
      do Result<&2,&2,A.Error,U32>:
        A.guard(U32.is_eq(actual,state) && light_valid(block,sky,rgb),"scene:world light state/levels invalid")
        Done{rgb}
def appearance(value:WM.Appearance,rgb:U32) -> WM.Appearance:
  WM.Appearance{tints,old,address,cull,nether,threshold} = value
  WM.Appearance{tints,rgb,address,cull,nether,threshold}
def lit_mode(mode:C.Mode,+cell:GS.Cell,lights:Map<&2,Maybe<&2,A.WorldLight>>) -> Result<&2,&2,A.Error,GS.Cell>:
  match mode:
    case C.Invisible{}: Done{cell}
    case _:
      GS.Cell{+point,+state,seed,surface} = cell
      do Result<&2,&2,A.Error,GS.Cell>:
        rgb:U32 <- world_light(Map.get(Maybe<&2,A.WorldLight>,None{},lights,GS.point_key(point)),state)
        Done{GS.Cell{point,state,seed,appearance(surface,rgb)}}
def lit_cell(entry:C.Entry,cell:GS.Cell,lights:Map<&2,Maybe<&2,A.WorldLight>>) -> Result<&2,&2,A.Error,GS.Cell>:
  C.Entry{identity,mode,root} = entry
  lit_mode(mode,cell,lights)
def light_cells(values:List<&2,GS.Cell>,+catalog:C.Catalog,+lights:Map<&2,Maybe<&2,A.WorldLight>>) -> Result<&2,&2,A.Error,List<&2,GS.Cell>>:
  match values:
    case Nil{}: Done{[]}
    case +head <> rest:
      GS.Cell{point,state,seed,surface} = head
      do Result<&2,&2,A.Error,List<&2,GS.Cell>>:
        entry:C.Entry <- catalog_error(C.Entry,C.lookup(catalog,state))
        head:GS.Cell <- lit_cell(entry,head,lights)
        tail:List<&2,GS.Cell> <- light_cells(rest,catalog,lights)
        Done{head <> tail}
def lighting_ready(value:A.Lighting,+stamp:Wire.Stamp) -> Result<&2,&2,A.Error,A.Lighting>:
  match value:
    case A.Missing{reason}: Fail{A.Refused{"scene:light authority unavailable:" ++ reason}}
    case A.Stable{+actual,cells,+entities}:
      do Result<&2,&2,A.Error,A.Lighting>:
        A.guard(Wire.stamp_equal(stamp,actual),"scene:light publication stamp mismatch")
        A.guard(entity_lights(entities),"scene:entity light levels/RGB invalid")
        A.guard(light_ids_unique(entities),"scene:duplicate entity light sample")
        Done{A.Stable{actual,cells,entities}}
def lit_sample(sample:GS.Sample,+catalog:C.Catalog,cells:Map<&2,Maybe<&2,A.WorldLight>>) -> Result<&2,&2,A.Error,GS.Sample>:
  GS.Sample{registry,tick,revision,origin,camera,values} = sample
  do Result<&2,&2,A.Error,GS.Sample>:
    values:List<&2,GS.Cell> <- light_cells(values,catalog,cells)
    Done{GS.Sample{registry,tick,revision,origin,camera,values}}
def rebase_material(value:M.Material,base:U32) -> M.Material:
  M.Material{texture,tint,light,shade,mode,address} = value
  M.Material{U32.add(base,texture),tint,light,shade,mode,address}
def rebase_quad(value:M.Quad,base:U32,order:U32) -> M.Quad:
  M.Quad{a,b,c,d,material,cull,old} = value
  M.Quad{a,b,c,d,rebase_material(material,base),cull,order}
def append_entities(values:List<&2,M.Quad>,+wc:U32,+ec:U32,+limits:WM.Limits,acc:WM.Accumulator) -> Result<&2,&2,A.Error,WM.Accumulator>:
  match values:
    case Nil{}: Done{acc}
    case +head <> rest:
      WM.Accumulator{reversed,+count,layers} = acc
      do Result<&2,&2,A.Error,WM.Accumulator>:
        A.guard(WM.quad_valid(head,ec),"scene:entity quad/local texture invalid")
        +next:M.Quad = rebase_quad(head,wc,count)
        acc:WM.Accumulator <- mesh_error(WM.Accumulator,WM.add_valid(WM.quad_valid(next,U32.add(wc,ec)),next,acc,limits,0))
        append_entities(rest,wc,ec,limits,acc)
def combined(stamp:Wire.Stamp,+entities:D.Frame,+frame:CW.Frame,+catalog:C.Catalog,+wc:U32,+ec:U32,
    render:WM.Frame,+limits:WM.Limits) -> Result<&2,&2,A.Error,A.Prepared>:
  D.Frame{draws,quads} = entities
  CW.Frame{identity,tick,revision,instances,+camera} = frame
  WM.Frame{width,height,+settings} = render
  WM.Limits{blocks,bindings,max_quads,layers,tints} = limits
  do Result<&2,&2,A.Error,A.Prepared>:
    catalog_error(Unit,CW.configuration(WM.Frame{width,height,settings},camera,limits))
    acc:WM.Accumulator <- catalog_error(WM.Accumulator,CW.instances(instances,catalog,wc,limits,blocks,bindings,WM.Accumulator{[],0,0}))
    acc:WM.Accumulator <- append_entities(quads,wc,ec,limits,acc)
    scene:M.Scene <- mesh_error(M.Scene,WM.finish(Done{acc},camera,settings))
    Done{A.Prepared{stamp,scene,entities}}
def entity_prepared(pair:L.Tables & Result<&2,&2,D.Error,D.Frame>,stamp:Wire.Stamp,frame:CW.Frame,catalog:C.Catalog,wc:U32,ec:U32,render:WM.Frame,limits:WM.Limits) -> L.Tables & Result<&2,&2,A.Error,A.Prepared>:
  (tables,status) = pair
  (tables,Result.bind(&2,&2,A.Error,D.Frame,A.Prepared,entity_error(D.Frame,status),entities => combined(stamp,entities,frame,catalog,wc,ec,render,limits)))
def prepared_world(value:Result<&2,&2,A.Error,CW.Frame>,frame:EF.Frame,stamp:Wire.Stamp,catalog:C.Catalog,wc:U32,items:D.Catalog,ec:U32,lights:List<&2,D.Light>,render:WM.Frame,limits:WM.Limits,scan:Nat,quads:Nat,tables:L.Tables) -> L.Tables & Result<&2,&2,A.Error,A.Prepared>:
  match value:
    case Fail{error}: (tables,Fail{error})
    case Done{world}:
      EF.Frame{GS.Sample{registry,tick,revision,MV.Vec3{x,y,z},camera,cells},entities,dimension,partial} = frame
      entity_prepared(IR.prepare_snapshot(D.Context{dimension,V.Vec3{x,y,z},partial,Camera.billboard(camera),items,lights,scan,quads},entities,tables),stamp,world,catalog,wc,ec,render,limits)
def prepare_lit(value:Result<&2,&2,A.Error,A.Lighting>,+frame:EF.Frame,context:A.Context,
    +catalog:C.Catalog,wc:U32,items:D.Catalog,ec:U32,tables:L.Tables) -> L.Tables & Result<&2,&2,A.Error,A.Prepared>:
  match value:
    case Fail{error}: (tables,Fail{error})
    case Done{A.Missing{reason}}: (tables,Fail{A.Refused{reason}})
    case Done{A.Stable{actual,cells,lights}}:
      EF.Frame{sample,entities,dimension,partial} = frame
      A.Context{stamp,lighting,render,limits,scan,quads} = context
      status = Result.bind(&2,&2,A.Error,GS.Sample,CW.Frame,lit_sample(sample,catalog,cells),sample => catalog_error(CW.Frame,GF.frame(sample,catalog)))
      prepared_world(status,frame,stamp,catalog,wc,items,ec,lights,render,limits,scan,quads,tables)
def prepare_gate(valid:Bool,+context:A.Context,frame:EF.Frame,catalog:C.Catalog,wc:U32,items:D.Catalog,ec:U32,tables:L.Tables) -> L.Tables & Result<&2,&2,A.Error,A.Prepared>:
  match valid:
    case False{}: (tables,Fail{A.Refused{"scene:atomic publication stamp mismatch"}})
    case True{}:
      A.Context{+stamp,+lighting,render,limits,scan,quads} = context
      prepare_lit(lighting_ready(lighting,stamp),frame,context,catalog,wc,items,ec,tables)
def prepare_owned(pair:L.Tables & Result<&2,&2,A.Error,A.Prepared>,resources:R.Assets,catalog:C.Catalog,wc:U32,prefix:Nat,items:D.Catalog,ec:U32) -> A.Assets & L.Tables & Result<&2,&2,A.Error,A.Prepared>:
  (tables,status) = pair
  (A.Assets{resources,catalog,wc,prefix,items,ec},tables,status)
def prepare(+context:A.Context,+frame:EF.Frame,assets:A.Assets,tables:L.Tables) -> A.Assets & L.Tables & Result<&2,&2,A.Error,A.Prepared>:
  A.Context{+stamp,lighting,render,limits,scan,quads} = context
  A.Assets{resources,+catalog,+wc,+prefix,+items,+ec} = assets
  prepare_owned(prepare_gate(Wire.matches(stamp,frame) && Wire.frame_fields_valid(frame),context,frame,catalog,wc,items,ec,tables),resources,catalog,wc,prefix,items,ec)
def render_result(value:Result<&2,&2,M.Error,Image>) -> Result<&2,&2,A.Error,Image>:
  match value:
    case Fail{M.Error{code}}: Fail{A.Refused{"scene:render:" ++ code}}
    case Done{image}: Done{image}
def rendered(pair:R.Assets & Result<&2,&2,M.Error,Image>,world:C.Catalog,wc:U32,prefix:Nat,items:D.Catalog,ec:U32,tables:L.Tables) -> A.Assets & L.Tables & Result<&2,&2,A.Error,Image>:
  (resources,status) = pair
  (A.Assets{resources,world,wc,prefix,items,ec},tables,render_result(status))
def draw_scene(assets:A.Assets,scene:M.Scene,width:U32,height:U32,tables:L.Tables) -> A.Assets & L.Tables & Result<&2,&2,A.Error,Image>:
  A.Assets{resources,world,wc,prefix,items,ec} = assets
  rendered(M.render(scene,resources,width,height),world,wc,prefix,items,ec,tables)
def draw_prepared(pair:A.Assets & L.Tables & Result<&2,&2,A.Error,A.Prepared>,width:U32,height:U32) -> A.Assets & L.Tables & Result<&2,&2,A.Error,Image>:
  (assets,tables,status) = pair
  match status:
    case Fail{error}: (assets,tables,Fail{error})
    case Done{A.Prepared{stamp,scene,entities}}:
      draw_scene(assets,scene,width,height,tables)
def draw(+context:A.Context,frame:EF.Frame,assets:A.Assets,tables:L.Tables) -> A.Assets & L.Tables & Result<&2,&2,A.Error,Image>:
  A.Context{stamp,lighting,WM.Frame{width,height,settings},limits,scan,quads} = context
  draw_prepared(prepare(context,frame,assets,tables),width,height)
