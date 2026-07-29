#!/usr/bin/env python3
"""
Generate the translation template CSV from the app's string catalog.

Output: translations_template.csv (semicolon-separated, UTF-8, standard CSV
quoting so a value may safely contain ';', '"' or newlines).

Columns:
    key          - catalog identifier. DO NOT EDIT. Used to import back.
    variant      - '' for a normal string; 'one'/'other'/... for a plural form.
                   DO NOT EDIT.
    instruction  - guidance for the translator (length, placeholders, bold).
    en           - English source text.
    nl           - Dutch text.
    <lang codes> - one empty column per target language, to be filled in.

Leave a target cell EMPTY to keep the current English fallback for that key.

Run from the Localization/ folder:  python3 export_template.py
"""

import csv
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(HERE, "..", "Jumping Fox", "Localizable.xcstrings")
OUTPUT = os.path.join(HERE, "translations_template.csv")

# Target languages, in the same order as AppLanguage.all (minus en/nl, which
# have their own dedicated columns). Keep this in sync with Localization.swift.
TARGET_LANGS = [
    "af", "sq", "am", "ar", "hy", "as", "az", "eu", "bn", "my", "bs", "bg",
    "ca", "zh", "da", "de", "et", "fo", "fi", "fr", "gl", "ka", "el", "gu",
    "he", "hi", "hu", "ga", "is", "id", "it", "ja", "kn", "kk", "km", "ko",
    "hr", "lo", "lv", "lt", "mk", "ms", "ml", "mr", "mn", "ne", "no", "uk",
    "or", "ug", "uz", "fa", "pl", "pt", "pa", "ro", "ru", "sr", "si", "sk",
    "sl", "es", "sw", "ta", "te", "th", "bo", "cs", "tr", "ur", "vi", "cy",
    "be", "zu", "sv",
]

PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|\.\d+f|f)")


def unit_value(localization):
    """Return (variant, value) pairs for a localization: one for a plain
    string, several for a plural."""
    if "stringUnit" in localization:
        return [("", localization["stringUnit"]["value"])]
    if "variations" in localization:
        plural = localization["variations"].get("plural", {})
        # Conventional order: one before other, then the rest.
        order = ["zero", "one", "two", "few", "many", "other"]
        cats = sorted(plural.keys(), key=lambda c: order.index(c) if c in order else 99)
        return [(c, plural[c]["stringUnit"]["value"]) for c in cats]
    return [("", "")]


def context_hint(key):
    """Short guidance on where the text appears and how long it may be."""
    k = key.lower()
    if "accessibility" in k:
        return "VoiceOver label (not shown on screen). Favour clarity over brevity."
    if k.startswith("notif."):
        which = "title (heading)" if ".title" in k else "body (one short sentence)"
        return (
            f"Push-notification {which}. Warm, encouraging and child-friendly; "
            "keep it short and keep any emoji exactly as-is."
        )
    if k.startswith("common."):
        return "Small button or label. Keep it very short."
    if k.endswith(".title") or ".title " in k:
        return "Heading. Short and punchy."
    if k.endswith(".subtitle") or ".subtitle " in k:
        return "Subheading. One short sentence."
    if k.startswith("character."):
        return "Animal name, a single word."
    if k.startswith("modeintro.") or k.startswith("game.intro."):
        return "Short bullet on the pre-game card. Keep it concise."
    if k.startswith("menu."):
        return "Menu item. Keep it short."
    if k.startswith("settings.") or k.startswith("premium.") or k.startswith("goal."):
        return "Settings text. Keep it compact."
    if k.startswith("parentgate."):
        return "Parental-gate text for grown-ups. Clear and short."
    if k.startswith("onboarding."):
        return "Onboarding screen text."
    if k.startswith("streak."):
        return "Streak or progress label. Keep it short."
    return "In-app text."


def build_instruction(key, en_value):
    parts = [context_hint(key)]

    placeholders = PLACEHOLDER_RE.findall(en_value)
    if placeholders:
        uniq = ", ".join(dict.fromkeys(placeholders))
        parts.append(
            f"Keep the placeholders exactly ({uniq}); the app fills them with "
            "numbers/text at runtime. You may reorder them to fit natural word order."
        )

    pipe_pairs = en_value.count("|") // 2
    if pipe_pairs:
        parts.append(
            f"|pipes| mark bold text ({pipe_pairs} pair(s) here). Wrap the matching "
            "word(s) in your language in |pipes|, do not translate the pipes away."
        )

    # Length reference to help translators keep UI text within bounds.
    ref = len(en_value)
    parts.append(f"English is {ref} characters. Try to stay close to that.")
    return " ".join(parts)


def main():
    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)
    strings = catalog["strings"]

    header = ["key", "variant", "instruction", "en", "nl"] + TARGET_LANGS
    rows = []

    for key in sorted(strings.keys()):
        locs = strings[key].get("localizations", {})
        en = locs.get("en")
        nl = locs.get("nl")
        if en is None:
            continue
        en_pairs = dict(unit_value(en))
        nl_pairs = dict(unit_value(nl)) if nl else {}

        for variant, en_value in unit_value(en):
            instruction = build_instruction(key, en_value)
            nl_value = nl_pairs.get(variant, "")
            row = [key, variant, instruction, en_value, nl_value] + [""] * len(TARGET_LANGS)
            rows.append(row)

    with open(OUTPUT, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f, delimiter=";", quoting=csv.QUOTE_MINIMAL)
        writer.writerow(header)
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows x {len(header)} columns to {OUTPUT}")


if __name__ == "__main__":
    main()
