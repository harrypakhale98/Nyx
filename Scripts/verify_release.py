"""Validate bundle facts from an unsigned/signed archive; no network required."""
import json,plistlib,re,sys,subprocess
from pathlib import Path
root=Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/Nyx.xcarchive')/'Products/Applications/Nyx.app'
info=plistlib.loads((root/'Info.plist').read_bytes())
assert info['UIDeviceFamily']==[1],info['UIDeviceFamily']
assert info['UISupportedInterfaceOrientations']==['UIInterfaceOrientationPortrait']
assert info['CFBundleIdentifier']=='com.harrypakhale.nyx'
assert not info.get('ITSAppUsesNonExemptEncryption',False)
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
assert set(re.findall(r'host="([^"]+)"',source))=={'developer.nps.gov','api.open-meteo.com'}
assert 'completionHandler(nil)' in source
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
report={'deviceFamily':info['UIDeviceFamily'],'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'bundledManifests':2,'runtimeHTTPHosts':['developer.nps.gov','api.open-meteo.com'],'runtimePackages':0,'catalogKeys':len(catalog['strings']),'privacyDeclaration':'UNRESOLVED — publisher review required','signing':signing}
Path('Research/release-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
