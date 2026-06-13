# Contributing to OpenDisplay

Thanks for your interest. OpenDisplay is a focused macOS menu-bar app for HiDPI and software display control on Apple Silicon, licensed under AGPL-3.0.

## Scope

It targets a single external sub-4K display on Apple Silicon, software-only (no DDC reliance, no HDR). Multi-monitor layout, hardware DDC control, HDR, Intel Macs, and the Mac App Store are out of scope by design. Bug fixes, reliability work, and in-scope features are welcome; large new surfaces are best raised in an issue first.

## Building

```sh
swift build                 # dev build
swift run                   # run the GUI from source
scripts/bundle.sh release   # build OpenDisplay.app (App Intents + URL scheme)
scripts/install.sh          # build and install to /Applications
```

Requires macOS 14+ on Apple Silicon and the Xcode command line tools.

## Pull requests

- Keep changes focused: one concern per PR.
- Match the surrounding style. Every source file carries an SPDX header; keep it.
- Do not remove or alter the copyright/attribution. It is required by the license and enforced at launch.
- Private SkyLight / MonitorPanel APIs are resolved at runtime via `dlsym`; any new private-API use must degrade gracefully when a symbol is missing.
- Never exercise display changes (rotate, resolution, deep dim) destructively against a live primary display in tests or scripts.

## Licensing of contributions

By submitting a contribution you certify the [Developer Certificate of Origin](https://developercertificate.org/) (sign your commits with `git commit -s`), and you agree that:

1. your contribution is licensed to the project and its users under the AGPL-3.0; and
2. you grant the project maintainer (Orellius) a perpetual, irrevocable license to also distribute your contribution under other terms, so the project may be dual-licensed or relicensed in the future.

This keeps the project open while leaving the maintainer the option to offer a commercial license later. If you are not comfortable with the relicensing grant, please open an issue to discuss before contributing.

## Signing and distribution

The project is signed ad-hoc, so a locally built copy runs without Gatekeeper friction. A notarized, Developer-ID-signed build for general download requires an Apple Developer Program membership and is the maintainer's step to perform.
