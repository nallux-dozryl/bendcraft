import Base
import ./generic_resource_world_sample_resource_initial_transport.bend as Initial
import ./generic_resource_world_sample_resources.bend as Resources
import ./generic_resource_world_sample_resource_policy.bend as Policy
import ./generic_resource_world_sample_presenter.bend as Draw
import ./registry.bend as Registry
import ./resource_block_catalog_profile.bend as Profile
import ./resource_block_catalog.bend as Catalog
import ./resource_catalog_world.bend as CW

# The actual initial-load result mapper preserves the full returned Registry.
# These contracts cover pure construction, not scheduling, IO or channel disposal.
law refused_initial_catalog_retains_the_entire_returned_registry:
  for jar:String
  for registry:Registry.Registry
  for +error:Catalog.Error
  {Initial.catalog_loaded(jar,(registry,Fail{error})) ==
    Initial.Failed{Some{registry},"resource catalog: " ++ Draw.error_text(error)} : Initial.Outcome}

law admitted_initial_catalog_installs_the_actual_registry_and_asset_owner:
  for +jar:String
  for registry:Registry.Registry
  for assets:CW.Assets
  {Initial.catalog_loaded(jar,(registry,Done{assets})) ==
    Initial.Loaded{Resources.installed(registry,Profile.static_requests(),assets,Policy.config(jar))} : Initial.Outcome}
