// Narrow observation of the pinned Base Window's AppKit focus/capture fields.
// It neither pumps input nor changes focus, capture, window or simulation state.
#ifdef __OBJC__
#import <AppKit/AppKit.h>
#endif

#ifdef CID(Native.status)
static Term mc_window_input_status_run(Env e, Term* f, IoWork* w) {
  bool focused = false;
  bool captured = false;
#ifdef __OBJC__
  NSWindow* win = (__bridge NSWindow*)(void*)io_hand_v(f[0]);
  focused = win.isKeyWindow && NSApp.isActive;
  captured = focused && [[win.contentView valueForKey:@"grab"] boolValue];
#endif
  Term focus = term_pak(focused ? CID(True) : CID(False), 0);
  Term capture = term_pak(captured ? CID(True) : CID(False), 0);
  return io_tup(e, f[0], io_tup(e, focus, capture));
}

static void __attribute__((constructor)) mc_window_input_status_use(void) {
  io_eff(CID(Native.status), mc_window_input_status_run, 0);
}
#endif
