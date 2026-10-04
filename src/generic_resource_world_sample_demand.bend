import Base
import ./registry.bend as B
import ./resource_block_catalog.bend as C
import ./block_resources.bend as BR
import ./generic_resource_world_sample.bend as GS
import ./client_world.bend as W

# Client demand planning only. Registry is the actual affine owner; committed
# requests are the inventory from the last successful complete resource load.
type Owner is Type:
  Owner{registry:B.Registry,registry_identity:String,committed:List<&2,C.Request>}
type Admission is Data:
  Admission{default_mode:Maybe<&2,C.Mode>,modes:Map<&2,C.Mode>,materials:BR.Policy}
type Limits is Data:
  Limits{max_cells:U32,max_families:U32,catalog:C.Limits}
type Plan is Data:
  Plan{registry_identity:String,requests:List<&2,C.Request>,additions:List<&2,C.Request>,materials:BR.Policy}
type Commitment is Data:
  Commitment{names:Map<&2,Unit>,count:U32}
type Work is Data:
  Work{states:Map<&2,Unit>,families:Map<&2,Unit>,reversed:List<&2,C.Request>,count:U32}
# Recursive empty-tail context bounds native continuation representation.
type Context is Data:
  Context{registry_identity:String,committed:List<&2,C.Request>,names:Map<&2,Unit>,
    admission:Admission,limits:Limits,catalog:Maybe<&2,C.Catalog>,tail:List<&2,Context>}

def present(value:Map<&2,Unit> & Bool) -> Bool:
  (values,found) = value
  found
def mode_present(value:Map<&2,C.Mode> & Bool) -> Bool:
  (values,found) = value
  found
def mode_value(value:Map<&2,C.Mode> & C.Mode) -> C.Mode:
  (values,mode) = value
  mode
def missing_mode(value:Maybe<&2,C.Mode>,name:String,state:U32) -> Result<&2,&2,C.Error,C.Mode>:
  match value:
    case None{}: Fail{C.Error{"ModeNotAdmitted",name,U32.show(state)}}
    case Some{mode}: Done{mode}
def mode_found(found:Bool,+modes:Map<&2,C.Mode>,fallback:Maybe<&2,C.Mode>,+name:String,state:U32) -> Result<&2,&2,C.Error,C.Mode>:
  match found:
    case False{}: missing_mode(fallback,name,state)
    case True{}: Done{mode_value(Map.get(C.Mode,C.Unsupported{"unadmitted"},modes,name))}
def mode_for(value:Admission,+name:String,state:U32) -> Result<&2,&2,C.Error,C.Mode>:
  Admission{fallback,+modes,materials} = value
  mode_found(mode_present(Map.has(&2,C.Mode,modes,name)),modes,fallback,name,state)

def declared_identity(valid:Bool,declared:String,admitted:String) -> Result<&2,&2,C.Error,Unit>:
  match valid:
    case False{}: Fail{C.Error{"RegistryIdentityMismatch","catalog",declared ++ ":" ++ admitted}}
    case True{}: Done{Unit{}}
def identity_first(valid:Bool,+admitted:String,declared:String,+catalog:String) -> Result<&2,&2,C.Error,Unit>:
  do Result<&2,&2,C.Error,Unit>:
    declared_identity(valid,declared,admitted)
    declared_identity(String.eq(catalog,admitted),catalog,admitted)
def identity_guard(+admitted:String,+declared:String,catalog:String) -> Result<&2,&2,C.Error,Unit>:
  identity_first(String.eq(declared,admitted),admitted,declared,catalog)
def actual_identity(valid:Bool,admitted:String,actual:String) -> Result<&2,&2,C.Error,Unit>:
  match valid:
    case False{}: Fail{C.Error{"RegistryIdentityMismatch","registry",admitted ++ ":" ++ actual}}
    case True{}: Done{Unit{}}

def commitment(values:List<&2,C.Request>,+names:Map<&2,Unit>,+count:U32) -> Result<&2,&2,C.Error,Commitment>:
  match values:
    case Nil{}: Done{Commitment{names,count}}
    case C.Request{+name,mode} <> tail:
      do Result<&2,&2,C.Error,Commitment>:
        C.require(B.resource_valid(name),"InvalidCommittedRequest",name,"invalid family identifier")
        C.mode_guard(mode,name)
        C.require(Bool.not(present(Map.has(&2,Unit,names,name))),"DuplicateBlock",name,"duplicate committed catalog request")
        commitment(tail,Map.set(&2,Unit,names,name,Unit{}),U32.inc(count))

def configured(+sample:GS.Sample,+committed:List<&2,C.Request>,limits:Limits) -> Result<&2,&2,C.Error,Commitment>:
  Limits{+cells,+families,+catalog} = limits
  GS.Sample{identity,tick,revision,origin,camera,+values} = sample
  do Result<&2,&2,C.Error,Commitment>:
    C.require(U32.is_le(cells,4096) && U32.is_le(families,4096),"Limits","demand","unsupported demand limits")
    C.request_guard(committed,catalog)
    C.require(Nat.is_le(List.length(&2,C.Request,committed),U32.to_nat(families)),"DemandFamilyBudget","catalog","committed family inventory exceeds demand budget")
    C.require(GS.sample_valid(sample),"InvalidSample","world","")
    C.require(Nat.is_le(List.length(&2,GS.Cell,values),U32.to_nat(cells)),"DemandCellBudget","world","sample exceeds demand cell budget")
    commitment(committed,MTip{},0)

def mark_state(value:Work,state:U32) -> Work:
  Work{states,families,reversed,count} = value
  Work{Map.set(&2,Unit,states,U32.show(state),Unit{}),families,reversed,count}
def add_family(value:Work,+name:String,mode:C.Mode) -> Work:
  Work{states,families,reversed,count} = value
  Work{states,Map.set(&2,Unit,families,name,Unit{}),C.Request{name,mode} <> reversed,U32.inc(count)}
def family_guard(+context:Context,+work:Work,+name:String,+mode:C.Mode) -> Result<&2,&2,C.Error,Unit>:
  Context{identity,committed,names,admission,Limits{cells,+families,C.Limits{+blocks,states,text,resources}},catalog,tail} = context
  Work{seen,seen_families,reversed,+count} = work
  do Result<&2,&2,C.Error,Unit>:
    C.mode_guard(mode,name)
    C.require(U32.is_lt(count,families),"DemandFamilyBudget",name,"committed plus demanded families exceed budget")
    C.require(U32.is_lt(count,blocks),"BlockBudget","catalog","requested block count exceeds budget")
def family_admitted(value:Result<&2,&2,C.Error,Unit>,owner:Owner,work:Work,name:String,mode:C.Mode) -> Owner & Result<&2,&2,C.Error,Work>:
  match value:
    case Fail{error}: (owner,Fail{error})
    case Done{unit}: (owner,Done{add_family(work,name,mode)})
def family_mode(value:Result<&2,&2,C.Error,C.Mode>,owner:Owner,+context:Context,+work:Work,+name:String) -> Owner & Result<&2,&2,C.Error,Work>:
  match value:
    case Fail{error}: (owner,Fail{error})
    case Done{+mode}: family_admitted(family_guard(context,work,name,mode),owner,work,name,mode)
def family_seen(found:Bool,owner:Owner,+context:Context,work:Work,+name:String,state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  match found:
    case True{}: (owner,Done{work})
    case False{}:
      Context{identity,committed,names,admission,limits,catalog,tail} = context
      family_mode(mode_for(admission,name,state),owner,context,work,name)
def family_committed(found:Bool,owner:Owner,+context:Context,+work:Work,+name:String,state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  match found:
    case True{}: (owner,Fail{C.Error{"CommittedFamilyMissing",name,U32.show(state)}})
    case False{}:
      Work{states,+families,reversed,count} = work
      family_seen(present(Map.has(&2,Unit,families,name)),owner,context,work,name,state)
def decoded_state(valid:Bool,owner:Owner,+context:Context,work:Work,+name:String,+state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  match valid:
    case False{}: (owner,Fail{C.Error{"DecodedStateMismatch",name,U32.show(state)}})
    case True{}:
      Context{identity,committed,+names,admission,limits,catalog,tail} = context
      family_committed(present(Map.has(&2,Unit,names,name)),owner,context,work,name,state)
def decoded(value:B.Registry & Result<&2,&2,B.Error,B.Resolved>,identity:String,committed:List<&2,C.Request>,context:Context,work:Work,+state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  match value:
    case (registry,Fail{error}):
      (Owner{registry,identity,committed},Fail{C.Error{"Registry","registry",B.error_text(error)}})
    case (registry,Done{B.Resolved{protocol,name,id,properties}}):
      decoded_state(U32.is_eq(state,id),Owner{registry,identity,committed},context,work,name,state)

# With an installed catalog, only this exact miss branch performs a Registry
# state decode. Startup absence has its own explicit state_catalog(None) path.
# The returned Registry owner is retained when decode/admission later refuses.
def missing_lookup(missing:Bool,error:C.Error,owner:Owner,context:Context,work:Work,+state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  match missing:
    case False{}: (owner,Fail{error})
    case True{}:
      Owner{registry,identity,committed} = owner
      decoded(B.Registry.decode(registry,state),identity,committed,context,work,state)
def loaded_family(found:Bool,owner:Owner,work:Work,name:String,state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  match found:
    case False{}: (owner,Fail{C.Error{"CatalogLedgerMismatch",name,U32.show(state)}})
    case True{}: (owner,Done{work})
def loaded_guarded(value:Result<&2,&2,C.Error,Unit>,owner:Owner,+context:Context,work:Work,+name:String,state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  match value:
    case Fail{error}: (owner,Fail{error})
    case Done{unit}:
      Context{identity,committed,+names,admission,limits,catalog,tail} = context
      loaded_family(present(Map.has(&2,Unit,names,name)),owner,work,name,state)
def looked_up(value:Result<&2,&2,C.Error,C.Entry>,owner:Owner,context:Context,work:Work,state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  match value:
    case Fail{C.Error{+code,+resource,+detail}}:
      missing_lookup(String.eq(code,"StateNotLoaded"),C.Error{code,resource,detail},owner,context,work,state)
    case Done{C.Entry{B.Resolved{protocol,+name,id,properties},+mode,root}}:
      loaded_guarded(C.mode_guard(mode,name),owner,context,work,name,state)
def state_catalog(catalog:Maybe<&2,C.Catalog>,owner:Owner,context:Context,work:Work,+state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  match catalog:
    case None{}:
      Owner{registry,identity,committed} = owner
      decoded(B.Registry.decode(registry,state),identity,committed,context,work,state)
    case Some{catalog}: looked_up(C.lookup(catalog,state),owner,context,work,state)
def state_seen(found:Bool,owner:Owner,+context:Context,work:Work,+state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  match found:
    case True{}: (owner,Done{work})
    case False{}:
      Context{identity,committed,names,admission,limits,catalog,tail} = context
      state_catalog(catalog,owner,context,mark_state(work,state),state)
def state_checked(owner:Owner,+context:Context,+work:Work,+state:U32) -> Owner & Result<&2,&2,C.Error,Work>:
  Work{+states,families,reversed,count} = work
  state_seen(present(Map.has(&2,Unit,states,U32.show(state))),owner,context,work,state)
def collect_cells(values:List<&2,GS.Cell>,owner:Owner,+context:Context,status:Result<&2,&2,C.Error,Work>) -> Owner & Result<&2,&2,C.Error,Work>:
  match values status:
    case _ Fail{error}: (owner,Fail{error})
    case Nil{} Done{work}: (owner,Done{work})
    case GS.Cell{point,state,seed,appearance} <> tail Done{work}:
      W.paired(Owner,Result<&2,&2,C.Error,Work>,Owner & Result<&2,&2,C.Error,Work>,
        state_checked(owner,context,work,state),owner => next => collect_cells(tail,owner,context,next))

# CLoad replaces its complete asset/context owner. Plan.requests therefore
# retains every committed family before the newly demanded first-seen suffix.
def plan_guarded(value:Result<&2,&2,C.Error,Unit>,plan:Plan) -> Result<&2,&2,C.Error,Plan>:
  match value:
    case Fail{error}: Fail{error}
    case Done{unit}: Done{plan}
def plan(context:Context,work:Work) -> Result<&2,&2,C.Error,Plan>:
  Context{identity,+committed,names,Admission{fallback,modes,materials},Limits{cells,families,catalog_limits},catalog,tail} = context
  Work{states,new_families,reversed,count} = work
  +additions = List.reverse(&2,C.Request,reversed)
  +requests = List.append(&2,C.Request,committed,additions)
  plan_guarded(C.request_guard(requests,catalog_limits),Plan{identity,requests,additions,materials})
def finished(value:Owner & Result<&2,&2,C.Error,Work>,context:Context) -> Owner & Result<&2,&2,C.Error,Plan>:
  match value:
    case (owner,Fail{error}): (owner,Fail{error})
    case (owner,Done{work}): (owner,plan(context,work))
def prepared(value:Result<&2,&2,C.Error,Commitment>,owner:Owner,sample:GS.Sample,catalog:Maybe<&2,C.Catalog>,admission:Admission,limits:Limits) -> Owner & Result<&2,&2,C.Error,Plan>:
  match value:
    case Fail{error}: (owner,Fail{error})
    case Done{Commitment{names,count}}:
      Owner{registry,+identity,+committed} = owner
      GS.Sample{sample_identity,tick,revision,origin,camera,cells} = sample
      +context = Context{identity,committed,names,admission,limits,catalog,[]}
      finished(collect_cells(cells,Owner{registry,identity,committed},context,Done{Work{MTip{},MTip{},[],count}}),context)
def registry_guarded(value:Result<&2,&2,C.Error,Unit>,owner:Owner,+sample:GS.Sample,+catalog:Maybe<&2,C.Catalog>,+admission:Admission,+limits:Limits) -> Owner & Result<&2,&2,C.Error,Plan>:
  match value:
    case Fail{error}: (owner,Fail{error})
    case Done{unit}:
      Owner{registry,identity,+committed} = owner
      prepared(configured(sample,committed,limits),Owner{registry,identity,committed},sample,catalog,admission,limits)
def identified(value:B.Registry & Result<&2,&2,String,String>,+identity:String,+committed:List<&2,C.Request>,sample:GS.Sample,catalog:Maybe<&2,C.Catalog>,admission:Admission,limits:Limits) -> Owner & Result<&2,&2,C.Error,Plan>:
  match value:
    case (registry,Fail{message}): (Owner{registry,identity,committed},Fail{C.Error{"RegistryIdentity","registry",message}})
    case (registry,Done{+actual}):
      registry_guarded(actual_identity(String.eq(identity,actual),identity,actual),Owner{registry,identity,committed},sample,catalog,admission,limits)
def gated(value:Result<&2,&2,C.Error,Unit>,owner:Owner,sample:GS.Sample,catalog:Maybe<&2,C.Catalog>,admission:Admission,limits:Limits) -> Owner & Result<&2,&2,C.Error,Plan>:
  match value:
    case Fail{error}: (owner,Fail{error})
    case Done{unit}:
      Owner{registry,identity,committed} = owner
      identified(B.Registry.identity(registry),identity,committed,sample,catalog,admission,limits)

# Pure planning neither commits requests nor installs/replaces texture owners.
# The integrated worker commits only after a coherent full load and actual
# candidate CW/sample admission succeeds. Caller Registry must be load-validated.
def collect(owner:Owner,+sample:GS.Sample,+catalog:C.Catalog,admission:Admission,limits:Limits) -> Owner & Result<&2,&2,C.Error,Plan>:
  Owner{registry,+identity,committed} = owner
  GS.Sample{declared,tick,revision,origin,camera,cells} = sample
  C.Catalog{catalog_identity,entries,loaded} = catalog
  gated(identity_guard(identity,declared,catalog_identity),Owner{registry,identity,committed},sample,Some{catalog},admission,limits)

def inventory_empty(values:List<&2,C.Request>) -> Bool:
  match values:
    case Nil{}: True{}
    case head <> tail: False{}
def initial_inventory_checked(empty:Bool,owner:Owner,sample:GS.Sample,admission:Admission,limits:Limits) -> Owner & Result<&2,&2,C.Error,Plan>:
  match empty:
    case False{}: (owner,Fail{C.Error{"InitialCommittedInventory","demand","initial demand requires an empty committed inventory"}})
    case True{}: gated(Done{Unit{}},owner,sample,None{},admission,limits)
def initial_gated(value:Result<&2,&2,C.Error,Unit>,owner:Owner,sample:GS.Sample,admission:Admission,limits:Limits) -> Owner & Result<&2,&2,C.Error,Plan>:
  match value:
    case Fail{error}: (owner,Fail{error})
    case Done{unit}:
      Owner{registry,identity,+committed} = owner
      initial_inventory_checked(inventory_empty(committed),Owner{registry,identity,committed},sample,admission,limits)

# Startup has no asset/catalog owner yet. Absence is explicit; first-sample
# states decode directly after identity/sample/limit admission, without a fake
# catalog, synthetic StateNotLoaded result, or hardcoded initial content list.
def initial(owner:Owner,+sample:GS.Sample,admission:Admission,limits:Limits) -> Owner & Result<&2,&2,C.Error,Plan>:
  Owner{registry,+identity,committed} = owner
  GS.Sample{+declared,tick,revision,origin,camera,cells} = sample
  initial_gated(declared_identity(String.eq(declared,identity),declared,identity),Owner{registry,identity,committed},sample,admission,limits)
