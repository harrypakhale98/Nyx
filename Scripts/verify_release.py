"""Validate bundle facts from an unsigned/signed archive; no network required."""
import json,plistlib,re,sys,subprocess
from pathlib import Path
root=Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/Nyx.xcarchive')/'Products/Applications/Nyx.app'
info=plistlib.loads((root/'Info.plist').read_bytes())
assert info['UIDeviceFamily']==[1],info['UIDeviceFamily']
assert info['UISupportedInterfaceOrientations']==['UIInterfaceOrientationPortrait']
assert info['CFBundleIdentifier']=='com.harrypakhale.nyx'
assert info.get('ITSAppUsesNonExemptEncryption') is False,'ITSAppUsesNonExemptEncryption must be present and NO'
assert 'NSLocationWhenInUseUsageDescription' in info
assert 'NSLocationAlwaysAndWhenInUseUsageDescription' not in info
assert 'NSPhotoLibraryUsageDescription' not in info
for folder in [root,root/'PlugIns/NyxWidgets.appex']:
 manifest=plistlib.loads((folder/'PrivacyInfo.xcprivacy').read_bytes())
 assert manifest['NSPrivacyTracking']==False
 assert manifest['NSPrivacyTrackingDomains']==[]
 assert manifest['NSPrivacyCollectedDataTypes']==[] # draft; see unresolved publisher gate in PRIVACY.md
 apis=manifest['NSPrivacyAccessedAPITypes']
 assert len(apis)==1 and apis[0]['NSPrivacyAccessedAPIType']=='NSPrivacyAccessedAPICategoryUserDefaults'
 assert set(apis[0]['NSPrivacyAccessedAPITypeReasons'])=={'CA92.1','1C8F.1'}
for name in ['Nyx','NyxWidgets']:
 ent=plistlib.loads(Path('Config/'+name+'.entitlements').read_bytes())
 assert ent['com.apple.security.application-groups']==['group.com.harrypakhale.nyx']
project=Path('Nyx.xcodeproj/project.pbxproj').read_text()
assert 'XCRemoteSwiftPackageReference' not in project
source=Path('Nyx/Services/DataServices.swift').read_text()
assert set(re.findall(r'host="([^"]+)"',source))=={'developer.nps.gov','api.open-meteo.com','air-quality-api.open-meteo.com'}
assert 'completionHandler(nil)' in source
# Every shipping source file: URLSession and web URLs may appear only in the guarded transport.
shipping=[f for f in list(Path('Nyx').rglob('*.swift'))+list(Path('NyxWidgets').rglob('*.swift'))]
for f in shipping:
 if f.name=='DataServices.swift': continue
 text=f.read_text()
 assert 'URLSession' not in text,f'URLSession outside the guarded transport: {f}'
 assert not re.search(r'"https?://',text),f'web URL literal outside the guarded transport: {f}'
# Version and build come from project.yml; the archive must carry them in both bundles.
spec=Path('project.yml').read_text()
marketing=re.search(r'MARKETING_VERSION:\s*"([^"]+)"',spec).group(1)
build=re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"',spec).group(1)
widget=plistlib.loads((root/'PlugIns/NyxWidgets.appex/Info.plist').read_bytes())
for bundle in [info,widget]:
 assert (bundle['CFBundleShortVersionString'],bundle['CFBundleVersion'])==(marketing,build),(bundle['CFBundleShortVersionString'],bundle['CFBundleVersion'],marketing,build)
packages=project.count('XCRemoteSwiftPackageReference')
manifests=sum((folder/'PrivacyInfo.xcprivacy').exists() for folder in [root,root/'PlugIns/NyxWidgets.appex'])
npsKey=info.get('NPS_API_KEY','')
assert '$(' not in npsKey,'NPS_API_KEY was not expanded'
catalog=json.loads(Path('Nyx/Resources/Localizable.xcstrings').read_text())
assert len(catalog['strings'])>=300
for key,item in catalog['strings'].items():
 assert 'en' in item.get('localizations',{}),key
signed=(root/'embedded.mobileprovision').exists()
if signed:
 subprocess.run(['codesign','--verify','--deep','--strict',str(root)],check=True,capture_output=True)
 profile=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(root/'embedded.mobileprovision')]))
 development=profile['Entitlements'].get('get-task-allow',False)
 signing='development-signed Release; App Store export/validation pending' if development else 'signed Release; distribution validation pending'
else: signing='unsigned archive; distribution validation pending'
report={'deviceFamily':info['UIDeviceFamily'],'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'bundledManifests':manifests,'runtimeHTTPHosts':sorted(set(re.findall(r'host="([^"]+)"',source))),'runtimePackages':packages,'npsKeyEmbedded':bool(npsKey),'catalogKeys':len(catalog['strings']),'privacyDeclaration':'UNRESOLVED — publisher review required','signing':signing}
Path('Research/release-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
