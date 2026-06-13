<p align="center">
  <img src="assets/logo.png" width="116" alt="OpenDisplay">
</p>
<h1 align="center">OpenDisplay</h1>
<p align="center">HiDPI resolutions for sub-4K external monitors on Apple Silicon.</p>

---

On Apple Silicon, macOS only offers HiDPI ("Retina") scaling on 4K and 5K panels. Drive a 1440p monitor and the only scaled options are rendered at 1x, so text and UI look soft. The HiDPI modes for these panels do exist: macOS generates them but leaves them out of System Settings and the public `CGDisplayCopyAllDisplayModes` API. OpenDisplay reads them from the private SkyLight enumeration and applies them with the standard public configuration call.

## Features

- Lists the HiDPI modes your display actually supports, not just the ones System Settings shows.
- Apply one from the menubar or the control-panel window; it takes effect immediately.
- Remembers your choice and reapplies it when the display reconnects.
- Around 350 lines of Swift, no dependencies, no kernel extension.

## Install

Requires macOS 14 or later on Apple Silicon, with the Xcode command line tools.

```sh
git clone <repo-url> && cd opendisplay
scripts/bundle.sh      # builds OpenDisplay.app
open OpenDisplay.app
```

To run from source during development: `swift run`.

## How it works

`SLDisplayCopyAllDisplayModes` in the private SkyLight framework returns a display's full mode list, including HiDPI variants, when passed the `kCGDisplayShowDuplicateLowResolutionModes` option. The public `CGDisplayCopyAllDisplayModes` filters those out, which is why they never reach System Settings. OpenDisplay enumerates the private list, picks a HiDPI mode (one whose pixel dimensions are twice its point dimensions), and applies it with the public `CGConfigureDisplayWithDisplayMode`.

The four private symbols are resolved at runtime with `dlsym`, and every lookup is optional. If a future macOS renames them, the app reports that the API is unavailable instead of crashing. That surface was already renamed once, from the `CGS*` names to `SL*`, so the guard is not theoretical.

## Compatibility

Built and verified on macOS 26 (Apple Silicon). Distributed outside the Mac App Store, which forbids private API use. Notarization is unaffected, since it scans for malware rather than policing APIs.

## The limit worth knowing

A HiDPI mode renders at 2x and downsamples to the panel's physical pixels. Text and edges get sharper; the physical pixel count does not change. A 27-inch 1440p panel is about 109 PPI, while a Retina-class panel is about 218. The improvement is most visible on scaled-down resolutions, where the workspace is larger and rendered at 2x. True Retina density requires a higher-PPI display.

## Roadmap

- Per-display selection for multi-monitor setups.
- Launch at login.
- Under consideration: brightness over DDC, mirroring, virtual displays.

## License

MIT. See [LICENSE](LICENSE).
