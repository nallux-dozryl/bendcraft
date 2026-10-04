import Base
import ./mesh_render.bend as M
import ./mesh_render_reader_laws.bend as L

def L.chosen_fragment_preserves_conditional(first,candidate,best):
  match first candidate best:
    case True{} M.Fragment{distance,order,index,color} M.Fragment{other,other_order,other_index,other_color}: {==}
    case False{} M.Fragment{distance,order,index,color} M.Fragment{other,other_order,other_index,other_color}: {==}

def L.chosen_hit_preserves_conditional(first,distance,u,v,other,other_u,other_v):
  match first:
    case True{}: {==}
    case False{}: {==}

def L.finish_quads_preserves_complete_image(quads,image):
  match quads:
    case Nil{}: {==}
    case head <> tail: L.finish_quads_preserves_complete_image(tail,image)

def L.finish_tree_preserves_complete_image(tree,image):
  match tree:
    case M.Empty{}: {==}
    case M.Flat{quads}: L.finish_quads_preserves_complete_image(quads,image)
    case M.Leaf{bounds,quads}: L.finish_quads_preserves_complete_image(quads,image)
    case M.Branch{bounds,+left,+right}:
      Equal.trans(Image,M.finish_tree(right,M.finish_tree(left,image)),M.finish_tree(left,image),image,
        L.finish_tree_preserves_complete_image(right,M.finish_tree(left,image)),
        L.finish_tree_preserves_complete_image(left,image))
