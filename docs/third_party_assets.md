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

## Kenney Pattern Pack 2

- Author: Kenney.
- Source: https://kenney.nl/assets/pattern-pack-2
- License: Creative Commons Zero 1.0 (CC0 1.0).
- Usage: five selected thin geometric PNG patterns provide low-opacity, family-specific
  tile edge motifs while the central number area remains clear.
- Bundled notice:
  `features/asset_library/resources/licenses/kenney_pattern_pack_2.txt`.

## Local Licensed Content (Not Distributed)

### Puzzle Music 2

- Author: GravitySound.
- Source: https://www.gamedevmarket.net/asset/puzzle-music-2
- License: GameDev Market Pro Licence.
- Usage: ten purchased WAV loops can be installed with
  `tools/install_puzzle_music_2_local.ps1` into the current user's
  `user://content_packages/puzzle_music_2` directory. The runtime discovers the
  generated GF content-package manifest, loads one bounded file at a time through
  `GFBackgroundWorkUtility`, and shuffles playback through `GFAudioUtility`.
- Distribution boundary: the purchased source WAV files and their original source
  directory are never committed or exported. A missing local package silently
  degrades to no background music.

## Review-Only Source Packs

These packs are copied into `features/asset_library/resources/source_packs/` for local review only. The release presets exclude both `source_packs/` and `review/`; none of these sources are distributed until license and usage are confirmed and an asset is promoted into the runtime manifest.

- `jdsherbert_ultimate_ui_sfx_free_mono`: license unknown.
- `downloaded_shader_pack`: license unknown.
- `manual_shader_notes`: manually captured shader notes from project discussion. Most entries remain license unknown until original origin is confirmed; `steampunkdemon_rain_snow_overlay` is attributed to Brian Smith (steampunkdemon.itch.io) and recorded as MIT.
- `four_hundred_sounds_pack`: license unknown.
- `ultimate_toon_source`: license unknown.
