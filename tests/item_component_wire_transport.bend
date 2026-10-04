import Base
import ./item_component_wire.bend as Fixture
import ./item_component.bend as F
import ./player_crafting_backend.bend as BackendFixture
import ./core_refusal.bend as CoreImage
import ../src/remote_resource_transport.bend as T
import ../src/remote_resource_backend.bend as B
import ../src/local_player_session.bend as S
import ../src/player_inventory.bend as I
import ../src/inventory.bend as Inv
import ../src/player_item_definitions.bend as D
import ../src/player_item_catalog.bend as Catalog
import ../src/player_crafting_session_adapter.bend as CS
import ../src/player_crafting_authority_components.bend as Mode
import ../src/item_component.bend as C
import ../src/crafting_recipe.bend as R
import ../src/resource_client_wire.bend as W
import ../src/json.bend as J
import ../src/core.bend as Core

type ActorImage is Data:
  ActorImage{inventory:J.Value,context:Maybe<&2,CS.Context>,lease:B.Lease,counter:Nat,nonce:String,capability:String,world:CoreImage.WorldImage}

def tree_paired(left:Array<Inv.Slot> & J.Value,right:Array<Inv.Slot> & J.Value) -> Array<Inv.Slot> & J.Value:
  (xs,a) = left
  (ys,b) = right
  (ANode{xs,ys},J.JArray{[a,b]})

def tree(slots:Array<Inv.Slot>) -> Array<Inv.Slot> & J.Value:
  match slots:
    case ALeaf{+slot}: (ALeaf{slot},J.JArray{[W.inventory_slot_value(slot)]})
    case ANode{left,right}: tree_paired(tree(left),tree(right))

def imaged_fields(+length:U32,+selected:U32,+abilities:I.Abilities,+profile:I.Profile,
    result:Array<Inv.Slot> & J.Value) -> I.State & J.Value:
  I.Abilities{instabuild,maybuild} = abilities
  I.Profile{catalog,I.Status{invulnerable,mayfly,flying,walk,fly},I.Menu{opened,revision,output}} = profile
  (slots,image) = result
  (I.State{Inv.Inventory{slots,length},selected,abilities,profile},J.JObject{[
    J.JMember{"tree",image},J.JMember{"length",W.u(length)},J.JMember{"selected",W.u(selected)},
    J.JMember{"abilities",J.JArray{[J.JBool{instabuild},J.JBool{maybuild}]}},
    J.JMember{"status",J.JArray{[J.JBool{invulnerable},J.JBool{mayfly},J.JBool{flying},W.u(walk),W.u(fly)]}},
    J.JMember{"menu",J.JArray{[J.JBool{opened},W.n(revision),W.menu_result_value(output)]}},J.JMember{"catalog_count",W.u(D.count(catalog))}]} )

def inventory_image(owner:I.State) -> I.State & J.Value:
  I.State{Inv.Inventory{slots,length},selected,abilities,profile} = owner
  imaged_fields(length,selected,abilities,profile,tree(slots))

def imaged_inventory(+lease:B.Lease,+counter:Nat,+nonce:String,+capability:String,owner:Core.Capability,
    +context:Maybe<&2,CS.Context>,world:CoreImage.WorldImage,result:S.State & J.Value) -> B.State & ActorImage:
  (saved,inventory) = result
  (B.State{saved,lease,counter,nonce,capability,owner,context},ActorImage{inventory,context,lease,counter,nonce,capability,world})

def imaged_world(lease:B.Lease,counter:Nat,nonce:String,capability:String,owner:Core.Capability,
    context:Maybe<&2,CS.Context>,result:S.State & CoreImage.WorldImage) -> B.State & ActorImage:
  (saved,world) = result
  imaged_inventory(lease,counter,nonce,capability,owner,context,world,S.inventory_query(J.Value,saved,inventory_image))

def image(state:B.State) -> B.State & ActorImage:
  B.State{saved,lease,counter,nonce,capability,owner,context} = state
  imaged_world(lease,counter,nonce,capability,owner,context,BackendFixture.session_world(saved))

def selectors(values:List<&2,R.Selector>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case R.Item{id} <> rest: J.JArray{[W.u(0),J.JString{id}]} <> selectors(rest)
    case R.TagRef{id} <> rest: J.JArray{[W.u(1),J.JString{id}]} <> selectors(rest)

def ingredients(values:List<&2,R.Ingredient>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case R.Empty{} <> rest: J.JNull{} <> ingredients(rest)
    case R.AnyOf{values} <> rest: J.JArray{selectors(values)} <> ingredients(rest)

def recipes(values:List<&2,R.Recipe>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case R.Shaped{id,width,height,cells,output} <> rest:
      J.JArray{[W.u(0),J.JString{id},W.u(width),W.u(height),J.JArray{ingredients(cells)},W.inventory_slot_value(output)]} <> recipes(rest)
    case R.Shapeless{id,cells,output} <> rest:
      J.JArray{[W.u(1),J.JString{id},J.JArray{ingredients(cells)},W.inventory_slot_value(output)]} <> recipes(rest)
    case R.Unsupported{id,kind} <> rest: J.JArray{[W.u(2),J.JString{id},J.JString{kind}]} <> recipes(rest)

def strings(values:List<&2,String>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: J.JString{value} <> strings(rest)

def tags(values:List<&2,R.Tag>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case R.Tag{id,items} <> rest: J.JArray{[J.JString{id},J.JArray{strings(items)}]} <> tags(rest)

def definitions(values:List<&2,R.ItemDefinition>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case R.ItemDefinition{id,limit,remainder} <> rest:
      J.JArray{[J.JString{id},W.u(limit),W.inventory_slot_value(remainder)]} <> definitions(rest)

def consumptions(values:List<&2,R.Consumption>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case R.Consumption{index,count,remainder} <> rest:
      J.JArray{[W.u(index),W.u(count),W.inventory_slot_value(remainder)]} <> consumptions(rest)

def plan(value:Maybe<&2,R.Plan>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{R.Plan{id,output,R.Grid{width,height,slots},steps}}:
      J.JArray{[J.JString{id},W.inventory_slot_value(output),W.u(width),W.u(height),J.JArray{W.inventory_slot_values(slots)},J.JArray{consumptions(steps)}]}

def mode(value:Mode.Mode) -> J.Value:
  match value:
    case Mode.DefaultOnly{}: W.u(0)
    case Mode.TypedStew{defaults}: W.u(1)

def context(value:Maybe<&2,CS.Context>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{CS.Context{R.Catalog{specs,groups,items},cached,components}}:
      J.JArray{[J.JArray{recipes(specs)},J.JArray{tags(groups)},J.JArray{definitions(items)},plan(cached),mode(components)]}

def image_value(value:ActorImage) -> J.Value:
  ActorImage{inventory,old_context,B.Lease{epoch,next,remaining,active},counter,nonce,capability,world} = value
  J.JObject{[J.JMember{"inventory",inventory},J.JMember{"context",context(old_context)},
    J.JMember{"lease",J.JArray{[J.JString{epoch},W.n(next),W.u(remaining),J.JBool{active}]}},
    J.JMember{"counter",W.n(counter)},J.JMember{"nonce",J.JString{nonce}},J.JMember{"capability",J.JString{capability}}]}

def worlds(before:ActorImage,after:ActorImage) -> Bool:
  ActorImage{inventory,context,lease,counter,nonce,capability,first} = before
  ActorImage{inventory2,context2,lease2,counter2,nonce2,capability2,second} = after
  CoreImage.worlds_equal(first,second)

def reply(value:Result<&2,&2,String,J.Value>) -> J.Value:
  match value:
    case Fail{message}: F.error(message)
    case Done{value}: value

def report(+before:ActorImage,+prepared:T.PreparedAnswer,result:B.State & ActorImage) -> IO(Unit):
  T.PreparedAnswer{T.Answer{answer,assigned,keep},encoding} = prepared
  (state,+after) = result
  do IO<Unit>:
    CoreImage.require(worlds(before,after),"prospective inventory command changed complete raw Core")
    IO.print(J.encode(J.JObject{[J.JMember{"before",image_value(before)},J.JMember{"after",image_value(after)},
      J.JMember{"reply",reply(W.reply_json(answer))},J.JMember{"encoding",Fixture.encoded_string(encoding)},
      J.JMember{"assigned",J.JString{assigned}},J.JMember{"keep",J.JBool{keep}},J.JMember{"world_unchanged",J.JBool{True{}}}]}))
    BackendFixture.dispose(state)

def called(before:ActorImage,result:B.State & T.PreparedAnswer) -> IO(Unit):
  (state,prepared) = result
  report(before,prepared,image(state))

def observed(epoch:String,sequence:Nat,command:W.Command,result:B.State & ActorImage) -> IO(Unit):
  (state,before) = result
  called(before,T.command_prepared(state,epoch,sequence,command))

def shape(name:String,owner:I.State) -> I.State:
  match name owner:
    case "short" I.State{Inv.Inventory{slots,length},selected,abilities,profile}:
      I.State{Inv.Inventory{ALeaf{Inv.InvStack{Inv.ItemKey{"fixture:raw","\ninvalid"},4294967295}},length},selected,abilities,profile}
    case "unbalanced" I.State{Inv.Inventory{slots,length},selected,abilities,profile}:
      I.State{Inv.Inventory{ANode{ALeaf{Inv.InvEmpty{}},ANode{ALeaf{Inv.InvStack{Inv.ItemKey{"fixture:raw","\ninvalid"},4294967295}},ALeaf{Inv.InvStack{Inv.ItemKey{"minecraft:stone",""},7}}}},length},selected,abilities,profile}
    case _ own: own

def cached() -> R.Plan:
  R.Plan{"fixture:old-cache",Inv.InvStack{Inv.ItemKey{"minecraft:stone",""},7},R.Grid{2,2,[Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{}]},[]}

def fixture_context(name:String,key:Inv.ItemKey) -> Maybe<&2,CS.Context>:
  match name:
    case "none": None{}
    case "output": Some{CS.Context{R.Catalog{[R.Shaped{"fixture:long-output",1,1,[R.AnyOf{[R.Item{"minecraft:stone"}]}],Inv.InvStack{key,1}}],[],[R.ItemDefinition{"minecraft:stone",64,Inv.InvEmpty{}},R.ItemDefinition{"minecraft:suspicious_stew",1,Inv.InvEmpty{}}]},Some{cached()},Mode.TypedStew{C.InitializedSuspiciousStew{}}}}
    case _: Some{CS.Context{R.Catalog{[],[],[R.ItemDefinition{"minecraft:stone",64,Inv.InvEmpty{}},R.ItemDefinition{"minecraft:suspicious_stew",1,Inv.InvEmpty{}}]},Some{cached()},Mode.TypedStew{C.InitializedSuspiciousStew{}}}}

def need(-A:Data,result:Result<&2,&2,String,A>) -> IO(A):
  match result:
    case Fail{message}: IO.die(A,2,message)
    case Done{value}: IO.pure(A,value)

def requested(inventory:I.State,context_name:String,shape_name:String,key:Inv.ItemKey,request:W.Request) -> IO(Unit):
  match request:
    case W.Call{epoch,sequence,command}:
      do IO<Unit>:
        file:File <- IO.try(File,File.open("/dev/null","r"))
        observed(epoch,sequence,command,image(B.State{BackendFixture.session(file,shape(shape_name,inventory)),B.Lease{"fixture:epoch",1n,41,True{}},5n,"fixture:nonce","fixture:token",Core.Player{17},fixture_context(context_name,key)}))
    case _: IO.die(Unit,2,"call fixture required")

def ready(+value:J.Value,result:Result<&2,&1,String,I.State>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{inventory}:
      do IO<Unit>:
        context_raw:J.Value <- need(J.Value,F.required(J.member(value,"context"),"context"))
        context_name:String <- need(String,F.text_value(context_raw))
        shape_raw:J.Value <- need(J.Value,F.required(J.member(value,"shape"),"shape"))
        shape_name:String <- need(String,F.text_value(shape_raw))
        key:Inv.ItemKey <- need(Inv.ItemKey,F.fixture_key(value))
        raw:J.Value <- need(J.Value,F.required(J.member(value,"wire"),"wire"))
        wire:String <- need(String,F.text_value(raw))
        request:W.Request <- need(W.Request,W.decode_request(wire))
        requested(inventory,context_name,shape_name,key,request)

def fixtures(+catalog:D.Catalog,values:List<&2,J.Value>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case +value <> rest:
      do IO<Unit>:
        ready(value,Fixture.fixture_state(catalog,value))
        fixtures(catalog,rest)

def parsed(catalog:D.Catalog,value:J.Value) -> IO(Unit):
  match value:
    case J.JArray{values}: fixtures(catalog,values)
    case _: IO.die(Unit,2,"fixture array required")

def read_done(catalog:D.Catalog,result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    text:String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    value:J.Value <- need(J.Value,J.parse_bounded(text,8388608n,32))
    parsed(catalog,value)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "gate" <> rest: Fixture.arguments(exe <> rest)
    case exe <> "backend" <> Nil{}: BackendFixture.main()
    case exe <> table <> path <> Nil{}:
      do IO<Unit>:
        loaded:Result<&2,&2,String,D.Catalog> <- Catalog.load(table)
        catalog:D.Catalog <- need(D.Catalog,loaded)
        file:File <- IO.try(File,File.open(path,"r"))
        result:File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
        read_done(catalog,result)
    case _: IO.die(Unit,2,"expected table and fixture file")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
