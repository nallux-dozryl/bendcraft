// JavaScript has no native Base window. Keep the diagnostic boundary explicit.
function platform_observe() {
  return '{"native_macos":false}';
}
io_eff(CID(Platform.observe), platform_observe);

function platform_inspect(window) {
  return io_tup(window, '{"native_macos":false}');
}
io_eff(CID(Platform.inspect), platform_inspect);
