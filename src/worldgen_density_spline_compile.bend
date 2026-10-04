import Base
import ./worldgen_density_spline.bend as S
import ./json.bend as J

# One-layer transformation composes with the actual density compiler's one
# decreasing-fuel work recursion. Every callback has an explicit affine owner;
# no closure is copied and no whole owner is discarded on refusal.
def multi_result(-Owner:Type,index:U32,result:Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>) -> Owner & Result<&2,&2,String,S.Tree<U32>>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{points}}: (owner,Done{S.Multi{index,points}})

def coordinate_result(-Owner:Type,points:List<&2,S.Point<J.Value>>,result:Owner & Result<&2,&2,String,U32>,
    read_points:Owner -> List<&2,S.Point<J.Value>> -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>) -> Owner & Result<&2,&2,String,S.Tree<U32>>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{index}}: multi_result(Owner,index,read_points(owner,points))

def tree(-Owner:Type,tree:S.Tree<J.Value>,owner:Owner,
    read_coordinate:Owner -> J.Value -> Owner & Result<&2,&2,String,U32>,
    read_points:Owner -> List<&2,S.Point<J.Value>> -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>) -> Owner & Result<&2,&2,String,S.Tree<U32>>:
  match tree:
    case S.Constant{value}: (owner,Done{S.Constant{value}})
    case S.Multi{coordinate,points}: coordinate_result(Owner,points,read_coordinate(owner,coordinate),read_points)

def points_result(-Owner:Type,point:S.Point<U32>,result:Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>) -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{points}}: (owner,Done{point <> points})

def point_tree_result(-Owner:Type,location:F32,derivative:F32,rest:List<&2,S.Point<J.Value>>,
    result:Owner & Result<&2,&2,String,S.Tree<U32>>,
    read_rest:Owner -> List<&2,S.Point<J.Value>> -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>) -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{value}}: points_result(Owner,S.Point{location,value,derivative},read_rest(owner,rest))

def points(-Owner:Type,points:List<&2,S.Point<J.Value>>,owner:Owner,
    read_tree:Owner -> S.Tree<J.Value> -> Owner & Result<&2,&2,String,S.Tree<U32>>,
    read_rest:Owner -> List<&2,S.Point<J.Value>> -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>) -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>:
  match points:
    case Nil{}: (owner,Done{[]})
    case S.Point{location,value,derivative} <> rest:
      point_tree_result(Owner,location,derivative,rest,read_tree(owner,value),read_rest)
