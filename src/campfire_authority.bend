import Base
import ./inventory.bend as I
import ./cooking_recipe.bend as K
import ./crafting_recipe.bend as R
import ./campfire_authority_items.bend as A

type CampfireKind is Data:
  Ordinary{}
  Soul{}
type Cell is Data:
  Cell{input:A.Input,progress:U32,total:U32}
type Four is Data:
  Four{first:Cell,second:Cell,third:Cell,fourth:Cell}
type State is Type:
  State{kind:CampfireKind,lit:Bool,cells:Four,cached_recipe:Maybe<&2,String>}
type Record is Data:
  Record{cells:Four}
type Drop is Data:
  Drop{slot:U32,item:I.Slot}
type Effects is Data:
  Effects{drops:List<&2,Drop>,dirty:Bool,block_updates:Nat,block_changes:Nat}
type Placement is Data:
  Placement{remaining:A.Input,status:Result<&2,&2,String,U32>}
type Candidate is Data:
  Candidate{cells:Four,cache:Maybe<&2,String>,effects:Effects}
type Advanced is Data:
  Advanced{cell:Cell,cache:Maybe<&2,String>,effects:Effects}

def empty_cell() -> Cell: Cell{A.plain(),0,0}
def new(kind:CampfireKind,lit:Bool) -> State:
  State{kind,lit,Four{empty_cell(),empty_cell(),empty_cell(),empty_cell()},None{}}
def effects() -> Effects: Effects{[],False{},0n,0n}
def join_effects(a:Effects,b:Effects) -> Effects:
  Effects{drops,dirty,updates,changes} = a
  Effects{other,more,u,c} = b
  Effects{List.append(&2,Drop,drops,other),dirty || more,Nat.add(updates,u),Nat.add(changes,c)}
def signed_lt(+a:U32,+b:U32) -> Bool:
  U32.is_lt(U32.xor(a,2147483648),U32.xor(b,2147483648))
def signed_min(+a:U32,+b:U32) -> U32: R.choose(U32,a,b,signed_lt(a,b))
def signed_max(+a:U32,+b:U32) -> U32: R.choose(U32,b,a,signed_lt(a,b))
def cool(progress:U32,total:U32,positive:Bool) -> U32:
  match positive:
    case False{}: progress
    case True{}: signed_min(signed_max(U32.sub(progress,2),0),total)
def cooldown(cell:Cell) -> Advanced:
  Cell{input,+progress,+total} = cell
  +positive = signed_lt(0,progress)
  Advanced{Cell{input,cool(progress,total,positive),total},None{},Effects{[],positive,0n,0n}}
def current_cache(value:Maybe<&2,K.Plan>,cache:Maybe<&2,String>) -> Maybe<&2,String>:
  match value:
    case None{}: cache
    case Some{K.Plan{id,kind,output,before,time,xp}}: Some{id}
def result_item(value:Maybe<&2,K.Plan>,original:I.Slot) -> I.Slot:
  match value:
    case None{}: original
    case Some{K.Plan{id,kind,output,before,time,xp}}: output

def cooked(index:U32,cell:Cell,cache:Maybe<&2,String>,output:I.Slot,result:Result<&2,&2,String,Bool>) -> Result<&2,&2,String,Advanced>:
  Cell{input,progress,total} = cell
  match result:
    case Fail{message}: Fail{message}
    case Done{False{}}: Done{Advanced{Cell{input,progress,total},cache,Effects{[],True{},0n,0n}}}
    case Done{True{}}:
      Done{Advanced{Cell{A.plain(),progress,total},cache,Effects{[Drop{index,output}],True{},1n,1n}}}
def recipe_selected(+context:A.Context,cache:Maybe<&2,String>,index:U32,+cell:Cell,
    selected:Result<&2,&2,String,Maybe<&2,K.Plan>>) -> Result<&2,&2,String,Advanced>:
  Cell{A.Input{+original,patch},progress,total} = cell
  match selected:
    case Fail{message}: Fail{message}
    case Done{+value}:
      +output = result_item(value,original)
      cooked(index,cell,current_cache(value,cache),output,A.enabled(context,output))
def due(+context:A.Context,+cache:Maybe<&2,String>,index:U32,+cell:Cell,ready:Bool) -> Result<&2,&2,String,Advanced>:
  Cell{+input,progress,total} = cell
  match ready:
    case False{}: Done{Advanced{cell,cache,Effects{[],True{},0n,0n}}}
    case True{}: recipe_selected(context,cache,index,cell,A.select(context,cache,input))
def cook_cell(context:A.Context,cache:Maybe<&2,String>,index:U32,cell:Cell) -> Result<&2,&2,String,Advanced>:
  Cell{A.Input{slot,patch},+progress,+total} = cell
  match slot:
    case I.InvEmpty{}: Done{Advanced{Cell{A.Input{I.InvEmpty{},patch},progress,total},cache,effects()}}
    case I.InvStack{key,count}:
      due(context,cache,index,Cell{A.Input{I.InvStack{key,count},patch},U32.inc(progress),total},
        Bool.not(signed_lt(U32.inc(progress),total)))
def validate_cell(context:A.Context,cell:Cell) -> Result<&2,&2,String,Unit>:
  Cell{input,progress,total} = cell
  do Result<&2,&2,String,Unit>:
    metadata : Maybe<&2,I.ItemMetadata> <- A.admit(context,input)
    return Unit{}
def validate(+context:A.Context,cells:Four) -> Result<&2,&2,String,Unit>:
  A.Context{K.Catalog{recipes,tags,items},defaults,features} = context
  Four{a,b,c,d} = cells
  do Result<&2,&2,String,Unit>:
    A.guarded(A.supported(recipes),"unsupported campfire recipe domain")
    validate_cell(context,a)
    validate_cell(context,b)
    validate_cell(context,c)
    validate_cell(context,d)
    return Unit{}
def lit_last(a:Cell,b:Cell,c:Cell,acc:Effects,fourth:Advanced) -> Candidate:
  Advanced{d,cache,ed} = fourth
  Candidate{Four{a,b,c,d},cache,join_effects(acc,ed)}
def lit_three(+context:A.Context,a:Cell,b:Cell,acc:Effects,third:Advanced,d:Cell) -> Result<&2,&2,String,Candidate>:
  Advanced{c,cache,ec} = third
  do Result<&2,&2,String,Candidate>:
    fourth : Advanced <- cook_cell(context,cache,3,d)
    return lit_last(a,b,c,join_effects(acc,ec),fourth)
def lit_two(+context:A.Context,a:Cell,acc:Effects,second:Advanced,c:Cell,d:Cell) -> Result<&2,&2,String,Candidate>:
  Advanced{b,cache,eb} = second
  do Result<&2,&2,String,Candidate>:
    third : Advanced <- cook_cell(context,cache,2,c)
    lit_three(context,a,b,join_effects(acc,eb),third,d)
def lit_one(+context:A.Context,first:Advanced,b:Cell,c:Cell,d:Cell) -> Result<&2,&2,String,Candidate>:
  Advanced{a,cache,ea} = first
  do Result<&2,&2,String,Candidate>:
    second : Advanced <- cook_cell(context,cache,1,b)
    lit_two(context,a,ea,second,c,d)
def lit_four(+context:A.Context,cache:Maybe<&2,String>,cells:Four) -> Result<&2,&2,String,Candidate>:
  Four{a,b,c,d} = cells
  do Result<&2,&2,String,Candidate>:
    first : Advanced <- cook_cell(context,cache,0,a)
    lit_one(context,first,b,c,d)
def cooled_last(cache:Maybe<&2,String>,a:Cell,b:Cell,c:Cell,acc:Effects,last:Advanced) -> Candidate:
  Advanced{d,ignored,ed} = last
  Candidate{Four{a,b,c,d},cache,join_effects(acc,ed)}
def cooled_three(cache:Maybe<&2,String>,a:Cell,b:Cell,acc:Effects,third:Advanced,d:Cell) -> Candidate:
  Advanced{c,ignored,ec} = third
  cooled_last(cache,a,b,c,join_effects(acc,ec),cooldown(d))
def cooled_two(cache:Maybe<&2,String>,a:Cell,acc:Effects,second:Advanced,c:Cell,d:Cell) -> Candidate:
  Advanced{b,ignored,eb} = second
  cooled_three(cache,a,b,join_effects(acc,eb),cooldown(c),d)
def cooled_one(cache:Maybe<&2,String>,first:Advanced,b:Cell,c:Cell,d:Cell) -> Candidate:
  Advanced{a,ignored,ea} = first
  cooled_two(cache,a,ea,cooldown(b),c,d)
def unlit_four(cache:Maybe<&2,String>,cells:Four) -> Candidate:
  Four{a,b,c,d} = cells
  cooled_one(cache,cooldown(a),b,c,d)
def proposed(context:A.Context,lit:Bool,cells:Four,cache:Maybe<&2,String>,valid:Result<&2,&2,String,Unit>) -> Result<&2,&2,String,Candidate>:
  match lit valid:
    case _ Fail{message}: Fail{message}
    case True{} Done{unit}: lit_four(context,cache,cells)
    case False{} Done{unit}: Done{unlit_four(cache,cells)}
def committed(state:State,proposal:Result<&2,&2,String,Candidate>) -> State & Result<&2,&2,String,Effects>:
  match state proposal:
    case State{kind,lit,cells,cache} Fail{message}: (State{kind,lit,cells,cache},Fail{message})
    case State{kind,lit,cells,cache} Done{Candidate{next,cache,result}}: (State{kind,lit,next,cache},Done{result})
def step(+context:A.Context,state:State) -> State & Result<&2,&2,String,Effects>:
  State{kind,+lit,+cells,+cache} = state
  committed(State{kind,lit,cells,cache},proposed(context,lit,cells,cache,validate(context,cells)))

def cell_empty(cell:Cell) -> Bool:
  Cell{A.Input{slot,patch},progress,total} = cell
  match slot:
    case I.InvEmpty{}: True{}
    case I.InvStack{key,count}: False{}
def fourth_empty(empty:Bool) -> Maybe<&2,U32>:
  match empty:
    case False{}: None{}
    case True{}: Some{3}
def third_empty(c:Bool,d:Bool) -> Maybe<&2,U32>:
  match c:
    case False{}: fourth_empty(d)
    case True{}: Some{2}
def second_empty(b:Bool,c:Bool,d:Bool) -> Maybe<&2,U32>:
  match b:
    case False{}: third_empty(c,d)
    case True{}: Some{1}
def first_empty_flags(a:Bool,b:Bool,c:Bool,d:Bool) -> Maybe<&2,U32>:
  match a:
    case False{}: second_empty(b,c,d)
    case True{}: Some{0}
def first_empty(cells:Four) -> Maybe<&2,U32>:
  Four{a,b,c,d} = cells
  first_empty_flags(cell_empty(a),cell_empty(b),cell_empty(c),cell_empty(d))
def replace(cells:Four,index:U32,value:Cell) -> Four:
  Four{a,b,c,d} = cells
  match index:
    case 0: Four{value,b,c,d}
    case 1: Four{a,value,c,d}
    case 2: Four{a,b,value,d}
    case _: Four{a,b,c,value}
def retained(held:A.Input,infinite:Bool) -> A.Input:
  A.Input{+slot,patch} = held
  A.Input{R.choose(I.Slot,slot,K.consume_input(slot),infinite),patch}
def one(held:A.Input) -> A.Input:
  match held:
    case A.Input{I.InvEmpty{},patch}: A.plain()
    case A.Input{I.InvStack{key,count},patch}: A.Input{I.InvStack{key,1},patch}
def place_selected(state:State,+held:A.Input,infinite:Bool,+index:U32,selected:Result<&2,&2,String,Maybe<&2,K.Plan>>) -> State & Placement:
  State{kind,lit,cells,cache} = state
  match selected:
    case Fail{message}: (State{kind,lit,cells,cache},Placement{held,Fail{message}})
    case Done{None{}}: (State{kind,lit,cells,cache},Placement{held,Fail{"no campfire recipe"}})
    case Done{Some{K.Plan{id,recipe_kind,output,before,total,xp}}}:
      (State{kind,lit,replace(cells,index,Cell{one(held),0,total}),cache},Placement{retained(held,infinite),Done{index}})
def place_empty(+context:A.Context,state:State,+held:A.Input,infinite:Bool,empty:Maybe<&2,U32>) -> State & Placement:
  match empty:
    case None{}: (state,Placement{held,Fail{"campfire is full"}})
    case Some{index}: place_selected(state,held,infinite,index,A.select(context,None{},held))
def place_checked(+context:A.Context,state:State,+held:A.Input,infinite:Bool,valid:Result<&2,&2,String,Unit>) -> State & Placement:
  State{kind,+lit,+cells,+cache} = state
  match valid:
    case Fail{message}: (State{kind,lit,cells,cache},Placement{held,Fail{message}})
    case Done{unit}: place_empty(context,State{kind,lit,cells,cache},held,infinite,first_empty(cells))
def place(+context:A.Context,state:State,held:A.Input,infinite:Bool) -> State & Placement:
  State{kind,+lit,+cells,+cache} = state
  place_checked(context,State{kind,lit,cells,cache},held,infinite,validate(context,cells))

def placement_effects(value:Placement) -> Effects:
  Placement{remaining,status} = value
  match status:
    case Fail{message}: effects()
    case Done{index}: Effects{[],True{},1n,1n}

def cleared(cell:Cell) -> Cell:
  Cell{input,progress,total} = cell
  Cell{A.plain(),progress,total}
def drop_cell(index:U32,cell:Cell) -> List<&2,Drop>:
  Cell{A.Input{slot,patch},progress,total} = cell
  # Java dropContents calls dropItemStack for every slot, including empty slots.
  # Empty intents retain those RNG-consuming calls for the real drop adapter.
  [Drop{index,slot}]
def remove(state:State) -> State & Effects:
  State{kind,lit,Four{+a,+b,+c,+d},cache} = state
  (State{kind,lit,Four{cleared(a),cleared(b),cleared(c),cleared(d)},cache},
    Effects{List.append(&2,Drop,List.append(&2,Drop,drop_cell(0,a),drop_cell(1,b)),
      List.append(&2,Drop,drop_cell(2,c),drop_cell(3,d))),False{},0n,0n})
def clear(state:State) -> State:
  State{kind,lit,Four{a,b,c,d},cache} = state
  State{kind,lit,Four{cleared(a),cleared(b),cleared(c),cleared(d)},cache}
def cache_reset(state:State) -> State:
  State{kind,lit,cells,cache} = state
  State{kind,lit,cells,None{}}
def set_lit(state:State,+next:Bool) -> State:
  State{kind,+lit,cells,cache} = state
  State{kind,next,cells,R.choose(Maybe<&2,String>,cache,None{},Bool.not(Bool.xor(lit,next)))}
def snapshot(state:State) -> State & Record:
  State{kind,lit,+cells,cache} = state
  (State{kind,lit,cells,cache},Record{cells})
def loaded(state:State,record:Record,valid:Result<&2,&2,String,Unit>) -> State & Result<&2,&2,String,Unit>:
  State{kind,lit,cells,cache} = state
  Record{next} = record
  match valid:
    case Fail{message}: (State{kind,lit,cells,cache},Fail{message})
    case Done{unit}: (State{kind,lit,next,None{}},Done{Unit{}})
def load_record(+context:A.Context,state:State,record:Record) -> State & Result<&2,&2,String,Unit>:
  Record{+cells} = record
  loaded(state,Record{cells},validate(context,cells))
