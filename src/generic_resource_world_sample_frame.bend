import Base
import ./generic_resource_world_sample.bend as GS
import ./client_world.bend as W
import ./client_render.bend as R
import ./movement.bend as MV
import ./world_mesh.bend as WM
import ./blockstate_model.bend as S
import ./resource_block_catalog.bend as C
import ./resource_catalog_world.bend as CW

# Client-only catalog/model selection and resource binding. The shared actor
# sample module retains its existing DTO types without importing this graph.
def choice_ticket(choice:S.Choice,seed:U32) -> Result<&2,&2,C.Error,Maybe<&2,U32>>:
  match choice:
    case S.Single{variant}: Done{None{}}
    case S.WeightedChoice{entries,+total}:
      do Result<&2,&2,C.Error,Maybe<&2,U32>>:
        C.require(U32.is_gt(total,0),"InvalidWeightedChoice","catalog","zero total")
        Done{Some{U32.mod(seed,total)}}

def ticketed_part(ticket:Maybe<&2,U32>,index:U32,out:Map<&2,U32>) -> Map<&2,U32>:
  match ticket:
    case None{}: out
    case Some{value}: Map.set(&2,U32,out,U32.show(index),value)

def part_tickets(values:List<&2,S.SelectedPart>,+seed:U32,out:Map<&2,U32>) -> Result<&2,&2,C.Error,Map<&2,U32>>:
  match values:
    case Nil{}: Done{out}
    case S.SelectedPart{+index,choice} <> tail:
      do Result<&2,&2,C.Error,Map<&2,U32>>:
        ticket:Maybe<&2,U32> <- choice_ticket(choice,GS.mixed(seed,index))
        part_tickets(tail,seed,ticketed_part(ticket,index,out))

def selection(entry:C.Entry,seed:U32) -> Result<&2,&2,C.Error,C.Selection>:
  C.Entry{identity,mode,root} = entry
  match root:
    case None{}: Done{C.Selection{None{},MTip{}}}
    case Some{S.VariantRoot{choice}}:
      do Result<&2,&2,C.Error,C.Selection>:
        ticket:Maybe<&2,U32> <- choice_ticket(choice,seed)
        Done{C.Selection{ticket,MTip{}}}
    case Some{S.MultipartRoot{parts,names}}:
      do Result<&2,&2,C.Error,C.Selection>:
        tickets:Map<&2,U32> <- part_tickets(parts,seed,MTip{})
        Done{C.Selection{None{},tickets}}

def retained_instance(mode:C.Mode,point:W.Cell,state:U32,selection:C.Selection,
    appearance:WM.Appearance,origin:MV.Vec3,tail:List<&2,CW.Instance>) -> List<&2,CW.Instance>:
  match mode:
    case C.Invisible{}: tail
    case _: CW.Instance{W.relative_block(W.RawBlock{point,state,0},origin),selection,appearance} <> tail

def entry_mode(entry:C.Entry) -> C.Mode:
  C.Entry{identity,mode,root} = entry
  mode

def instances(values:List<&2,GS.Cell>,+origin:MV.Vec3,+catalog:C.Catalog) -> Result<&2,&2,C.Error,List<&2,CW.Instance>>:
  match values:
    case Nil{}: Done{Nil{}}
    case GS.Cell{point,+state,seed,appearance} <> tail:
      do Result<&2,&2,C.Error,List<&2,CW.Instance>>:
        +entry:C.Entry <- C.lookup(catalog,state)
        decision:C.Selection <- selection(entry,seed)
        rest:List<&2,CW.Instance> <- instances(tail,origin,catalog)
        Done{retained_instance(entry_mode(entry),point,state,decision,appearance,origin,rest)}

def framed(value:Result<&2,&2,C.Error,List<&2,CW.Instance>>,identity:String,tick:Nat,
    revision:Nat,camera:R.Camera) -> Result<&2,&2,C.Error,CW.Frame>:
  match value:
    case Fail{error}: Fail{error}
    case Done{instances}: Done{CW.Frame{identity,tick,revision,instances,camera}}

def frame_configured(valid:Bool,sample:GS.Sample,catalog:C.Catalog) -> Result<&2,&2,C.Error,CW.Frame>:
  match valid sample:
    case False{} _: Fail{C.Error{"InvalidSample","world",""}}
    case True{} GS.Sample{identity,tick,revision,origin,camera,cells}:
      framed(instances(cells,origin,catalog),identity,tick,revision,camera)

def frame_gated(value:Result<&2,&2,C.Error,Unit>,+sample:GS.Sample,catalog:C.Catalog) -> Result<&2,&2,C.Error,CW.Frame>:
  match value:
    case Fail{error}: Fail{error}
    case Done{unit}: frame_configured(GS.sample_valid(sample),sample,catalog)

def frame(+sample:GS.Sample,+catalog:C.Catalog) -> Result<&2,&2,C.Error,CW.Frame>:
  GS.Sample{+identity,tick,revision,origin,camera,cells} = sample
  C.Catalog{+registry,entries,loaded} = catalog
  frame_gated(CW.identity_guard(String.eq(identity,registry),identity,registry),sample,catalog)

def draw_frame(sample:GS.Sample,info:CW.Info) -> Result<&2,&2,C.Error,CW.Frame>:
  CW.Info{catalog,textures} = info
  frame(sample,catalog)
