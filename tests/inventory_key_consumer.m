// Hidden native boundary harness. The runner inserts the exact pinned Base view
// and actual project adapter at the two markers below, without a second adapter.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
typedef uint32_t u32;
typedef uint64_t u64;
typedef uintptr_t Term;
typedef struct { int unused; } Env;
typedef struct { int unused; } IoWork;
#define CID_WINDOW_OPEN 1
#define CID_NATIVE_CONFIGURE 2
#define CID_NATIVE_MEASURE 3
#define CID_NATIVE_MILLISECONDS 4
#define CID_NATIVE_INVENTORY_KEYS 13
#define CID_KEY 5
#define CID_MOUSE 6
#define CID_MOVE 7
#define CID_LOOK 8
#define CID_SCROLL 9
#define CID_CLOSE 10
#define CID_TRUE 11
#define CID_FALSE 12
static u32 f32_rewrap(float value) { u32 word; memcpy(&word,&value,4); return word; }
static Term term_pak(u32 tag, u32 payload) { return tag; }
static Term io_hand_v(Term value) { return value; }
static u32 term_aux(Term value) { return (u32)value; }
static Term io_tup(Env env, Term a, Term b) {
  Term* pair = calloc(2,sizeof(Term)); pair[0] = a; pair[1] = b; return (Term)pair;
}
static void io_eff(u32 effect, Term(*run)(Env,Term*,IoWork*),int flags) {}
// MC_BASE_SOURCE
// MC_ADAPTER_SOURCE

static unsigned checks;
static unsigned spaces;
static void require(BOOL passed, const char* name) {
  if (!passed) { fprintf(stderr,"native boundary failed: %s\n",name); exit(1); }
  checks += 1;
}
static void words(MCPlayerPresentationView* view,const u32* expected,NSUInteger count,const char* name) {
  if (view->evs.length != count * 5 * sizeof(u32) ||
      (count && memcmp(view->evs.bytes,expected,count * 5 * sizeof(u32)) != 0)) {
    const u32* actual = view->evs.bytes;
    for (NSUInteger i = 0; i < view->evs.length / sizeof(u32); i++)
      fprintf(stderr,"%u%s",actual[i],(i+1)%5 ? " " : "\n");
  }
  require(view->evs.length == count * 5 * sizeof(u32),name);
  if (count) require(memcmp(view->evs.bytes,expected,count * 5 * sizeof(u32)) == 0,name);
  view->evs.length = 0;
}
static void sample(MCPlayerPresentationView* view,const char* label) {
  printf("{\"case\":\"%s\",\"words\":[",label);
  const u32* words = view->evs.bytes;
  for (NSUInteger i = 0; i < view->evs.length/sizeof(u32); i++)
    printf("%s%u",i ? "," : "",words[i]);
  printf("]}\n");
  view->evs.length = 0;
}

static NSEvent* key(NSWindow* win,unsigned short code,NSString* text,BOOL down,BOOL repeat,NSUInteger flags) {
  return [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp
    location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:win.windowNumber
    context:nil characters:text charactersIgnoringModifiers:text isARepeat:repeat keyCode:code];
}
static NSEvent* modifier(NSWindow* win,unsigned short code,NSUInteger flags) {
  return [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint
    modifierFlags:flags timestamp:0 windowNumber:win.windowNumber context:nil
    characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:code];
}
static NSEvent* mouse(NSWindow* win,NSView* view,CGFloat x,CGFloat y,NSEventType type) {
  NSPoint point = [view convertPoint:NSMakePoint(x,y) toView:nil];
  return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0
    windowNumber:win.windowNumber context:nil eventNumber:1 clickCount:1 pressure:0];
}

int main(void) {
  @autoreleasepool {
    require(getenv("BEND_MINECRAFT_LAUNCH_MODE") && mc_presentation_hidden(),"hidden launch required");
    pid_t foreground = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    id observer = [NSWorkspace.sharedWorkspace.notificationCenter
      addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification object:nil queue:nil
      usingBlock:^(NSNotification* notification) { spaces += 1; }];
    [NSApplication sharedApplication];
    NSApp.activationPolicy = NSApplicationActivationPolicyProhibited;
    [NSApp finishLaunching];
    NSWindow* win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,320,180)
      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
      backing:NSBackingStoreBuffered defer:NO];
    win.releasedWhenClosed = NO;
    BendView* old = [[BendView alloc] initWithFrame:NSMakeRect(0,0,320,180)];
    old->evs = [NSMutableData new]; old->flags = NSEventModifierFlagShift;
    old.wantsLayer = YES;
    CAMetalLayer* originalLayer = (CAMetalLayer*)old.layer;
    originalLayer.drawableSize = CGSizeMake(128,128);
    win.contentView = old; win.delegate = old; [win makeFirstResponder:old];
    [old push:CID_CLOSE a:0 b:0 c:0 d:0];
    Term fields[6] = {(Term)(__bridge void*)win,1920,1080,CID_TRUE,CID_TRUE,CID_TRUE};
    Env env = {0};
    require(mc_presentation_configure_run(env,fields,NULL) == fields[0],"affine configure owner");
    MCPlayerPresentationView* view = (MCPlayerPresentationView*)win.contentView;
    require([view isKindOfClass:MCPlayerPresentationView.class],"project view installed");
    require(view.layer == originalLayer && view->evs == old->evs,"layer and queued event retained");
    require(win.delegate == view && win.firstResponder == view,"delegate and responder installed");
    words(view,(u32[]){CID_CLOSE,0,0,0,0},1,"queued close retained during installation");
    mc_presentation_install(win);
    require(win.contentView == view,"installation idempotence");
    require(NSEqualSizes(view.bounds.size,NSMakeSize(320,180)),"hidden ignores human/fullscreen geometry request");
    require(!(win.styleMask & NSWindowStyleMaskFullScreen),"hidden avoids fullscreen transition");
    [view setGrab:YES];
    require(!view->grab,"hidden unfocused capture refused");
    [view setGrab:NO]; [view setGrab:NO];
    require(!view->grab,"repeated release safe");

    [view mouseDown:mouse(win,view,17.9,42.1,NSEventTypeLeftMouseDown)];
    [view mouseUp:mouse(win,view,-1,42,NSEventTypeLeftMouseUp)];
    [view mouseDragged:mouse(win,view,400,42,NSEventTypeLeftMouseDragged)];
    [view mouseUp:mouse(win,view,319,180,NSEventTypeLeftMouseUp)];
    [view rightMouseDown:mouse(win,view,319.9,179.9,NSEventTypeRightMouseDown)];
    words(view,(u32[]){CID_MOUSE,17,42,0,1,CID_MOUSE,320,42,0,0,
      CID_MOVE,320,42,0,0,CID_MOUSE,319,180,0,0,CID_MOUSE,319,179,0,1},5,
      "content points and outside sentinels");
    CGEventRef right = CGEventCreateMouseEvent(NULL,kCGEventRightMouseDown,
      CGPointMake(10,10),kCGMouseButtonRight);
    NSEvent* rightEvent = [NSEvent eventWithCGEvent:right];
    require(rightEvent.buttonNumber == 1,"native right-button payload");
    NSPoint rightAt = [view at:rightEvent];
    [view rightMouseDown:rightEvent];
    words(view,(u32[]){CID_MOUSE,(u32)rightAt.x,(u32)rightAt.y,1,1},1,"right-button payload retained");
    CFRelease(right);
    [view mouseUp:mouse(win,view,0,-1,NSEventTypeLeftMouseUp)];
    [view mouseUp:mouse(win,view,320,179,NSEventTypeLeftMouseUp)];
    words(view,(u32[]){CID_MOUSE,0,180,0,0,CID_MOUSE,320,179,0,0},2,
      "top and exact right edge are outside");
    CGEventRef movement = CGEventCreateMouseEvent(NULL,kCGEventMouseMoved,
      CGPointMake(10,10),kCGMouseButtonLeft);
    CGEventSetIntegerValueField(movement,kCGMouseEventDeltaX,3);
    CGEventSetIntegerValueField(movement,kCGMouseEventDeltaY,-7);
    NSEvent* movementEvent = [NSEvent eventWithCGEvent:movement];
    require(movementEvent.deltaX == 3 && movementEvent.deltaY == -7,"native signed relative payload");
    // Fixture field only: no cursor hide/warp/disassociation is performed.
    view->grab = YES;
    [view mouseMoved:movementEvent];
    view->grab = NO;
    words(view,(u32[]){CID_LOOK,f32_rewrap(3),f32_rewrap(-7),0,0},1,"relative Look payload retained");
    CFRelease(movement);
    // Drawable pixel extent must never become the pointer content-point bound.
    originalLayer.drawableSize = CGSizeMake(640,360);
    [view mouseUp:mouse(win,view,321,90,NSEventTypeLeftMouseUp)];
    words(view,(u32[]){CID_MOUSE,320,90,0,0},1,"Retina pointer boundary remains in points");
    [view keyDown:key(win,13,@"w",YES,NO,0)];
    [view keyDown:key(win,13,@"w",YES,YES,0)];
    [view keyDown:key(win,13,@"W",YES,YES,NSEventModifierFlagShift)];
    [view keyUp:key(win,13,@"z",NO,NO,0)];
    [view keyUp:key(win,13,@"z",NO,NO,0)];
    words(view,(u32[]){CID_KEY,119,1,0,0,CID_KEY,119,0,0,0},2,
      "physical release retains down code and repeats do not toggle");
    [view keyDown:key(win,13,@"W",YES,NO,NSEventModifierFlagShift)];
    [view keyUp:key(win,13,@"w",NO,NO,0)];
    words(view,(u32[]){CID_KEY,119,1,0,0,CID_KEY,119,0,0,0},2,"uppercase character convention retained");
    [view keyDown:key(win,13,@"w",YES,NO,0)];
    [view keyDown:key(win,14,@"w",YES,NO,0)];
    [view keyUp:key(win,13,@"q",NO,NO,0)];
    words(view,(u32[]){CID_KEY,119,1,0,0},1,"duplicate logical keys stay held");
    [view keyUp:key(win,14,@"q",NO,NO,0)];
    words(view,(u32[]){CID_KEY,119,0,0,0},1,"last physical release clears logical key");

    [view flagsChanged:modifier(win,56,NX_SHIFTMASK|NX_DEVICELSHIFTKEYMASK)];
    [view flagsChanged:modifier(win,60,NX_SHIFTMASK|NX_DEVICELSHIFTKEYMASK|NX_DEVICERSHIFTKEYMASK)];
    [view flagsChanged:modifier(win,56,NX_SHIFTMASK|NX_DEVICERSHIFTKEYMASK)];
    [view flagsChanged:modifier(win,60,0)];
    words(view,(u32[]){CID_KEY,65592,1,0,0,CID_KEY,65596,1,0,0,
      CID_KEY,65592,0,0,0,CID_KEY,65596,0,0,0},4,"simultaneous sided Shift transitions");
    for (unsigned short code = 54; code <= 63; code++) {
      NSUInteger mask[] = {NX_DEVICERCMDKEYMASK,NX_DEVICELCMDKEYMASK,NX_DEVICELSHIFTKEYMASK,
        NX_ALPHASHIFTMASK,NX_DEVICELALTKEYMASK,NX_DEVICELCTLKEYMASK,
        NX_DEVICERSHIFTKEYMASK,NX_DEVICERALTKEYMASK,NX_DEVICERCTLKEYMASK,NX_SECONDARYFNMASK};
      [view flagsChanged:modifier(win,code,mask[code-54])];
      [view flagsChanged:modifier(win,code,0)];
      words(view,(u32[]){CID_KEY,65536+code,1,0,0,CID_KEY,65536+code,0,0,0},2,
        "native modifier masks match physical keys");
    }
    [view keyDown:key(win,13,@"w",YES,NO,0)];
    [view flagsChanged:modifier(win,56,NX_SHIFTMASK|NX_DEVICELSHIFTKEYMASK)];
    words(view,(u32[]){CID_KEY,119,1,0,0,CID_KEY,65592,1,0,0},2,"held keys before focus loss");
    [view windowDidResignKey:nil];
    [view windowDidResignKey:nil];
    words(view,(u32[]){CID_KEY,119,0,0,0,CID_KEY,65592,0,0,0},2,"focus loss releases once");
    require(view->flags == 0,"focus loss clears stale flags");
    [view keyDown:key(win,13,@"w",YES,YES,0)];
    words(view,NULL,0,"OS repeat after release does not become a fresh press");
    [view flagsChanged:modifier(win,56,NX_SHIFTMASK|NX_DEVICELSHIFTKEYMASK)];
    words(view,(u32[]){CID_KEY,65592,1,0,0},1,"modifier re-press after inactive release");
    [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidResignActiveNotification object:NSApp];
    words(view,(u32[]){CID_KEY,65592,0,0,0},1,"application notification releases cached input");
    [view keyDown:key(win,53,@"",YES,NO,0)];
    [view keyUp:key(win,53,@"",NO,NO,0)];
    words(view,(u32[]){CID_KEY,65589,1,0,0,CID_KEY,65589,0,0,0},2,"empty-character fallback unchanged");

    Term measured = mc_presentation_measure_run(env,fields,NULL);
    Term* pair = (Term*)measured;
    require(pair[0] == fields[0],"affine measure owner");
    Term* width = (Term*)pair[1]; Term* height = (Term*)width[1];
    Term* points = (Term*)height[1];
    require(width[0] == 640 && height[0] == 360 && points[0] == 320 && points[1] == 180,
      "hidden measure reports drawable and content independently");
    [win setContentSize:NSMakeSize(500,240)];
    require(NSEqualSizes(view.bounds.size,NSMakeSize(500,240)),"resized content view follows window");
    mc_presentation_sync(win);
    NSSize backing = [view convertRectToBacking:view.bounds].size;
    require(originalLayer.drawableSize.width == fmax(4,floor(backing.width)) &&
      originalLayer.drawableSize.height == fmax(4,floor(backing.height)),"drawable uses actual backing conversion");
    require(win.contentMaxSize.width == 4096/mc_presentation_scale(win),"maximum tracks current backing scale");
    [view keyDown:key(win,13,@"w",YES,NO,0)];
    view->evs.length = 0;
    [win close];
    words(view,(u32[]){CID_KEY,119,0,0,0},1,"close releases cached input");
    // Opt-in uses a second hidden native owner; the full legacy boundary above
    // remains byte-identical and never enabled the physical marker channel.
    NSWindow* keyedWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,320,180)
      styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    keyedWin.releasedWhenClosed = NO;
    BendView* keyedOld = [[BendView alloc] initWithFrame:NSMakeRect(0,0,320,180)];
    keyedOld->evs = [NSMutableData new]; keyedOld.wantsLayer = YES;
    keyedWin.contentView = keyedOld; keyedWin.delegate = keyedOld;
    [keyedWin makeFirstResponder:keyedOld];
    mc_presentation_install(keyedWin);
    MCPlayerPresentationView* keyed = (MCPlayerPresentationView*)keyedWin.contentView;
    Term keyedFields[] = {(Term)(__bridge void*)keyedWin};
    Term* enabled = (Term*)mc_presentation_inventory_keys_run(env,keyedFields,NULL);
    require(enabled[0] == keyedFields[0] && enabled[1] == CID_TRUE,"physical effect retains affine window and reports actual capability");
    mc_presentation_inventory_keys_run(env,keyedFields,NULL);
    words(keyed,NULL,0,"physical channel enable idempotent");
    [keyed mouseMoved:mouse(keyedWin,keyed,105,97,NSEventTypeMouseMoved)];
    [keyed keyDown:key(keyedWin,3,@"q",YES,NO,0)];
    [keyed keyDown:key(keyedWin,3,@"q",YES,YES,0)];
    [keyed keyUp:key(keyedWin,3,@"z",NO,NO,0)];
    sample(keyed,"physical-f-alternate-character");
    unsigned short hotbar[] = {18,19,20,21,23,22,26,28,25};
    for (unsigned i = 0; i < 9; i++) {
      [keyed mouseMoved:mouse(keyedWin,keyed,105,97,NSEventTypeMouseMoved)];
      [keyed keyDown:key(keyedWin,hotbar[i],@"w",YES,NO,NSEventModifierFlagShift)];
      [keyed keyUp:key(keyedWin,hotbar[i],@"z",NO,NO,0)];
      char label[64]; snprintf(label,sizeof(label),"physical-digit-%u",i);
      sample(keyed,label);
    }
    [keyed mouseMoved:mouse(keyedWin,keyed,105,97,NSEventTypeMouseMoved)];
    [keyed keyDown:key(keyedWin,12,@"f",YES,NO,0)];
    [keyed keyUp:key(keyedWin,12,@"f",NO,NO,0)];
    sample(keyed,"rebound-q-character-f");
    [keyed keyDown:key(keyedWin,3,@"q",YES,NO,0)];
    [keyed keyDown:key(keyedWin,18,@"q",YES,NO,0)];
    [keyed keyUp:key(keyedWin,3,@"z",NO,NO,0)];
    [keyed keyUp:key(keyedWin,18,@"z",NO,NO,0)];
    sample(keyed,"duplicate-logical-holds");
    [keyed keyDown:key(keyedWin,3,@"q",YES,NO,0)];
    [keyed keyDown:key(keyedWin,18,@"w",YES,NO,0)];
    keyed->evs.length = 0;
    [keyed windowDidResignKey:nil]; [keyed windowDidResignKey:nil];
    sample(keyed,"focus-loss-release");
    [keyed keyDown:key(keyedWin,53,@"",YES,NO,0)];
    [keyed keyUp:key(keyedWin,53,@"",NO,NO,0)];
    sample(keyed,"escape-empty-character");
    [keyedWin close];
    require(!keyedWin.isVisible && !keyedWin.isKeyWindow,"physical channel window remains hidden");
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    require(!win.isVisible && !win.isKeyWindow && !win.isMainWindow && !NSApp.isActive,
      "hidden window never ordered or focused");
    require(NSApp.activationPolicy == NSApplicationActivationPolicyProhibited,"Prohibited policy retained");
    require(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier == foreground,
      "foreground application retained");
    require(spaces == 0,"no Space-change notification");
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
    printf("{\"status\":\"passed\",\"assertions\":%u,\"frontmost_pid\":%d,\"space_changes\":%u,"
      "\"window_visible\":false,\"window_key\":false,\"app_active\":false,\"actual_backing_scale\":%.2f}\n",
      checks,foreground,spaces,mc_presentation_scale(win));
  }
  return 0;
}
