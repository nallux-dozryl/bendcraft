// Project-owned AppKit presentation adapter; Base/guarded transform stay pinned.
#include <time.h>
#ifdef __OBJC__
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#endif

#ifdef CID(Native.milliseconds)
static Term mc_presentation_milliseconds_run(Env e, Term* f, IoWork* w) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (u32)((u64)now.tv_sec * 1000 + now.tv_nsec / 1000000);
}
static void __attribute__((constructor)) mc_presentation_milliseconds_use(void) {
  io_eff(CID(Native.milliseconds), mc_presentation_milliseconds_run, 0);
}
#endif

#ifdef CID(Native.configure)
static Term mc_presentation_configure_run(Env e, Term* f, IoWork* w) {
#ifdef __OBJC__
  NSWindow* win = (__bridge NSWindow*)(void*)io_hand_v(f[0]);
  if (term_aux(f[5]) == CID(True)) {
    NSScreen* screen = win.screen ?: NSScreen.mainScreen;
    CGFloat scale = screen.backingScaleFactor;
    if (scale < 1) scale = 1;
    win.styleMask |= NSWindowStyleMaskResizable;
    win.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    win.contentMinSize = NSMakeSize(4, 4);
    win.contentMaxSize = NSMakeSize(4096 / scale, 4096 / scale);
    BOOL native = term_aux(f[3]) == CID(True);
    BOOL fullscreen = term_aux(f[4]) == CID(True);
    NSSize size = native ? (fullscreen ? screen.frame.size : screen.visibleFrame.size)
      : NSMakeSize((u32)f[1] / scale, (u32)f[2] / scale);
    [win setContentSize:size];
    if (fullscreen && !(win.styleMask & NSWindowStyleMaskFullScreen)) {
      [win toggleFullScreen:nil];
    }
    CAMetalLayer* layer = (CAMetalLayer*)win.contentView.layer;
    layer.contentsScale = scale;
    layer.drawableSize = CGSizeMake(fmax(4, floor(win.contentView.bounds.size.width * scale)),
      fmax(4, floor(win.contentView.bounds.size.height * scale)));
  }
#endif
  return f[0];
}
static void __attribute__((constructor)) mc_presentation_configure_use(void) {
  io_eff(CID(Native.configure), mc_presentation_configure_run, 0);
}
#endif

#ifdef CID(Native.measure)
static Term mc_presentation_measure_run(Env e, Term* f, IoWork* w) {
  u32 width = 128, height = 128, point_width = 128, point_height = 128;
#ifdef __OBJC__
  NSWindow* win = (__bridge NSWindow*)(void*)io_hand_v(f[0]);
  NSView* view = win.contentView;
  CAMetalLayer* layer = (CAMetalLayer*)view.layer;
  point_width = (u32)fmax(1, floor(view.bounds.size.width));
  point_height = (u32)fmax(1, floor(view.bounds.size.height));
  // Hidden launch keeps the existing 512-point fixed Window and CPU128 fixture.
  const char* mode = getenv("BEND_MINECRAFT_LAUNCH_MODE");
  if (mode == NULL || strcmp(mode, "hidden") != 0) {
    CGFloat scale = (win.screen ?: NSScreen.mainScreen).backingScaleFactor;
    if (scale < 1) scale = 1;
    layer.contentsScale = scale;
    layer.drawableSize = CGSizeMake(fmax(4, floor(view.bounds.size.width * scale)),
      fmax(4, floor(view.bounds.size.height * scale)));
  }
  width = (u32)layer.drawableSize.width;
  height = (u32)layer.drawableSize.height;
#endif
  return io_tup(e, f[0], io_tup(e, width, io_tup(e, height,
    io_tup(e, point_width, point_height))));
}
static void __attribute__((constructor)) mc_presentation_measure_use(void) {
  io_eff(CID(Native.measure), mc_presentation_measure_run, 0);
}
#endif
