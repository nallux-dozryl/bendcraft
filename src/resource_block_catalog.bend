import Base
import ./registry.bend as G
import ./blockstate_model.bend as S
import ./block_model.bend as B
import ./block_bake.bend as K
import ./block_resources.bend as BR
import ./world_mesh.bend as WM

# Registry state IDs are not model IDs. This catalog retains the exact registry
# identity and property assignment alongside the compiled blockstate root.
type Error is Data:
  Error{code:String,resource:String,detail:String}
type Mode is Data:
  Model{}
  Invisible{}
  Unsupported{renderer:String}
type Request is Data:
  Request{name:String,mode:Mode}
type Limits is Data:
  Limits{max_blocks:U32,max_states:U32,max_state_text:U32,resources:BR.Limits}
type Block is Data:
  Block{metadata:G.Block,mode:Mode}
type Entry is Data:
  Entry{identity:G.Resolved,mode:Mode,root:Maybe<&2,S.Root>}
type Plan is Data:
  Plan{registry_identity:String,entries:Map<&2,Entry>,models:Map<&2,Unit>,states:U32}
type Catalog is Data:
  Catalog{registry_identity:String,entries:Map<&2,Entry>,loaded_catalog:BR.Catalog}
# Tickets belong to the caller's RNG owner. Singles require no random ticket;
# each selected weighted multipart index requires its own bounded ticket.
type Selection is Data:
  Selection{variant_ticket:Maybe<&2,U32>,part_tickets:Map<&2,U32>}
type Bound is Data:
  Bound{identity:G.Resolved,variants:List<&2,S.Variant>,binding:WM.Binding}

def defaults() -> Limits:
  Limits{256,65535,1048576,BR.defaults()}

def require(valid:Bool,code:String,resource:String,detail:String) -> Result<&2,&2,Error,Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{Error{code,resource,detail}}

def registry_result(-A:Data,result:Result<&2,&2,G.Error,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{Error{"Registry","registry",G.error_text(error)}}

def state_result(-A:Data,result:Result<&2,&2,S.Error,A>,name:String) -> Result<&2,&2,Error,A>:
  match result:
    case Done{value}: Done{value}
    case Fail{S.Error{code,path,detail}}: Fail{Error{"Blockstate:" ++ code,name,path ++ ":" ++ detail}}

def resource_result(-A:Data,result:Result<&2,&2,BR.Error,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Done{value}: Done{value}
    case Fail{BR.Error{code,name,detail}}: Fail{Error{"Resource:" ++ code,name,detail}}

def bake_result(result:Result<&2,&2,K.Error,List<&2,K.Baked>>,name:String) -> Result<&2,&2,Error,List<&2,K.Baked>>:
  match result:
    case Done{value}: Done{value}
    case Fail{K.Unsupported{code}}: Fail{Error{"Bake:Unsupported",name,code}}
    case Fail{K.Invalid{code}}: Fail{Error{"Bake:Invalid",name,code}}
    case Fail{K.MissingMaterial{reference}}: Fail{Error{"Bake:MissingMaterial",name,reference}}

def mode_guard(mode:Mode,name:String) -> Result<&2,&2,Error,Unit>:
  match mode:
    case Unsupported{renderer}: Fail{Error{"UnsupportedRenderer",name,renderer}}
    case _: Done{Unit{}}

def limits_valid(value:Limits) -> Bool:
  Limits{blocks,states,text,resources} = value
  U32.is_le(blocks,4096) && U32.is_le(states,65535) &&
    U32.is_le(text,4194304) && BR.limits_valid(resources)

def request_guard(+requests:List<&2,Request>,+limits:Limits) -> Result<&2,&2,Error,Unit>:
  Limits{blocks,states,text,resources} = limits
  do Result<&2,&2,Error,Unit>:
    require(limits_valid(limits),"Limits","catalog","unsupported resource catalog limits")
    require(Nat.is_le(List.length(&2,Request,requests),U32.to_nat(blocks)),"BlockBudget","catalog","requested block count exceeds budget")

# Complete affine registry owner is returned on every lookup outcome.
def looked_up(value:G.Registry & Result<&2,&2,G.Error,G.Block>,mode:Mode) -> G.Registry & Result<&2,&2,Error,Block>:
  (registry,result) = value
  match result:
    case Fail{error}: (registry,Fail{Error{"Registry","registry",G.error_text(error)}})
    case Done{metadata}: (registry,Done{Block{metadata,mode}})

def assignments_map(values:List<&2,G.Assignment>,out:Map<&2,String>) -> Map<&2,String>:
  match values:
    case Nil{}: out
    case G.Assignment{name,value} <> rest: assignments_map(rest,Map.set(&2,String,out,name,value))

def integer_domain(values:List<&2,String>) -> Bool:
  match values:
    case Nil{}: True{}
    case value <> rest: Bool.not(Maybe.is_none(&2,U32,S.property_integer(value))) && integer_domain(rest)

def schema_properties(values:List<&2,G.Property>,out:Map<&2,S.Property>) -> Map<&2,S.Property>:
  match values:
    case Nil{}: out
    case G.Property{name,+domain,count,stride} <> rest:
      schema_properties(rest,Map.set(&2,S.Property,out,name,S.Property{domain,integer_domain(domain)}))

def schema(value:G.Block) -> S.Schema:
  G.Block{protocol,name,first,count,default_id,properties} = value
  S.Schema{name,schema_properties(properties,MTip{})}

def states_walk(fuel:Nat,+first:U32,+offset:U32,+properties:List<&2,G.Property>) -> Result<&2,&2,Error,List<&2,S.State>>:
  match fuel:
    case 0n: Done{Nil{}}
    case 1n+rest:
      do Result<&2,&2,Error,List<&2,S.State>>:
        values:List<&2,G.Assignment> <- registry_result(List<&2,G.Assignment>,G.decode_properties(properties,offset,Done{Nil{}}))
        tail:List<&2,S.State> <- states_walk(rest,first,U32.inc(offset),properties)
        Done{S.State{U32.add(first,offset),assignments_map(values,MTip{})} <> tail}

def states(+value:G.Block) -> Result<&2,&2,Error,List<&2,S.State>>:
  G.Block{protocol,name,first,count,default_id,properties} = value
  states_walk(U32.to_nat(count),first,0,properties)

def identity(value:G.Block,+state:U32) -> Result<&2,&2,Error,G.Resolved>:
  G.Block{protocol,+name,+first,count,default_id,properties} = value
  do Result<&2,&2,Error,G.Resolved>:
    require(U32.is_ge(state,first) && U32.is_lt(U32.sub(state,first),count),"StateBlockMismatch",name,U32.show(state))
    values:List<&2,G.Assignment> <- registry_result(List<&2,G.Assignment>,G.decode_properties(properties,U32.sub(state,first),Done{Nil{}}))
    Done{G.Resolved{protocol,name,state,values}}

def dependency_map(values:List<&2,String>,out:Map<&2,Unit>) -> Map<&2,Unit>:
  match values:
    case Nil{}: out
    case name <> rest: dependency_map(rest,Map.set(&2,Unit,out,name,Unit{}))

def root_required(found:Maybe<&2,S.Root>,name:String,state:U32) -> Result<&2,&2,Error,S.Root>:
  match found:
    case None{}: Fail{Error{"MissingStateModel",name,U32.show(state)}}
    case Some{root}: Done{root}

def diagnostic_guard(values:List<&2,S.Error>,name:String) -> Result<&2,&2,Error,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case S.Error{code,path,detail} <> rest: Fail{Error{"BlockstateDiagnostic:" ++ code,name,path ++ ":" ++ detail}}

def entry_root(mode:Mode,+prepared:S.Prepared,name:String,+state:U32) -> Result<&2,&2,Error,Maybe<&2,S.Root>>:
  match mode:
    case Invisible{}: Done{None{}}
    case Model{}:
      do Result<&2,&2,Error,Maybe<&2,S.Root>>:
        root:S.Root <- root_required(S.lookup(prepared,state),name,state)
        Done{Some{root}}
    case Unsupported{renderer}: Fail{Error{"UnsupportedRenderer",name,renderer}}

def entry_dependencies(found:Maybe<&2,S.Root>,out:Map<&2,Unit>) -> Map<&2,Unit>:
  match found:
    case None{}: out
    case Some{root}: dependency_map(S.dependencies(root),out)

def add_states(values:List<&2,S.State>,+metadata:G.Block,+mode:Mode,+prepared:S.Prepared,plan:Plan) -> Result<&2,&2,Error,Plan>:
  match values:
    case Nil{}: Done{plan}
    case S.State{+id,properties} <> rest:
      G.Block{protocol,+name,first,count,default_id,domain} = metadata
      Plan{registry,+entries,models,total} = plan
      do Result<&2,&2,Error,Plan>:
        require(Bool.not(S.map_present(Entry,Map.has(&2,Entry,entries,U32.show(id)))),"DuplicateStateId",name,U32.show(id))
        identity:G.Resolved <- identity(metadata,id)
        +root:Maybe<&2,S.Root> <- entry_root(mode,prepared,name,id)
        add_states(rest,metadata,mode,prepared,Plan{registry,Map.set(&2,Entry,entries,U32.show(id),Entry{identity,mode,root}),entry_dependencies(root,models),U32.inc(total)})

def checked_prepared(+prepared:S.Prepared,+values:List<&2,S.State>,metadata:G.Block,mode:Mode,plan:Plan,name:String) -> Result<&2,&2,Error,Plan>:
  S.Prepared{roots,diagnostics} = prepared
  do Result<&2,&2,Error,Plan>:
    diagnostic_guard(diagnostics,name)
    add_states(values,metadata,mode,prepared,plan)

def prepared_block(+block:Block,+definition:S.Definition,+plan:Plan,+limits:Limits) -> Result<&2,&2,Error,Plan>:
  Block{+metadata,+mode} = block
  G.Block{protocol,+name,first,+count,default_id,properties} = metadata
  Plan{registry,entries,models,+total} = plan
  Limits{max_blocks,+max_states,text,resources} = limits
  do Result<&2,&2,Error,Plan>:
    mode_guard(mode,name)
    require(U32.is_le(total,max_states) && U32.is_le(count,U32.sub(max_states,U32.min(total,max_states))),"StateBudget",name,"requested state count exceeds catalog budget")
    +values:List<&2,S.State> <- states(metadata)
    +prepared:S.Prepared <- state_result(S.Prepared,S.instantiate(definition,schema(metadata),values),name)
    checked_prepared(prepared,values,metadata,mode,plan,name)

def invisible_block(block:Block,plan:Plan,limits:Limits) -> Result<&2,&2,Error,Plan>:
  prepared_block(block,S.Definition{None{},None{}},plan,limits)

def installed(registry_identity:String,entries:Map<&2,Entry>,loaded_catalog:BR.Catalog) -> Catalog:
  Catalog{registry_identity,entries,loaded_catalog}

def empty_identity() -> G.Resolved:
  G.Resolved{0,"",0,Nil{}}

def empty_entry() -> Entry:
  Entry{empty_identity(),Unsupported{"unbound"},None{}}

def state_identity_guard(matches:Bool,entry:Entry,+state:U32) -> Result<&2,&2,Error,Entry>:
  match matches:
    case False{}: Fail{Error{"StateIdentityMismatch","catalog",U32.show(state)}}
    case True{}: Done{entry}

def admitted_entry(+entry:Entry,+state:U32) -> Result<&2,&2,Error,Entry>:
  Entry{G.Resolved{protocol,name,id,properties},mode,root} = entry
  state_identity_guard(U32.is_eq(state,id),entry,state)

def lookup_found(found:Bool,+entries:Map<&2,Entry>,+state:U32) -> Result<&2,&2,Error,Entry>:
  match found:
    case False{}: Fail{Error{"StateNotLoaded","catalog",U32.show(state)}}
    case True{}: admitted_entry(S.map_value(Entry,Map.get(Entry,empty_entry(),entries,U32.show(state))),state)

def lookup(+catalog:Catalog,+state:U32) -> Result<&2,&2,Error,Entry>:
  Catalog{registry,+entries,loaded} = catalog
  lookup_found(S.map_present(Entry,Map.has(&2,Entry,entries,U32.show(state))),entries,state)

def ticket(choice:S.Choice,found:Maybe<&2,U32>,name:String) -> Result<&2,&2,Error,S.Variant>:
  match choice found:
    case S.Single{variant} _: Done{variant}
    case weighted Some{value}: state_result(S.Variant,S.choose(weighted,value),name)
    case _ None{}: Fail{Error{"MissingRandomTicket",name,"weighted model choice needs an explicit ticket"}}

def part_ticket_found(found:Bool,+tickets:Map<&2,U32>,+index:U32) -> Maybe<&2,U32>:
  match found:
    case False{}: None{}
    case True{}: Some{S.map_value(U32,Map.get(U32,0,tickets,U32.show(index)))}

def part_ticket(+tickets:Map<&2,U32>,+index:U32) -> Maybe<&2,U32>:
  part_ticket_found(S.map_present(U32,Map.has(&2,U32,tickets,U32.show(index))),tickets,index)

def selected_parts(values:List<&2,S.SelectedPart>,+tickets:Map<&2,U32>,+name:String) -> Result<&2,&2,Error,List<&2,S.Variant>>:
  match values:
    case Nil{}: Done{Nil{}}
    case S.SelectedPart{+index,choice} <> rest:
      do Result<&2,&2,Error,List<&2,S.Variant>>:
        variant:S.Variant <- ticket(choice,part_ticket(tickets,index),name)
        tail:List<&2,S.Variant> <- selected_parts(rest,tickets,name)
        Done{variant <> tail}

def select_root(root:S.Root,selection:Selection,name:String) -> Result<&2,&2,Error,List<&2,S.Variant>>:
  match root selection:
    case S.VariantRoot{choice} Selection{variant,parts}:
      do Result<&2,&2,Error,List<&2,S.Variant>>:
        model:S.Variant <- ticket(choice,variant,name)
        Done{model <> Nil{}}
    case S.MultipartRoot{selected,dependencies} Selection{variant,parts}: selected_parts(selected,parts,name)

def selected_mode(mode:Mode,root:Maybe<&2,S.Root>,selection:Selection,name:String,state:U32) -> Result<&2,&2,Error,List<&2,S.Variant>>:
  match mode root:
    case Unsupported{renderer} _: Fail{Error{"UnsupportedRenderer",name,renderer}}
    case Invisible{} _: Done{Nil{}}
    case Model{} Some{value}: select_root(value,selection,name)
    case _ _: Fail{Error{"MissingStateModel",name,U32.show(state)}}

def selected(+entry:Entry,selection:Selection) -> Result<&2,&2,Error,List<&2,S.Variant>>:
  Entry{G.Resolved{protocol,+name,state,properties},mode,root} = entry
  selected_mode(mode,root,selection,name,state)

def variant_state(value:S.Variant) -> K.State:
  S.Variant{model,x,y,z,uvlock} = value
  K.State{x,y,z,uvlock}

def baked_variants(values:List<&2,S.Variant>,+loaded:BR.Catalog) -> Result<&2,&2,Error,List<&2,K.Baked>>:
  match values:
    case Nil{}: Done{Nil{}}
    case +variant <> rest:
      S.Variant{+model,x,y,z,lock} = variant
      BR.Catalog{roots,source,models,sprites,context,usage} = loaded
      do Result<&2,&2,Error,List<&2,K.Baked>>:
        resolved:B.Resolved <- resource_result(B.Resolved,BR.model(loaded,model))
        +quads:List<&2,K.Baked> <- bake_result(K.bake(resolved,variant_state(variant),context),model)
        require(Bool.not(List.is_empty(&2,K.Baked,quads)),"EmptyModelGeometry",model,"use an explicit invisible or special renderer mode")
        tail:List<&2,K.Baked> <- baked_variants(rest,loaded)
        Done{List.append(&2,K.Baked,quads,tail)}

def bound_entry(+entry:Entry,+variants:List<&2,S.Variant>,baked:List<&2,K.Baked>,appearance:WM.Appearance) -> Bound:
  Entry{+identity,mode,root} = entry
  G.Resolved{protocol,name,state,properties} = identity
  Bound{identity,variants,WM.Binding{state,baked,appearance}}

def bind_entry(+entry:Entry,selection:Selection,+loaded:BR.Catalog,appearance:WM.Appearance) -> Result<&2,&2,Error,Bound>:
  do Result<&2,&2,Error,Bound>:
    +variants:List<&2,S.Variant> <- selected(entry,selection)
    baked:List<&2,K.Baked> <- baked_variants(variants,loaded)
    Done{bound_entry(entry,variants,baked,appearance)}

def bind(+catalog:Catalog,state:U32,selection:Selection,appearance:WM.Appearance) -> Result<&2,&2,Error,Bound>:
  Catalog{registry,entries,loaded} = catalog
  do Result<&2,&2,Error,Bound>:
    entry:Entry <- lookup(catalog,state)
    bind_entry(entry,selection,loaded,appearance)

def binding_result(result:Result<&2,&2,Error,Bound>) -> Result<&2,&2,Error,WM.Binding>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Bound{identity,variants,value}}: Done{value}

def binding(+catalog:Catalog,state:U32,selection:Selection,appearance:WM.Appearance) -> Result<&2,&2,Error,WM.Binding>:
  binding_result(bind(catalog,state,selection,appearance))

def first_parts(values:List<&2,S.SelectedPart>,out:Map<&2,U32>) -> Map<&2,U32>:
  match values:
    case Nil{}: out
    case S.SelectedPart{index,choice} <> rest: first_parts(rest,Map.set(&2,U32,out,U32.show(index),0))

# Explicit deterministic choice for previews; it is not Java's position RNG.
def first_selection(value:Entry) -> Selection:
  Entry{identity,mode,root} = value
  match root:
    case Some{S.MultipartRoot{parts,names}}: Selection{Some{0},first_parts(parts,MTip{})}
    case _: Selection{Some{0},MTip{}}
