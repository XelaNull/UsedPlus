# FS25_UsedPlus Translations

This folder contains all localization files for the UsedPlus mod.

## Files

| File | Language | Code |
|------|----------|------|
| `translation_en.xml` | English | EN |
| `translation_de.xml` | German | DE |
| `translation_fr.xml` | French | FR |
| `translation_es.xml` | Spanish | ES |
| `translation_it.xml` | Italian | IT |
| `translation_pl.xml` | Polish | PL |
| `translation_ru.xml` | Russian | RU |
| `translation_br.xml` | Brazilian Portuguese | BR |
| `translation_cz.xml` | Czech | CZ |
| `translation_uk.xml` | Ukrainian | UK |

## Entry Format

Each translation entry uses this format:

```xml
<e k="usedplus_finance_title" v="Vehicle Financing" eh="6efef1bd" />
```

| Attribute | Description |
|-----------|-------------|
| `k` | Key - unique identifier referenced in Lua code |
| `v` | Value - the translated text |
| `eh` | English Hash - 8-character MD5 hash of the English source text |

## Version Tracking with `eh` Attribute

The `eh` (English Hash) attribute enables tracking when translations become stale:

1. Each entry stores a hash of its English source text
2. When the English text changes, the hash no longer matches
3. Running `check` identifies which entries need re-translation

This eliminates guesswork about which translations are current.

## Translation Sync Tool

`translation_sync.py` manages translation versioning.

### Commands

```bash
# Check which entries are out of sync
python translation_sync.py check

# Add/update hashes to all translation files
python translation_sync.py stamp

# Generate detailed sync report
python translation_sync.py report
```

### Example Output

**check command:**
```
Checking translation sync status...

  German      : OK
  French      : OK
  Spanish     : NEEDS UPDATE
    Out of sync (3):
      - usedplus_finance_title
      - usedplus_lease_description
      - usedplus_credit_tooltip
  Italian     : OK
  ...

Total out of sync: 3 entries need re-translation
```

**report command:**
```
============================================================
TRANSLATION SYNC REPORT
============================================================

English source: 1388 strings

German (DE):
  In sync:      1385
  Out of sync:  3
  Missing hash: 0
  Untranslated: 0
  --- Out of sync entries (need re-translation) ---
    usedplus_finance_title:
      EN: Vehicle Financing Options
    ...
```

## Workflow

### Adding New Strings

1. Add the new key to `translation_en.xml`
2. Add the same key to all other translation files with translated values
3. Run `python translation_sync.py stamp` to add hashes

### Updating English Text

1. Modify the value in `translation_en.xml`
2. Run `python translation_sync.py check` to see affected translations
3. Update the translations in each language file
4. Run `python translation_sync.py stamp` to update hashes

### Verifying Translations

Run `python translation_sync.py check` anytime to verify all translations are current.

## Translation Guidelines

### Context Matters

Some terms have different meanings in different contexts:

| English | Context | Correct Translation Approach |
|---------|---------|------------------------------|
| Poor | Credit rating | "Bad" quality, not "impoverished" |
| Fair | Credit rating | "Acceptable/Passable", not "just/equitable" |
| Good | Credit rating | Adjective "good", not adverb "well" |

### Special Characters

XML requires escaping these characters in values:

| Character | Escape Sequence |
|-----------|-----------------|
| `<` | `&lt;` |
| `>` | `&gt;` |
| `&` | `&amp;` |
| `"` | `&quot;` |

Example: `<e k="key" v="Score &lt;600 is poor" />`

### Placeholders

Some strings contain placeholders that must be preserved:

- `%s` - String placeholder
- `%d` - Integer placeholder
- `%.2f` - Decimal placeholder
- `%1$s`, `%2$s` - Ordered placeholders

Example: `"Payment: %s per month"` must keep `%s` in all translations.

## Requirements

- Python 3.6+
- No external dependencies (uses only standard library)
