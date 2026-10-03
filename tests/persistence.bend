import Base
import ../src/persistence.bend as P
import ../src/world_codec.bend as W
import ../src/atomic_file.bend as A
import ../src/nbt.bend as N
import ../src/json.bend as J
import ../src/core.bend as C
import ./world_codec.bend as F

# Finite native observations; OS durability is tested separately by real effects.
def unsynced_fixture() -> J.Value:
  P.publication_value(A.PublishedUnsynced{5, "directory sync fixture"}, 123, 7)

def equal_result(result: Result<&2, &2, String, U32>, expected: U32) -> Bool:
  match result:
    case Done{actual}: U32.is_eq(actual, expected)
    case Fail{message}: False{}

def peer_exhausted(result: Result<&2, &2, String, U32>) -> Bool:
  match result:
    case Fail{"persisted peer identity range exhausted"}: True{}
    case _: False{}

def decode_failed(result: Result<&2, &1, String, P.Saved>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{saved}: False{}

def rich_clock(clock: C.Clock) -> Bool:
  match clock:
    case C.Clock{42n, 1000n, False{}, False{}, 4n, 4n}: True{}
    case _: False{}

def saved_clock(high: U32, pair: C.World & C.Clock) -> Bool:
  (world, clock) = pair
  U32.is_eq(high, 8) && rich_clock(clock)

def rich_loaded(result: Result<&2, &1, String, P.Saved>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{P.Saved{world, high}}: saved_clock(high, C.clock(world))

def roundtrip_envelope(result: Result<&2, &2, String, List<&2, U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: rich_loaded(P.envelope_decode(P.default_limits(), bytes, 16, "fixture-registry"))

def rich_bytes(result: Result<&2, &2, String, List<&2, U32>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{bytes}: roundtrip_envelope(P.envelope_encode(P.default_limits(), "fixture-registry", 0, bytes))

def rich_encoded(pair: C.World & Result<&2, &2, String, List<&2, U32>>) -> Bool:
  (world, result) = pair
  rich_bytes(result)

def regressions() -> Bool:
  equal_result(P.next_peer(0), 1) && equal_result(P.next_peer(4294967294), 4294967295) && peer_exhausted(P.next_peer(4294967295)) &&
  U32.is_eq(P.effective_highwater(7, None{}), 7) && U32.is_eq(P.effective_highwater(7, Some{8}), 8) &&
  U32.is_eq(P.effective_highwater(9, Some{8}), 9) && rich_encoded(W.encode(F.rich(), "fixture-registry")) &&
  decode_failed(P.envelope_decode(P.default_limits(), [], 16, "fixture-registry")) &&
  String.eq(J.encode(unsynced_fixture()), "{\"status\":\"published_unsynced\",\"published\":true,\"durable\":false,\"code\":5,\"message\":\"directory sync fixture\",\"bytes\":123,\"peer_highwater\":7}") &&
  String.eq(J.encode(P.publication_value(A.Durable{}, 123, 7)), "{\"status\":\"durable\",\"published\":true,\"durable\":true,\"bytes\":123,\"peer_highwater\":7}") &&
  String.eq(J.encode(P.publication_value(A.NotPublished{5, "fixture"}, 123, 7)), "{\"status\":\"not_published\",\"published\":false,\"durable\":false,\"code\":5,\"message\":\"fixture\"}")

def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.print(N.choose(String, "regressions\tpass", "regressions\tFAIL", regressions()))
    case "outcome" <> Nil{}: IO.print(J.encode(unsynced_fixture()))
    case _: IO.die(Unit, 2, "usage: persistence-tests [outcome]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(List.tail(&1, String, args))
