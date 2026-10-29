//
//  AppDelegate.m
//  InstaDrop
//
//  Implements tap-to-drag itself so the button is released the instant the
//  finger lifts:
//
//    tap, then touch again quickly  ->  mouse down
//    move finger                    ->  drag events
//    lift finger                    ->  mouse up
//
//  Requires "Use trackpad for dragging" to be OFF in System Settings >
//  Accessibility > Pointer Control > Trackpad Options (Tap to click stays on),
//  and Accessibility permission for this app.
//
#import "AppDelegate.h"
#import "MultiTouch.h"

// Tuning. Trackpad positions are normalized (0...1), times are in seconds.
static const double kTapMaxDuration  = 0.20;   // a touch shorter than this can be a tap...
static const double kTapMaxMove      = 0.03;   // ...if it moved less than this
static const double kDoubleTapWindow = 0.25;   // second touch must start this soon after a tap
static const double kDragStartMove   = 0.004;  // second touch becomes a drag after moving this much...
static const double kDragStartHold   = 0.10;   // ...or after being held this long
static const double kNoTap           = -100;

// Link opened by the "Donate" menu item (GitHub Sponsors, Ko-fi, PayPal.me, ...).
// Leave empty to hide the menu item.
static NSString *const kDonateURL = @"";

typedef NS_ENUM(int, Phase) {
    PhaseIdle,           // no finger down
    PhaseFirstTouch,     // one finger down, may become a tap
    PhaseDragCandidate,  // touched again right after a tap, not yet a drag
    PhaseDragging,       // we are holding the mouse button
    PhaseIgnore          // multi-finger or non-tap touch; wait for all fingers to lift
};

static Phase phase = PhaseIdle;
static double touchStart;
static double lastTapEnd = kNoTap;
static double maxMove;
static mtPoint startPos;
static volatile bool dragging;

static CGEventSourceRef eventSource;
static CFMachPortRef moveTap;
static CFArrayRef devices;

#pragma mark - Events

static void postMouse(CGEventType type, CGPoint location, int64_t dx, int64_t dy) {
    CGEventRef event = CGEventCreateMouseEvent(eventSource, type, location, kCGMouseButtonLeft);
    if (!event) return;
    CGEventSetIntegerValueField(event, kCGMouseEventClickState, 1);
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaX, dx);
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaY, dy);
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

static CGPoint cursorLocation(void) {
    CGEventRef event = CGEventCreate(NULL);
    CGPoint location = CGEventGetLocation(event);
    CFRelease(event);
    return location;
}

// While we hold the button the system still reports plain mouse-move events.
// Replace them with real drag events so apps and window dragging follow along.
static CGEventRef moveTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(moveTap, true);
        return event;
    }
    if (type == kCGEventMouseMoved && dragging) {
        postMouse(kCGEventLeftMouseDragged,
                  CGEventGetLocation(event),
                  CGEventGetIntegerValueField(event, kCGMouseEventDeltaX),
                  CGEventGetIntegerValueField(event, kCGMouseEventDeltaY));
        return NULL;
    }
    return event;
}

static void installMoveTap(void) {
    moveTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                               CGEventMaskBit(kCGEventMouseMoved), moveTapCallback, NULL);
    if (!moveTap) {
        NSLog(@"Could not create event tap; is Accessibility permission granted?");
        return;
    }
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, moveTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);
}

#pragma mark - Gesture detection

static int touchCallback(MTDeviceRef device, Finger *data, int nFingers, double timestamp, int frame) {
    // nFingers also includes hovering/lingering fingers; only count real contact
    // (state 4 = making touch, 5 = touching).
    int touching = 0;
    Finger *first = NULL;
    for (int i = 0; i < nFingers; i++) {
        if (data[i].state == 4 || data[i].state == 5) {
            if (!first) first = &data[i];
            touching++;
        }
    }

    @synchronized ([AppDelegate class]) {
        if (first && (phase == PhaseFirstTouch || phase == PhaseDragCandidate)) {
            float dx = first->normalized.pos.x - startPos.x;
            float dy = first->normalized.pos.y - startPos.y;
            maxMove = MAX(maxMove, sqrt(dx * dx + dy * dy));
        }

        // Any second finger cancels a pending tap or drag start.
        if (touching > 1 && phase != PhaseDragging) {
            lastTapEnd = kNoTap;
            phase = PhaseIgnore;
            return 0;
        }

        switch (phase) {
            case PhaseIdle:
                if (touching == 1) {
                    touchStart = timestamp;
                    startPos = first->normalized.pos;
                    maxMove = 0;
                    phase = (timestamp - lastTapEnd < kDoubleTapWindow) ? PhaseDragCandidate : PhaseFirstTouch;
                }
                break;

            case PhaseFirstTouch:
                if (touching == 0) {
                    BOOL isTap = timestamp - touchStart < kTapMaxDuration && maxMove < kTapMaxMove;
                    lastTapEnd = isTap ? timestamp : kNoTap;
                    phase = PhaseIdle;
                }
                break;

            case PhaseDragCandidate:
                if (touching == 0) {
                    // Plain double tap: leave it to the system (double-click).
                    lastTapEnd = kNoTap;
                    phase = PhaseIdle;
                } else if (maxMove > kDragStartMove || timestamp - touchStart > kDragStartHold) {
                    dragging = true;
                    postMouse(kCGEventLeftMouseDown, cursorLocation(), 0, 0);
                    phase = PhaseDragging;
                }
                break;

            case PhaseDragging:
                if (touching == 0) {
                    postMouse(kCGEventLeftMouseUp, cursorLocation(), 0, 0);
                    dragging = false;
                    lastTapEnd = kNoTap;
                    phase = PhaseIdle;
                }
                break;

            case PhaseIgnore:
                if (touching == 0) phase = PhaseIdle;
                break;
        }
    }
    return 0;
}

static void startTouchTracking(void) {
    // MTDeviceCreateDefault() is unreliable on Apple Silicon; use every device.
    devices = MTDeviceCreateList();
    for (CFIndex i = 0; devices && i < CFArrayGetCount(devices); i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        MTRegisterContactFrameCallback(device, touchCallback);
        MTDeviceStart(device, 0);
    }
}

#pragma mark - App

@implementation AppDelegate

- (void)awakeFromNib {
    self.statusBar = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSImage *icon = [NSImage imageNamed:@"StatusIcon"];
    icon.size = NSMakeSize(18, 18);
    self.statusBar.button.image = icon;
    self.statusBar.menu = _statusMenu;

    if (kDonateURL.length == 0) {
        NSInteger index = [_statusMenu indexOfItemWithTarget:self andAction:@selector(donate:)];
        if (index >= 0) {
            [_statusMenu removeItemAtIndex:index];
            if (index < _statusMenu.numberOfItems && _statusMenu.itemArray[index].isSeparatorItem) {
                [_statusMenu removeItemAtIndex:index]; // the separator that followed it
            }
        }
    }
}

- (IBAction)donate:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kDonateURL]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Prompts for Accessibility permission, needed to post events and run the tap.
    NSDictionary *options = @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES };
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);

    eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    installMoveTap();
    startTouchTracking();
}

@end
