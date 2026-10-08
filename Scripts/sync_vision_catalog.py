"""Merge the Vision Pro app's compiler-extracted strings into its own String Catalog.

NyxVision keeps a separate `NyxVision/Resources/Localizable.xcstrings` (engine strings it shares
with the iPhone app plus its own), so `sync_catalog.py`'s pruning of the iPhone catalog never
removes Vision-only copy. Run after a visionOS simulator build:
    python3 Scripts/sync_vision_catalog.py /tmp/NyxVisionBuild
"""
import json,pathlib,glob,sys
path=pathlib.Path('NyxVision/Resources/Localizable.xcstrings')
catalog=json.loads(path.read_text()) if path.exists() else {'sourceLanguage':'en','strings':{},'version':'1.0'}
strings=catalog['strings']
build=sys.argv[1] if len(sys.argv)>1 else '/tmp/NyxVisionBuild'
extracted=set()
for filename in glob.glob(build+'/Build/Intermediates.noindex/*.build/Debug-xrsimulator/NyxVision.build/Objects-normal/arm64/*.stringsdata'):
 try: data=json.load(open(filename))
 except (ValueError,OSError): continue
 for item in data.get('tables',{}).get('Localizable',[]):
  key=item['key']
  extracted.add(key)
  if key in strings: continue
  strings[key]={'extractionState':'manual','localizations':{'en':{'stringUnit':{'state':'translated','value':key}}}}
  if item.get('comment'): strings[key]['comment']=item['comment']
# Prune copy no longer in code: auto-added entries (value == key) and counted ones (plural
# variations written by apply_translations.py); hand-written keys (constellation.*, shower.*) stay.
def generated(key,entry):
    en=entry.get('localizations',{}).get('en',{})
    return 'variations' in en or 'substitutions' in en or en.get('stringUnit',{}).get('value')==key
if extracted:
 for key in [k for k,v in strings.items() if k not in extracted and not k.startswith(('constellation.','shower.')) and generated(k,v)]:
  del strings[key]
catalog['strings']=dict(sorted(strings.items()))
path.write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+'\n')
print('Vision catalog:',len(strings),'keys')
# Spanish (and the data-backed shower.*/access.* keys) after every sync, so new copy never drops it.
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
import apply_translations
apply_translations.main()
