# C76 Common Asset Library

This package is the project-local staging area for reusable assets. Keep runtime assets self-contained under this directory and register them in `gf_content_package.json` with a stable `asset.*` key.

Candidate assets live under `source_packs/` and `review/`. They are intentionally excluded from the runtime manifest until reviewed, licensed, and promoted.

Rules:

- Use stable asset keys for catalog and audit workflows.
- Use `GFAssetCatalog` providers for runtime and review search; do not build parallel indexes in tools.
- Keep third-party author, source URL, and license metadata in the manifest.
- Keep experiments out of the manifest until they are usable by a project.
- Run `tools/audit_asset_library.ps1` after adding, moving, or removing assets.
- Treat a partial `GFProjectReferenceScanner` result as an audit failure, and keep GF attribution coverage complete for runtime assets.
- Run `tools/import_asset_sources.ps1` to refresh source-pack copies and review records.
- Open `features/asset_library/scenes/asset_review_browser.tscn` to preview, listen, tag, rate, and annotate candidate assets.
- Run `tools/purge_rejected_assets.ps1` after a review batch to remove rejected copies and records; a complete `GFProjectReferenceScanner` pass blocks deletion of referenced assets, and `source_exclusions.json` prevents exact source identities from being re-imported.
- Use `Space`, `1`/`2`/`3`, `J`/`K`, and `Ctrl+S` for continuous keyboard review; text inputs suppress bare-key actions.
