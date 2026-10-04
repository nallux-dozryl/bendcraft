# Retained ordinary-checking contract with an unresolved independent-kernel
# normalization obligation. The26-root historical verdict reported out of fuel
# for this statement; it is intentionally outside the admitted root aggregation.
import Base
import ./superflat_population.bend as P
import ./core.bend as C
import ./section_map.bend as SM
import ./section.bend as Section
import ./schedule.bend as Q

def existing_origin(section:Section.Section) -> C.World:
  C.World{0n,0n,True{},True{},0n,2,
    SM.set(SM.EmptySections{},C.section_key(C.Position{"minecraft:overworld",0,0,0}),section),[],[]}

# The section is arbitrary: this includes every edit and every cell in its
# actual owned array. The real production population path never overwrites it.
law existing_section_population_is_identity:
  for section:Section.Section
  for stamp:Q.Stamp
  {P.populate(P.Flat{"minecraft:overworld",4294967232,384,0,[]},P.Region{0,0,1,1,0,1},stamp,P.default_budget(),existing_origin(section)) ==
    (existing_origin(section),Done{P.Receipt{1n,0n,1n}}) : C.World & Result<&2,&2,String,P.Receipt>}

