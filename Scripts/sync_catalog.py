"""Merge compiler-extracted strings after xcodebuild (Xcode's IDE does this interactively)."""
import json,pathlib,glob,sys
path=pathlib.Path('Nyx/Resources/Localizable.xcstrings')
catalog=json.loads(path.read_text())
strings=catalog['strings']
build=sys.argv[1] if len(sys.argv)>1 else '/tmp/NyxBuild'
extracted=set()
# iPhone and watch simulator builds both: the watch app shares this catalog.
for filename in glob.glob(build+'/Build/Intermediates.noindex/*.build/Debug-*simulator/*/Objects-normal/arm64/*.stringsdata'):
 if 'Tests.build/' in filename: continue  # test literals are not app copy
 try: data=json.load(open(filename))
 except (ValueError,OSError): continue
 for item in data.get('tables',{}).get('Localizable',[]):
  key=item['key']
  extracted.add(key)
  if key in strings: continue
  strings[key]={'extractionState':'manual','localizations':{'en':{'stringUnit':{'state':'translated','value':key}}}}
  if item.get('comment'): strings[key]['comment']=item['comment']
# Drop copy that no longer appears in code. Only auto-added entries (value == key) are pruned;
# hand-written entries such as the Learn essays (essay.*) are never touched.
# App Intents summaries ("Darkness at ${park} tonight") never reach .stringsdata, so they are kept.
if extracted:
 for key in [k for k,v in strings.items() if k not in extracted and '${' not in k and v.get('localizations',{}).get('en',{}).get('stringUnit',{}).get('value')==k]:
  del strings[key]
# iPad wording for strings that name the device (see device_strings.py).
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
import device_strings
device_strings.apply(catalog)
catalog['strings']=dict(sorted(strings.items()))
path.write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+'\n')
# Usage strings, kept identical to project.yml's Info.plist values. "This device": one plist serves iPhone and iPad.
usage={'NSAlarmKitUsageDescription':"Nyx sets alarms you choose for moments in the night, like the Milky Way's core rising. They are set on this device only.",
       'NSLocationWhenInUseUsageDescription':'Nyx uses your location on this device to find nearby national parks. Your coordinates are never sent to a service.'}
info={'sourceLanguage':'en','strings':{key:{'extractionState':'manual','localizations':{'en':{'stringUnit':{'state':'translated','value':value}}}} for key,value in usage.items()},'version':'1.0'}
path.with_name('InfoPlist.xcstrings').write_text(json.dumps(info,indent=2)+'\n')
print('Catalog:',len(strings),'keys')
# Spanish (and the data-backed shower.*/access.* keys) after every sync, so new copy never drops it.
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
import apply_translations
apply_translations.main()
