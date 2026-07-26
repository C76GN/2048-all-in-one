# Third-Party Assets

This inventory distinguishes runtime-distributed assets from review-only source material.

## Runtime Assets

## Universal UI Soundpack

- Author: Nathan Gibson
- Source: https://nathangibson.myportfolio.com
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)
- Usage: selected OGG UI and gameplay feedback sounds under `features/asset_library/resources/audio/`.
- Bundled notice: `features/asset_library/resources/licenses/universal_ui_soundpack.md`.

## Lucide Icons

- Author: Lucide Contributors
- Source: https://lucide.dev/
- License: ISC
- Usage: selected SVG interface icons registered by `features/asset_library/resources/gf_content_package.json`.
- Bundled notice: `features/asset_library/resources/textures/icons/license_lucide.txt`.

## Noto Sans SC

- Author: The Noto Project Authors
- Source: https://fonts.google.com/noto/specimen/Noto+Sans+SC
- License: SIL Open Font License 1.1
- Usage: the shared runtime body, display, and numeric font at `shared/assets/fonts/noto_sans_sc_variable.ttf`.
- Bundled notice: `shared/assets/fonts/noto_sans_sc_ofl.txt`.

## Review-Only Source Packs

These packs are copied into `features/asset_library/resources/source_packs/` for local review only. The release presets exclude both `source_packs/` and `review/`; none of these sources are distributed until license and usage are confirmed and an asset is promoted into the runtime manifest.

- `jdsherbert_ultimate_ui_sfx_free_mono`: license unknown.
- `downloaded_shader_pack`: license unknown.
- `manual_shader_notes`: manually captured shader notes from project discussion. Most entries remain license unknown until original origin is confirmed; `steampunkdemon_rain_snow_overlay` is attributed to Brian Smith (steampunkdemon.itch.io) and recorded as MIT.
- `four_hundred_sounds_pack`: license unknown.
- `ultimate_toon_source`: license unknown.
