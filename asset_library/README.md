# C76 Common Asset Library

This package is the project-local staging area for reusable assets. Keep runtime assets self-contained under this directory and register them in `gf_content_package.json` with a stable `asset.*` key.

Candidate assets live under `source_packs/` and `review/`. They are intentionally excluded from the runtime manifest until reviewed, licensed, and promoted.

Rules:

- Use stable asset keys for catalog and audit workflows.
- Keep third-party author, source URL, and license metadata in the manifest.
- Keep experiments out of the manifest until they are usable by a project.
- Run `tools/audit_asset_library.ps1` after adding, moving, or removing assets.
- Run `tools/import_asset_sources.ps1` to refresh source-pack copies and review records.
- Open `scenes/tools/asset_review_browser.tscn` to preview, listen, tag, rate, and annotate candidate assets.
