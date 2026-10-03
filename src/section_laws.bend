# Implementation laws only: no behavioral parity claim about Java 26.3.
import Base
import ./section.bend as Storage

# The returned owner is unchanged on an invalid public index.
law get_index_rejects:
  for section: Storage.Section
  for +index: U32
  for invalid: {U32.is_lt(index, 4096) == False{} : Bool}
  {Storage.Section.get_index(section, index) == (section, Fail{Storage.BadIndex{index}}) : Storage.Section & Result<&2, &2, Storage.Section.Error, U32>}

law set_index_rejects:
  for section: Storage.Section
  for +index: U32
  for state: U32
  for invalid: {U32.is_lt(index, 4096) == False{} : Bool}
  {Storage.Section.set_index(section, index, state) == (section, Fail{Storage.BadIndex{index}}) : Storage.Section & Result<&2, &2, Storage.Section.Error, Unit>}

law local_index_rejects:
  for +x: U32
  for +y: U32
  for +z: U32
  for invalid: {Storage.Section.local_valid(x, y, z) == False{} : Bool}
  {Storage.Section.local_index(x, y, z) == Fail{Storage.BadLocal{x, y, z}} : Result<&2, &2, Storage.Section.Error, U32>}

law local_index_accepts:
  for +x: U32
  for +y: U32
  for +z: U32
  for valid: {Storage.Section.local_valid(x, y, z) == True{} : Bool}
  {Storage.Section.local_index(x, y, z) == Done{Storage.Section.index_value(x, y, z)} : Result<&2, &2, Storage.Section.Error, U32>}

law compose_rejects_section:
  for +section: U32
  for local: U32
  for invalid: {Storage.Coord.section_valid(section) == False{} : Bool}
  {Storage.Coord.compose(section, local) == Fail{Storage.BadSection{section}} : Result<&2, &2, Storage.Section.Error, U32>}

# Observation helpers consume the owner instead of illegally copying it.
def section_value(read: Storage.Section & Result<&2, &2, Storage.Section.Error, U32>) -> Result<&2, &2, Storage.Section.Error, U32>:
  (section, result) = read
  result

def updated(write: Storage.Section & Result<&2, &2, Storage.Section.Error, Unit>) -> Storage.Section:
  (section, result) = write
  section

# Universal scalar inputs through the actual constructor and checked APIs.
law origin_read_after_write:
  for initial: U32
  for +state: U32
  {section_value(Storage.Section.get_index(updated(Storage.Section.set_index(Storage.Section.new(initial), 0, state)), 0)) == Done{state} : Result<&2, &2, Storage.Section.Error, U32>}

law last_read_after_write:
  for initial: U32
  for +state: U32
  {section_value(Storage.Section.get_index(updated(Storage.Section.set_index(Storage.Section.new(initial), 4095, state)), 4095)) == Done{state} : Result<&2, &2, Storage.Section.Error, U32>}

law origin_write_preserves_last:
  for +initial: U32
  for state: U32
  {section_value(Storage.Section.get_index(updated(Storage.Section.set_index(Storage.Section.new(initial), 0, state)), 4095)) == Done{initial} : Result<&2, &2, Storage.Section.Error, U32>}

law last_write_preserves_origin:
  for +initial: U32
  for state: U32
  {section_value(Storage.Section.get_index(updated(Storage.Section.set_index(Storage.Section.new(initial), 4095, state)), 0)) == Done{initial} : Result<&2, &2, Storage.Section.Error, U32>}

law axis_index_order:
  {Storage.Section.local_index(15, 1, 2) == Done{303} : Result<&2, &2, Storage.Section.Error, U32>}

law negative_boundary_split:
  {Storage.Coord.split(4294967279) == (4294967294, 15) : U32 & U32}

law signed_minimum_roundtrip:
  {Storage.Coord.compose(Storage.Coord.section(2147483648), Storage.Coord.local(2147483648)) == Done{2147483648} : Result<&2, &2, Storage.Section.Error, U32>}

law signed_maximum_roundtrip:
  {Storage.Coord.compose(Storage.Coord.section(2147483647), Storage.Coord.local(2147483647)) == Done{2147483647} : Result<&2, &2, Storage.Section.Error, U32>}

law get_local_rejects:
  for section: Storage.Section
  for +x: U32
  for +y: U32
  for +z: U32
  for invalid: {Storage.Section.local_valid(x, y, z) == False{} : Bool}
  {Storage.Section.get(section, x, y, z) == (section, Fail{Storage.BadLocal{x, y, z}}) : Storage.Section & Result<&2, &2, Storage.Section.Error, U32>}

law set_local_rejects:
  for section: Storage.Section
  for +x: U32
  for +y: U32
  for +z: U32
  for state: U32
  for invalid: {Storage.Section.local_valid(x, y, z) == False{} : Bool}
  {Storage.Section.set(section, x, y, z, state) == (section, Fail{Storage.BadLocal{x, y, z}}) : Storage.Section & Result<&2, &2, Storage.Section.Error, Unit>}

law compose_rejects_remainder:
  for +section: U32
  for +local: U32
  for valid_section: {Storage.Coord.section_valid(section) == True{} : Bool}
  for invalid_local: {U32.is_lt(local, 16) == False{} : Bool}
  {Storage.Coord.compose(section, local) == Fail{Storage.BadRemainder{local}} : Result<&2, &2, Storage.Section.Error, U32>}

# Observe the unmodified owner after explicitly updating/dropping its clone.
def clone_survivor(copies: Storage.Section & Storage.Section, state: U32) -> Result<&2, &2, Storage.Section.Error, U32>:
  (first, second) = copies
  _ = Storage.Section.set_index(first, 0, state)
  section_value(Storage.Section.get_index(second, 0))

law clone_isolation:
  for +initial: U32
  for state: U32
  {clone_survivor(Storage.Section.clone(Storage.Section.new(initial)), state) == Done{initial} : Result<&2, &2, Storage.Section.Error, U32>}
