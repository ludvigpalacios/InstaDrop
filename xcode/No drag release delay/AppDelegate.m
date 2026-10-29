//
//  AppDelegate.m
//  No drag release delay
//
//  Created by Pravdomil Toman on 16/12/2017.
//  Copyright © 2017 Pravdomil Toman. All rights reserved.
//
//  Newer macOS ignores a synthetic mouse-up while its own tap-to-drag logic is
//  holding the button, so this version does tap-to-drag itself:
//
//    tap, then touch again quickly  ->  mouse down
//    move finger                    ->  drag events
//    lift finger                    ->  mouse up, immediately
//
//  For this to work, turn OFF "Use trackpad for dragging" in
//  System Settings > Accessibility > Pointer Control > Trackpad Options.
//  Keep "Tap to click" on.
//
#import "AppDelegate.h"
#import "MultiTouch.h"

// ---- Tuning (trackpad positions are normalized 0...1; time is in seconds) ----
static const double kTapMaxDuration   = 0.25;  // a touch shorter than this can be a tap
static const double kTapMaxMove       = 0.03;  // ...if it moved less than this
static const double kDoubleTapWindow  = 0.35;  // second touch must start within this after the tap
static const double kDragStartMove    = 0.012; // second touch becomes a drag after moving this much
static const double kDragStartHold    = 0.18;  // ...or after being held this long

typedef NS_ENUM(int, Phase) {
    PhaseIdle,          // nothing touching
    PhaseFirstTouch,    // one finger down, might become a tap
    PhaseDragCandidate, // second touch shortly after a tap, not yet a drag
    PhaseDragging,      // mouse button is held down by us
    PhaseIgnore         // multi-finger or non-tap gesture, wait until fingers lift
};

static Phase phase = PhaseIdle;
static double touchStart = 0;
static mtPoint startPos;
static double maxMove = 0;
static double lastTapEnd = -100;
static volatile bool dragging = false;

static CFArrayRef devices = NULL;
static CFMachPortRef moveTap = NULL;
static NSObject *stateLock;

// ---- Event posting ----

static void postMouseEvent(CGEventType eventType) {
    if (!AXIsProcessTrusted()) {
        NSLog(@"NOT posting: app is not trusted for Accessibility");
        return;
    }

    CGEventRef locEvent = CGEventCreate(NULL);
    CGPoint location = CGEventGetLocation(locEvent);
    CFRelease(locEvent);

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef event = CGEventCreateMouseEvent(source, eventType, location, kCGMouseButtonLeft);
    if (event) {
        CGEventSetIntegerValueField(event, kCGMouseEventClickState, 1);
        CGEventPost(kCGHIDEventTap, event);
        CFRelease(event);
    }
    if (source) CFRelease(source);
}

static int convertedMoves = 0;

// While we hold the button, the system may still report plain "mouse moved" events.
// Apps need "mouse dragged" events, so convert them. Also logs button events so we
// can see whether our posted events actually enter the event stream.
static CGEventRef moveTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        NSLog(@"Event tap was disabled by the system, re-enabling");
        if (moveTap) CGEventTapEnable(moveTap, true);
        return event;
    }

    if (type == kCGEventMouseMoved && dragging) {
        CGEventSetType(event, kCGEventLeftMouseDragged);
        convertedMoves++;
    } else if (type == kCGEventLeftMouseDown || type == kCGEventLeftMouseUp) {
        NSLog(@"Tap saw %@ (source pid %lld, clickState %lld)",
              type == kCGEventLeftMouseDown ? @"LeftMouseDown" : @"LeftMouseUp",
              CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID),
              CGEventGetIntegerValueField(event, kCGMouseEventClickState));
    } else if (type == kCGEventLeftMouseDragged && dragging) {
        convertedMoves++; // already a drag event (system converted it for us)
    }
    return event;
}

static void installMoveTap(void) {
    moveTap = CGEventTapCreate(kCGSessionEventTap,
                               kCGHeadInsertEventTap,
                               kCGEventTapOptionDefault,
                               CGEventMaskBit(kCGEventMouseMoved) | CGEventMaskBit(kCGEventLeftMouseDown) |
                               CGEventMaskBit(kCGEventLeftMouseUp) | CGEventMaskBit(kCGEventLeftMouseDragged),
                               moveTapCallback,
                               NULL);
    if (!moveTap) {
        NSLog(@"Could not create event tap (Accessibility permission missing?)");
        return;
    }
    CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, moveTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
    CFRelease(src);
    CGEventTapEnable(moveTap, true);
    NSLog(@"Event tap installed");
}

// ---- Gesture state machine ----

static int callback(MTDeviceRef device, Finger *data, int nFingers, double timestamp, int frame) {
    // Count only fingers in contact (4 = making touch, 5 = touching); hovering and
    // lingering fingers are also reported in nFingers.
    int touching = 0;
    Finger *first = NULL;
    for (int i = 0; i < nFingers; i++) {
        if (data[i].state == 4 || data[i].state == 5) {
            if (!first) first = &data[i];
            touching++;
        }
    }

    @synchronized (stateLock) {
        double move = 0;
        if (first && (phase == PhaseFirstTouch || phase == PhaseDragCandidate)) {
            float dx = first->normalized.pos.x - startPos.x;
            float dy = first->normalized.pos.y - startPos.y;
            move = sqrt(dx * dx + dy * dy);
            if (move > maxMove) maxMove = move;
        }

        switch (phase) {
            case PhaseIdle:
                if (touching == 1) {
                    touchStart = timestamp;
                    startPos = first->normalized.pos;
                    maxMove = 0;
                    if (timestamp - lastTapEnd < kDoubleTapWindow) {
                        phase = PhaseDragCandidate;
                    } else {
                        phase = PhaseFirstTouch;
                    }
                } else if (touching > 1) {
                    lastTapEnd = -100;
                    phase = PhaseIgnore;
                }
                break;

            case PhaseFirstTouch:
                if (touching > 1) {
                    lastTapEnd = -100;
                    phase = PhaseIgnore;
                } else if (touching == 0) {
                    if (timestamp - touchStart < kTapMaxDuration && maxMove < kTapMaxMove) {
                        lastTapEnd = timestamp; // a tap; a quick second touch now starts a drag
                    } else {
                        lastTapEnd = -100;
                    }
                    phase = PhaseIdle;
                }
                break;

            case PhaseDragCandidate:
                if (touching > 1) {
                    lastTapEnd = -100;
                    phase = PhaseIgnore;
                } else if (touching == 0) {
                    // Released without moving or holding: this was just a double tap,
                    // which the system turns into a double-click.
                    lastTapEnd = -100;
                    phase = PhaseIdle;
                } else if (maxMove > kDragStartMove || timestamp - touchStart > kDragStartHold) {
                    NSLog(@"Drag started");
                    convertedMoves = 0;
                    dragging = true;
                    postMouseEvent(kCGEventLeftMouseDown);
                    phase = PhaseDragging;
                }
                break;

            case PhaseDragging:
                if (touching == 0) {
                    NSLog(@"Drag ended -> mouse up (%d move/drag events seen during drag)", convertedMoves);
                    postMouseEvent(kCGEventLeftMouseUp);
                    dragging = false;
                    lastTapEnd = -100;
                    phase = PhaseIdle;
                }
                break;

            case PhaseIgnore:
                if (touching == 0) {
                    phase = PhaseIdle;
                }
                break;
        }
    }

    return 0;
}

static void registerCallback(void) {
    // MTDeviceCreateDefault() is unreliable on Apple Silicon Macs, so enumerate all devices.
    devices = MTDeviceCreateList();

    if (devices && CFArrayGetCount(devices) > 0) {
        for (CFIndex i = 0; i < CFArrayGetCount(devices); i++) {
            MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
            MTRegisterContactFrameCallback(dev, callback);
            MTDeviceStart(dev, 0);
        }
        NSLog(@"Registered %ld multitouch device(s)", (long)CFArrayGetCount(devices));
        return;
    }

    MTDeviceRef dev = MTDeviceCreateDefault();
    if (dev) {
        MTRegisterContactFrameCallback(dev, callback);
        MTDeviceStart(dev, 0);
    } else {
        NSLog(@"No multitouch device found");
    }
}

@implementation AppDelegate

- (void)awakeFromNib {
    self.statusBar = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusBar.button.title = @"⥺";
    self.statusBar.menu = _statusMenu;
}

- (IBAction)donate:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=BCL2X3AFQBAP2&item_name=No%20drag%20release%20delay%20beer"]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    stateLock = [NSObject new];

    NSDictionary *options = @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES };
    BOOL trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    NSLog(@"Accessibility trusted: %@", trusted ? @"YES" : @"NO");

    NSLog(@"Post-event access: %@, listen-event access: %@",
          CGPreflightPostEventAccess() ? @"YES" : @"NO",
          CGPreflightListenEventAccess() ? @"YES" : @"NO");

    installMoveTap();
    registerCallback();
}

@end
