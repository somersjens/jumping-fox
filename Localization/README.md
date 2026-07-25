# Translation workflow

The app ships one string catalog — `Jumping Fox/Localizable.xcstrings` — with a
column per language. English (`en`) and Dutch (`nl`) are hand-written; every
other language currently holds the **English text as a fallback**, so nothing is
ever missing on screen. This folder holds the tooling to translate the rest with
a single spreadsheet.

## Files

| File | Purpose |
|------|---------|
| `export_template.py` | Generates `translations_template.csv` from the catalog. |
| `translations_template.csv` | The spreadsheet to fill in (regenerate any time). |
| `import_translations.py` | Loads a filled CSV back into the catalog. |

## The CSV format

Semicolon-separated (`;`), UTF-8, standard CSV quoting (a value may safely
contain `;`, `"` or a line break — Excel / Numbers / Google Sheets all read it).

| Column | Edit? | Meaning |
|--------|-------|---------|
| `key` | **No** | Catalog identifier. Used to match rows on import. |
| `variant` | **No** | Empty for a normal string; `one` / `other` for the two rows of a plural string. |
| `instruction` | No | Guidance: where the text appears, how long it may be, which placeholders and bold markers to preserve. |
| `en` | Rarely | English source. Only change if you mean to change the source wording. |
| `nl` | Optional | Dutch. |
| `af`, `sq`, … `sv` | **Yes** | One column per target language — fill these in. |

### Rules for translators

- **Placeholders** like `%lld` (a number) and `%@` (some text) must stay exactly
  as-is; the app fills them at runtime. You may move them to fit natural word
  order. Numbered placeholders (`%1$lld`, `%2$lld`) keep their numbers.
- **Bold** is marked with `|pipes|`: text between a pair of pipes is shown bold.
  Keep the same number of pipe pairs and wrap the equivalent word(s) in your
  language. Example: `Earn |1| trophy` → German `Verdiene |1| Trophäe`.
- **Plural** strings appear as two rows (`one` and `other`). Fill both. If your
  language needs more categories (`zero`, `few`, `many`, `two`), add a row with
  that value in `variant` and tell us — the importer will place it correctly.
- **Empty cell = keep the English fallback.** You can translate one language (or
  even a few rows) at a time and send it back; empty cells are never overwritten.

## Round trip

Regenerate the empty template (safe any time — it never touches the catalog):

```bash
cd Localization
python3 export_template.py
```

Import a filled file back into the catalog:

```bash
cd Localization
python3 import_translations.py path/to/translations_filled.csv --dry-run   # preview
python3 import_translations.py path/to/translations_filled.csv             # apply
```

The importer writes each non-empty cell with state `translated`, matching rows by
`key` + `variant` (so duplicate English strings are never confused). It reports a
per-language count and skips — never invents — any unknown key.

After importing, open the project in Xcode and build once so the per-language
`.lproj` bundles are regenerated, then run the app and switch languages from the
in-app flag picker to check the result.

## Adding a brand-new language later

1. Add one row to `AppLanguage.all` in `Jumping Fox/Localization.swift`
   (`code`, `flag`, own-language `displayName`).
2. Add the same code to `knownRegions` in `Jumping Fox.xcodeproj/project.pbxproj`.
3. Seed the catalog column with the English fallback (or add a column to the CSV
   and import translations). The runtime already falls back to English for any
   key a language has not translated yet.
