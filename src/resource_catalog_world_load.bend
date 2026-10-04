import Base
import ./resource_catalog_world.bend as W
import ./resource_block_catalog.bend as C
import ./resource_block_catalog_load.bend as L
import ./registry.bend as G
import ./block_resources.bend as BR

# Resource loading retains the complete registry owner and the blockstate
# catalog. Texture slots are those of this catalog's loaded material context.
def texture_count(catalog:C.Catalog) -> U32:
  C.Catalog{identity,entries,BR.Catalog{roots,source,models,sprites,context,usage}} = catalog
  U32.from_nat(List.length(&2,BR.SpriteInfo,sprites))

def wrapped(value:G.Registry & Result<&2,&1,C.Error,L.Loaded>) -> G.Registry & Result<&2,&1,C.Error,W.Assets>:
  (registry,status) = value
  match status:
    case Fail{error}: (registry,Fail{error})
    case Done{L.Loaded{resources,+catalog}}:
      (registry,Done{W.Assets{resources,catalog,texture_count(catalog)}})

def load(jar:String,registry:G.Registry,requests:List<&2,C.Request>,policy:BR.Policy,limits:C.Limits) -> IO(G.Registry & Result<&2,&1,C.Error,W.Assets>):
  do IO<G.Registry & Result<&2,&1,C.Error,W.Assets>>:
    value:G.Registry & Result<&2,&1,C.Error,L.Loaded> <- L.load(jar,registry,requests,policy,limits)
    return wrapped(value)

law load_failure_preserves_registry_and_error:
  for registry:G.Registry
  for +error:C.Error
  {wrapped((registry,Fail{error})) == (registry,Fail{error}) : G.Registry & Result<&2,&1,C.Error,W.Assets>}
def load_failure_preserves_registry_and_error(registry,error):
  {==}
