#!/usr/bin/env python3
"""Checks the translation files.

    python3 Localization/check.py          all languages
    python3 Localization/check.py en       one language

For each language folder (xx.lproj):
  - files are valid (plutil -lint);
  - each translation keeps the placeholders of its key (%@, %lld, %lf...);
  - no em dash or en dash, no lone percent sign;
  - texts found in the code (Text("...") etc., via genstrings) that have no translation.
The last list is a guide: genstrings sees Text("..."), not every Button or Label.
French is the source language: the code is written in French and fr.lproj only holds exceptions.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOC = os.path.join(ROOT, "Localization")
SOURCES = os.path.join(ROOT, "Sources")

SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|lf|f|\.\d+lf|\.\d+f)")
DASHES = ("—", "–")


def load(path):
    out = subprocess.run(["plutil", "-convert", "json", "-o", "-", path],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return json.loads(out.stdout)


def specs(text):
    """Placeholders in order, positions (%1$@) ignored."""
    return sorted(re.sub(r"\d+\$", "", m) for m in SPEC.findall(text))


def normalized(key):
    """Compares keys whatever the placeholder type; genstrings writes % where the real key has %%."""
    return SPEC.sub("%@", key.replace("%%", "%"))


def code_keys():
    files = []
    for base, _, names in os.walk(SOURCES):
        files += [os.path.join(base, n) for n in names if n.endswith(".swift")]
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["xcrun", "genstrings", "-SwiftUI", "-q", "-o", tmp] + files,
                       capture_output=True)
        path = os.path.join(tmp, "Localizable.strings")
        data = load(path) if os.path.exists(path) else None
    return set(data or {})


def check(lang, keys_in_code):
    folder = os.path.join(LOC, f"{lang}.lproj")
    problems = 0
    table = {}
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if not name.endswith((".strings", ".stringsdict")):
            continue
        lint = subprocess.run(["plutil", "-lint", path], capture_output=True, text=True)
        if lint.returncode != 0:
            print(f"  ERROR {name}: {lint.stdout.strip()}")
            problems += 1
            continue
        if name == "Localizable.strings":
            table.update(load(path) or {})
        if name == "Localizable.stringsdict":
            plurals = load(path) or {}
            table.update({k: k for k in plurals})

    for key, value in table.items():
        if not isinstance(value, str):
            continue
        if specs(key) != specs(value):
            print(f"  ERROR placeholders differ: {key!r} -> {value!r}")
            problems += 1
        if any(d in value for d in DASHES):
            print(f"  ERROR long dash: {value!r}")
            problems += 1
        if re.search(r"%(?!%|\d+\$|lld|ld|d|@|lf|f|\.\d)", value.replace("%%", "")):
            print(f"  ERROR lone percent sign (write %%): {value!r}")
            problems += 1

    if lang != "fr":
        known = {normalized(k) for k in table}
        missing = sorted(k for k in keys_in_code if normalized(k) not in known)
        print(f"  {len(table)} translations, {len(missing)} texts from the code not translated yet")
        for k in missing:
            print(f"    - {k}")
    return problems


def main():
    langs = sys.argv[1:] or sorted(d[:-6] for d in os.listdir(LOC) if d.endswith(".lproj"))
    keys_in_code = code_keys()
    problems = 0
    for lang in langs:
        print(f"[{lang}]")
        problems += check(lang, keys_in_code)
    print("OK" if problems == 0 else f"{problems} problem(s)")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
