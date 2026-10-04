function mc_presentation_configure() {
  throw new Error("player_presentation requires the native macOS presentation adapter");
}
function mc_presentation_measure() {
  throw new Error("player_presentation requires the native macOS presentation adapter");
}
io_eff(CID(Native.configure), mc_presentation_configure);
io_eff(CID(Native.measure), mc_presentation_measure);
function mc_presentation_milliseconds() {
  return Math.floor(performance.now()) >>> 0;
}
io_eff(CID(Native.milliseconds), mc_presentation_milliseconds);
