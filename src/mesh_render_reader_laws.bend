import Base
import ./mesh_render.bend as M
import ./png.bend as P

# Compare the actual scalar selector with the established conditional interface.
law chosen_fragment_preserves_conditional:
  for +first:Bool
  for +candidate:M.Fragment
  for +best:M.Fragment
  {M.chosen_fragment(first,candidate,best) == P.choose(M.Fragment,candidate,best,first) : M.Fragment}

law chosen_hit_preserves_conditional:
  for +first:Bool
  for +distance:F32
  for +u:F32
  for +v:F32
  for +other:F32
  for +other_u:F32
  for +other_v:F32
  {M.chosen_hit(first,distance,u,v,other,other_u,other_v) == P.choose(Maybe<&2,M.Hit>,Some{M.Hit{distance,u,v}},Some{M.Hit{other,other_u,other_v}},first) : Maybe<&2,M.Hit>}

# The production last-owner walkers preserve the entire drawn Image.
law finish_quads_preserves_complete_image:
  for quads:List<&2,M.Prepared>
  for +image:Image
  {M.finish_quads(quads,image) == image : Image}

law finish_tree_preserves_complete_image:
  for tree:M.Spatial
  for +image:Image
  {M.finish_tree(tree,image) == image : Image}
