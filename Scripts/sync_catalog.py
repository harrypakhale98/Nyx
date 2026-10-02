"""Merge compiler-extracted strings after xcodebuild (Xcode's IDE does this interactively)."""
import json,pathlib,glob,sys
path=pathlib.Path('Nyx/Resources/Localizable.xcstrings')
catalog=json.loads(path.read_text())
strings=catalog['strings']
for filename in glob.glob('/tmp/NyxBuild/Build/Intermediates.noindex/Nyx.build/Debug-iphonesimulator/*/Objects-normal/arm64/*.stringsdata'):
 try: data=json.load(open(filename))
 except (ValueError,OSError): continue
 for item in data.get('tables',{}).get('Localizable',[]):
  key=item['key']
  if key in strings: continue
  strings[key]={'extractionState':'manual','localizations':{'en':{'stringUnit':{'state':'translated','value':key}}}}
  if item.get('comment'): strings[key]['comment']=item['comment']
catalog['strings']=dict(sorted(strings.items()))
path.write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+'\n')
info={'sourceLanguage':'en','strings':{'NSLocationWhenInUseUsageDescription':{'extractionState':'manual','localizations':{'en':{'stringUnit':{'state':'translated','value':'Nyx uses your location on this iPhone to find nearby national parks. Your location is never sent to a service.'}}}}},'version':'1.0'}
path.with_name('InfoPlist.xcstrings').write_text(json.dumps(info,indent=2)+'\n')
print('Catalog:',len(strings),'keys')
