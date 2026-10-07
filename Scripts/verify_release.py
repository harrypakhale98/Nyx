"""Validate bundle facts from an unsigned/signed archive; no network required.
Usage: python3 Scripts/verify_release.py [--require-key] [IOS_ARCHIVE] [VISION_ARCHIVE]. Never prints the NPS key, only whether it was expanded.
--require-key fails when the archive carries no NPS key (every upload to App Store Connect must)."""
import json,plistlib,re,sys,subprocess
from pathlib import Path
requireKey='--require-key' in sys.argv[1:]
args=[a for a in sys.argv[1:] if not a.startswith('--')]
root=Path(args[0] if args else '/tmp/Nyx.xcarchive')/'Products/Applications/Nyx.app'
info=plistlib.loads((root/'Info.plist').read_bytes())
# Universal since 1.1: iPhone stays portrait; iPad takes every orientation.
assert info['UIDeviceFamily']==[1,2],info['UIDeviceFamily']
assert info.get('UISupportedInterfaceOrientations~iphone')==['UIInterfaceOrientationPortrait'],info.get('UISupportedInterfaceOrientations~iphone')
assert set(info.get('UISupportedInterfaceOrientations~ipad',[]))=={'UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'}
assert info.get('NSSupportsLiveActivities') is True
assert 'NSAlarmKitUsageDescription' in info
assert set(info.get('CFBundleIcons',{}).get('CFBundleAlternateIcons',{}))=={'AppIconNew','AppIconQuarter','AppIconFull'},info.get('CFBundleIcons')
assert (root/'es.lproj').is_dir(),'Spanish localization missing from the app bundle'
assert info['CFBundleIdentifier']=='com.harrypakhale.nyx'
assert info.get('ITSAppUsesNonExemptEncryption') is False,'ITSAppUsesNonExemptEncryption must be present and NO'
assert 'NSLocationWhenInUseUsageDescription' in info
assert 'NSLocationAlwaysAndWhenInUseUsageDescription' not in info
assert 'NSPhotoLibraryUsageDescription' not in info
# One background mode, for the saved-park refresh (explained in the review notes), and its task id.
assert info.get('UIBackgroundModes')==['fetch'],info.get('UIBackgroundModes')
assert info.get('BGTaskSchedulerPermittedIdentifiers')==['com.harrypakhale.nyx.refresh'],info.get('BGTaskSchedulerPermittedIdentifiers')
assert info.get('CADisableMinimumFrameDurationOnPhone') is True
# The journal export type, declared and opened by Nyx (copied in, never edited in place).
assert [t.get('UTTypeIdentifier') for t in info.get('UTExportedTypeDeclarations',[])]==['com.harrypakhale.nyx.journal']
assert info.get('LSSupportsOpeningDocumentsInPlace') is False
watchApp=root/'Watch/NyxWatch.app'
watchInfo=plistlib.loads((watchApp/'Info.plist').read_bytes())
assert watchInfo['CFBundleIdentifier']=='com.harrypakhale.nyx.watchkitapp'
assert watchInfo['WKCompanionAppBundleIdentifier']=='com.harrypakhale.nyx'
assert watchInfo['UIDeviceFamily']==[4],watchInfo['UIDeviceFamily']
def check_manifest(folder,userDefaults=True):
 manifest=plistlib.loads((folder/'PrivacyInfo.xcprivacy').read_bytes())
 assert manifest['NSPrivacyTracking']==False
 assert manifest['NSPrivacyTrackingDomains']==[]
 assert manifest['NSPrivacyCollectedDataTypes']==[] # Data Not Collected; reasoning in PRIVACY.md
 apis=manifest['NSPrivacyAccessedAPITypes']
 if not userDefaults: assert apis==[],apis; return
 assert len(apis)==1 and apis[0]['NSPrivacyAccessedAPIType']=='NSPrivacyAccessedAPICategoryUserDefaults'
 assert set(apis[0]['NSPrivacyAccessedAPITypeReasons'])=={'CA92.1','1C8F.1'}
for folder in [root,root/'PlugIns/NyxWidgets.appex',watchApp,watchApp/'PlugIns/NyxWatchWidgets.appex']: check_manifest(folder)
# The app's manifest source names exactly the three hosts it may contact (a comment, stripped when bundled; none is a tracking domain).
assert set(re.findall(r'[a-z-]+(?:\.[a-z-]+)*\.(?:gov|com)',' '.join(re.findall(r'<!--(.*?)-->',Path('Nyx/Resources/PrivacyInfo.xcprivacy').read_text(),re.S))))=={'developer.nps.gov','api.open-meteo.com','air-quality-api.open-meteo.com'}
for name in ['Nyx','NyxWidgets','NyxWatch','NyxWatchWidgets']:
 ent=plistlib.loads(Path('Config/'+name+'.entitlements').read_bytes())
 assert ent['com.apple.security.application-groups']==['group.com.harrypakhale.nyx']
project=Path('Nyx.xcodeproj/project.pbxproj').read_text()
assert 'XCRemoteSwiftPackageReference' not in project
source=Path('Nyx/Services/DataServices.swift').read_text()
assert set(re.findall(r'host="([^"]+)"',source))=={'developer.nps.gov','api.open-meteo.com','air-quality-api.open-meteo.com'}
assert 'completionHandler(nil)' in source
# Every shipping source file: URLSession and web URLs may appear only in the guarded transport.
shipping=[f for folder in ['Nyx','NyxWidgets','NyxWatch','NyxWatchWidgets','NyxWatchShared'] for f in Path(folder).rglob('*.swift')]
# The watch makes no requests at all: its targets must never compile the network transport.
spec_text=Path('project.yml').read_text()
for target in ['NyxWatch','NyxWatchWidgets','NyxVision','NyxVisionWidgets']:
 block=re.search(r'\n  '+target+r':\n(.*?)(?=\n  [A-Za-z]+:\n)',spec_text,re.S).group(1)
 assert 'DataServices.swift' not in block,f'{target} must not include the network transport'
for f in [f for folder in ['NyxWatch','NyxWatchWidgets','NyxWatchShared','NyxVision','NyxVisionWidgets'] for f in Path(folder).rglob('*.swift')]:
 assert 'URLSession' not in f.read_text() and 'URLRequest' not in f.read_text(),f'network code in a watch source: {f}'
for f in shipping:
 if f.name=='DataServices.swift': continue
 text=f.read_text()
 assert 'URLSession' not in text,f'URLSession outside the guarded transport: {f}'
 assert not re.search(r'"https?://',text),f'web URL literal outside the guarded transport: {f}'
# Pages opened in Safari at a tap (SwiftUI Link), never fetched by Nyx: exactly this list.
browser=Path('Nyx/Views/SkyGlowViews.swift').read_text()
assert set(re.findall(r'page\(host:"([^"]+)"',browser))=={'globeatnight.org','www.nps.gov'}
# Version and build come from project.yml; the archive must carry them in both bundles.
spec=Path('project.yml').read_text()
marketing=re.search(r'MARKETING_VERSION:\s*"([^"]+)"',spec).group(1)
build=re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"',spec).group(1)
widget=plistlib.loads((root/'PlugIns/NyxWidgets.appex/Info.plist').read_bytes())
watchWidget=plistlib.loads((watchApp/'PlugIns/NyxWatchWidgets.appex/Info.plist').read_bytes())
for bundle in [info,widget,watchInfo,watchWidget]:
 assert (bundle['CFBundleShortVersionString'],bundle['CFBundleVersion'])==(marketing,build),(bundle['CFBundleShortVersionString'],bundle['CFBundleVersion'],marketing,build)
packages=project.count('XCRemoteSwiftPackageReference')
manifests=sum((folder/'PrivacyInfo.xcprivacy').exists() for folder in [root,root/'PlugIns/NyxWidgets.appex',watchApp,watchApp/'PlugIns/NyxWatchWidgets.appex'])
npsKey=info.get('NPS_API_KEY','')
assert '$(' not in npsKey,'NPS_API_KEY was not expanded'
assert not requireKey or npsKey.strip(),'NPS_API_KEY is empty: park alerts would never load (--require-key)'
# The key comes from the git-ignored Config/Secrets.xcconfig on this Mac; compare without printing it.
secrets=Path('Config/Secrets.xcconfig')
if secrets.exists():
 local=re.search(r'^\s*NPS_API_KEY\s*=\s*(\S*)',secrets.read_text(),re.M)
 assert local and local.group(1)==npsKey,'archive NPS key differs from Config/Secrets.xcconfig'
assert 'Secrets.xcconfig' in Path('.gitignore').read_text()
assert subprocess.run(['git','ls-files','--error-unmatch','Config/Secrets.xcconfig'],capture_output=True).returncode!=0,'Secrets.xcconfig is tracked'
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
# Apple Vision Pro: a separate archive of the same bundle ID (universal purchase), no network code at all.
vision=None
visionArchive=Path(args[1]) if len(args)>1 else None
if visionArchive:
 vroot=visionArchive/'Products/Applications/NyxVision.app'
 vinfo=plistlib.loads((vroot/'Info.plist').read_bytes())
 assert vinfo['CFBundleIdentifier']=='com.harrypakhale.nyx'
 assert vinfo['UIDeviceFamily']==[7],vinfo['UIDeviceFamily']
 assert vinfo.get('ITSAppUsesNonExemptEncryption') is False
 assert (vinfo['CFBundleShortVersionString'],vinfo['CFBundleVersion'])==(marketing,build)
 check_manifest(vroot,userDefaults=False)
 # The visionOS widget: its own empty manifest, the same version and build.
 vwidget=vroot/'PlugIns/NyxVisionWidgets.appex'
 check_manifest(vwidget,userDefaults=False)
 vwinfo=plistlib.loads((vwidget/'Info.plist').read_bytes())
 assert (vwinfo['CFBundleShortVersionString'],vwinfo['CFBundleVersion'])==(marketing,build)
 vsigned=(vroot/'embedded.mobileprovision').exists()
 if vsigned: subprocess.run(['codesign','--verify','--deep','--strict',str(vroot)],check=True,capture_output=True)
 vision={'version':vinfo['CFBundleShortVersionString'],'build':vinfo['CFBundleVersion'],'deviceFamily':vinfo['UIDeviceFamily'],'networkCode':False,'signed':vsigned}
report={'deviceFamily':info['UIDeviceFamily'],'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'bundledManifests':manifests,'runtimeHTTPHosts':sorted(set(re.findall(r'host="([^"]+)"',source))),'runtimePackages':packages,'npsKeyEmbedded':bool(npsKey),'catalogKeys':len(catalog['strings']),'privacyDeclaration':'Data Not Collected (PRIVACY.md); publisher confirms in App Store Connect','signing':signing,'verified':__import__('datetime').date.today().isoformat(),'archives':[str(root.parents[2])]+([str(visionArchive)] if visionArchive else []),'watchApp':{'version':watchInfo['CFBundleShortVersionString'],'build':watchInfo['CFBundleVersion']},'visionApp':vision}
Path('Research/release-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
