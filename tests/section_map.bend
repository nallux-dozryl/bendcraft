import Base
import ../src/section.bend as S
import ../src/section_map.bend as M

def require(ok: Bool, text: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, text)

def read_value(expected: U32, r: S.Section & Result<&2, &2, S.Section.Error, U32>) -> IO(Unit):
  (section, result) = r
  match result:
    case Fail{error}:
      IO.die(Unit, 1, "section map read failed")
    case Done{value}:
      require(U32.is_eq(expected, value), "section map returned wrong owner")

def popped(expected: U32, r: M.Sections & Maybe<&1, S.Section>) -> IO(M.Sections):
  (map, found) = r
  match found:
    case None{}:
      IO.die(M.Sections, 1, "section map lost key")
    case Some{section}:
      do IO<M.Sections>:
        read_value(expected, S.Section.get_index(section, 0))
        return map

def absent(r: M.Sections & Maybe<&1, S.Section>) -> IO(M.Sections):
  (map, found) = r
  match found:
    case None{}:
      IO.pure(M.Sections, map)
    case Some{section}:
      IO.die(M.Sections, 1, "absent section key was found")

def main() -> IO(Unit):
  # Independent Python FNV-1a fixture: both keys hash to 1582148253.
  do IO<Unit>:
    require(U32.is_eq(M.hash("costarring"), 1582148253) && U32.is_eq(M.hash("liquid"), 1582148253), "hash fixture changed")
    m0 : M.Sections = M.EmptySections{}
    m1 : M.Sections = M.set(m0, "costarring", S.Section.new(1))
    m2 : M.Sections = M.set(m1, "liquid", S.Section.new(2))
    m3 : M.Sections = M.set(m2, "ordinary", S.Section.new(3))
    m4 : M.Sections = M.set(m3, "costarring", S.Section.new(4))
    m5 : M.Sections <- absent(M.pop(m4, "missing"))
    m6 : M.Sections <- popped(4, M.pop(m5, "costarring"))
    m7 : M.Sections <- absent(M.pop(m6, "costarring"))
    m8 : M.Sections <- popped(2, M.pop(m7, "liquid"))
    m9 : M.Sections <- popped(3, M.pop(m8, "ordinary"))
    m10 : M.Sections <- absent(M.pop(m9, "ordinary"))
    IO.print("PASS section map: owned arrays, hash collision isolation, replace, absent/pop preservation")
