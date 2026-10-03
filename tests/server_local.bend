import Base
import ../src/core.bend as C
import ../src/json.bend as J
import ../src/live.bend as L
import ../src/schedule.bend as Q
import ../src/server.bend as S

def position() -> C.Position:
  C.Position{"minecraft:overworld", 4294967279, 0, 32}

def read_status(status: Result<&2, &2, C.Error, U32>) -> J.Value:
  match status:
    case Done{state}: L.obj([J.JMember{"state", L.uint(state)}])
    case Fail{error}: L.obj([J.JMember{"missing", L.boolean(True{})}])

def read_ready(result: C.World & Result<&2, &2, C.Error, U32>) -> C.World & J.Value:
  (world, status) = result
  (world, read_status(status))

def local_read(world: C.World) -> C.World & J.Value:
  read_ready(C.read_block(world, position()))

def clock_ready(result: C.World & C.Clock) -> C.World & J.Value:
  (world, clock) = result
  C.Clock{tick, day_time, paused, daylight, revision, pending} = clock
  (world, L.obj([J.JMember{"tick", L.natural(tick)}, J.JMember{"revision", L.natural(revision)}, J.JMember{"pending", L.natural(pending)}]))

def local_clock(world: C.World) -> C.World & J.Value:
  clock_ready(C.clock(world))

def admitted(result: C.World & Result<&2, &2, C.Error, Unit>) -> C.World & J.Value:
  (world, status) = result
  local_clock(world)

def admit_clock(result: C.World & C.Clock) -> C.World & J.Value:
  (world, clock) = result
  C.Clock{tick, day_time, paused, daylight, revision, pending} = clock
  admitted(C.admit(world, C.Developer{}, Q.Stamp{1n+tick, 0, 1n}, C.BlockSet{position(), 321}))

def local_admit(world: C.World) -> C.World & J.Value:
  admit_clock(C.clock(world))

def local_step(world: C.World) -> C.World & J.Value:
  local_clock(C.step(world))

def report(value: J.Value) -> IO(Unit):
  IO.print(J.encode(value))

def local_query(code: U32, world: C.World) -> C.World & J.Value:
  match code:
    case 113: local_read(world)
    case 109: local_admit(world)
    case 115: local_step(world)
    case other: local_clock(world)

def command(+handle: S.Handle<C.World>, input: File, code: U32, rest: File -> IO(Unit)) -> IO(Unit):
  match code:
    case 120:
      do IO<Unit>:
        File.close(input)
        S.stop(C.World, handle)
        IO.die(Unit, 0, "local fixture closed")
    case other:
      do IO<Unit>:
        answer : J.Value <- S.local_call(C.World, J.Value, handle, world => local_query(other, world))
        report(answer)
        rest(input)

def read_next(+handle: S.Handle<C.World>, result: File & Result<&1, &1, U32 & String, List<&2, U32>>, rest: File -> IO(Unit)) -> IO(Unit):
  (input, status) = result
  match status:
    case Done{Con{code, tail}}: command(handle, input, code, rest)
    case other:
      do IO<Unit>:
        File.close(input)
        S.stop(C.World, handle)
        IO.die(Unit, 0, "local fixture input ended")

@unsafe
def loop(+handle: S.Handle<C.World>, input: File) -> IO(Unit):
  do IO<Unit>:
    result : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(input, 1)
    read_next(handle, result, file => loop(handle, file))

def main() -> IO(Unit):
  do IO<Unit>:
    handle : S.Handle<C.World> <- S.start_handle(~C.World, ~S.Driver{C.realtime_step, S.core_dispatch}, C.new(500))
    input : File <- IO.try(File, File.open("/dev/stdin", "r"))
    loop(handle, input)
