import Base
import ../src/world_codec.bend as W
import ../src/core.bend as C
import ../src/schedule.bend as Q
import ../src/section.bend as S
import ../src/section_map.bend as M
import ../src/nbt.bend as N
import ./nbt.bend as H

# Four native worlds with independently specified Python expectations.
def collision() -> C.World:
  C.replace_sections(C.new(16), M.set(M.set(M.EmptySections{}, "minecraft:overworld/12009114/36153475/77999535", S.Section.new(1)), "minecraft:overworld/21442934/118325841/132352103", S.Section.new(2)))

def signed() -> C.World:
  C.replace_sections(C.new(16), M.set(M.set(M.EmptySections{}, "minecraft:overworld/4294967295/0/4294967294", S.Section.new(3)), "minecraft:the_end/4160749568/134217727/0", S.Section.new(4)))

def rich() -> C.World:
  C.World{42n, 1000n, False{}, False{}, 4n, 16,
    M.set(M.set(M.EmptySections{}, "minecraft:overworld/0/0/0", S.Section{Array.set(U32, Array.set(U32, [0 : U32 * 4096n], 0, 7), 4095, 15)}),
      "minecraft:the_nether/1/0/0", S.Section{Array.set(U32, [2 : U32 * 4096n], 17, 3)}),
    [Q.Pending{Q.Stamp{43n, 7, 1n}, C.SectionCreate{C.Position{"minecraft:overworld", 32, 0, 0}, 4}},
      Q.Pending{Q.Stamp{43n, 8, 2n}, C.BlockSet{C.Position{"minecraft:the_nether", 16, 0, 0}, 3}},
      Q.Pending{Q.Stamp{44n, 3, 100n}, C.TimeSet{999n}}, Q.Pending{Q.Stamp{44n, 3, 101n}, C.DaylightSet{False{}}}],
    [C.Applied{Q.Stamp{42n, 7, 2n}, 4n}, C.Rejected{Q.Stamp{41n, 6, 1n}, C.UnknownDimension{"custom:unknown"}}, C.Applied{Q.Stamp{40n, 1, 3n}, 1n}]}

def fixture(name: String) -> C.World:
  match name:
    case "empty": C.new(16)
    case "rich": rich()
    case "signed": signed()
    case "collision": collision()
    case _: C.new(16)

def encode_line(pair: C.World & Result<&2, &2, String, List<&2, U32>>) -> String:
  (world, result) = pair
  H.encoded(result)

def emit(name: String) -> String:
  encode_line(W.encode(fixture(name), "fixture-registry"))

def peer_line(result: Result<&2, &1, String, W.Loaded>) -> String:
  match result:
    case Fail{message}: "error\t" ++ message
    case Done{W.Loaded{world, None{}}}: "none"
    case Done{W.Loaded{world, Some{peer}}}: "peer\t" ++ U32.show(peer)

def roundtrip_loaded(registry: String, result: Result<&2, &1, String, W.Loaded>) -> String:
  match result:
    case Fail{message}: "error\t" ++ message
    case Done{W.Loaded{world, high}}: encode_line(W.encode(world, registry))

def dispatch_loaded(registry: String, peer: Bool, result: Result<&2, &1, String, W.Loaded>) -> String:
  match peer:
    case True{}: peer_line(result)
    case False{}: roundtrip_loaded(registry, result)

def failed(pair: C.World & Result<&2, &2, String, List<&2, U32>>) -> Bool:
  (world, result) = pair
  H.fails_encode(result)

def compare_bytes(a: List<&2, U32>, result: Result<&2, &2, String, List<&2, U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{b}: String.eq(H.hex_bytes(a), H.hex_bytes(b))

def encoded_again(a: List<&2, U32>, pair: C.World & Result<&2, &2, String, List<&2, U32>>) -> Bool:
  (world, result) = pair
  compare_bytes(a, result)

def owner_twice(pair: C.World & Result<&2, &2, String, List<&2, U32>>) -> Bool:
  (world, result) = pair
  match result:
    case Fail{message}: False{}
    case Done{bytes}: encoded_again(bytes, W.encode(world, "fixture-registry"))

def roundtrip_compare(+original: List<&2, U32>, result: Result<&2, &1, String, W.Loaded>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{W.Loaded{world, high}}: encoded_again(original, W.encode(world, "fixture-registry"))

def decoded_again(pair: C.World & Result<&2, &2, String, List<&2, U32>>) -> Bool:
  (world, result) = pair
  match result:
    case Fail{message}: False{}
    case Done{+bytes}: roundtrip_compare(bytes, W.decode(bytes, 16, "fixture-registry"))

def malformed_array() -> C.World:
  C.replace_sections(C.new(16), M.set(M.EmptySections{}, "minecraft:overworld/0/0/0", S.Section{ANode{ALeaf{9}, ALeaf{8}}}))

def invalid_array_pop(failed: Bool, pair: M.Sections & Maybe<&1, S.Section>) -> Bool:
  (sections, found) = pair
  match found:
    case Some{S.Section{ANode{ALeaf{9}, ALeaf{8}}}}: failed
    case _: False{}

def invalid_scalar_world() -> C.World:
  C.World{0n, 0n, True{}, True{}, 0n, 16, M.EmptySections{}, [], [C.Rejected{Q.Stamp{0n, 1, 0n}, C.UnknownDimension{SCon{Chr{55296}, SCon{Chr{56320}, SNil{}}}}}]}


law checked_native_nat_boundary:
  {W.native_nat_text("281474976710655") == True{} : Bool}

def checked_native_nat_boundary():
  {==}



law checked_native_nat_overflow:
  {W.nat_value(W.default_limits(), W.string_tag("281474976710656")) == Fail{"world Nat exceeds native 48-bit range"} : Result<&2, &2, String, Nat>}

def checked_native_nat_overflow():
  {==}

def input_bytes(+count: U32, +registry: String, peer: Bool, result: Result<&2, &2, String, List<&2, U32>>) -> String:
  match result:
    case Fail{message}: "error\t" ++ message
    case Done{bytes}:
      dispatch_loaded(registry, peer, W.decode(bytes, count, registry))

def one(count: U32, registry: String, peer: Bool, input: String) -> String:
  input_bytes(count, registry, peer, H.unhex(input))

def invalid_array_owner(pair: C.World & Result<&2, &2, String, List<&2, U32>>) -> Bool:
  (world, result) = pair
  C.World{tick, time, paused, daylight, rev, count, sections, pending, events} = world
  invalid_array_pop(H.fails_encode(result), M.pop(sections, "minecraft:overworld/0/0/0"))

def failure_recovered_result(world: C.World, result: Result<&2, &2, String, List<&2, U32>>) -> String:
  match result:
    case Done{bytes}: "unexpected success"
    case Fail{error}: encode_line(W.encode(world, "fixture-registry"))

def replay_clock_fields(clock: C.Clock) -> Bool:
  match clock:
    case C.Clock{44n, 999n, False{}, False{}, 8n, 0n}: True{}
    case _: False{}

def duplicate_branch(left: Bool, child: M.Sections) -> M.Sections:
  match left:
    case True{}: M.Branch{child, M.EmptySections{}}
    case False{}: M.Branch{M.EmptySections{}, child}

def batch(+count: U32, +registry: String, +peer: Bool, args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case input <> rest:
      do IO<Unit>:
        IO.print(one(count, registry, peer, input))
        batch(count, registry, peer, rest)

def file_read(count: U32, registry: String, peer: Bool, result: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  (file, content) = result
  do IO<Unit>:
    input : String <- IO.try(String, IO.pure(Result<&1, &1, U32 & String, String>, content))
    File.close(file)
    IO.print(one(count, registry, peer, input))

def file_size(count: U32, registry: String, peer: Bool, result: File & Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  (file, measured) = result
  do IO<Unit>:
    size : U32 <- IO.try(U32, IO.pure(Result<&1, &1, U32 & String, U32>, measured))
    content : File & Result<&1, &1, U32 & String, String> <- File.read(file, size)
    file_read(count, registry, peer, content)

def file_input(count: U32, registry: String, peer: Bool, path: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "r"))
    sized : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
    file_size(count, registry, peer, sized)

def counted(+mode: String, +count: U32, +registry: String, args: List<String>) -> IO(Unit):
  match mode args:
    case "file" path <> Nil{}: file_input(count, registry, False{}, path)
    case "peer-file" path <> Nil{}: file_input(count, registry, True{}, path)
    case "batch" inputs: batch(count, registry, False{}, inputs)
    case "peer-batch" inputs: batch(count, registry, True{}, inputs)
    case "peer" input <> Nil{}: IO.print(one(count, registry, True{}, input))
    case _ _: IO.die(Unit, 2, "invalid world codec mode")

def input_count(mode: String, value: Maybe<&2, U32>, registry: String, args: List<String>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit, 2, "invalid state count")
    case Some{count}: counted(mode, count, registry, args)

def failure_recovered(pair: C.World & Result<&2, &2, String, List<&2, U32>>) -> String:
  (world, result) = pair
  failure_recovered_result(world, result)

def replay_clock(pair: C.World & C.Clock) -> Bool:
  (world, clock) = pair
  replay_clock_fields(clock)

def replay_loaded(result: Result<&2, &1, String, W.Loaded>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{W.Loaded{world, high}}: replay_clock(C.clock(C.step(C.step(world))))

def replay_bytes(result: Result<&2, &2, String, List<&2, U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: replay_loaded(W.decode(bytes, 16, "fixture-registry"))

def duplicate_bucket(depth: Nat, +bits: U32) -> M.Sections:
  match depth:
    case 0n: M.Bucket{[M.Entry{"minecraft:overworld/0/0/0", S.Section.new(1)}, M.Entry{"minecraft:overworld/0/0/0", S.Section.new(2)}]}
    case 1n+n:
      duplicate_branch(U32.is_eq(U32.and(bits, 1), 0), duplicate_bucket(n, U32.shr(bits)))

def replay_encoded(pair: C.World & Result<&2, &2, String, List<&2, U32>>) -> Bool:
  (world, result) = pair
  replay_bytes(result)

def regressions() -> Bool:
  replay_encoded(W.encode(rich(), "fixture-registry")) &&
  String.eq(failure_recovered(W.encode_with(W.Limits{N.Limits{0, 512, 1048576}, 512, 65536, 15, 65535}, rich(), "fixture-registry")), emit("rich")) &&
  failed(W.encode(C.replace_sections(C.new(16), duplicate_bucket(32n, M.hash("minecraft:overworld/0/0/0"))), "fixture-registry")) &&
  owner_twice(W.encode(rich(), "fixture-registry")) &&
  owner_twice(W.encode(collision(), "fixture-registry")) &&
  decoded_again(W.encode(rich(), "fixture-registry")) &&
  decoded_again(W.encode(signed(), "fixture-registry")) &&
  invalid_array_owner(W.encode(malformed_array(), "fixture-registry")) &&
  failed(W.encode(C.replace_sections(C.new(16), M.Bucket{[M.Entry{"minecraft:overworld/0/0/0", S.Section.new(0)}]}), "fixture-registry")) &&
  failed(W.encode(C.World{0n, 0n, True{}, True{}, 0n, 16, M.EmptySections{}, [Q.Pending{Q.Stamp{0n, 1, 0n}, C.TimeSet{0n}}], []}, "fixture-registry")) &&
  failed(W.encode(invalid_scalar_world(), "fixture-registry")) &&
  failed(W.encode_with(W.Limits{N.Limits{0, 512, 1048576}, 512, 65536, 15, 65535}, C.new(16), "fixture-registry")) &&
  failed(W.encode_with(W.Limits{N.default_limits(), 0, 65536, 15, 65535}, rich(), "fixture-registry")) &&
  failed(W.encode_with(W.Limits{N.default_limits(), 512, 0, 15, 65535}, C.new(16), "fixture-registry")) &&
  failed(W.encode_with(W.Limits{N.default_limits(), 512, 65536, 0, 65535}, C.new(16), "fixture-registry")) &&
  failed(W.encode_with(W.Limits{N.default_limits(), 512, 65536, 15, 0}, C.new(16), "fixture-registry"))

# This is a finite helper fixture, not a universal world roundtrip theorem.

def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.print(N.choose(String, "regressions\tpass", "regressions\tFAIL", regressions()))
    case "emit" <> name <> Nil{}: IO.print(emit(name))
    case mode <> count <> registry <> rest: input_count(mode, U32.read(count), registry, rest)
    case _: IO.die(Unit, 2, "usage: world-codec-tests [emit NAME | batch COUNT REGISTRY HEX... | file COUNT REGISTRY PATH | peer COUNT REGISTRY HEX]")

# Unequal child classes are abstract Array values; native blk_node rejects construction.
law checked_malformed_array_shape:
  {W.array_cells(2n, ANode{ALeaf{9}, ANode{ALeaf{8}, ALeaf{7}}}, 16) == (ANode{ALeaf{9}, ANode{ALeaf{8}, ALeaf{7}}}, Fail{"malformed owned section Array layout"}) : Array<U32> & Result<&2, &2, String, List<&2, U32>>}

def checked_malformed_array_shape():
  {==}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(List.tail(&1, String, args))
