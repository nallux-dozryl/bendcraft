import Base
import ../src/section.bend as Storage

# Expected indices come from traversal order; inverse coordinates use integer
# division/modulo rather than the implementation's masks and shifts.
def fail_unless(ok: Bool) -> U32:
  match ok:
    case True{}:
      0
    case False{}:
      1

def expect_index(result: Result<&2, &2, Storage.Section.Error, U32>, expected: U32) -> U32:
  match result:
    case Fail{error}:
      1
    case Done{actual}:
      fail_unless(U32.is_eq(actual, expected))

def expect_local(result: Result<&2, &2, Storage.Section.Error, Storage.Section.Local>, x: U32, y: U32, z: U32) -> U32:
  match result:
    case Fail{error}:
      1
    case Done{Storage.Local{a, b, c}}:
      fail_unless(Bool.and(U32.is_eq(a, x), Bool.and(U32.is_eq(b, y), U32.is_eq(c, z))))

def local_rows(fuel: Nat, +index: U32, failures: U32) -> U32:
  match fuel:
    case 0n:
      failures
    case 1n+p:
      +x = (index % 16 : U32)
      +y = (index / 256 : U32)
      +z = ((index / 16) % 16 : U32)
      local_rows(p, (index + 1 : U32), (failures + expect_index(Storage.Section.local_index(x, y, z), index) + expect_local(Storage.Section.index_local(index), x, y, z) : U32))

def expect_read(read: Storage.Section & Result<&2, &2, Storage.Section.Error, U32>, expected: U32) -> Storage.Section & U32:
  (section, result) = read
  (section, expect_index(result, expected))

def expect_write(write: Storage.Section & Result<&2, &2, Storage.Section.Error, Unit>) -> Storage.Section & U32:
  (section, result) = write
  match result:
    case Fail{error}:
      (section, 1)
    case Done{Unit{}}:
      (section, 0)

def state_at(index: U32) -> U32:
  (index * 104729 + 2147483648 : U32)

def scan(fuel: Nat, +index: U32, failures: U32, read: Storage.Section & U32) -> Storage.Section & U32:
  match fuel:
    case 0n:
      (section, bad) = read
      (section, (failures + bad : U32))
    case 1n+p:
      (section, bad) = read
      scan(p, (index + 1 : U32), (failures + bad : U32), expect_read(Storage.Section.get_index(section, index), 3735928559))

# Compare the adjacent pair member with a separately determined expectation.
def neighbor_expected(index: U32, odd: Bool) -> U32:
  match odd:
    case False{}:
      3735928559
    case True{}:
      state_at((index - 1 : U32))

def fill.neighbor(failures: U32, read: Storage.Section & U32) -> Storage.Section & U32:
  (section, bad) = read
  (section, (failures + bad : U32))

def fill.read(+index: U32, failures: U32, read: Storage.Section & U32) -> Storage.Section & U32:
  (section, bad) = read
  fill.neighbor((failures + bad : U32), expect_read(Storage.Section.get_index(section, U32.xor(index, 1)), neighbor_expected(index, U32.is_ne((index % 2 : U32), 0))))

def fill.written(+index: U32, write: Storage.Section & U32) -> Storage.Section & U32:
  (section, bad) = write
  fill.read(index, bad, expect_read(Storage.Section.get_index(section, index), state_at(index)))

def fill(fuel: Nat, +index: U32, failures: U32, previous: Storage.Section & U32) -> Storage.Section & U32:
  match fuel:
    case 0n:
      (section, bad) = previous
      (section, (failures + bad : U32))
    case 1n+p:
      (section, bad) = previous
      fill(p, (index + 1 : U32), (failures + bad : U32), fill.written(index, expect_write(Storage.Section.set(section, (index % 16 : U32), (index / 256 : U32), ((index / 16) % 16 : U32), state_at(index)))))

def verify.read(+index: U32, read: Storage.Section & U32) -> Storage.Section & U32:
  (section, bad) = read
  fill.neighbor(bad, expect_read(Storage.Section.get(section, (index % 16 : U32), (index / 256 : U32), ((index / 16) % 16 : U32)), state_at(index)))

def verify(fuel: Nat, +index: U32, failures: U32, previous: Storage.Section & U32) -> Storage.Section & U32:
  match fuel:
    case 0n:
      (section, bad) = previous
      (section, (failures + bad : U32))
    case 1n+p:
      (section, bad) = previous
      verify(p, (index + 1 : U32), (failures + bad : U32), verify.read(index, expect_read(Storage.Section.get_index(section, index), state_at(index))))

# Fail constructors and their payloads are checked, then the owner is re-read.
def expect_bad_index_read(read: Storage.Section & Result<&2, &2, Storage.Section.Error, U32>, +index: U32) -> Storage.Section & U32:
  (section, result) = read
  match result:
    case Fail{Storage.BadIndex{actual}}:
      (section, fail_unless(U32.is_eq(actual, index)))
    case _:
      (section, 1)

def expect_bad_index_write(write: Storage.Section & Result<&2, &2, Storage.Section.Error, Unit>, +index: U32) -> Storage.Section & U32:
  (section, result) = write
  match result:
    case Fail{Storage.BadIndex{actual}}:
      (section, fail_unless(U32.is_eq(actual, index)))
    case _:
      (section, 1)

def bad_indices.read(+index: U32, read: Storage.Section & U32) -> Storage.Section & U32:
  (section, bad) = read
  fill.neighbor(bad, expect_bad_index_write(Storage.Section.set_index(section, index, 99), index))

def bad_indices(indices: List<&2, U32>, failures: U32, previous: Storage.Section & U32) -> Storage.Section & U32:
  match indices:
    case Nil{}:
      (section, bad) = previous
      (section, (failures + bad : U32))
    case +index <> rest:
      (section, bad) = previous
      bad_indices(rest, (failures + bad : U32), bad_indices.read(index, expect_bad_index_read(Storage.Section.get_index(section, index), index)))

def reject_index_local(index: U32, result: Result<&2, &2, Storage.Section.Error, Storage.Section.Local>) -> U32:
  match result:
    case Fail{Storage.BadIndex{actual}}:
      fail_unless(U32.is_eq(actual, index))
    case _:
      1

def bad_local_equal(error: Storage.Section.Error, x: U32, y: U32, z: U32) -> U32:
  match error:
    case Storage.BadLocal{a, b, c}:
      fail_unless(Bool.and(U32.is_eq(a, x), Bool.and(U32.is_eq(b, y), U32.is_eq(c, z))))
    case _:
      1

def expect_bad_local_read(read: Storage.Section & Result<&2, &2, Storage.Section.Error, U32>, x: U32, y: U32, z: U32) -> Storage.Section & U32:
  (section, result) = read
  match result:
    case Fail{error}:
      (section, bad_local_equal(error, x, y, z))
    case _:
      (section, 1)

def expect_bad_local_write(write: Storage.Section & Result<&2, &2, Storage.Section.Error, Unit>, x: U32, y: U32, z: U32) -> Storage.Section & U32:
  (section, result) = write
  match result:
    case Fail{error}:
      (section, bad_local_equal(error, x, y, z))
    case _:
      (section, 1)

def bad_locals.read(+x: U32, +y: U32, +z: U32, read: Storage.Section & U32) -> Storage.Section & U32:
  (section, bad) = read
  fill.neighbor(bad, expect_bad_local_write(Storage.Section.set(section, x, y, z, 99), x, y, z))

def bad_locals(locals: List<&2, Storage.Section.Local>, failures: U32, previous: Storage.Section & U32) -> Storage.Section & U32:
  match locals:
    case Nil{}:
      (section, bad) = previous
      (section, (failures + bad : U32))
    case Storage.Local{+x, +y, +z} <> rest:
      (section, bad) = previous
      bad_locals(rest, (failures + bad : U32), bad_locals.read(x, y, z, expect_bad_local_read(Storage.Section.get(section, x, y, z), x, y, z)))

type WorldFixture is Data:
  WorldFixture{world: U32, section: U32, local: U32}

def world_row(+world: U32, +section: U32, +local: U32, actual: U32 & U32) -> U32:
  (q, r) = actual
  (fail_unless(Bool.and(U32.is_eq(q, section), U32.is_eq(r, local))) + expect_index(Storage.Coord.compose(section, local), world) : U32)

def worlds(fixtures: List<&2, WorldFixture>, failures: U32) -> U32:
  match fixtures:
    case Nil{}:
      failures
    case WorldFixture{+world, section, local} <> rest:
      worlds(rest, (failures + world_row(world, section, local, Storage.Coord.split(world)) : U32))

# Filled snapshot expected values are checked against monotonically counted IDs.
def snapshot_rows(values: List<&2, U32>, +index: U32, failures: U32) -> U32:
  match values:
    case Nil{}:
      (failures + fail_unless(U32.is_eq(index, 4096)) : U32)
    case state <> rest:
      snapshot_rows(rest, (index + 1 : U32), (failures + fail_unless(U32.is_eq(state, state_at(index))) : U32))

# Clone retains independent ownership, and later writes cannot alter a snapshot.
def clone.original(saved: List<&2, U32>, failures: U32, read: Storage.Section & U32) -> U32:
  (first, bad) = read
  (failures + bad + snapshot_rows(saved, 0, 0) : U32)

def clone.second_written(first: Storage.Section, saved: List<&2, U32>, failures: U32, write: Storage.Section & U32) -> U32:
  (second, bad) = write
  clone.original(saved, (failures + bad : U32), expect_read(Storage.Section.get_index(first, 4095), state_at(4095)))

def clone.second(first: Storage.Section, saved: List<&2, U32>, failures: U32, read: Storage.Section & U32) -> U32:
  (second, bad) = read
  clone.second_written(first, saved, (failures + bad : U32), expect_write(Storage.Section.set_index(second, 4095, 31)))

def clone.first(second: Storage.Section, saved: List<&2, U32>, failures: U32, read: Storage.Section & U32) -> U32:
  (first, bad) = read
  clone.second(first, saved, (failures + bad : U32), expect_read(Storage.Section.get_index(second, 0), 2147483648))

def clone.written(second: Storage.Section, saved: List<&2, U32>, failures: U32, write: Storage.Section & U32) -> U32:
  (first, bad) = write
  clone.first(second, saved, (failures + bad : U32), expect_read(Storage.Section.get_index(first, 0), 4294967295))

def clone.copied(saved: List<&2, U32>, failures: U32, copies: Storage.Section & Storage.Section) -> U32:
  (first, second) = copies
  clone.written(second, saved, failures, expect_write(Storage.Section.set_index(first, 0, 4294967295)))

def clone.saved(failures: U32, snapshot: Storage.Section & List<&2, U32>) -> U32:
  (section, saved) = snapshot
  clone.copied(saved, failures, Storage.Section.clone(section))

def phase.verify(result: Storage.Section & U32) -> U32:
  (section, failures) = result
  clone.saved(failures, Storage.Section.snapshot(section))

def phase.fill(result: Storage.Section & U32) -> U32:
  (section, failures) = result
  phase.verify(verify(4096n, 0, failures, (section, 0)))

def phase.initial(result: Storage.Section & U32) -> U32:
  (section, failures) = result
  phase.fill(fill(4096n, 0, failures, (section, 0)))

def phase.rejected(result: Storage.Section & U32) -> U32:
  (section, failures) = result
  phase.initial(scan(4096n, 0, failures, (section, 0)))

def phase.indices(result: Storage.Section & U32) -> U32:
  (section, failures) = result
  phase.rejected(bad_locals([Storage.Local{16, 0, 0}, Storage.Local{0, 16, 0}, Storage.Local{0, 0, 16}, Storage.Local{17, 15, 15}, Storage.Local{15, 17, 15}, Storage.Local{15, 15, 17}, Storage.Local{4294967295, 0, 0}, Storage.Local{0, 4294967295, 0}, Storage.Local{0, 0, 4294967295}, Storage.Local{16, 16, 16}], failures, (section, 0)))

def storage_test() -> U32:
  phase.indices(bad_indices([4096, 4097, 8191, 8192, 65536, 2147483648, 4294967295], 0, (Storage.Section.new(3735928559), 0)))

# Python 3 generated these encoded fixtures from signed integer //16 and %16.
def world_fixtures() -> List<&2, WorldFixture>:
  [WorldFixture{2147483648, 4160749568, 0}, WorldFixture{2147483649, 4160749568, 1}, WorldFixture{4293967295, 4294904795, 15}, WorldFixture{4294901759, 4294963199, 15}, WorldFixture{4294963199, 4294967039, 15}, WorldFixture{4294967039, 4294967279, 15}, WorldFixture{4294967040, 4294967280, 0}, WorldFixture{4294967041, 4294967280, 1}, WorldFixture{4294967263, 4294967293, 15}, WorldFixture{4294967264, 4294967294, 0}, WorldFixture{4294967265, 4294967294, 1}, WorldFixture{4294967279, 4294967294, 15}, WorldFixture{4294967280, 4294967295, 0}, WorldFixture{4294967281, 4294967295, 1}, WorldFixture{4294967295, 4294967295, 15}, WorldFixture{0, 0, 0}, WorldFixture{1, 0, 1}, WorldFixture{15, 0, 15}, WorldFixture{16, 1, 0}, WorldFixture{17, 1, 1}, WorldFixture{31, 1, 15}, WorldFixture{32, 2, 0}, WorldFixture{33, 2, 1}, WorldFixture{255, 15, 15}, WorldFixture{256, 16, 0}, WorldFixture{257, 16, 1}, WorldFixture{4095, 255, 15}, WorldFixture{4096, 256, 0}, WorldFixture{65535, 4095, 15}, WorldFixture{65536, 4096, 0}, WorldFixture{1000001, 62500, 1}, WorldFixture{2147483646, 134217727, 14}, WorldFixture{2147483647, 134217727, 15}]

def expect_bad_section(result: Result<&2, &2, Storage.Section.Error, U32>, expected: U32) -> U32:
  match result:
    case Fail{Storage.BadSection{actual}}:
      fail_unless(U32.is_eq(actual, expected))
    case _:
      1

def expect_bad_remainder(result: Result<&2, &2, Storage.Section.Error, U32>, expected: U32) -> U32:
  match result:
    case Fail{Storage.BadRemainder{actual}}:
      fail_unless(U32.is_eq(actual, expected))
    case _:
      1

def compose_errors() -> U32:
  (expect_bad_section(Storage.Coord.compose(134217728, 0), 134217728) +
   expect_bad_section(Storage.Coord.compose(4160749567, 15), 4160749567) +
   expect_bad_section(Storage.Coord.compose(2147483648, 0), 2147483648) +
   expect_bad_section(Storage.Coord.compose(134217728, 16), 134217728) +
   expect_bad_remainder(Storage.Coord.compose(0, 16), 16) +
   expect_bad_remainder(Storage.Coord.compose(4294967295, 4294967295), 4294967295) +
   reject_index_local(4096, Storage.Section.index_local(4096)) +
   reject_index_local(4294967295, Storage.Section.index_local(4294967295)) : U32)

def finish(failures: U32, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("{\"suite\":\"section\",\"failures\":0,\"local_coordinates\":4096,\"world_fixtures\":33,\"initial_cells\":4096,\"written_cells\":4096,\"read_after_write_cells\":4096,\"neighbor_isolation_checks\":4096,\"verified_cells\":4096,\"snapshot_cells\":4096}")
    case False{}:
      IO.die(Unit, 1, "section failures: " ++ U32.show(failures))

def main() -> IO(Unit):
  +failures = (local_rows(4096n, 0, 0) + worlds(world_fixtures(), 0) + compose_errors() + storage_test() : U32)
  finish(failures, U32.is_zero(failures))
