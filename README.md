<img width="1254" height="1254" alt="InstaDroppng" src="https://github.com/user-attachments/assets/0f101cc1-0fea-417c-a307-ddaa8203e617" />
# InstaDrop

**Lift your finger, drop the item. Instantly.**

InstaDrop is a tiny menu bar app for macOS that removes the roughly one-second
"release delay" from trackpad tap-to-drag. Double-tap, drag, lift, and the item
drops right where you let go, with no waiting and no accidental extra movement.

> **Updated for macOS 27 Golden Gate** and Apple Silicon.

## The problem

With tap-to-drag, macOS keeps the drag alive for about a second after you lift
your finger, in case you want to continue. That means a file, window, or text
selection keeps following the cursor after you've let go.

Older tools worked around this by sending a mouse-up when your finger lifted.
On macOS Golden Gate the system ignores that, because its own drag logic is
still holding the button.

## How InstaDrop works

InstaDrop does the tap-to-drag itself instead of fighting the system's version:

| You do                                  | InstaDrop does                          |
| --------------------------------------- | --------------------------------------- |
| Tap, then touch again quickly           | Presses the mouse button                |
| Move your finger                        | Sends drag events                       |
| Lift your finger                        | Releases the mouse button immediately   |

A plain double tap (no movement, no hold) is left alone, so double-clicking
still works normally.

### Responsive dragging

The drag starts almost the instant your second touch begins to move: after a
tiny movement, or after a 0.1 second hold if you don't move yet. That keeps
dragging snappy, so it feels like a real button press rather than a gesture
waiting to be recognised. Both thresholds are adjustable (see
[Tuning](#tuning)).

## Requirements

- macOS 27 Golden Gate on a Mac with Apple Silicon
- Accessibility permission for the app

Other macOS versions are untested.

## Setup

1. Build and run the app (see below).
2. When prompted, allow it in
   **System Settings → Privacy & Security → Accessibility**.
3. Turn **off** the system's own dragging:
   **System Settings → Accessibility → Pointer Control → Trackpad Options →
   Use trackpad for dragging**.
4. Keep **Tap to click** turned on. The first tap of the gesture is still the
   system's click.

The app lives in the menu bar as **⥺**.

If you rebuild the app, macOS may stop trusting it because the ad-hoc signature
changes. Remove the app from the Accessibility list, add it again, and relaunch.

## Building from source

1. Open `InstaDrop.xcodeproj` in Xcode.
2. The project is set to **Sign to Run Locally** and builds for arm64 and
   x86_64. No developer account is needed.
3. Build and run with **Product → Run**.

## Tuning

The gesture timing lives in constants at the top of `AppDelegate.m`:

| Constant            | Default | Meaning                                                      |
| ------------------- | ------- | ------------------------------------------------------------ |
| `kTapMaxDuration`   | 0.20 s  | A touch shorter than this can count as a tap                 |
| `kTapMaxMove`       | 0.03    | ...if it moved less than this (fraction of the trackpad)     |
| `kDoubleTapWindow`  | 0.25 s  | The second touch must start within this time after the tap   |
| `kDragStartMove`    | 0.004   | The second touch becomes a drag after moving this much       |
| `kDragStartHold`    | 0.10 s  | ...or after being held this long                             |

If dragging starts too late or by accident, adjust the two `kDragStart` values.
If moving the cursor right after a click starts a drag, lower `kDoubleTapWindow`.
If the second touch of a real double-tap drag has to be too fast, raise it.

## Troubleshooting

- **Nothing happens.** Check that the app is enabled under Accessibility, and
  that "Use trackpad for dragging" is turned off.
- **Console shows "Could not create event tap".** Accessibility permission is
  missing. Remove the app from the list, add it again, and relaunch.
- **Log lines like "Error registering app with intents framework".** These
  come from macOS and are harmless.

## Limitations

- One-finger double-tap drag only. Three-finger drag is not implemented.
- Uses Apple's private `MultitouchSupport` framework to read trackpad touches,
  so it can't be distributed through the Mac App Store and a future macOS update
  could break it.
- If you use more than one trackpad at once, gesture tracking can get confused.

## Credits

InstaDrop is a rewrite of **No drag release delay** by Pravdomil Toman (2017).
The private multitouch declarations come from
[FingerMgmt](https://github.com/jnordberg/FingerMgmt) by Johan Nordberg.

## License

Add a license for this repository. Check the license of the original project
before publishing, since this code is derived from it.
