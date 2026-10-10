"""Raw native-resolution App Store captures for the 1.2 iPhone set. Run after a Debug simulator build.

Usage: python3 Scripts/capture_store.py [SIMULATOR_ID] [DERIVED_DATA] [en|es] [name,name…] [--out FOLDER]
Capture on the iOS 27 iPhone 18 Pro: its 1206×2622 screen is App Store Connect's required iPhone slot
("Dynamic Island, medium display"), so the frames need no scaling. Raw captures are size-neutral
(NN-name.png) and go to FOLDER (default `Store/1.2 v10/raw`, or `Store/1.2 v10/raw/es` for es).
The optional name list retakes only those frames and keeps the rest of the set.

The 1.2 story, real sky first: the sky over the park, Tonight (the only dial in the first three frames),
What's up, then the score's own page, field mode and Where to look in red, the calendar, what city light
takes, every park on the map, and the constellation. Tonight, What's up and the score show Death Valley.
Every frame uses live data (`-nyx-state live`: real Open-Meteo forecasts and NPS alerts at capture time,
scored by the shipping engine), except the journal, which is DEBUG seed data with no personal photo.
Every launch adds `-nyx-reduce-motion`, so no reveal or dial is mid-flight in a still.
The Spanish frames follow the 1.1 order until the native review and are not recaptured with this list.
"""
import subprocess,time,pathlib,sys,tempfile
args=sys.argv[1:]
out=None
if '--out' in args:
 i=args.index('--out'); out=args[i+1]; del args[i:i+2]
sim=args[0] if len(args)>0 else '5BB44DBD-DBE4-4FA3-84C8-8E92D3B3F0B3'
derived=args[1] if len(args)>1 else '/tmp/NyxBuild'
lang=args[2] if len(args)>2 else 'en'
# Optional fourth argument: only these frames (e.g. field,compass), so a retake keeps the rest of the set.
only=set(args[3].split(',')) if len(args)>3 else None
def run(*a): return subprocess.run(['xcrun','simctl',*a],check=True,capture_output=True)
subprocess.run(['xcrun','simctl','boot',sim],capture_output=True)
run('bootstatus',sim,'-b')
run('install',sim,derived+'/Build/Products/Debug-iphonesimulator/Nyx.app')
folder=pathlib.Path(out or ('Store/1.2 v10/raw'+('/es' if lang=='es' else '')));folder.mkdir(parents=True,exist_ok=True)
language=['-AppleLanguages','(es)','-AppleLocale','es_MX'] if lang=='es' else []
today=time.strftime('%Y-%m-%d')
# (name, launch arguments)
shots=[
 # Death Valley's full-screen sky on 3 July 2027, a new-moon summer night: the date is on screen and the
 # default hour (the middle of true darkness) faces south with the Milky Way core in view.
 ('sky',['-nyx-screen','detail','-nyx-park','deva','-nyx-state','live','-nyx-date','2027-07-03','-nyx-sky-view']),
 ('tonight',['-nyx-screen','tonight','-nyx-state','live']),
 ('whatsup',['-nyx-screen','tonight','-nyx-state','live','-nyx-link',f'nyx://whatsup?date={today}&park=deva']),
 # Death Valley, the park Tonight leads with, so the two frames agree on one park and one night.
 ('score',['-nyx-screen','detail','-nyx-state','live','-nyx-park','deva']),
 ('field',['-nyx-screen','field','-nyx-state','live','-nyx-field-minutes','60']),
 # A real summer night: 3 July 2027 at Joshua Tree, new Moon, about 3¾ hours after sunset (the core near transit).
 # Beyond the forecast, so the header's score says it uses the park's usual clouds.
 ('compass',['-nyx-screen','field-compass','-nyx-state','live','-nyx-date','2027-07-03','-nyx-field-minutes','225']),
 ('calendar',['-nyx-screen','calendar','-nyx-state','live']),
 # The Place chapter at Death Valley: the park's own sky, the 'City · Class 8' switch and 'An illustration'.
 ('city-light',['-nyx-screen','light','-nyx-state','live','-nyx-park','deva']),
 ('parks-map',['-nyx-screen','parks','-nyx-state','live','-nyx-parks-map']),
 ('constellation',['-nyx-screen','journal','-nyx-state','populated']),
]
run('status_bar',sim,'override','--time','9:41','--batteryState','charged','--batteryLevel','100','--wifiMode','active','--wifiBars','3','--cellularMode','active','--cellularBars','4')
try:
 for index,(name,args) in enumerate(shots,1):
  if only and name not in only: continue
  run('launch','--terminate-running-process',sim,'com.harrypakhale.nyx',*args,'-nyx-reduce-motion',*language)
  time.sleep(14 if 'live' in args else 8)
  path=folder/f'{index:02d}-{name}.png'
  # Captured to a temporary file and copied in: simctl may be refused when it overwrites a frame in place.
  raw=pathlib.Path(tempfile.gettempdir())/f'nyx-store-{path.name}'
  run('io',sim,'screenshot',str(raw))
  subprocess.run(['cp',str(raw),str(path)],check=True); raw.unlink()
  # App Store Connect rejects screenshots with an alpha channel: flatten through JPEG.
  flat=path.with_suffix('.flat.jpg')
  subprocess.run(['sips','-s','format','jpeg','-s','formatOptions','100',str(path),'--out',str(flat)],check=True,capture_output=True)
  subprocess.run(['sips','-s','format','png',str(flat),'--out',str(path)],check=True,capture_output=True)
  flat.unlink()
  # No 1284×2778 copy: the framer draws the screen scaled inside every slot's frame.
  print(path,flush=True)
finally:
 run('status_bar',sim,'clear')
