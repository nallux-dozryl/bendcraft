// Project-owned AppKit presentation adapter; Base/guarded transform stay pinned.
#include <time.h>
#ifdef __OBJC__
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <IOKit/hidsystem/IOLLEvent.h>

static BOOL mc_presentation_hidden(void) {
  const char* mode = getenv("BEND_MINECRAFT_LAUNCH_MODE");
  return mode != NULL && strcmp(mode, "hidden") == 0;
}

static CGFloat mc_presentation_scale(NSWindow* win) {
  CGFloat scale = win.backingScaleFactor;
  return isfinite(scale) && scale >= 1 ? scale : 1;
}

// The layer belongs to Base Window.frame. Keep its current backing extent in
// sync before Bend allocates a frame, including after migration between screens.
static void mc_presentation_sync(NSWindow* win) {
  NSView* view = win.contentView;
  CGFloat scale = mc_presentation_scale(win);
  win.contentMinSize = NSMakeSize(4 / scale, 4 / scale);
  win.contentMaxSize = NSMakeSize(4096 / scale, 4096 / scale);
  if (!(win.styleMask & NSWindowStyleMaskFullScreen)) {
    NSSize size = view.bounds.size;
    NSSize bounded = NSMakeSize(fmin(size.width, 4096 / scale),
      fmin(size.height, 4096 / scale));
    if (!NSEqualSizes(size, bounded)) [win setContentSize:bounded];
  }
  NSSize backing = [view convertRectToBacking:view.bounds].size;
  CAMetalLayer* layer = (CAMetalLayer*)view.layer;
  layer.contentsScale = scale;
  layer.drawableSize = CGSizeMake(fmax(4, floor(backing.width)),
    fmax(4, floor(backing.height)));
}

#ifdef CID(Native.configure)
#ifdef CID(Window.open)
// Base supplies the event buffer, delegate methods and cursor ownership. This
// subclass repairs only the project input boundary; Base and its guarded launch
// transform remain unchanged. Physical key identity pairs a down with its up;
// opt-in consumers also receive a tagged hardware identity before the logical
// character. The tag records whether that character was actually queued.
@interface MCPlayerPresentationView : BendView {
  NSMutableDictionary<NSNumber*, NSNumber*>* heldKeys;
  BOOL inventoryPhysicalKeys;
}
- (void)releaseKeys;
- (void)enableInventoryPhysicalKeys;
@end

@implementation MCPlayerPresentationView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    heldKeys = [NSMutableDictionary new];
    [NSNotificationCenter.defaultCenter addObserver:self
      selector:@selector(applicationResigned:)
      name:NSApplicationDidResignActiveNotification object:nil];
  }
  return self;
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSPoint)at:(NSEvent*)event {
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  // U32 cannot carry a negative point. Use the same outside sentinel on either
  // side, and never clamp an outside release/drag onto a valid edge slot.
  CGFloat width = fmax(1, floor(self.bounds.size.width));
  CGFloat height = fmax(1, floor(self.bounds.size.height));
  return NSMakePoint(isfinite(p.x) && p.x >= 0 && p.x < width ? floor(p.x) : width,
    isfinite(p.y) && p.y >= 0 && p.y < height ? floor(p.y) : height);
}

- (BOOL)hasLogicalKey:(NSNumber*)code {
  return [heldKeys.allValues containsObject:code];
}

- (void)physicalKey:(unsigned short)physical logical:(u32)code down:(BOOL)down {
  NSNumber* identity = @(physical);
  NSNumber* prior = heldKeys[identity];
  if (down) {
    // OS repeat is held state, not another inventory/menu activation.
    if (prior != nil) return;
    NSNumber* logical = @(code);
    BOOL alreadyHeld = [self hasLogicalKey:logical];
    heldKeys[identity] = logical;
    if (inventoryPhysicalKeys)
      [self push:CID(Key) a:UINT32_C(2147483648) + (!alreadyHeld ? 65536 : 0) + physical b:YES c:0 d:0];
    if (!alreadyHeld) [self push:CID(Key) a:code b:YES c:0 d:0];
  } else if (prior != nil) {
    [heldKeys removeObjectForKey:identity];
    BOOL lastLogical = ![self hasLogicalKey:prior];
    if (inventoryPhysicalKeys)
      [self push:CID(Key) a:UINT32_C(2147483648) + (lastLogical ? 65536 : 0) + physical b:NO c:0 d:0];
    if (lastLogical)
      [self push:CID(Key) a:prior.unsignedIntValue b:NO c:0 d:0];
  }
}

- (void)key:(NSEvent*)event down:(BOOL)down {
  if (down && event.isARepeat) return;
  NSString* text = [event.charactersIgnoringModifiers lowercaseString];
  u32 code = text.length ? [text characterAtIndex:0] : 65536 + event.keyCode;
  [self physicalKey:event.keyCode logical:code down:down];
}

- (void)flagsChanged:(NSEvent*)event {
  NSUInteger mask = 0;
  switch (event.keyCode) {
    case 54: mask = NX_DEVICERCMDKEYMASK; break;
    case 55: mask = NX_DEVICELCMDKEYMASK; break;
    case 56: mask = NX_DEVICELSHIFTKEYMASK; break;
    case 57: mask = NX_ALPHASHIFTMASK; break;
    case 58: mask = NX_DEVICELALTKEYMASK; break;
    case 59: mask = NX_DEVICELCTLKEYMASK; break;
    case 60: mask = NX_DEVICERSHIFTKEYMASK; break;
    case 61: mask = NX_DEVICERALTKEYMASK; break;
    case 62: mask = NX_DEVICERCTLKEYMASK; break;
    case 63: mask = NX_SECONDARYFNMASK; break;
    default: break;
  }
  if (mask) [self physicalKey:event.keyCode logical:65536 + event.keyCode
    down:(event.modifierFlags & mask) != 0];
  flags = event.modifierFlags;
}

- (void)releaseKeys {
  NSArray<NSNumber*>* logical = [[NSSet setWithArray:heldKeys.allValues].allObjects
    sortedArrayUsingSelector:@selector(compare:)];
  if (inventoryPhysicalKeys) {
    NSArray<NSNumber*>* physical = [heldKeys.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber* code in physical)
      [self push:CID(Key) a:UINT32_C(2147483648) + code.unsignedShortValue b:NO c:0 d:0];
  }
  [heldKeys removeAllObjects];
  for (NSNumber* code in logical)
    [self push:CID(Key) a:code.unsignedIntValue b:NO c:0 d:0];
  flags = 0;
}

- (void)enableInventoryPhysicalKeys {
  if (inventoryPhysicalKeys) return;
  // Reconcile the old channel before changing its release contract. The live
  // presenter enables this before first capture; legacy consumers never opt in.
  [self releaseKeys];
  inventoryPhysicalKeys = YES;
}

- (void)setGrab:(BOOL)on {
  // An inactive application may still have a key window. Never let that race
  // disassociate the user's cursor while status reports capture=false.
  if (on && (mc_presentation_hidden() || !NSApp.isActive || !self.window.isKeyWindow))
    return;
  BOOL wasGrabbed = grab;
  [super setGrab:on];
  if (wasGrabbed && !grab) [self releaseKeys];
}

- (void)windowDidResignKey:(NSNotification*)notification {
  [super windowDidResignKey:notification];
  [self releaseKeys];
}

- (void)applicationResigned:(NSNotification*)notification {
  [self setGrab:NO];
  [self releaseKeys];
}

- (void)windowWillClose:(NSNotification*)notification {
  [self setGrab:NO];
  [self releaseKeys];
  [NSNotificationCenter.defaultCenter removeObserver:self];
}
@end

static void mc_presentation_install(NSWindow* win) {
  if ([win.contentView isKindOfClass:MCPlayerPresentationView.class]) return;
  BendView* previous = (BendView*)win.contentView;
  // Install before initial capture; release defensively for an existing owner.
  [previous setGrab:NO];
  MCPlayerPresentationView* view = [[MCPlayerPresentationView alloc]
    initWithFrame:previous.frame];
  view->evs = previous->evs;
  view->flags = 0;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  view.wantsLayer = YES;
  view.layer = previous.layer;
  win.contentView = view;
  win.delegate = view;
  [win makeFirstResponder:view];
}
#endif
#endif
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

#ifdef CID(Native.inventory_keys)
static Term mc_presentation_inventory_keys_run(Env e, Term* f, IoWork* w) {
  bool enabled = false;
#ifdef __OBJC__
#ifdef CID(Native.configure)
#ifdef CID(Window.open)
  NSWindow* win = (__bridge NSWindow*)(void*)io_hand_v(f[0]);
  if ([win.contentView isKindOfClass:MCPlayerPresentationView.class]) {
    [(MCPlayerPresentationView*)win.contentView enableInventoryPhysicalKeys];
    enabled = true;
  }
#endif
#endif
#endif
  return io_tup(e, f[0], term_pak(enabled ? CID(True) : CID(False), 0));
}
static void __attribute__((constructor)) mc_presentation_inventory_keys_use(void) {
  io_eff(CID(Native.inventory_keys), mc_presentation_inventory_keys_run, 0);
}
#endif

#ifdef CID(Native.configure)
static Term mc_presentation_configure_run(Env e, Term* f, IoWork* w) {
#ifdef __OBJC__
  NSWindow* win = (__bridge NSWindow*)(void*)io_hand_v(f[0]);
#ifdef CID(Window.open)
  mc_presentation_install(win);
#endif
  if (term_aux(f[5]) == CID(True) && !mc_presentation_hidden()) {
    NSScreen* screen = win.screen ?: NSScreen.mainScreen;
    CGFloat scale = mc_presentation_scale(win);
    win.styleMask |= NSWindowStyleMaskResizable;
    win.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    win.contentMinSize = NSMakeSize(4 / scale, 4 / scale);
    win.contentMaxSize = NSMakeSize(4096 / scale, 4096 / scale);
    BOOL native = term_aux(f[3]) == CID(True);
    BOOL fullscreen = term_aux(f[4]) == CID(True);
    NSSize size = native ? (fullscreen ? screen.frame.size : screen.visibleFrame.size)
      : NSMakeSize((u32)f[1] / scale, (u32)f[2] / scale);
    [win setContentSize:NSMakeSize(fmin(size.width,4096 / scale),
      fmin(size.height,4096 / scale))];
    // Configure may be used again by settings. Honor both requested modes.
    if (fullscreen != !!(win.styleMask & NSWindowStyleMaskFullScreen)) {
#ifdef CID(Window.open)
      [(BendView*)win.contentView setGrab:NO];
#endif
      [win toggleFullScreen:nil];
    }
    mc_presentation_sync(win);
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
  if (!mc_presentation_hidden()) mc_presentation_sync(win);
  point_width = (u32)fmax(1, floor(view.bounds.size.width));
  point_height = (u32)fmax(1, floor(view.bounds.size.height));
  // Hidden launch keeps the existing 512-point fixed Window and CPU128 fixture.
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
