#!/usr/bin/env python3
"""Fail closed when a font does not contain every declared coverage codepoint."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from fontTools.ttLib import TTFont


def _read_codepoints(path: Path) -> list[int]:
    records = path.read_text(encoding="utf-8").strip().split(",")
    codepoints: list[int] = []
    for record in records:
        token = record.strip()
        if not token.startswith("U+"):
            raise ValueError(f"invalid coverage token: {record}")
        codepoint = int(token[2:], 16)
        if codepoint <= 0 or codepoint > 0x10FFFF:
            raise ValueError(f"invalid Unicode codepoint: {record}")
        codepoints.append(codepoint)
    if len(codepoints) != len(set(codepoints)):
        raise ValueError("coverage contains duplicate codepoints")
    return codepoints


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", required=True)
    parser.add_argument("--coverage", required=True)
    arguments = parser.parse_args()
    font_path = Path(arguments.font).resolve()
    coverage_path = Path(arguments.coverage).resolve()
    try:
        codepoints = _read_codepoints(coverage_path)
        with TTFont(font_path, lazy=True) as font:
            cmap = font.getBestCmap() or {}
            missing = [codepoint for codepoint in codepoints if codepoint not in cmap]
    except (OSError, ValueError) as error:
        print(f"Font coverage: FAIL: {error}", file=sys.stderr)
        return 1
    if missing:
        preview = ",".join(f"U+{codepoint:04X}" for codepoint in missing[:32])
        print(
            f"Font coverage: FAIL: {font_path.name} misses {len(missing)} codepoints: "
            f"{preview}",
            file=sys.stderr,
        )
        return 1
    print(f"Font coverage: PASS: {font_path.name}: {len(codepoints)} codepoints")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
