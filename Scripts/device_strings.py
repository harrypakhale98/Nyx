"""iPad wording for copy that names the device: each English string that says "iPhone" (or "this
phone") gains an `ipad` device variation, so the same key reads "this iPad" on an iPad. The watch's
strings, which are about the paired iPhone, keep their wording. Idempotent; run by sync_catalog.py."""
import json,pathlib
path=pathlib.Path(__file__).resolve().parent.parent/'Nyx/Resources/Localizable.xcstrings'
# About the paired iPhone (watch app) or true of iPhone only (the Taptic Engine essay): unchanged.
KEEP={'Follow iPhone again','Match iPhone','Saved on iPhone','Moon and darkness only. Open Nyx on iPhone for clouds.',
      'Nyx on Apple Watch makes no network requests. Clouds come from Nyx on your iPhone.',
      'Nyx on iPhone sends your saved parks and clouds. Until then, the score is moon and darkness only.','essay.access'}
def ipad(text):
    return text.replace('this phone','this iPad').replace('iPhone','iPad')
def apply(catalog):
    changed=0
    for key,entry in catalog['strings'].items():
        if key in KEEP or key.startswith('essay.'): continue
        en=entry.setdefault('localizations',{}).get('en')
        unit=(en or {}).get('stringUnit') or ((en or {}).get('variations',{}).get('device',{}).get('other',{}).get('stringUnit'))
        value=unit['value'] if unit else key
        if 'iPhone' not in value and 'this phone' not in value: continue
        variation={'device':{'ipad':{'stringUnit':{'state':'translated','value':ipad(value)}},'other':{'stringUnit':{'state':'translated','value':value}}}}
        if (en or {}).get('variations') != variation:
            entry['localizations']['en']={'variations':variation}; changed+=1
    return changed
if __name__=='__main__':
    catalog=json.loads(path.read_text())
    n=apply(catalog)
    path.write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+'\n')
    print('iPad variations updated:',n)
