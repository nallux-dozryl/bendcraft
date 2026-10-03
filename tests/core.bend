import Base
import ../src/core.bend as C
import ../src/schedule.bend as Q

def require(ok: Bool, text: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, text)

def admitted(r: C.World & Result<&2, &2, C.Error, Unit>) -> IO(C.World):
  (w, result) = r
  match result:
    case Done{u}:
      IO.pure(C.World, w)
    case Fail{error}:
      IO.die(C.World, 1, "expected action admission")

def rejected(r: C.World & Result<&2, &2, C.Error, Unit>) -> IO(C.World):
  (w, result) = r
  match result:
    case Fail{error}:
      IO.pure(C.World, w)
    case Done{u}:
      IO.die(C.World, 1, "invalid action was admitted")

def read_expect(expected: U32, r: C.World & Result<&2, &2, C.Error, U32>) -> IO(C.World):
  (w, result) = r
  match result:
    case Fail{error}:
      IO.die(C.World, 1, "expected loaded block")
    case Done{value}:
      do IO<C.World>:
        require(U32.is_eq(value, expected), "block value mismatch")
        return w

def clock_expect(tick: Nat, time: Nat, pending: Nat, rev: Nat, r: C.World & C.Clock) -> IO(C.World):
  (w, C.Clock{ctick, ctime, paused, daylight, crev, cpending}) = r
  do IO<C.World>:
    require(Nat.is_eq(tick, ctick) && Nat.is_eq(time, ctime) && Nat.is_eq(pending, cpending) && Nat.is_eq(rev, crev), "clock/pending/revision mismatch")
    return w

def main() -> IO(Unit):
  +origin = {C.Position{"minecraft:overworld", 0, 0, 0} : C.Position}
  +negative = {C.Position{"minecraft:overworld", 4294967280, 0, 0} : C.Position}
  do IO<Unit>:
    w0 : C.World = C.new(3)
    w1 : C.World <- rejected(C.admit(w0, C.Observer{}, Q.Stamp{1n, 1, 0n}, C.SectionCreate{origin, 0}))
    w2 : C.World <- rejected(C.admit(w1, C.Player{1}, Q.Stamp{1n, 1, 1n}, C.TimeSet{900n}))
    w3 : C.World <- rejected(C.admit(w2, C.Developer{}, Q.Stamp{1n, 1, 2n}, C.SectionCreate{origin, 3}))
    w4 : C.World <- clock_expect(0n, 0n, 0n, 0n, C.clock(w3))
    w5 : C.World <- admitted(C.admit(w4, C.Developer{}, Q.Stamp{1n, 2, 0n}, C.BlockSet{origin, 2}))
    w6 : C.World <- admitted(C.admit(w5, C.Developer{}, Q.Stamp{1n, 1, 3n}, C.SectionCreate{origin, 0}))
    w7 : C.World <- admitted(C.admit(w6, C.Developer{}, Q.Stamp{3n, 1, 4n}, C.BlockSet{origin, 1}))
    w8 : C.World <- clock_expect(0n, 0n, 3n, 0n, C.clock(C.realtime_step(w7)))
    w9 : C.World <- read_expect(2, C.read_block(C.step(w8), origin))
    w10 : C.World <- clock_expect(1n, 1n, 1n, 2n, C.clock(w9))
    w11 : C.World <- rejected(C.admit(w10, C.Developer{}, Q.Stamp{1n, 1, 5n}, C.TimeSet{42n}))
    w12 : C.World <- admitted(C.admit(w11, C.Developer{}, Q.Stamp{2n, 1, 6n}, C.SectionCreate{negative, 1}))
    w13 : C.World <- admitted(C.admit(w12, C.Developer{}, Q.Stamp{2n, 1, 7n}, C.SectionCreate{origin, 0}))
    w14 : C.World <- read_expect(2, C.read_block(C.step(w13), origin))
    w15 : C.World <- read_expect(1, C.read_block(w14, negative))
    w16 : C.World <- clock_expect(2n, 2n, 1n, 3n, C.clock(w15))
    w17 : C.World <- read_expect(2, C.read_block(C.step(C.cancel(w16, Q.Stamp{0n, 1, 4n})), origin))
    w18 : C.World <- clock_expect(3n, 3n, 0n, 3n, C.clock(w17))
    w19 : C.World <- admitted(C.admit(w18, C.Developer{}, Q.Stamp{4n, 1, 8n}, C.TimeSet{1000n}))
    w20 : C.World <- admitted(C.admit(w19, C.Developer{}, Q.Stamp{4n, 1, 9n}, C.DaylightSet{False{}}))
    w21 : C.World <- clock_expect(4n, 1000n, 0n, 5n, C.clock(C.step(w20)))
    w22 : C.World <- clock_expect(6n, 1000n, 0n, 5n, C.clock(C.advance(2n, w21)))
    w23 : C.World <- clock_expect(7n, 1000n, 0n, 5n, C.clock(C.realtime_step(C.set_paused(w22, False{}))))
    IO.print("PASS core: authority, validation, deterministic action order, delayed/cancelled work, section isolation, failed-create rollback, explicit/realtime ticks")
