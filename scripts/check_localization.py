#!/usr/bin/env python3
"""Check the Swift translation dictionaries before they can trap at launch."""

from pathlib import Path
import re
import sys


SOURCE = Path(__file__).resolve().parents[1] / "NotchPulse/managers/AppLocalization.swift"
source = SOURCE.read_text(encoding="utf-8")
languages = list(re.finditer(r"^        \.(\w+): \[$", source, re.MULTILINE))
if not languages:
    sys.exit("No translation dictionaries found")

all_keys = {}
failed = False
for index, match in enumerate(languages):
    end = languages[index + 1].start() if index + 1 < len(languages) else source.find("\n    ]", match.end())
    if end < 0:
        sys.exit(f"Could not find end of {match.group(1)} translations")
    body = source[match.end():end]
    seen = set()
    for entry in re.finditer(r'^\s*"((?:\\.|[^"\\])+)"\s*:', body, re.MULTILINE):
        key = entry.group(1)
        if key in seen:
            print(f"{match.group(1)}: duplicate key {key!r}", file=sys.stderr)
            failed = True
        seen.add(key)
    all_keys[match.group(1)] = seen

english = all_keys.get("english")
if english is None:
    sys.exit("English translations missing")
for language, keys in all_keys.items():
    missing = english - keys
    extra = keys - english
    if missing or extra:
        print(f"{language}: {len(missing)} missing, {len(extra)} extra translation keys", file=sys.stderr)
        failed = True

if failed:
    sys.exit(1)
print(f"Localization OK: {len(all_keys)} languages, {len(english)} keys each")
