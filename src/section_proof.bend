import Base
import ./section.bend as Storage
import ./section_laws.bend as Laws

def Laws.get_index_rejects(section, index, invalid):
  match section:
    case Storage.Section{a}:
      %Equal.sym(Bool, U32.is_lt(index, 4096), False{}, invalid) : {Storage.Section.get_index.fin(Storage.Section{a}, index, _) == (Storage.Section{a}, Fail{Storage.BadIndex{index}}) : Storage.Section & Result<&2, &2, Storage.Section.Error, U32>}
      {==}

def Laws.set_index_rejects(section, index, state, invalid):
  match section:
    case Storage.Section{a}:
      %Equal.sym(Bool, U32.is_lt(index, 4096), False{}, invalid) : {Storage.Section.set_index.fin(Storage.Section{a}, index, state, _) == (Storage.Section{a}, Fail{Storage.BadIndex{index}}) : Storage.Section & Result<&2, &2, Storage.Section.Error, Unit>}
      {==}

def Laws.local_index_rejects(x, y, z, invalid):
  %Equal.sym(Bool, Storage.Section.local_valid(x, y, z), False{}, invalid) : {Storage.Section.local_index.fin(x, y, z, _) == Fail{Storage.BadLocal{x, y, z}} : Result<&2, &2, Storage.Section.Error, U32>}
  {==}

def Laws.local_index_accepts(x, y, z, valid):
  %Equal.sym(Bool, Storage.Section.local_valid(x, y, z), True{}, valid) : {Storage.Section.local_index.fin(x, y, z, _) == Done{Storage.Section.index_value(x, y, z)} : Result<&2, &2, Storage.Section.Error, U32>}
  {==}

def Laws.compose_rejects_section(section, local, invalid):
  %Equal.sym(Bool, Storage.Coord.section_valid(section), False{}, invalid) : {Storage.Coord.compose.section(section, local, _) == Fail{Storage.BadSection{section}} : Result<&2, &2, Storage.Section.Error, U32>}
  {==}

def Laws.origin_read_after_write(initial, state):
  {==}

def Laws.last_read_after_write(initial, state):
  {==}

def Laws.origin_write_preserves_last(initial, state):
  {==}

def Laws.last_write_preserves_origin(initial, state):
  {==}

def Laws.axis_index_order():
  {==}

def Laws.negative_boundary_split():
  {==}

def Laws.signed_minimum_roundtrip():
  {==}

def Laws.signed_maximum_roundtrip():
  {==}

def Laws.get_local_rejects(section, x, y, z, invalid):
  match section:
    case Storage.Section{a}:
      %Equal.sym(Bool, Storage.Section.local_valid(x, y, z), False{}, invalid) : {Storage.Section.get.checked(Storage.Section{a}, Storage.Section.local_index.fin(x, y, z, _)) == (Storage.Section{a}, Fail{Storage.BadLocal{x, y, z}}) : Storage.Section & Result<&2, &2, Storage.Section.Error, U32>}
      {==}

def Laws.set_local_rejects(section, x, y, z, state, invalid):
  match section:
    case Storage.Section{a}:
      %Equal.sym(Bool, Storage.Section.local_valid(x, y, z), False{}, invalid) : {Storage.Section.set.checked(Storage.Section{a}, Storage.Section.local_index.fin(x, y, z, _), state) == (Storage.Section{a}, Fail{Storage.BadLocal{x, y, z}}) : Storage.Section & Result<&2, &2, Storage.Section.Error, Unit>}
      {==}

def Laws.compose_rejects_remainder(section, local, valid_section, invalid_local):
  %Equal.sym(Bool, Storage.Coord.section_valid(section), True{}, valid_section) : {Storage.Coord.compose.section(section, local, _) == Fail{Storage.BadRemainder{local}} : Result<&2, &2, Storage.Section.Error, U32>}
  %Equal.sym(Bool, U32.is_lt(local, 16), False{}, invalid_local) : {Storage.Coord.compose.local(section, local, _) == Fail{Storage.BadRemainder{local}} : Result<&2, &2, Storage.Section.Error, U32>}
  {==}

def Laws.clone_isolation(initial, state):
  {==}
