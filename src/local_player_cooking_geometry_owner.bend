import Base
import ./slab_collision.bend as Slab
import ./local_collision_world.bend as Collision

# The live geometry service retains its sole catalog array owner. Environment
# policies remain explicit caller admissions alongside that actual catalog.
type Owner is Type:
  Owner{catalog:Slab.Catalog,environment:Collision.Environment}
