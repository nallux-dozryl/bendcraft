import Base
import ./worldgen_density_spline.bend as S

def extended(-Owner:Type,x:F32,location:F32,derivative:F32,
    result:Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{value}}: (owner,Done{S.extend(x,location,value,derivative)})

def interpolated(-Owner:Type,x:F32,l0:F32,l1:F32,v0:F32,d0:F32,d1:F32,
    result:Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{v1}}: (owner,Done{S.hermite(x,l0,l1,v0,v1,d0,d1)})

def endpoint(-Owner:Type,owner:Owner,x:F32,point:Maybe<&2,S.Point<U32>>,
    read:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match point:
    case None{}: (owner,Fail{"density spline selected point is absent"})
    case Some{S.Point{location,value,derivative}}:
      extended(Owner,x,location,derivative,read(value,owner))

def segment_left(-Owner:Type,x:F32,l0:F32,l1:F32,v1:S.Tree<U32>,d0:F32,d1:F32,
    result:Owner & Result<&2,&2,String,F32>,
    read:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{v0}}: interpolated(Owner,x,l0,l1,v0,d0,d1,read(v1,owner))

def segment(-Owner:Type,owner:Owner,x:F32,left:Maybe<&2,S.Point<U32>>,right:Maybe<&2,S.Point<U32>>,
    read_left:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>,
    read_right:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match left right:
    case Some{S.Point{l0,v0,d0}} Some{S.Point{l1,v1,d1}}:
      segment_left(Owner,x,l0,l1,v1,d0,d1,read_left(v0,owner),read_right)
    case _ _: (owner,Fail{"density spline selected point is absent"})

def selection(-Owner:Type,owner:Owner,+x:F32,+points:List<&2,S.Point<U32>>,selected:Result<&2,&2,String,S.Selection>,
    read_one:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>,
    read_left:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>,
    read_right:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match selected:
    case Fail{message}: (owner,Fail{message})
    case Done{S.Endpoint{index}}: endpoint(Owner,owner,x,S.point_at(U32,points,index),read_one)
    case Done{S.Segment{left,right}}:
      segment(Owner,owner,x,S.point_at(U32,points,left),S.point_at(U32,points,right),read_left,read_right)

def coordinate(-Owner:Type,+points:List<&2,S.Point<U32>>,result:Owner & Result<&2,&2,String,F32>,
    read_one:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>,
    read_left:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>,
    read_right:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{+x}}: selection(Owner,owner,x,points,S.select(U32,points,x),read_one,read_left,read_right)

# Callback services receive and return the complete affine owner explicitly.
# The production caller supplies decreasing-depth density/spline traversal.
# Only the selected one or two child splines are evaluated, in vanilla order.
def step(-Owner:Type,tree:S.Tree<U32>,owner:Owner,
    read_coordinate:Owner -> U32 -> Owner & Result<&2,&2,String,F32>,
    read_one:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>,
    read_left:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>,
    read_right:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match tree:
    case S.Constant{value}: (owner,Done{value})
    case S.Multi{index,points}: coordinate(Owner,points,read_coordinate(owner,index),read_one,read_left,read_right)
