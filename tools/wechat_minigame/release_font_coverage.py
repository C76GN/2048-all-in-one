#!/usr/bin/env python3
"""Build and verify the deterministic WeChat release-font coverage evidence."""

from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import json
from pathlib import Path
import sys
from typing import Iterable


SCHEMA_VERSION = 1
POLICY_ID = "wechat-release-shipped-literals-v1"
SOURCE_FONT = "shared/assets/fonts/noto_sans_sc_variable.ttf"
LICENSE_FILE = "shared/assets/fonts/noto_sans_sc_ofl.txt"
SUBSET_FONT = "shared/assets/fonts/wechat_release_sans_subset.ttf"
COVERAGE_FILE = "shared/assets/fonts/wechat_release_font_coverage.txt"
MANIFEST_FILE = "shared/assets/fonts/wechat_release_font_coverage.json"
TRANSLATION_FILE = "shared/assets/translations.csv"
SCAN_ROOTS = ("app", "features", "shared")
SCAN_SUFFIXES = (".cfg", ".gd", ".json", ".tscn", ".tres")
EXCLUDED_PREFIXES = (
    "features/asset_library/resources/review/",
    "features/asset_library/resources/source_packs/",
    "features/asset_library/tools/",
    "features/platform_runtime/tools/",
    "features/themes/tools/",
)
EXCLUDED_EXACT = {
    COVERAGE_FILE,
    MANIFEST_FILE,
}
FORCED_CODEPOINTS = tuple(range(0x20, 0x7F)) + (
    0x00A0,  # no-break space
    0x2026,  # ellipsis
)


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_file(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _canonical_relative(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def _is_coverage_source(relative_path: str) -> bool:
    if relative_path in EXCLUDED_EXACT:
        return False
    if any(relative_path.startswith(prefix) for prefix in EXCLUDED_PREFIXES):
        return False
    return Path(relative_path).suffix.lower() in SCAN_SUFFIXES


def _iter_coverage_sources(root: Path) -> Iterable[Path]:
    paths: list[Path] = []
    for relative_root in SCAN_ROOTS:
        scan_root = root / relative_root
        if not scan_root.is_dir():
            raise ValueError(f"coverage root is missing: {relative_root}")
        for path in scan_root.rglob("*"):
            if not path.is_file():
                continue
            relative_path = _canonical_relative(path, root)
            if _is_coverage_source(relative_path):
                paths.append(path)
    return sorted(paths, key=lambda item: _canonical_relative(item, root))


def _decode_literal(quote: str, body: str, triple: bool) -> str:
    delimiter = quote * (3 if triple else 1)
    try:
        value = ast.literal_eval(delimiter + body + delimiter)
    except (SyntaxError, ValueError):
        return body
    return value if isinstance(value, str) else body


def _extract_string_literals(source: str) -> list[str]:
    """Extract GDScript/resource quoted literals while ignoring # comments."""

    literals: list[str] = []
    index = 0
    source_length = len(source)
    while index < source_length:
        character = source[index]
        if character == "#":
            newline = source.find("\n", index + 1)
            index = source_length if newline < 0 else newline + 1
            continue
        if character not in ('"', "'"):
            index += 1
            continue

        quote = character
        triple = source.startswith(quote * 3, index)
        delimiter_length = 3 if triple else 1
        index += delimiter_length
        body_start = index
        escaped = False
        while index < source_length:
            if escaped:
                escaped = False
                index += 1
                continue
            if source[index] == "\\":
                escaped = True
                index += 1
                continue
            if source.startswith(quote * delimiter_length, index):
                body = source[body_start:index]
                literals.append(_decode_literal(quote, body, triple))
                index += delimiter_length
                break
            index += 1
        else:
            # An incomplete source file cannot prove new glyph coverage.
            break
    return literals


def _translation_literals(path: Path) -> list[str]:
    values: list[str] = []
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        for row in csv.reader(source):
            values.extend(row)
    return values


def _codepoints_from_text(
    values: Iterable[str], *, include_forced: bool = True
) -> set[int]:
    codepoints: set[int] = set(FORCED_CODEPOINTS if include_forced else ())
    for value in values:
        for character in value:
            codepoint = ord(character)
            if codepoint >= 0x20 and not 0xD800 <= codepoint <= 0xDFFF:
                codepoints.add(codepoint)
    return codepoints


def _canonical_codepoint_records(codepoints: Iterable[int]) -> list[str]:
    return [f"U+{codepoint:04X}" for codepoint in sorted(codepoints)]


def _coverage_text(codepoints: Iterable[int]) -> str:
    return ",".join(_canonical_codepoint_records(codepoints)) + "\n"


def _build_evidence(root: Path) -> tuple[str, dict[str, object]]:
    translation_path = root / TRANSLATION_FILE
    if not translation_path.is_file():
        raise ValueError(f"translation source is missing: {TRANSLATION_FILE}")

    all_literals: list[str] = _translation_literals(translation_path)
    source_paths: list[str] = []
    for path in _iter_coverage_sources(root):
        relative_path = _canonical_relative(path, root)
        source = path.read_text(encoding="utf-8-sig")
        literals = _extract_string_literals(source)
        all_literals.extend(literals)
        source_paths.append(relative_path)

    codepoints = _codepoints_from_text(all_literals)
    coverage_text = _coverage_text(codepoints)
    source_font_path = root / SOURCE_FONT
    license_path = root / LICENSE_FILE
    subset_font_path = root / SUBSET_FONT
    for required_path in (source_font_path, license_path):
        if not required_path.is_file():
            raise ValueError(
                f"required font evidence is missing: {_canonical_relative(required_path, root)}"
            )

    manifest: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "policy_id": POLICY_ID,
        "coverage": {
            "codepoint_count": len(codepoints),
            "codepoints_sha256": _sha256_bytes(coverage_text.encode("utf-8")),
            "forced_codepoints": _canonical_codepoint_records(FORCED_CODEPOINTS),
            "translation_source": {
                "path": TRANSLATION_FILE,
                "sha256": _sha256_file(translation_path),
            },
            "scan_roots": list(SCAN_ROOTS),
            "scan_suffixes": list(SCAN_SUFFIXES),
            "excluded_prefixes": list(EXCLUDED_PREFIXES),
            "source_file_count": len(source_paths),
            "source_paths_sha256": _sha256_bytes(
                ("\n".join(source_paths) + "\n").encode("utf-8")
            ),
        },
        "source_font": {
            "path": SOURCE_FONT,
            "sha256": _sha256_file(source_font_path),
        },
        "license": {
            "path": LICENSE_FILE,
            "spdx": "OFL-1.1",
            "sha256": _sha256_file(license_path),
        },
        "subset_font": {
            "path": SUBSET_FONT,
            "bytes": subset_font_path.stat().st_size if subset_font_path.is_file() else 0,
            "sha256": _sha256_file(subset_font_path) if subset_font_path.is_file() else "",
        },
        "limitations": [
            "Coverage is limited to shipped translations, project runtime literals, and printable ASCII.",
            "Arbitrary user-authored Unicode text is not guaranteed by this package subset.",
            "The subset does not imply WeChat SDK login, share, payment, cloud-save, or open-data support.",
        ],
    }
    return coverage_text, manifest


def _manifest_text(manifest: dict[str, object]) -> str:
    return json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def _write(root: Path) -> None:
    coverage_text, manifest = _build_evidence(root)
    (root / COVERAGE_FILE).write_text(coverage_text, encoding="utf-8", newline="\n")
    (root / MANIFEST_FILE).write_text(
        _manifest_text(manifest), encoding="utf-8", newline="\n"
    )


def _check(root: Path) -> None:
    coverage_text, manifest = _build_evidence(root)
    actual_coverage_path = root / COVERAGE_FILE
    actual_manifest_path = root / MANIFEST_FILE
    if not (root / SUBSET_FONT).is_file():
        raise ValueError(f"release subset font is missing: {SUBSET_FONT}")
    if not actual_coverage_path.is_file():
        raise ValueError(f"coverage file is missing: {COVERAGE_FILE}")
    if not actual_manifest_path.is_file():
        raise ValueError(f"coverage manifest is missing: {MANIFEST_FILE}")
    if actual_coverage_path.read_text(encoding="utf-8") != coverage_text:
        raise ValueError("release font coverage file is stale")
    if actual_manifest_path.read_text(encoding="utf-8") != _manifest_text(manifest):
        raise ValueError("release font coverage manifest is stale")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=".")
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true")
    action.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    root = Path(arguments.project_root).resolve()
    try:
        if arguments.write:
            _write(root)
        else:
            _check(root)
    except (OSError, UnicodeError, ValueError, csv.Error) as error:
        print(f"WeChat release font coverage: FAIL: {error}", file=sys.stderr)
        return 1
    print("WeChat release font coverage: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
