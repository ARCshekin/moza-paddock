# Third-party code and runtime components

## Included source

The DirectInput bridge, shared-memory helpers, effect evaluator, C atomics, and
related tests contain adapted code from
[crossover-ffb](https://github.com/0xbiel/crossover-ffb), commit
`36ca8a66b117162b1d121061c6cce0e39ddaae5e`.

Copyright (c) 2026 crossover-ffb contributors. MIT license. The complete notice is
retained in [Bridge/LICENSE](Bridge/LICENSE); provenance and changes are listed
in [Bridge/UPSTREAM.md](Bridge/UPSTREAM.md). The project MIT license does not
replace or remove this notice.

## Protocol references

- [boxflat](https://github.com/Lawstorant/boxflat) — reference for MOZA serial
  framing and configuration command facts. GPL upstream; no boxflat package is bundled.
- [universal-pidff](https://github.com/JacKeTUs/universal-pidff) — reference for
  HID PID initialization and effect ordering. Linux driver is not bundled.
- [Content Manager / actools](https://github.com/gro-ove/actools) — reference for
  race INI values and the AC shared-memory layout. Its UI and game assets are not bundled.

## External software

Wine, DXVK, Vulkan/MoltenVK, Steam, CrossOver, Assetto Corsa, and installed mods
remain separate products with their own licenses. This repository contains no
game files, Steam credentials, CrossOver binaries, Windows redistributables, or
downloaded Wine runtime binaries. A Steam license for the game is required.

Any managed runtime downloads must retain upstream license notices and source
links in the install manifest. The source license of this application does not
grant redistribution rights to proprietary game or runtime components.

## Managed downloads

The pinned manifest at [Scripts/runtime/manifest.json](Scripts/runtime/manifest.json)
fetches Wine Staging 11.21 (Wine: LGPL-2.1-or-later) from Gcenx's official WineHQ
macOS packages and DXVK macOS 1.10.3 builtin (Zlib). Runtime bundles retain
upstream notices for Wine, MoltenVK, Vulkan loader, Mono, Gecko and other
dependencies. These downloads are installed locally and are not included in
Git or application source releases. Source and build references:
[Wine](https://gitlab.winehq.org/wine/wine),
[macOS packages](https://github.com/Gcenx/macOS_Wine_builds),
[DXVK macOS](https://github.com/Gcenx/DXVK-macOS).

## Game prerequisites

Assetto Corsa requires Microsoft's original June 2010 D3DX11/D3DCompiler
runtimes. The local installer extracts x64 DLLs from the user's Steam-provided
redistributable CABs and verifies the hashes in
[directx-manifest.json](Scripts/runtime/directx-manifest.json). These proprietary
DLLs/CABs are not included in the repository or covered by this project's MIT
license. [Official runtime and terms](https://www.microsoft.com/en-us/download/details.aspx?id=8109).
