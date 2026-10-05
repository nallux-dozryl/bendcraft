import Base
import ./vanilla_block_lighting_model.bend as M
import ./block_model.bend as B

# Actual initialized26.3 AdjacencyInfo and AmbientVertexRemap constants.
# Provenance: reference/vanilla_block_lighting.json; no recipe/state ID table.
def adjacency(direction:B.Direction) -> M.Adjacency:
  match direction:
    case B.Down{}: M.Adjacency{B.West{},B.East{},B.North{},B.South{},[10, 3, 10, 9, 4, 9, 4, 3],[10, 2, 10, 8, 4, 8, 4, 2],[11, 2, 11, 8, 5, 8, 5, 2],[11, 3, 11, 9, 5, 9, 5, 3],0,1,2,3,True{}}
    case B.Up{}: M.Adjacency{B.East{},B.West{},B.North{},B.South{},[5, 3, 5, 9, 11, 9, 11, 3],[5, 2, 5, 8, 11, 8, 11, 2],[4, 2, 4, 8, 10, 8, 10, 2],[4, 3, 4, 9, 10, 9, 10, 3],2,3,0,1,True{}}
    case B.North{}: M.Adjacency{B.Up{},B.Down{},B.East{},B.West{},[1, 10, 1, 4, 7, 4, 7, 10],[1, 11, 1, 5, 7, 5, 7, 11],[0, 11, 0, 5, 6, 5, 6, 11],[0, 10, 0, 4, 6, 4, 6, 10],3,0,1,2,True{}}
    case B.South{}: M.Adjacency{B.West{},B.East{},B.Down{},B.Up{},[1, 10, 7, 10, 7, 4, 1, 4],[0, 10, 6, 10, 6, 4, 0, 4],[0, 11, 6, 11, 6, 5, 0, 5],[1, 11, 7, 11, 7, 5, 1, 5],0,1,2,3,True{}}
    case B.West{}: M.Adjacency{B.Up{},B.Down{},B.North{},B.South{},[1, 3, 1, 9, 7, 9, 7, 3],[1, 2, 1, 8, 7, 8, 7, 2],[0, 2, 0, 8, 6, 8, 6, 2],[0, 3, 0, 9, 6, 9, 6, 3],3,0,1,2,True{}}
    case B.East{}: M.Adjacency{B.Down{},B.Up{},B.North{},B.South{},[6, 3, 6, 9, 0, 9, 0, 3],[6, 2, 6, 8, 0, 8, 0, 2],[7, 2, 7, 8, 1, 8, 1, 2],[7, 3, 7, 9, 1, 9, 1, 3],1,2,3,0,True{}}
