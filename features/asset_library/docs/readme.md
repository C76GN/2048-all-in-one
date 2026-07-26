# C76 Common Asset Library

This is the authoritative operational guide for the project-local asset-library feature. Project-wide policy, trust boundaries, promotion rules, and the full source-of-truth table live in [`docs/asset_library.md`](../../../docs/asset_library.md). Generated reports are run evidence only; they do not override either guide, the runtime manifest, or review records.

Keep runtime assets self-contained under this directory and register them in `gf_content_package.json` with a stable `asset.*` key.

Candidate assets live under `source_packs/` and `review/`. They are intentionally excluded from the runtime manifest and player exports until reviewed, licensed, copied or transcoded into a runtime directory, registered, and audited.

Rules:

- Use stable asset keys for catalog and audit workflows.
- Use `GFAssetCatalog` providers for runtime and review search; do not build parallel indexes in tools.
- Keep third-party author, source URL, and license metadata in the manifest.
- Keep experiments out of the manifest until they are usable by a project.
- Run `tools/audit_asset_library.ps1` after adding, moving, or removing assets.
- Treat a partial `GFProjectReferenceScanner` result as an audit failure, and keep GF attribution coverage complete for runtime assets.
- Run `tools/import_asset_sources.ps1` to refresh source-pack copies and review records.
- Treat each `resources/import_sources.json` `source_path` as a workstation-specific tool input, not a portable asset identity. Authoring records and generated reports currently retain the original path for traceability, so redact it before sharing outside the repository and never use it as a runtime or review identity; identity is `source_pack_id + relative_path + SHA-256`. A path-only local adjustment is not a semantic asset change.
- Open `features/asset_library/scenes/asset_review_browser.tscn` to preview, listen, tag, rate, and annotate candidate assets.
- The review browser synchronizes `review_status` and `reviewed_at` by default across playable encodings in an explicitly verified same-source audio group, so one sound decision is not repeated merely because WAV, OGG, and MP3 encodings differ. Ratings, notes, tags, paths, hashes, playability, and license metadata remain format-specific.
- Audio format groups are declared per source pack in `resources/import_sources.json` only after same-content verification; filenames are never matched globally or fuzzily across packs.
- Run Godot headlessly with `res://features/asset_library/tools/sync_audio_review_variants.gd` after importing to backfill inbox records from an unambiguous playable consensus. Conflicting decisions and decisions that exist only on an unplayable format are reported without writes.
- Run `tools/purge_rejected_assets.ps1` after a review batch to remove rejected copies and records; a complete `GFProjectReferenceScanner` pass blocks deletion of referenced assets, and `source_exclusions.json` prevents exact source identities from being re-imported.
- Use `Space`, `1`/`2`/`3`, `J`/`K`, and `Ctrl+S` for continuous keyboard review; text inputs suppress bare-key actions.
