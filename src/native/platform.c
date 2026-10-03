// Native launch observations only. No window creation or game implementation.
#ifdef __OBJC__
#import <AppKit/AppKit.h>

static unsigned platform_space_events = 0;
static id platform_space_observer;

static void platform_watch_spaces(void) {
  if (platform_space_observer == nil) {
    platform_space_observer = [NSWorkspace.sharedWorkspace.notificationCenter
      addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification object:nil
      queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note) {
        platform_space_events += 1;
      }];
  }
}

static int platform_frontmost_pid(void) {
  return NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
}
#endif

#ifdef CID(Platform.observe)
static Term platform_observe_run(Env e, Term* f, IoWork* w) {
  char text[256];
#ifdef __OBJC__
  platform_watch_spaces();
  snprintf(text, sizeof text,
    "{\"native_macos\":true,\"pid\":%d,\"frontmost_pid\":%d,\"space_change_notifications\":%u}",
    getpid(), platform_frontmost_pid(), platform_space_events);
#else
  snprintf(text, sizeof text, "{\"native_macos\":false}");
#endif
  return io_str(e, text, strlen(text));
}

static void __attribute__((constructor)) platform_observe_use(void) {
  io_eff(CID(Platform.observe), platform_observe_run, 0);
}
#endif

#ifdef CID(Platform.inspect)
static Term platform_inspect_run(Env e, Term* f, IoWork* w) {
  char text[512];
#ifdef __OBJC__
  NSWindow* win = (__bridge NSWindow*)(void*)io_hand_v(f[0]);
  snprintf(text, sizeof text,
    "{\"native_macos\":true,\"pid\":%d,\"frontmost_pid\":%d,"
    "\"space_change_notifications\":%u,\"visible\":%s,\"key\":%s,"
    "\"main\":%s,\"app_active\":%s,\"activation_policy\":%ld,"
    "\"on_active_space\":%s,\"window_number\":%ld}",
    getpid(), platform_frontmost_pid(), platform_space_events,
    win.isVisible ? "true" : "false", win.isKeyWindow ? "true" : "false",
    win.isMainWindow ? "true" : "false", NSApp.isActive ? "true" : "false",
    (long)NSApp.activationPolicy, win.isOnActiveSpace ? "true" : "false",
    (long)win.windowNumber);
#else
  snprintf(text, sizeof text, "{\"native_macos\":false}");
#endif
  return io_tup(e, f[0], io_str(e, text, strlen(text)));
}

static void __attribute__((constructor)) platform_inspect_use(void) {
  io_eff(CID(Platform.inspect), platform_inspect_run, 0);
}
#endif
