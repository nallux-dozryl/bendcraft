// Browser monotonic clock; precision follows the browser's exposed timer.
function cooking_entities_nanoseconds() {
  const n = BigInt(Math.trunc(performance.now() * 1000000));
  return io_tup((n >> 32n) & 0xffffffffn, n & 0xffffffffn);
}
io_eff(CID(Native.nanoseconds), cooking_entities_nanoseconds);
