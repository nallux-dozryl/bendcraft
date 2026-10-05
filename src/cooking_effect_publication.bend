import Base
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as R
import ./cooking_world_bindings.bend as B
import ./cooking_effect_publication_journal.bend as J

type Context is Data:
  Context{bindings:B.Catalog}

def guard(allowed:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match allowed:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}
def binding_equal(a:B.Binding,b:B.Binding) -> Bool:
  B.Binding{s,n,k,l,d,bright} = a
  B.Binding{ss,nn,kk,ll,dd,bb} = b
  U32.is_eq(s,ss) && String.eq(n,nn) && B.same_family(k,kk) &&
    Bool.not(Bool.xor(l,ll)) && U32.is_eq(d,dd) && U32.is_eq(bright,bb)
def registered(binding:B.Binding,value:Result<&2,&2,String,B.Classification>) -> Result<&2,&2,String,Unit>:
  match value:
    case Done{B.Cooking{actual}}:
      guard(binding_equal(binding,actual),"cooking-publication:unauthenticated-source-binding")
    case _: Fail{"cooking-publication:source-is-not-registered-cooker"}
def validate_source(catalog:B.Catalog,+source:J.Source) -> Result<&2,&2,String,Unit>:
  J.Source{position,+binding,incarnation} = source
  B.Binding{state,block,family,lit,dark,bright} = binding
  registered(binding,B.classify(catalog,state))
def sources(+catalog:B.Catalog,+source:J.Source,current:Maybe<&2,J.Source>) -> Result<&2,&2,String,J.Source>:
  match current:
    case None{}: Fail{"cooking-publication:current-block-entity-owner-required"}
    case Some{+actual}:
      do Result<&2,&2,String,J.Source>:
        validate_source(catalog,source)
        validate_source(catalog,actual)
        guard(J.same_owner(source,actual),"cooking-publication:stale-block-entity-incarnation")
        return actual
def initialize_status(engine:G.Engine,+bindings:B.Catalog,core_states:U32,registry_states:U32,
    status:Result<&2,&2,String,String>) -> G.Engine & Result<&2,&2,String,Context>:
  B.Catalog{+expected,+count,values} = bindings
  match status:
    case Fail{message}: (engine,Fail{message})
    case Done{actual}:
      (engine,Result.bind(&2,&2,String,Unit,Context,
        guard(U32.is_eq(core_states,count) && U32.is_eq(registry_states,count) &&
          String.eq(expected,actual),"cooking-publication:registry-identity-mismatch"),unit => Done{Context{bindings}}))
def initialized(world:C.World,bindings:B.Catalog,result:R.Registry & Result<&2,&2,String,String>) ->
    G.Engine & Result<&2,&2,String,Context>:
  C.World{tick,time,paused,daylight,revision,+states,sections,pending,events} = world
  (R.Registry{blocks,names,block_count,+registry_states},status) = result
  initialize_status(G.Engine{C.World{tick,time,paused,daylight,revision,states,sections,pending,events},
    R.Registry{blocks,names,block_count,registry_states}},bindings,states,registry_states,status)
# One startup authentication of the immutable registry; never a per-tick hash.
def initialize(engine:G.Engine,bindings:B.Catalog) -> G.Engine & Result<&2,&2,String,Context>:
  G.Engine{world,registry} = engine
  initialized(world,bindings,R.Registry.identity(registry))
def last_authenticated(catalog:B.Catalog,value:Maybe<&2,J.Receipt>) -> Result<&2,&2,String,Unit>:
  match value:
    case None{}: Done{Unit{}}
    case Some{J.Receipt{position,source,chunk,sequence}}: validate_source(catalog,source)
def restore_authenticated(view:J.View,status:Result<&2,&2,String,Unit>) -> Result<&2,&1,String,J.State>:
  match status:
    case Fail{message}: Fail{message}
    case Done{unit}: J.restore(view)
# Historical last publication is authenticated against the immutable current
# catalog, not against a current incarnation which may legitimately be newer.
def restore_journal(context:Context,+view:J.View) -> Result<&2,&1,String,J.State>:
  Context{catalog} = context
  J.View{sequence,unsaved,last} = view
  restore_authenticated(view,last_authenticated(catalog,last))
def no_assignments(values:List<&2,R.Assignment>) -> Bool:
  match values:
    case Nil{}: True{}
    case _: False{}
def air(value:R.Resolved) -> Bool:
  R.Resolved{protocol,+name,state,assignments} = value
  (String.eq(name,"minecraft:air") || String.eq(name,"minecraft:cave_air") ||
    String.eq(name,"minecraft:void_air")) && no_assignments(assignments)
def decoded_air(world:C.World,result:R.Registry & Result<&2,&2,R.Error,R.Resolved>) ->
    G.Engine & Result<&2,&2,String,Unit>:
  (registry,status) = result
  match status:
    case Fail{error}: (G.Engine{world,registry},Fail{"cooking-publication:registry:" ++ R.error_text(error)})
    case Done{resolved}:
      (G.Engine{world,registry},guard(air(resolved),"cooking-publication:comparator-or-conductor-receiver-required"))
def read_air(registry:R.Registry,result:C.World & Result<&2,&2,C.Error,U32>) ->
    G.Engine & Result<&2,&2,String,Unit>:
  (world,status) = result
  match status:
    case Fail{error}: (G.Engine{world,registry},Fail{"cooking-publication:loaded-horizontal-neighbour-required"})
    case Done{state}: decoded_air(world,R.Registry.decode(registry,state))
def neighbour(engine:G.Engine,position:C.Position) -> G.Engine & Result<&2,&2,String,Unit>:
  G.Engine{world,registry} = engine
  read_air(registry,C.read_block(world,position))
def neighbour_completed(result:G.Engine & Result<&2,&2,String,Unit>,
    next:G.Engine -> G.Engine & Result<&2,&2,String,Unit>) -> G.Engine & Result<&2,&2,String,Unit>:
  (engine,status) = result
  match status:
    case Fail{message}: (engine,Fail{message})
    case Done{unit}: next(engine)
def neighbours(positions:List<&2,C.Position>,engine:G.Engine) -> G.Engine & Result<&2,&2,String,Unit>:
  match positions:
    case Nil{}: (engine,Done{Unit{}})
    case position <> +rest:
      neighbour_completed(neighbour(engine,position),engine => neighbours(rest,engine))
def horizontal(position:C.Position) -> List<&2,C.Position>:
  C.Position{+d,+x,+y,+z} = position
  [C.Position{d,x,y,U32.sub(z,1)},C.Position{d,U32.add(x,1),y,z},
   C.Position{d,x,y,U32.add(z,1)},C.Position{d,U32.sub(x,1),y,z}]
def target_decoded(world:C.World,+current:J.Source,result:R.Registry & Result<&2,&2,R.Error,R.Resolved>) ->
    G.Engine & Result<&2,&2,String,Unit>:
  J.Source{position,B.Binding{+state,+name,family,lit,dark,bright},incarnation} = current
  (registry,status) = result
  match status:
    case Fail{error}: (G.Engine{world,registry},Fail{"cooking-publication:registry:" ++ R.error_text(error)})
    case Done{R.Resolved{protocol,block,actual,assignments}}:
      (G.Engine{world,registry},guard(String.eq(name,block) && U32.is_eq(state,actual),
        "cooking-publication:core-block-identity-or-state-mismatch"))
def target_read(registry:R.Registry,+current:J.Source,result:C.World & Result<&2,&2,C.Error,U32>) ->
    G.Engine & Result<&2,&2,String,Unit>:
  J.Source{position,B.Binding{+state,name,family,lit,dark,bright},incarnation} = current
  (world,status) = result
  match status:
    case Fail{error}: (G.Engine{world,registry},Fail{"cooking-publication:loaded-cooker-required"})
    case Done{actual}: target_decoded(world,current,R.Registry.decode(registry,actual))
def target(engine:G.Engine,current:J.Source,position:C.Position) -> G.Engine & Result<&2,&2,String,Unit>:
  G.Engine{world,registry} = engine
  target_read(registry,current,C.read_block(world,position))
def marked(engine:G.Engine,result:J.State & J.Receipt) -> G.Engine & J.State & Result<&2,&2,String,J.Receipt>:
  (owner,receipt) = result
  (engine,owner,Done{receipt})
def maximum_sequence() -> Nat:
  J.maximum_sequence()
def mark_valid(engine:G.Engine,position:C.Position,source:J.Source,owner:J.State,room:Bool) ->
    G.Engine & J.State & Result<&2,&2,String,J.Receipt>:
  match room:
    case False{}: (engine,owner,Fail{"cooking-publication:journal-sequence-exhausted"})
    case True{}: marked(engine,J.marked(position,source,owner))
def mark_ready(engine:G.Engine,position:C.Position,source:J.Source,owner:J.State) ->
    G.Engine & J.State & Result<&2,&2,String,J.Receipt>:
  J.State{J.View{+sequence,unsaved,last}} = owner
  mark_valid(engine,position,source,J.State{J.View{sequence,unsaved,last}},Nat.is_lt(sequence,maximum_sequence()))
def finished(+position:C.Position,+source:J.Source,owner:J.State,
    result:G.Engine & Result<&2,&2,String,Unit>) -> G.Engine & J.State & Result<&2,&2,String,J.Receipt>:
  (engine,status) = result
  match status:
    case Fail{message}: (engine,owner,Fail{message})
    case Done{unit}: mark_ready(engine,position,source,owner)
def scanned(+position:C.Position,source:J.Source,owner:J.State,
    result:G.Engine & Result<&2,&2,String,Unit>) -> G.Engine & J.State & Result<&2,&2,String,J.Receipt>:
  (engine,status) = result
  match status:
    case Fail{message}: (engine,owner,Fail{message})
    case Done{unit}: finished(position,source,owner,neighbours(horizontal(position),engine))
def sourced(engine:G.Engine,owner:J.State,+position:C.Position,source:J.Source,
    status:Result<&2,&2,String,J.Source>) -> G.Engine & J.State & Result<&2,&2,String,J.Receipt>:
  match status:
    case Fail{message}: (engine,owner,Fail{message})
    case Done{current}: scanned(position,source,owner,target(engine,current,position))
def positioned(engine:G.Engine,owner:J.State,+position:C.Position,+source:J.Source,
    context:Context,current:Maybe<&2,J.Source>,allowed:Bool) -> G.Engine & J.State & Result<&2,&2,String,J.Receipt>:
  Context{bindings} = context
  match allowed:
    case False{}: (engine,owner,Fail{"cooking-publication:source-position-mismatch"})
    case True{}: sourced(engine,owner,position,source,sources(bindings,source,current))
# `source` is producer-captured; `current` comes from the same actual owned
# Store.Entry/incarnation query. Never attest a legacy position-only Dirty here.
def dirty(engine:G.Engine,+context:Context,+source:J.Source,current:Maybe<&2,J.Source>,
    +position:C.Position,owner:J.State) -> G.Engine & J.State & Result<&2,&2,String,J.Receipt>:
  J.Source{+captured,binding,incarnation} = source
  positioned(engine,owner,position,source,context,current,B.equal_position(captured,position))
