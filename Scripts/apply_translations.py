"""Merge the Spanish translation memory in Research/localization into the String Catalogs.

Reproducible and idempotent: run it after any catalog change (sync_catalog.py and
sync_vision_catalog.py call it at the end). It writes the same JSON layout Xcode and
sync_catalog.py use (2-space indent, ": " separators, keys sorted, UTF-8), so a run that changes
nothing leaves every file byte-for-byte identical.

Sources (Research/localization/):
  es-strings.json         English key -> Spanish, for Nyx/Resources/Localizable.xcstrings
  learn-es/<name>.md      the Learn essays; override the essay.<name> values
  es-shower-names.json    meteor shower code -> Spanish name (keys shower.<CODE>)
  es-access-notes.json    park id -> Spanish access note (keys access.<id>)
  es-infoplist.json       Info.plist usage strings, for Nyx/Resources/InfoPlist.xcstrings
  es-vision-strings.json  for NyxVision/Resources/Localizable.xcstrings

English values for the data-backed keys (shower.*, access.*) are taken from sky-events.json and
parks.json, so the bundled data stays the single source of the English text.

    python3 Scripts/apply_translations.py            # merge
    python3 Scripts/apply_translations.py --check    # report only; exit 1 if a key lacks Spanish
"""
import json,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parent.parent
L10N=ROOT/'Research/localization'
LANG='es'
sys.path.insert(0,str(ROOT/'Scripts'))
import device_strings

def load(path): return json.loads(path.read_text(encoding='utf-8'))
def dump(data): return json.dumps(data,indent=2,ensure_ascii=False)+'\n'
def unit(value): return {'stringUnit':{'state':'translated','value':value}}
def ipad_es(value): return value.replace('este teléfono','este iPad').replace('iPhone','iPad')

def data_keys():
    """English and Spanish for the keys whose English lives in bundled data."""
    en,es={},{}
    showers=load(ROOT/'Nyx/Resources/sky-events.json').get('meteorShowers',[])
    names=load(L10N/'es-shower-names.json')
    for shower in showers:
        key='shower.'+shower['code']
        en[key]=shower['name']
        if shower['code'] in names: es[key]=names[shower['code']]
    notes=load(L10N/'es-access-notes.json') if (L10N/'es-access-notes.json').exists() else {}
    for park in load(ROOT/'Nyx/Resources/parks.json'):
        access=park.get('access')
        if not access: continue
        key='access.'+park['id']
        en[key]=access['note']
        if park['id'] in notes: es[key]=notes[park['id']]
    return en,es

def essays():
    return {'essay.'+path.stem:path.read_text(encoding='utf-8').strip() for path in sorted((L10N/'learn-es').glob('*.md'))}

def merge(path,translations,english=None,device=False):
    """Returns the keys that have no Spanish. `english` adds or refreshes hand-written source keys."""
    original=path.read_text(encoding='utf-8')
    catalog=json.loads(original)
    strings=catalog['strings']
    for key,value in (english or {}).items():
        entry=strings.setdefault(key,{'extractionState':'manual','localizations':{}})
        entry.setdefault('localizations',{})['en']=unit(value)
    missing=[]
    for key,entry in strings.items():
        if entry.get('shouldTranslate') is False: continue
        localizations=entry.setdefault('localizations',{})
        value=translations.get(key)
        if value is None:
            missing.append(key); localizations.pop(LANG,None); continue
        variations=localizations.get('en',{}).get('variations',{})
        if device and 'device' in variations:
            # Mirror the English iPad wording ("this iPad"); the watch's paired-iPhone copy keeps "iPhone".
            ipad=value if key in device_strings.KEEP else ipad_es(value)
            localizations[LANG]={'variations':{'device':{'ipad':unit(ipad),'other':unit(value)}}}
        elif variations:
            raise SystemExit(f'{path.name}: unsupported variation {list(variations)} for {key!r}')
        else:
            localizations[LANG]=unit(value)
    catalog['strings']=dict(sorted(strings.items()))
    text=dump(catalog)
    if text!=original and '--check' not in sys.argv: path.write_text(text,encoding='utf-8')
    return missing

def main():
    strings=load(L10N/'es-strings.json')
    strings.update(essays())
    english,spanish=data_keys()
    strings.update(spanish)
    report={}
    report['Localizable']=merge(ROOT/'Nyx/Resources/Localizable.xcstrings',strings,english,device=True)
    report['InfoPlist']=merge(ROOT/'Nyx/Resources/InfoPlist.xcstrings',load(L10N/'es-infoplist.json'))
    vision=ROOT/'NyxVision/Resources/Localizable.xcstrings'
    if vision.exists():
        # The Vision Pro window shows shower names too (WhatsUp), from its own catalog.
        showers={key:value for key,value in english.items() if key.startswith('shower.')}
        report['NyxVision']=merge(vision,{**load(L10N/'es-vision-strings.json'),**spanish},showers)
    gaps=0
    for name,missing in report.items():
        for key in missing: print(f'{name}: no Spanish for {key!r}'); gaps+=1
    print('Spanish:',', '.join(f'{name} {"ok" if not missing else str(len(missing))+" missing"}' for name,missing in report.items()))
    return gaps

if __name__=='__main__':
    sys.exit(1 if main() and '--check' in sys.argv else 0)
