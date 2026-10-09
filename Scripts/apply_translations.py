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
  en-plurals.json         English one/other forms for the counted strings (Nyx and NyxVision catalogs)
  es-plurals.json         the same keys in Spanish. Written as real plural variations, never a branch in code.
                          A string with one counted number is {"one": "...", "other": "..."}. A string with
                          several is {"format": "%#@nights@ under the stars at %#@parks@",
                          "nights": {"arg": 1, "one": "%arg night", "other": "%arg nights"}, ...}.
  learn/<name>.md         (Nyx/Resources) the English of essay.<name>, so the essays have one source

English values for the data-backed keys (shower.*, access.*) are taken from sky-events.json and
parks.json, so the bundled data stays the single source of the English text.

    python3 Scripts/apply_translations.py            # merge
    python3 Scripts/apply_translations.py --check    # report only; exit 1 if a key lacks Spanish
"""
import json,pathlib,re,sys
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
    for path in sorted((ROOT/'Nyx/Resources/learn').glob('*.md')):
        en['essay.'+path.stem]=path.read_text(encoding='utf-8').strip()
    return en,es

def constellation_keys():
    """English names for the Vision Pro sky (Nyx/Resources/constellations.json); Spanish is in es-vision-strings.json."""
    path=ROOT/'Nyx/Resources/constellations.json'
    names=load(path).get('names',{}) if path.exists() else {}
    return {'constellation.'+abbr:name for abbr,name in names.items()}

def essays():
    return {'essay.'+path.stem:path.read_text(encoding='utf-8').strip() for path in sorted((L10N/'learn-es').glob('*.md'))}

CATEGORIES=('one','other')

def plural_problems(key,spec):
    """What is wrong with one plural spec (a list of messages; empty when it is complete)."""
    names=[name for name in spec if name!='format']
    if 'format' in spec:
        out=[]
        wanted=re.findall(r'%#@(\w+)@',spec['format'])
        if sorted(wanted)!=sorted(names): out.append(f'format names {wanted} but forms for {names}')
        for name in names:
            if not isinstance(spec[name].get('arg'),int): out.append(f'{name}: no "arg" number')
            out+=[f'{name}: no "{c}" form' for c in CATEGORIES if not spec[name].get(c)]
        return out
    return [f'no "{c}" form' for c in CATEGORIES if not spec.get(c)]

def plural_localization(spec):
    """The catalog JSON for one language of a counted string (Xcode's own layout)."""
    if 'format' not in spec:
        return {'variations':{'plural':{c:unit(spec[c]) for c in CATEGORIES}}}
    return {'stringUnit':unit(spec['format'])['stringUnit'],
            'substitutions':{name:{'argNum':sub['arg'],'formatSpecifier':'lld','variations':{'plural':{c:unit(sub[c]) for c in CATEGORIES}}}
                             for name,sub in spec.items() if name!='format'}}

def plural_texts(spec):
    """Every text a plural spec can print, for the format-specifier check."""
    if 'format' not in spec: return [spec[c] for c in CATEGORIES if spec.get(c)]
    return [spec['format']]+[sub[c] for name,sub in spec.items() if name!='format' for c in CATEGORIES if sub.get(c)]

SPEC=re.compile(r'%(?:(\d+)\$)?(?:#@\w+@|arg\b|[-+0#]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDuUiIfgeEsScCpx%])')
def specifiers(text):
    """The multiset of format specifiers in a text, positions ignored: %@ and %lld count the same however numbered.
    A literal %% counts too, and a stray % that starts no specifier shows up as '%?' (it would crash or print wrongly)."""
    found=[re.sub(r'^%\d+\$','%',m.group(0)) for m in SPEC.finditer(text)]
    left=SPEC.sub('',text).count('%')
    return sorted(found+['%?']*left)

def mismatch(english,spanish):
    return specifiers(english)!=specifiers(spanish)

def format_problems(strings):
    """Keys whose Spanish has other format specifiers than the English (count and type; positions are free)."""
    out=[]
    for key,entry in strings.items():
        loc=entry.get('localizations',{})
        en,es=loc.get('en'),loc.get(LANG)
        if not en or not es: continue
        if 'stringUnit' in en and 'stringUnit' in es and 'substitutions' not in en:
            if mismatch(en['stringUnit']['value'],es['stringUnit']['value']): out.append(key)
        elif 'variations' in en and 'variations' in es:
            a,b=en['variations'],es['variations']
            if 'device' in a and 'device' in b:
                if any(mismatch(a['device'][kind]['stringUnit']['value'],b['device'][kind]['stringUnit']['value']) for kind in ('ipad','other')): out.append(key)
            elif 'plural' in a and 'plural' in b:
                if mismatch(a['plural']['other']['stringUnit']['value'],b['plural']['other']['stringUnit']['value']): out.append(key)
        elif 'substitutions' in en and 'substitutions' in es:
            def joined(loc): return ' '.join([loc['stringUnit']['value']]+[sub['variations']['plural']['other']['stringUnit']['value'] for _,sub in sorted(loc['substitutions'].items())])
            if mismatch(joined(en),joined(es)): out.append(key)
    return out

def merge(path,translations,english=None,device=False,plurals=None):
    """Returns the keys that have no Spanish. `english` adds or refreshes hand-written source keys.
    `plurals` is (English specs, Spanish specs): counted strings that become real plural variations."""
    original=path.read_text(encoding='utf-8')
    catalog=json.loads(original)
    strings=catalog['strings']
    for key,value in (english or {}).items():
        entry=strings.setdefault(key,{'extractionState':'manual','localizations':{}})
        entry.setdefault('localizations',{})['en']=unit(value)
    plural_en,plural_es=plurals or ({}, {})
    missing=[]
    for key,spec in plural_en.items():
        if key not in strings: continue  # a counted string this target does not use
        problems=plural_problems(key,spec)
        if problems: raise SystemExit(f'{path.name}: en plural {key!r}: {"; ".join(problems)}')
        strings[key].setdefault('localizations',{})['en']=plural_localization(spec)
    for key,entry in strings.items():
        if entry.get('shouldTranslate') is False: continue
        localizations=entry.setdefault('localizations',{})
        if key in plural_en:
            spec=plural_es.get(key)
            if spec is None or plural_problems(key,spec):
                missing.append(key if spec is None else f'{key} (plural: {"; ".join(plural_problems(key,spec))})')
                localizations.pop(LANG,None); continue
            localizations[LANG]=plural_localization(spec); continue
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
    return missing,format_problems(strings)

def optional(path): return load(path) if path.exists() else {}


def main():
    strings=load(L10N/'es-strings.json')
    strings.update(essays())
    english,spanish=data_keys()
    strings.update(spanish)
    plurals=(optional(L10N/'en-plurals.json'),optional(L10N/'es-plurals.json'))
    report,formats={},{}
    report['Localizable'],formats['Localizable']=merge(ROOT/'Nyx/Resources/Localizable.xcstrings',strings,english,device=True,plurals=plurals)
    report['InfoPlist'],formats['InfoPlist']=merge(ROOT/'Nyx/Resources/InfoPlist.xcstrings',load(L10N/'es-infoplist.json'))
    vision=ROOT/'NyxVision/Resources/Localizable.xcstrings'
    if vision.exists():
        # The Vision Pro window shows shower names too (WhatsUp), from its own catalog, and the constellation names.
        showers={key:value for key,value in english.items() if key.startswith('shower.')}
        report['NyxVision'],formats['NyxVision']=merge(vision,{**load(L10N/'es-vision-strings.json'),**spanish},{**showers,**constellation_keys()},plurals=plurals)
    gaps=0
    for name,missing in report.items():
        for key in missing: print(f'{name}: no Spanish for {key!r}'); gaps+=1
    for name,keys in formats.items():
        for key in keys: print(f'{name}: format specifiers differ from the English for {key!r}'); gaps+=1
    print('Spanish:',', '.join(f'{name} {"ok" if not missing else str(len(missing))+" missing"}' for name,missing in report.items()))
    return gaps

if __name__=='__main__':
    sys.exit(1 if main() and '--check' in sys.argv else 0)
