import Base
import ./worldgen_overworld.bend as O
import ./worldgen_overworld_laws.bend as Laws

# Every actual column request retains the complete sampler, including its
# prepared plan and all affine noise arrays, through sampling or refusal.
law every_column_read_retains_complete_sampler:
  for sampler:O.Sampler
  for +request:O.ColumnRequest
  for budget:U32
  {Laws.column_owner(O.sample_column(sampler,request,budget)) == sampler : O.Sampler}
