# Third-Party Assets

This inventory distinguishes runtime-distributed assets from review-only source material.

## Runtime Assets

### Universal UI Soundpack

- Author: Nathan Gibson
- Source: https://nathangibson.myportfolio.com
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)
- Usage: selected OGG UI and gameplay feedback sounds under `features/asset_library/resources/audio/`.
- Bundled notice: `features/asset_library/resources/licenses/universal_ui_soundpack.md`.

### Lucide Icons

- Author: Lucide Contributors
- Source: https://lucide.dev/
- License: ISC
- Usage: selected SVG interface icons registered by `features/asset_library/resources/gf_content_package.json`.
- Bundled notice: `features/asset_library/resources/textures/icons/license_lucide.txt`.

### Noto Sans SC

- Author: The Noto Project Authors
- Source: https://fonts.google.com/noto/specimen/Noto+Sans+SC
- License: SIL Open Font License 1.1
- Usage: the shared runtime body, display, and numeric font at `shared/assets/fonts/noto_sans_sc_variable.ttf`.
- Bundled notice: `shared/assets/fonts/noto_sans_sc_ofl.txt`.

### Kenney Pattern Pack 2

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
- Usage: `tools/install_puzzle_music_2_local.ps1` reads the ten purchased WAV
  sources without modifying them, encodes local OGG Vorbis copies, and registers
  those copies under the current user's
  `user://content_packages/puzzle_music_2` directory. The runtime discovers the
  generated GF content-package manifest, loads one bounded compressed stream at a
  time through `GFBackgroundWorkUtility`, and shuffles playback through
  `GFAudioUtility`. Legacy WAV manifests remain readable for rollback.
- Distribution boundary: the purchased source WAV files and their original source
  directory are never committed or exported. A missing local package silently
  degrades to no background music.

## Review-Only Source Packs

Shared review metadata is kept under `features/asset_library/resources/review/`. Raw packs are restored from ignored workstation paths declared in `import_sources.local.json`; unknown-license binaries are neither tracked by Git nor included in player exports. The release presets also exclude `source_packs/` and `review/`. Promotion still requires a known license, attribution, a stable runtime key, and a successful audit.

- `universal_ui_soundpack`: CC BY 4.0. The promoted runtime subset is listed above; the complete source pack may be materialized locally for review.
- `jdsherbert_ultimate_ui_sfx_free_mono`: license unknown.
- `downloaded_shader_pack`: license unknown.
- `manual_effect_notes`: manually captured interaction and VFX recipes from project discussion; origin and license remain unknown until each candidate is traced to its source.
- `manual_shader_notes`: manually captured shader notes from project discussion. Most entries remain license unknown until original origin is confirmed; `steampunkdemon_rain_snow_overlay` is attributed to Brian Smith (steampunkdemon.itch.io) and recorded as MIT.
- `four_hundred_sounds_pack`: license unknown.
- `ultimate_toon_source`: license unknown.
