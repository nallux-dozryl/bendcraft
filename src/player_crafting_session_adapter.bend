import Base
import ./local_player_session.bend as S
import ./player_inventory.bend as I
import ./crafting_recipe.bend as R
import ./player_crafting_authority.bend as A
import ./player_crafting_authority_components.bend as M
import ./player_crafting_authority_menu.bend as Menu

# Transient recipe context is ordinary immutable Data. The Session keeps the
# single original inventory Array and its existing durable Shell ABI.
type Context is Data:
  Context{catalog:R.Catalog,cache:Maybe<&2,R.Plan>,components:M.Mode}

type Request is Data:
  CraftInspect{}
  CraftOpen{}
  CraftClose{}
  CraftClick{index:U32,kind:I.Click}

type Observation is Data:
  Observation{context:Context,reply:Menu.Reply}

def new_with_components(catalog:R.Catalog,components:M.Mode) -> Context:
  Context{catalog,None{},components}

def new(catalog:R.Catalog) -> Context:
  new_with_components(catalog,M.DefaultOnly{})

def invalidate(context:Context) -> Context:
  Context{catalog,cache,mode} = context
  Context{catalog,None{},mode}

# Only this helper constructs the temporary authority, always with PlayerGrid.
# Menu requests preserve that grid owner; the bench Array never enters this
# player Session adapter. Bench authority has its separate owned A.State API.
def returned(result:A.State & Menu.Reply) -> I.State & Observation:
  (A.State{player,catalog,owner,cache,mode},reply) = result
  (player,Observation{Context{catalog,cache,mode},reply})

def dispatched(request:Request,state:A.State) -> I.State & Observation:
  match request:
    case CraftInspect{}: returned(Menu.refresh(state))
    case CraftOpen{}: returned(Menu.open(state))
    case CraftClose{}: returned(Menu.close(state))
    case CraftClick{index,kind}: returned(Menu.click(state,index,kind))

def inventory_request(player:I.State,context:Context,request:Request) -> I.State & Observation:
  Context{catalog,cache,mode} = context
  dispatched(request,A.State{player,catalog,A.PlayerGrid{},cache,mode})

def observed(result:S.State & Observation) -> S.State & Context & Menu.Reply:
  (state,Observation{context,reply}) = result
  (state,context,reply)

def request(state:S.State,context:Context,+value:Request) -> S.State & Context & Menu.Reply:
  observed(S.inventory_query(Observation,state,player => inventory_request(player,context,value)))

def open(state:S.State,context:Context) -> S.State & Context & Menu.Reply:
  request(state,context,CraftOpen{})

def close(state:S.State,context:Context) -> S.State & Context & Menu.Reply:
  request(state,context,CraftClose{})

def click(state:S.State,context:Context,index:U32,kind:I.Click) -> S.State & Context & Menu.Reply:
  request(state,context,CraftClick{index,kind})

# Observation refreshes only derived recipe state; menu-open and revision fields
# remain exactly as received. A failed lookup retains the complete old context.
def inspect(state:S.State,context:Context) -> S.State & Context & Menu.Reply:
  request(state,context,CraftInspect{})
