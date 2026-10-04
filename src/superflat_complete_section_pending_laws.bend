import Base
import ./superflat_section_shape_laws.bend as Shape
import ./superflat_population.bend as P

# These unchanged completion corollaries are pending kernel certification.
# The reusable generic Shape laws are certified independently.
law complete_section_has_perfect_shape:
  for +flat:P.Flat
  for +origin:U32
  {Shape.section_shape(P.complete_section(flat,origin)) == Shape.perfect(12n) : Shape.Shape}

law complete_section_has_4096_cells:
  for +flat:P.Flat
  for +origin:U32
  {Shape.leaves(Shape.section_shape(P.complete_section(flat,origin))) == 4096n : Nat}
