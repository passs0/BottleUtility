<p align="center">
  <img src="assets/icon_mac.png" width="160" height="160" alt="Bottle Utility Icon" />
</p>

<h1 align="center">Bottle Utility</h1>

<p align="center">
  An in-place patcher for CrossOver on Apple Silicon. Upgrades GStreamer (with FFmpeg), DXMT, DXVK, and bottle tweaks without duplicating <code>CrossOver.app</code>.
</p>

<p align="center">
  <a href="https://github.com/passs0/BottleUtility/releases/latest"><img src="https://img.shields.io/github/v/release/passs0/BottleUtility?label=Latest%20Release&color=007AFF" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B%20%7C%20Apple%20Silicon-black?logo=apple" alt="macOS 13.0+" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" /></a>
</p>

<p align="center">
  <img src="assets/preview.png" width="600" alt="Bottle Utility" />
</p>

---

## What it does

- **In-place patching:** Detects CrossOver and CrossOver Preview and patches the selected bundle directly so existing bottles pick up the updates.
- **GStreamer + FFmpeg:** Installs [`Sikarugir-App/gstreamer`](https://github.com/Sikarugir-App/gstreamer) and links `winegstreamer.so` to fix broken or frozen UE4/UE5 cutscenes.
- **DXMT, DXVK & D3DMetal:** Pulls the latest [`3Shain/dxmt`](https://github.com/3Shain/dxmt) and optional [`Gcenx/DXVK-macOS`](https://github.com/Gcenx/DXVK-macOS) releases, and lets you upgrade or restore CrossOver's `D3DMetal.framework` from an Apple Game Porting Toolkit `.dmg`.
- **Optimizations:** Toggles NVIDIA RTX (`0x10DE`) D3DMetal spoofing, Metal Performance HUD (`MTL_HUD_ENABLED=1`), macOS Game Mode, `WINEMSYNC=1`, and `ROSETTA_ADVERTISE_AVX=1`.
- **Game Fixes add-ons:** Downloads and runs built-in game fixes (`RE9-CrossOver-Fix`, `SH2R-CrossOver-Fix`) from `Addons/` on demand.
- **Cache cleanup:** Inspects and clears D3DMetal shader caches and GStreamer registries.

## Install

Download **`BottleUtility-v2.5.0.dmg`** from [Releases](https://github.com/passs0/BottleUtility/releases/latest) and drag `Bottle Utility.app` to `/Applications`.

If Gatekeeper blocks the first launch:
```zsh
xattr -cr "/Applications/Bottle Utility.app"
```

Or build from source:
```zsh
git clone https://github.com/passs0/BottleUtility.git && cd BottleUtility
./build.sh
cp -R "build/Bottle Utility.app" /Applications/
```

## Credits

Inspired by [CXPatcher](https://github.com/italomandara/CXPatcher) and [Procyon](https://github.com/italomandara/Procyon) by [@italomandara](https://github.com/italomandara), [3Shain/dxmt](https://github.com/3Shain/dxmt), [Sikarugir-App/gstreamer](https://github.com/Sikarugir-App/gstreamer), and [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS).

Built with [Google Antigravity](https://antigravity.google) — 100% AI-written code and UI, steered and tested by hand.

## License

[MIT](LICENSE)
