# ALYVE WALL

SwiftUI iPhone app for making animated wallpapers. Export them as seamless-loop MP4s for iPhone and Mac, as Lock Screen Live Photos, or as stills.

- **12 styles:** Gradient, Aurora, Lava Lamp, Bokeh, Starfield, Rain, Snow, Dots, Fireflies, Clouds, Petals, Ripples
- **2–5 colours**, 12 preset palettes, "Surprise me"
- **One image:** a transparent PNG logo on top (drag, pinch, opacity, float), or a photo behind the effect
- **Motion:** speed, amount, size, glow, loop length 5–30 s, shuffle layout
- **Free:** 720p iPhone/Mac video, 720×1280 Live Photo, 30 fps, small "ALYVE WALL" watermark
- **Premium (£1.99 one-off, `games.redhead.alyvewall.premium`):** no watermark, iPhone up to Pro Max native, Mac up to 5K, 60 fps, Full HD Live Photo

## Layout

- `AlyveWall/Engine` is the CoreGraphics renderer and AVFoundation exporter. It has no UIKit, so it also compiles on macOS.
- `AlyveWall/UI` holds the SwiftUI screens. `AlyveWall/Store` holds the StoreKit 2 code.
- `Products.storekit` is the local StoreKit config, already wired into the scheme.

Every motion makes a whole number of cycles per loop, so the last frame of a video flows straight into the first.

## Tools

```bash
swiftc -O -parse-as-library AlyveWall/Engine/*.swift Tools/EngineHarness.swift -o /tmp/harness && /tmp/harness /tmp/alyve-out
```
This writes a contact sheet of every style, checks that each loop is seamless, and makes a test 4K MP4 and Live Photo.

```bash
swiftc -O -parse-as-library AlyveWall/Engine/*.swift Tools/MakeIcon.swift -o /tmp/makeicon && /tmp/makeicon AlyveWall/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```
This regenerates the app icon.

In Debug builds, the `-selfTest` launch argument exports an MP4 and a Live Photo and saves both to Photos.
