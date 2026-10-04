import Base
import ./superflat_complete_section_pending_laws.bend as Pending
import ./superflat_section_shape_laws.bend as Laws
import ./superflat_section_shape_proof.bend as ShapeProof
import ./section.bend as S
import ./superflat_population.bend as P

# Ordinary checking passes these unchanged bodies. The bounded kernel rejects
# complete_section_has_perfect_shape with out of fuel; neither is certified.
def Pending.complete_section_has_perfect_shape(flat,origin):
  match flat:
    case P.Flat{dimension,min_y,height,+air,layers}:
      Equal.trans(Laws.Shape,
        Laws.section_shape(P.complete_section(P.Flat{dimension,min_y,height,air,layers},origin)),
        Laws.section_shape(S.Section.new(air)),Laws.perfect(12n),
        Laws.fill_preserves_complete_shape(4096n,0,origin,P.Flat{dimension,min_y,height,air,layers},S.Section.new(air)),
        Laws.section_new_has_perfect_shape(air))

def Pending.complete_section_has_4096_cells(flat,origin):
  %Equal.sym(Laws.Shape,Laws.section_shape(P.complete_section(flat,origin)),Laws.perfect(12n),
    Pending.complete_section_has_perfect_shape(flat,origin)) :
    {Laws.leaves(_) == 4096n : Nat}
  Equal.trans(Nat,Laws.leaves(Laws.perfect(12n)),Nat.pow(2n,12n),4096n,
    Laws.perfect_shape_capacity(12n),{==})
