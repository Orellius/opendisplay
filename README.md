# OpenDisplay

Unlock HiDPI ("Retina") rendering on sub-4K external monitors driven by an Apple Silicon Mac. Free, open source, no closed app.

macOS generates proper HiDPI display modes for most external panels but hides them from System Settings and the public `CGDisplayCopyAllDisplayModes` API, so on a 1440p monitor you only get soft 1x scaling. OpenDisplay reads the hidden modes through the private SkyLight enumeration and applies them with the standard public configuration call. The result is the same crisp, 2x-rendered desktop a paid tool gives you, in a few hundred lines you can audit.

## What it does (v0.1)

- Lists the HiDPI resolutions your display actually supports (the ones macOS hides).
- Applies one live from a menubar quick-pick or a control-panel window.
- Remembers your choice and re-applies it when the display reconnects.

## What it does not do (yet)

Brightness/DDC, virtual displays, mirroring, and XDR brightness are out of scope for v0.1. Open an issue if you want one.

## The honest limit

This is the rendering half of "Retina," not the density half. A HiDPI mode renders at 2x and downsamples to your panel's physical pixels, so text and UI are smoother and crisper than native 1x. It cannot add physical pixels: a 27" 1440p panel is ~109 PPI, and a true Retina display is ~218 PPI. Scaled-down HiDPI (for example a 1920x1080 workspace) is the most noticeable improvement on a 1440p panel because the UI is larger and 2x-rendered. For true Retina density you need a higher-PPI (5K) panel.

## Build and run

```sh
swift build            # or: swift run
scripts/bundle.sh      # produces OpenDisplay.app (menubar agent)
open OpenDisplay.app
```

Requires macOS 14+ on Apple Silicon and the Xcode command line tools.

## How it works

- `SkyLight.swift` resolves four private `SLDisplayCopyAllDisplayModes` / `SLDisplayMode*` symbols at runtime via `dlsym`, enumerates modes with the `ShowDuplicateLowResolutionModes` option (which reveals the HiDPI ones), and applies the chosen mode with the public `CGConfigureDisplayWithDisplayMode`.
- Because the private symbols have no headers and were renamed once already (the old `CGS*` names became `SL*`), every lookup is optional and the app reports cleanly if a future macOS moves them.

## Distribution

Distributed outside the Mac App Store (the App Store forbids private API use). Notarization works normally; it is a malware scan, not API policing.

## License

MIT. See LICENSE.
