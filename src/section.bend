# A section owns exactly one array. Construct it through Section.new.
# Coordinates are local U32 values; signed world/section coordinates are
# two's-complement I32 bit patterns stored in U32.
import Base

type Section is Type:
  Section{blocks: Array<U32>}

type Section.Local is Data:
  Local{x: U32, y: U32, z: U32}

type Section.Error is Data:
  BadLocal{x: U32, y: U32, z: U32}
  BadIndex{index: U32}
  BadSection{coordinate: U32}
  BadRemainder{local: U32}

def Section.new(state: U32) -> Section:
  Section{[state : U32*4096n]}

def Section.local_valid(x: U32, y: U32, z: U32) -> Bool:
  Bool.and(U32.is_lt(x, 16), Bool.and(U32.is_lt(y, 16), U32.is_lt(z, 16)))

# Unchecked arithmetic is internal to the successful branch of local_index.
def Section.index_value(x: U32, y: U32, z: U32) -> U32:
  (x + U32.shln(z, 4n) + U32.shln(y, 8n) : U32)

def Section.local_index.fin(x: U32, y: U32, z: U32, valid: Bool) -> Result<&2, &2, Section.Error, U32>:
  match valid:
    case False{}:
      Fail{BadLocal{x, y, z}}
    case True{}:
      Done{Section.index_value(x, y, z)}

def Section.local_index(+x: U32, +y: U32, +z: U32) -> Result<&2, &2, Section.Error, U32>:
  Section.local_index.fin(x, y, z, Section.local_valid(x, y, z))

def Section.index_local.fin(index: U32, valid: Bool) -> Result<&2, &2, Section.Error, Section.Local>:
  match valid:
    case False{}:
      Fail{BadIndex{index}}
    case True{}:
      +i = index
      Done{Local{U32.and(i, 15), U32.shrn(i, 8n), U32.and(U32.shrn(i, 4n), 15)}}

def Section.index_local(+index: U32) -> Result<&2, &2, Section.Error, Section.Local>:
  Section.index_local.fin(index, U32.is_lt(index, 4096))

# Public access validates indices before entering Base array operations.
# The fixed shape comes from Section.new and is preserved by every update.
def Section.array_get(a: Array<U32>, +index: U32) -> Array<U32> & U32:
  Array.get(U32, a, index)

def Section.array_set(a: Array<U32>, +index: U32, state: U32) -> Array<U32>:
  Array.set(U32, a, index, state)

def Section.get.read(r: Array<U32> & U32) -> Section & Result<&2, &2, Section.Error, U32>:
  (a, state) = r
  (Section{a}, Done{state})

def Section.get.checked(section: Section, index: Result<&2, &2, Section.Error, U32>) -> Section & Result<&2, &2, Section.Error, U32>:
  match section index:
    case Section{a} Fail{error}:
      (Section{a}, Fail{error})
    case Section{a} Done{i}:
      Section.get.read(Section.array_get(a, i))

def Section.get(section: Section, x: U32, y: U32, z: U32) -> Section & Result<&2, &2, Section.Error, U32>:
  Section.get.checked(section, Section.local_index(x, y, z))

def Section.get_index.fin(section: Section, index: U32, valid: Bool) -> Section & Result<&2, &2, Section.Error, U32>:
  match section valid:
    case Section{a} False{}:
      (Section{a}, Fail{BadIndex{index}})
    case Section{a} True{}:
      Section.get.read(Section.array_get(a, index))

def Section.get_index(section: Section, +index: U32) -> Section & Result<&2, &2, Section.Error, U32>:
  Section.get_index.fin(section, index, U32.is_lt(index, 4096))

def Section.set.checked(section: Section, index: Result<&2, &2, Section.Error, U32>, state: U32) -> Section & Result<&2, &2, Section.Error, Unit>:
  match section index:
    case Section{a} Fail{error}:
      (Section{a}, Fail{error})
    case Section{a} Done{i}:
      (Section{Section.array_set(a, i, state)}, Done{Unit{}})

def Section.set(section: Section, x: U32, y: U32, z: U32, state: U32) -> Section & Result<&2, &2, Section.Error, Unit>:
  Section.set.checked(section, Section.local_index(x, y, z), state)

def Section.set_index.fin(section: Section, index: U32, state: U32, valid: Bool) -> Section & Result<&2, &2, Section.Error, Unit>:
  match section valid:
    case Section{a} False{}:
      (Section{a}, Fail{BadIndex{index}})
    case Section{a} True{}:
      (Section{Section.array_set(a, index, state)}, Done{Unit{}})

def Section.set_index(section: Section, +index: U32, state: U32) -> Section & Result<&2, &2, Section.Error, Unit>:
  Section.set_index.fin(section, index, state, U32.is_lt(index, 4096))

def Section.clone.fin(copied: Array<U32> & Array<U32>) -> Section & Section:
  (first, second) = copied
  (Section{first}, Section{second})

def Section.clone(section: Section) -> Section & Section:
  Section{a} = section
  Section.clone.fin(Array.clone(U32, a))

# Copy scalar IDs to an immutable list while returning the original owner.
# Reading backwards and prepending yields ascending index order.
def Section.snapshot.go(fuel: Nat, +index: U32, acc: List<&2, U32>, read: Array<U32> & U32) -> Section & List<&2, U32>:
  match fuel:
    case 0n:
      (a, state) = read
      (Section{a}, state <> acc)
    case 1n+p:
      (a, state) = read
      Section.snapshot.go(p, (index - 1 : U32), state <> acc, Section.array_get(a, (index - 1 : U32)))

def Section.snapshot(section: Section) -> Section & List<&2, U32>:
  Section{a} = section
  Section.snapshot.go(4095n, 4095, Nil{}, Section.array_get(a, 4095))

# Signed I32 world coordinate -> signed section coordinate: arithmetic >> 4.
def Coord.section.sign(shifted: U32, negative: Bool) -> U32:
  match negative:
    case False{}:
      shifted
    case True{}:
      U32.or(shifted, 4026531840)

def Coord.section(+world: U32) -> U32:
  Coord.section.sign(U32.shrn(world, 4n), U32.is_ge(world, 2147483648))

# Euclidean remainder 0..15, including negative signed coordinates.
def Coord.local(world: U32) -> U32:
  U32.and(world, 15)

def Coord.split(+world: U32) -> U32 & U32:
  (Coord.section(world), Coord.local(world))

# Multiplication is modulo 2^32; compose checks that the signed result fits.
def Coord.compose_value(section: U32, local: U32) -> U32:
  (U32.shln(section, 4n) + local : U32)

def Coord.section_valid(+section: U32) -> Bool:
  Bool.or(U32.is_lt(section, 134217728), U32.is_ge(section, 4160749568))

def Coord.compose.local(section: U32, local: U32, valid: Bool) -> Result<&2, &2, Section.Error, U32>:
  match valid:
    case False{}:
      Fail{BadRemainder{local}}
    case True{}:
      Done{Coord.compose_value(section, local)}

def Coord.compose.section(section: U32, +local: U32, valid: Bool) -> Result<&2, &2, Section.Error, U32>:
  match valid:
    case False{}:
      Fail{BadSection{section}}
    case True{}:
      Coord.compose.local(section, local, U32.is_lt(local, 16))

def Coord.compose(+section: U32, local: U32) -> Result<&2, &2, Section.Error, U32>:
  Coord.compose.section(section, local, Coord.section_valid(section))
