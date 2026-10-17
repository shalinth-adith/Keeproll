# Merges the translation tables into the string catalog. Usage: python3 scripts/l10n/apply.py
import json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from translations_hi import T as HI
from translations_ta import T as TA

path = 'Keeproll/Resources/Localizable.xcstrings'
d = json.load(open(path))
missing = {'hi': [], 'ta': []}
for key, entry in d['strings'].items():
    if entry.get('shouldTranslate') is False:
        continue
    for lang, table in (('hi', HI), ('ta', TA)):
        if key in table:
            entry.setdefault('localizations', {})[lang] = {'stringUnit': {'state': 'translated', 'value': table[key]}}
        else:
            missing[lang].append(key)
json.dump(d, open(path, 'w'), ensure_ascii=False, indent=2, sort_keys=True)
for lang, keys in missing.items():
    print(lang, 'missing', len(keys))
    for k in keys: print('   ', repr(k))
# Placeholder sanity: every %@ / %lld / %% in the source must appear in the translation.
import re
bad = 0
for key, entry in d['strings'].items():
    src = re.findall(r'%(?:lld|@|%)', key)
    for lang in ('hi', 'ta'):
        v = entry.get('localizations', {}).get(lang, {}).get('stringUnit', {}).get('value')
        if v is None: continue
        if sorted(re.findall(r'%(?:lld|@|%)', v)) != sorted(src):
            bad += 1; print('placeholder mismatch', lang, repr(key), '->', repr(v))
print('placeholder mismatches:', bad)
