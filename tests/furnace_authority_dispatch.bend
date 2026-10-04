import Base
import ../src/crafting_recipe_decoder.bend as D
import ../src/crafting_recipe.bend as R
import ../src/inventory.bend as Inv
import ../src/json.bend as J

# The expected dispatch labels are independent fixture data. Full recipe values,
# including ingredient alternatives and component identity, are compared below.
type Branch is Data:
  Shaped{}
  Shapeless{}
  Other{}
type Case is Data:
  Case{kind:String,branch:Branch}

def selectors(a:List<&2,R.Selector>,b:List<&2,R.Selector>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case R.Item{x} <> xs R.Item{y} <> ys: String.eq(x,y) && selectors(xs,ys)
    case R.TagRef{x} <> xs R.TagRef{y} <> ys: String.eq(x,y) && selectors(xs,ys)
    case _ _: False{}
def ingredient(a:R.Ingredient,b:R.Ingredient) -> Bool:
  match a b:
    case R.Empty{} R.Empty{}: True{}
    case R.AnyOf{x} R.AnyOf{y}: selectors(x,y)
    case _ _: False{}
def ingredients(a:List<&2,R.Ingredient>,b:List<&2,R.Ingredient>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: ingredient(x,y) && ingredients(xs,ys)
    case _ _: False{}
def recipe(a:R.Recipe,b:R.Recipe) -> Bool:
  match a b:
    case R.Shaped{i,w,h,c,o} R.Shaped{j,x,y,d,p}: String.eq(i,j) && U32.is_eq(w,x) && U32.is_eq(h,y) && ingredients(c,d) && R.snapshot_equal([o],[p])
    case R.Shapeless{i,c,o} R.Shapeless{j,d,p}: String.eq(i,j) && ingredients(c,d) && R.snapshot_equal([o],[p])
    case R.Unsupported{i,k} R.Unsupported{j,l}: String.eq(i,j) && String.eq(k,l)
    case _ _: False{}
def same(a:Result<&2,&2,String,R.Recipe>,b:Result<&2,&2,String,R.Recipe>) -> Bool:
  match a b:
    case Fail{x} Fail{y}: String.eq(x,y)
    case Done{x} Done{y}: recipe(x,y)
    case _ _: False{}
def expected_output(branch:Branch,value:J.Value,output:Inv.Slot) -> Result<&2,&2,String,R.Recipe>:
  match branch:
    case Shaped{}: D.shaped("probe:dispatch",value,output)
    case Shapeless{}: D.shapeless("probe:dispatch",value,output)
    case Other{}: Fail{"unsupported ordinary recipe subclass"}
def expected_decode(branch:Branch,kind:String,value:J.Value) -> Result<&2,&2,String,R.Recipe>:
  match branch:
    case Shaped{}: D.ordinary(kind,"probe:dispatch",value)
    case Shapeless{}: D.ordinary(kind,"probe:dispatch",value)
    case Other{}: Done{R.Unsupported{"probe:dispatch",kind}}
def cases(values:List<&2,Case>,+value:J.Value,+output:Inv.Slot) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case Case{+kind,+branch} <> rest:
      J.JBool{same(D.ordinary_output(kind,"probe:dispatch",value,output),expected_output(branch,value,output))} <>
      J.JBool{same(D.decode_kind(kind,"probe:dispatch",value),expected_decode(branch,kind,value))} <> cases(rest,value,output)
def input(values:List<&2,String>,+dispatch:List<&2,Case>,+output:Inv.Slot) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case raw <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        value : J.Value <- J.parse(raw)
        tail : List<&2,J.Value> <- input(rest,dispatch,output)
        return List.append(&2,J.Value,cases(dispatch,value,output),tail)
def report(result:Result<&2,&2,String,List<&2,J.Value>>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{values}: IO.print(J.encode(J.JArray{values}))
def main() -> IO(Unit):
  report(input([
    "{\"pattern\":[\" AB\",\"   \"],\"key\":{\"A\":[\"stone\",\"#logs\"],\"B\":\"dirt\"},\"result\":{\"id\":\"stick\",\"count\":3}}",
    "{\"ingredients\":[[\"stone\",\"#logs\"],\"dirt\"],\"result\":{\"id\":\"stick\",\"count\":3}}",
    "{}",
    "{\"pattern\":[],\"key\":{},\"ingredients\":[],\"result\":{\"id\":\"stick\",\"count\":0}}",
    "{\"pattern\":[\"A\"],\"key\":{\"A\":\"stone\"},\"ingredients\":[\"stone\"],\"result\":{\"id\":\"stick\",\"components\":{\"minecraft:food\":{}}}}"
  ],[
    Case{"minecraft:crafting_shaped",Shaped{}},Case{"minecraft:crafting_shapeless",Shapeless{}},
    Case{"minecraft:crafting_shaped_extra",Other{}},Case{"minecraft:crafting_shapeless_extra",Other{}},
    Case{"minecraft:crafting_shape",Other{}},Case{"minecraft:crafting_shapeles",Other{}},
    Case{"minecraft:crafting_special_repairitem",Other{}},Case{"",Other{}}
  ],Inv.InvStack{Inv.ItemKey{"probe:output","exact-component-identity"},7}))
