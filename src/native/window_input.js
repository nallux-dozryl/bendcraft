function mc_window_input_status(window) {
  throw new Error("window_input.Native.status requires the native macOS client");
}
io_eff(CID(Native.status), mc_window_input_status);
