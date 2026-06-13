<p align="center">
  <img src="assets/logo.png" width="116" alt="OpenDisplay">
</p>
<h1 align="center">OpenDisplay</h1>
<p align="center">HiDPI resolutions for sub-4K external monitors on Apple Silicon.</p>

---

On Apple Silicon, macOS only offers HiDPI ("Retina") scaling on 4K and 5K panels. Drive a 1440p monitor and the only scaled options are rendered at 1x, so text and UI look soft. The HiDPI modes for these panels do exist: macOS generates them but leaves them out of System Settings and the public `CGDisplayCopyAllDisplayModes` API. OpenDisplay reads them from the private SkyLight enumeration and applies them with the standard public configuration call.

## Features

- HiDPI resolutions macOS hides on sub-4K panels, from the menu bar, the control panel, or a scrub slider. Takes effect immediately and is reapplied when the display reconnects.
- Software brightness, color warmth, and contrast as a live gamma transfer, restored on quit. Brightness can dim below the gamma floor with a translucent overlay for true deep dimming.
- Refresh-rate switching, in both HiDPI and native modes.
- Display rotation when the panel supports it, via the private MonitorPanel API.
- A headless HiDPI virtual display for remote access when no panel is attached.
- A night schedule, idle dimming, brightness/warmth presets, blackout, and quick-reset.
- Prevent display sleep while OpenDisplay runs, and optionally protect the chosen resolution so an app or macOS can't change it out from under you.
- A custom display name, shown in the panel and the menu bar.
- Settings export and import to a JSON file.
- Global hotkeys for brightness and warmth, with a choice of glass or classic on-screen display.
- Favorite resolutions pinned to the menu bar.
- A Display pane that reads panel identity and geometry (name, serial, PPI, EDID UUID) with copy and export.
- An `opendisplay` command line, an `opendisplay://` URL scheme, and App Intents for Shortcuts.
- Launch at login. No dependencies, no kernel extension.

## Install

Requires macOS 14 or later on Apple Silicon, with the Xcode command line tools.

```sh
git clone <repo-url> && cd opendisplay
scripts/bundle.sh      # builds OpenDisplay.app
open OpenDisplay.app
```

To run from source during development: `swift run`.

## Command line

The app binary doubles as a CLI. Symlink it onto your PATH:

```sh
ln -s "$PWD/OpenDisplay.app/Contents/MacOS/OpenDisplay" /usr/local/bin/opendisplay
opendisplay help
```

```
opendisplay list                hidden HiDPI modes (* = current)
opendisplay res 1920            set a HiDPI mode by looks-like width
opendisplay native              return to the native mode
opendisplay brightness 60       software brightness 0-100
opendisplay warmth 30           color warmth 0-100
opendisplay contrast 40         contrast 0-100 (50 = neutral)
opendisplay refresh 120         refresh rate at the current resolution
opendisplay rotate 90           rotate the display
opendisplay virtual 2560        create a headless HiDPI display and hold it
opendisplay info                panel identity and geometry
```

Wrap any of these in a Shortcuts "Run Shell Script" action to drive the display from Shortcuts.

The bundled app also registers an `opendisplay://` URL scheme for links, Shortcuts' "Open URL", Raycast, or Alfred:

```
opendisplay://brightness/50     opendisplay://warmth/30     opendisplay://contrast/40
opendisplay://res/1920          opendisplay://native        opendisplay://rotate/90
opendisplay://reset             opendisplay://blackout
```

## How it works

`SLDisplayCopyAllDisplayModes` in the private SkyLight framework returns a display's full mode list, including HiDPI variants, when passed the `kCGDisplayShowDuplicateLowResolutionModes` option. The public `CGDisplayCopyAllDisplayModes` filters those out, which is why they never reach System Settings. OpenDisplay enumerates the private list, picks a HiDPI mode (one whose pixel dimensions are twice its point dimensions), and applies it with the public `CGConfigureDisplayWithDisplayMode`.

The four private symbols are resolved at runtime with `dlsym`, and every lookup is optional. If a future macOS renames them, the app reports that the API is unavailable instead of crashing. That surface was already renamed once, from the `CGS*` names to `SL*`, so the guard is not theoretical.

## Compatibility

Built and verified on macOS 26 (Apple Silicon). Distributed outside the Mac App Store, which forbids private API use. Notarization is unaffected, since it scans for malware rather than policing APIs.

## The limit worth knowing

A HiDPI mode renders at 2x and downsamples to the panel's physical pixels. Text and edges get sharper; the physical pixel count does not change. A 27-inch 1440p panel is about 109 PPI, while a Retina-class panel is about 218. The improvement is most visible on scaled-down resolutions, where the workspace is larger and rendered at 2x. True Retina density requires a higher-PPI display.

## Scope

Tuned for a single external sub-4K display on Apple Silicon. Multi-monitor layout, DDC hardware control, and HDR boost are out of scope by design. Color-profile assignment, RGB/YCbCr pixel-encoding, and saturation are not supported: on this class of panel they need either a destructive live-screen switch to verify or a private path that isn't reliable enough to ship.

## License

MIT. See [LICENSE](LICENSE).
