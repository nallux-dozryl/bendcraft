import Base
import ./random.bend as R
import ./locomotion.bend as L
import ./vanilla_lightmap_model.bend as M
import ./vanilla_lightmap.bend as V
import ./vanilla_lightmap_eval.bend as E

law fresh_texture_is_actual_white_and_does_not_draw_random:
  for random:R.Source
  {V.fresh(random) == V.State{random,0.0,False{},M.initial_uniforms(),M.InitialWhite{}} : V.State}
def fresh_texture_is_actual_white_and_does_not_draw_random(random): {==}
law rejected_context_recovers_complete_renderer_and_table_owners:
  for state:V.State
  for tables:L.Tables
  for input:M.Inputs
  {V.ready(False{},state,tables,input) == (state,(tables,Fail{M.Refused{"lightmap: nonfinite context"}})) : V.State & (L.Tables & Result<&2,&2,M.Error,M.Publication>)}
def rejected_context_recovers_complete_renderer_and_table_owners(state,tables,input): {==}
law rejected_evaluated_uniforms_do_not_clear_dirty_or_replace_texture:
  for state:V.State
  for tables:L.Tables
  for uniforms:M.Uniforms
  {V.prepared(state,tables,uniforms,False{}) == (state,(tables,Fail{M.Refused{"lightmap: nonfinite evaluated uniforms"}})) : V.State & (L.Tables & Result<&2,&2,M.Error,M.Publication>)}
def rejected_evaluated_uniforms_do_not_clear_dirty_or_replace_texture(state,tables,uniforms): {==}
law clean_extract_does_not_draw_rng_read_context_or_change_pixels:
  for random:R.Source
  for flicker:F32
  for uniforms:M.Uniforms
  for +texture:M.Texture
  for tables:L.Tables
  for presence:M.Presence
  {V.extract(presence,V.State{random,flicker,False{},uniforms,texture},tables) == (V.State{random,flicker,False{},uniforms,texture},(tables,Done{M.Publication{False{},texture}})) : V.State & (L.Tables & Result<&2,&2,M.Error,M.Publication>)}
def clean_extract_does_not_draw_rng_read_context_or_change_pixels(random,flicker,uniforms,texture,tables,presence): {==}
law absent_dirty_extract_retains_rng_flicker_dirty_and_previous_uniforms:
  for random:R.Source
  for flicker:F32
  for +uniforms:M.Uniforms
  for texture:M.Texture
  for tables:L.Tables
  {V.extract(M.Absent{},V.State{random,flicker,True{},uniforms,texture},tables) == (V.State{random,flicker,True{},uniforms,M.Evaluated{uniforms}},(tables,Done{M.Publication{True{},M.Evaluated{uniforms}}})) : V.State & (L.Tables & Result<&2,&2,M.Error,M.Publication>)}
def absent_dirty_extract_retains_rng_flicker_dirty_and_previous_uniforms(random,flicker,uniforms,texture,tables): {==}
law successful_uniform_commit_preserves_rng_and_clears_dirty:
  for random:R.Source
  for flicker:F32
  for dirty:Bool
  for old:M.Uniforms
  for texture:M.Texture
  for +next:M.Uniforms
  for tables:L.Tables
  {V.prepared(V.State{random,flicker,dirty,old,texture},tables,next,True{}) == (V.State{random,flicker,False{},next,M.Evaluated{next}},(tables,Done{M.Publication{True{},M.Evaluated{next}}})) : V.State & (L.Tables & Result<&2,&2,M.Error,M.Publication>)}
def successful_uniform_commit_preserves_rng_and_clears_dirty(random,flicker,dirty,old,texture,next,tables): {==}
law hidden_flash_cannot_modify_sky_factor:
  for flash:Maybe<&2,M.Interpolation>
  for fog:Bool
  for partial:F32
  {V.flash(flash,fog,partial,True{}) == 0.0 : F32}
def hidden_flash_cannot_modify_sky_factor(flash,fog,partial): {==}
law missing_flash_has_no_sky_addition:
  for fog:Bool
  for partial:F32
  {V.visible_flash(None{},fog,partial) == 0.0 : F32}
def missing_flash_has_no_sky_addition(fog,partial): {==}
law long_or_infinite_night_vision_returns_one_without_table_read:
  for tables:L.Tables
  for ticks:U32
  for partial:F32
  {V.night_ready(tables,ticks,partial,False{}) == (tables,1.0) : L.Tables & F32}
def long_or_infinite_night_vision_returns_one_without_table_read(tables,ticks,partial): {==}
law invalid_pixel_coordinates_or_uniforms_cannot_publish_rgb:
  for uniforms:M.Uniforms
  for block:U32
  for sky:U32
  {E.pixel_gate(False{},uniforms,block,sky) == Fail{M.Refused{"lightmap: nonfinite uniforms or coordinate outside 0..15"}} : Result<&2,&2,M.Error,M.Color>}
def invalid_pixel_coordinates_or_uniforms_cannot_publish_rgb(uniforms,block,sky): {==}
law black_raw_shader_is_not_claimed_finite:
  for uniforms:M.Uniforms
  for color:M.Color
  {E.nonblack(False{},uniforms,color) == Fail{M.Refused{"lightmap: shader notGamma has undefined zero division at black"}} : Result<&2,&2,M.Error,M.Color>}
def black_raw_shader_is_not_claimed_finite(uniforms,color): {==}
law observed_black_storage_is_opaque_black:
  for uniforms:M.Uniforms
  for color:M.Color
  {E.storage_color(True{},uniforms,color) == Done{4278190080} : Result<&2,&2,M.Error,U32>}
def observed_black_storage_is_opaque_black(uniforms,color): {==}
law nonfinite_shader_output_is_never_integer_quantized:
  for color:M.Color
  {E.storage_gamma(color,False{}) == Fail{M.Refused{"lightmap: nonfinite shader result cannot be quantized"}} : Result<&2,&2,M.Error,U32>}
def nonfinite_shader_output_is_never_integer_quantized(color): {==}
