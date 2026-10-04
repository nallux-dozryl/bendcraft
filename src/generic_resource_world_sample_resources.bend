import Base
import ./generic_resource_world_sample.bend as GS
import ./generic_resource_world_sample_demand.bend as Demand
import ./generic_resource_world_sample_frame.bend as Frame
import ./generic_resource_world_sample_presenter.bend as Draw
import ./registry.bend as Registry
import ./resource_block_catalog.bend as C
import ./resource_catalog_world.bend as CW
import ./resource_frame.bend as RF
import ./world_mesh.bend as WM
import ./mesh_render.bend as M

type Config is Data:
  Config{jar:String,admission:Demand.Admission,limits:Demand.Limits}
type Session is Type:
  Session{owner:Demand.Owner,assets:CW.Assets,config:Config}

# The caller supplies the Registry and complete request inventory returned by
# the same validated successful load as assets. This retains that real owner;
# extracting its admitted identity does not fabricate a new registry/catalog.
def installed(registry:Registry.Registry,committed:List<&2,C.Request>,assets:CW.Assets,config:Config) -> Session:
  CW.Assets{resources,+catalog,textures} = assets
  Session{Demand.Owner{registry,CW.catalog_identity(catalog),committed},
    CW.Assets{resources,catalog,textures},config}

# These pure helpers are used by actual failure continuations below. They keep
# the returned Registry, the previous ledger and the previous asset owner.
def retained(error:C.Error,owner:Demand.Owner,assets:CW.Assets,config:Config) -> Session & Result<&2,&2,C.Error,Unit>:
  (Session{owner,assets,config},Fail{error})

def load_refused(registry:Registry.Registry,error:C.Error,identity:String,
    committed:List<&2,C.Request>,previous:CW.Assets,config:Config) -> Session & Result<&2,&2,C.Error,Unit>:
  retained(error,Demand.Owner{registry,identity,committed},previous,config)

def unchanged(value:Result<&2,&2,C.Error,CW.Frame>,owner:Demand.Owner,assets:CW.Assets,config:Config) -> Session & Result<&2,&2,C.Error,Unit>:
  match value:
    case Fail{error}: retained(error,owner,assets,config)
    case Done{frame}: (Session{owner,assets,config},Done{Unit{}})

def unchanged_informed(value:CW.Assets & CW.Info,sample:GS.Sample,
    owner:Demand.Owner,config:Config) -> Session & Result<&2,&2,C.Error,Unit>:
  (assets,info) = value
  unchanged(Frame.draw_frame(sample,info),owner,assets,config)

def rejected(error:C.Error,candidate:CW.Assets,owner:Demand.Owner,
    previous:CW.Assets,config:Config) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  do IO<Session & Result<&2,&2,C.Error,Unit>>:
    CW.close_assets(candidate)
    return retained(error,owner,previous,config)

def addition_names(values:List<&2,C.Request>) -> String:
  match values:
    case Nil{}: ""
    case C.Request{name,mode} <> Nil{}: name
    case C.Request{name,mode} <> tail: name ++ "," ++ addition_names(tail)

# Only the actual candidate Frame/CW.scene continuation reaches publication.
# Scene admission checks every selected binding, appearance and shared budget.
# A mere plan or successful resource load does not update the committed ledger.
def candidate_admitted(value:Result<&2,&2,C.Error,M.Scene>,candidate:CW.Assets,
    plan:Demand.Plan,owner:Demand.Owner,previous:CW.Assets,config:Config) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  match value:
    case Fail{error}: rejected(error,candidate,owner,previous,config)
    case Done{scene}:
      Demand.Plan{identity,+requests,additions,materials} = plan
      Demand.Owner{registry,previous_identity,committed} = owner
      next : Session = Session{Demand.Owner{registry,identity,requests},candidate,config}
      do IO<Session & Result<&2,&2,C.Error,Unit>>:
        IO.print("catalog.demand|" ++ Nat.show(List.length(&2,C.Request,committed)) ++ "|" ++
          Nat.show(List.length(&2,C.Request,requests)) ++ "|" ++ addition_names(additions))
        CW.close_assets(previous)
        return (next,Done{Unit{}})

def candidate_framed(value:Result<&2,&2,C.Error,CW.Frame>,candidate:CW.Assets,
    plan:Demand.Plan,owner:Demand.Owner,previous:CW.Assets,config:Config,
    catalog:C.Catalog,textures:U32,width:U32,height:U32) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  match value:
    case Fail{error}: rejected(error,candidate,owner,previous,config)
    case Done{frame}:
      candidate_admitted(CW.scene(frame,catalog,textures,WM.frame(width,height),WM.defaults()),
        candidate,plan,owner,previous,config)

def candidate_informed(value:CW.Assets & CW.Info,sample:GS.Sample,
    plan:Demand.Plan,owner:Demand.Owner,previous:CW.Assets,config:Config,
    width:U32,height:U32) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  (candidate,CW.Info{+catalog,+textures}) = value
  candidate_framed(Frame.draw_frame(sample,CW.Info{catalog,textures}),candidate,
    plan,owner,previous,config,catalog,textures,width,height)

def loaded(value:Registry.Registry & Result<&2,&1,C.Error,CW.Assets>,sample:GS.Sample,
    plan:Demand.Plan,identity:String,committed:List<&2,C.Request>,previous:CW.Assets,
    config:Config,width:U32,height:U32) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  match value:
    case (registry,Fail{error}):
      IO.pure(Session & Result<&2,&2,C.Error,Unit>,
        load_refused(registry,error,identity,committed,previous,config))
    case (registry,Done{candidate}):
      candidate_informed(CW.info(candidate),sample,plan,
        Demand.Owner{registry,identity,committed},previous,config,width,height)

# CL/BR load a fresh coherent material context. Previous assets remain outside
# the call; loading only additions or merging unrelated texture slots is invalid.
def reload(+plan:Demand.Plan,sample:GS.Sample,width:U32,height:U32,
    owner:Demand.Owner,previous:CW.Assets,+config:Config) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  Demand.Plan{declared,requests,additions,materials} = plan
  Demand.Owner{registry,identity,committed} = owner
  Config{jar,admission,Demand.Limits{cells,families,limits}} = config
  do IO<Session & Result<&2,&2,C.Error,Unit>>:
    value:Registry.Registry & Result<&2,&1,C.Error,CW.Assets> <-
      RF.catalog_load(jar,registry,requests,materials,limits)
    loaded(value,sample,plan,identity,committed,previous,config,width,height)

def additions_checked(values:List<&2,C.Request>,plan:Demand.Plan,sample:GS.Sample,
    width:U32,height:U32,owner:Demand.Owner,assets:CW.Assets,config:Config) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  match values:
    case Nil{}:
      IO.pure(Session & Result<&2,&2,C.Error,Unit>,unchanged_informed(CW.info(assets),sample,owner,config))
    case head <> tail: reload(plan,sample,width,height,owner,assets,config)

def planned(value:Demand.Owner & Result<&2,&2,C.Error,Demand.Plan>,sample:GS.Sample,
    width:U32,height:U32,assets:CW.Assets,config:Config) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  match value:
    case (owner,Fail{error}):
      IO.pure(Session & Result<&2,&2,C.Error,Unit>,retained(error,owner,assets,config))
    case (owner,Done{+plan}):
      Demand.Plan{identity,requests,additions,materials} = plan
      additions_checked(additions,plan,sample,width,height,owner,assets,config)

def missing(valid:Bool,error:C.Error,+sample:GS.Sample,width:U32,height:U32,
    owner:Demand.Owner,assets:CW.Assets,+config:Config,catalog:C.Catalog) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  match valid:
    case False{}:
      IO.pure(Session & Result<&2,&2,C.Error,Unit>,retained(error,owner,assets,config))
    case True{}:
      Config{jar,admission,limits} = config
      planned(Demand.collect(owner,sample,catalog,admission,limits),sample,width,height,assets,config)

# Warm frames only resolve/validate the actual existing catalog frame. Normal
# draw subsequently admits the scene. They do not hash Registry or replan demand.
def current_framed(value:Result<&2,&2,C.Error,CW.Frame>,sample:GS.Sample,width:U32,height:U32,
    owner:Demand.Owner,assets:CW.Assets,config:Config,catalog:C.Catalog) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  match value:
    case Fail{C.Error{+code,resource,detail}}:
      missing(String.eq(code,"StateNotLoaded"),C.Error{code,resource,detail},
        sample,width,height,owner,assets,config,catalog)
    case Done{frame}:
      IO.pure(Session & Result<&2,&2,C.Error,Unit>,(Session{owner,assets,config},Done{Unit{}}))

def informed(value:CW.Assets & CW.Info,+sample:GS.Sample,width:U32,height:U32,
    owner:Demand.Owner,config:Config) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  (assets,CW.Info{+catalog,textures}) = value
  current_framed(Frame.draw_frame(sample,CW.Info{catalog,textures}),
    sample,width,height,owner,assets,config,catalog)

def ensure(sample:GS.Sample,width:U32,height:U32,session:Session) -> IO(Session & Result<&2,&2,C.Error,Unit>):
  Session{owner,assets,config} = session
  informed(CW.info(assets),sample,width,height,owner,config)

def drawn(value:CW.Assets & Result<&2,&2,String,Image>,owner:Demand.Owner,
    config:Config) -> Session & Result<&2,&2,String,Image>:
  (assets,status) = value
  (Session{owner,assets,config},status)

def draw(sample:GS.Sample,session:Session,width:U32,height:U32) -> Session & Result<&2,&2,String,Image>:
  Session{owner,assets,config} = session
  drawn(Draw.draw(sample,assets,width,height),owner,config)

def close(session:Session) -> IO(Unit):
  Session{owner,assets,config} = session
  CW.close_assets(assets)
