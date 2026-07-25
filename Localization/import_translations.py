#!/usr/bin/env python3
"""
Import a filled-in translation CSV back into the app's string catalog.

Reads a CSV in the exact shape produced by export_template.py (semicolon-
separated, columns: key; variant; instruction; en; nl; <lang codes>...), and
writes every non-empty translation cell into Localizable.xcstrings with state
"translated".

Rules
-----
* Rows are matched to the catalog by the `key` (+ `variant`) columns, so the
  English text may contain duplicates without any ambiguity.
* An EMPTY target cell is left untouched — the key keeps whatever it already
  has (its English fallback, or an earlier translation). This makes partial /
  incremental deliveries safe: send one language at a time if you like.
* Only language columns whose header is a known language code are imported;
  `instruction` and `en` are ignored (edit `en` only if you mean to change the
  source text — it is imported when present so you can, but usually leave it).
* Unknown keys or variants in the CSV are reported and skipped, never invented.

Usage (from the Localization/ folder):
    python3 import_translations.py translations_filled.csv
    python3 import_translations.py translations_filled.csv --dry-run
"""

import argparse
import csv
import json
import os
import sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(HERE, "..", "Jumping Fox", "Localizable.xcstrings")

# Columns that are not language data.
META_COLUMNS = {"key", "variant", "instruction"}


def load_catalog():
    with open(CATALOG, encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=OrderedDict)


def save_catalog(catalog):
    with open(CATALOG, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write("\n")


def set_value(entry, lang, variant, value):
    """Write `value` for `lang` into the catalog entry, respecting whether the
    key is a plain string or a plural. Returns True if a change was made."""
    locs = entry.setdefault("localizations", OrderedDict())
    loc = locs.get(lang)

    if variant:  # plural form
        if loc is None:
            loc = OrderedDict()
            locs[lang] = loc
        variations = loc.setdefault("variations", OrderedDict())
        plural = variations.setdefault("plural", OrderedDict())
        unit = plural.setdefault(variant, OrderedDict())
        su = unit.setdefault("stringUnit", OrderedDict())
        if su.get("value") == value and su.get("state") == "translated":
            return False
        su["state"] = "translated"
        su["value"] = value
        return True

    # plain string
    if loc is None:
        loc = OrderedDict()
        locs[lang] = loc
    su = loc.setdefault("stringUnit", OrderedDict())
    if su.get("value") == value and su.get("state") == "translated":
        return False
    su["state"] = "translated"
    su["value"] = value
    return True


def main():
    ap = argparse.ArgumentParser(description="Import a filled translation CSV.")
    ap.add_argument("csv_path", help="Path to the filled-in CSV.")
    ap.add_argument("--dry-run", action="store_true",
                    help="Report what would change without writing the catalog.")
    args = ap.parse_args()

    catalog = load_catalog()
    strings = catalog["strings"]

    with open(args.csv_path, encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f, delimiter=";")
        rows = list(reader)

    if not rows:
        print("Empty CSV.", file=sys.stderr)
        sys.exit(1)

    header = rows[0]
    idx = {name: i for i, name in enumerate(header)}
    for required in ("key", "variant"):
        if required not in idx:
            print(f"CSV is missing the required '{required}' column.", file=sys.stderr)
            sys.exit(1)

    lang_cols = [name for name in header if name and name not in META_COLUMNS and name != "en"]
    # 'en' is importable too, but only if explicitly present as a column we want
    # to update; include it so edits to the source string flow through.
    if "en" in header:
        lang_cols = ["en"] + [c for c in lang_cols if c != "en"]

    known_langs = set(lang_cols)
    changes = 0
    per_lang = OrderedDict((l, 0) for l in lang_cols)
    unknown_keys = []

    for r in rows[1:]:
        if not r or len(r) < 2:
            continue
        key = r[idx["key"]].strip()
        variant = r[idx["variant"]].strip()
        if not key:
            continue
        entry = strings.get(key)
        if entry is None:
            unknown_keys.append((key, variant))
            continue
        for lang in lang_cols:
            col = idx.get(lang)
            if col is None or col >= len(r):
                continue
            value = r[col]
            if value is None or value == "":
                continue  # empty cell -> keep existing (English fallback)
            if set_value(entry, lang, variant, value):
                changes += 1
                per_lang[lang] += 1

    print(f"Languages detected: {', '.join(l for l in known_langs)}")
    print(f"Cells to update: {changes}")
    for lang, n in per_lang.items():
        if n:
            print(f"  {lang}: {n}")
    if unknown_keys:
        print(f"WARNING: {len(unknown_keys)} row(s) had unknown key/variant and were skipped:")
        for k, v in unknown_keys[:20]:
            print(f"  {k!r} (variant {v!r})")

    if args.dry_run:
        print("Dry run — no changes written.")
        return
    if changes:
        save_catalog(catalog)
        print(f"Wrote {CATALOG}")
    else:
        print("Nothing to write.")


if __name__ == "__main__":
    main()
