"""Raw native-resolution App Store captures for the 1.1 iPhone set. Run after a Debug simulator build.

Usage: python3 Scripts/capture_store.py [SIMULATOR_ID] [DERIVED_DATA] [en|es] [name,name…]
Every frame uses live data (`-nyx-state live`: real Open-Meteo forecasts and NPS alerts at capture time,
scored by the shipping engine), except the journal, which is DEBUG seed data with no personal photo.
Trip and Listen are scrolled by DEBUG flags (`-nyx-trip-route`, `-nyx-listen`), so no frame needs a hand scroll.
Writes Store/Screenshots/NN-name-6.9.png (English) or Store/Screenshots/es/NN-name-6.9.png, no alpha,
plus 1284×2778 copies in the matching 6.5-inch folder.
"""
import subprocess,time,pathlib,sys,os
sim=sys.argv[1] if len(sys.argv)>1 else '2E90D43E-75AD-44AA-AA66-44A4F5155CF5'
derived=sys.argv[2] if len(sys.argv)>2 else '/tmp/NyxBuild'
lang=sys.argv[3] if len(sys.argv)>3 else 'en'
# Optional fourth argument: only these frames (e.g. field,compass), so a retake keeps the rest of the set.
only=set(sys.argv[4].split(',')) if len(sys.argv)>4 else None
def run(*args): return subprocess.run(['xcrun','simctl',*args],check=True,capture_output=True)
subprocess.run(['xcrun','simctl','boot',sim],capture_output=True)
run('bootstatus',sim,'-b')
run('install',sim,derived+'/Build/Products/Debug-iphonesimulator/Nyx.app')
folder=pathlib.Path('Store/Screenshots'+('/es' if lang=='es' else ''));folder.mkdir(parents=True,exist_ok=True)
small=folder/'6.5-inch';small.mkdir(exist_ok=True)
language=['-AppleLanguages','(es)','-AppleLocale','es_MX'] if lang=='es' else []
today=time.strftime('%Y-%m-%d')
# (name, launch arguments, manual scroll instruction or None)
shots=[
 ('tonight',['-nyx-screen','tonight','-nyx-state','live'],None),
 ('detail',['-nyx-screen','detail','-nyx-state','live'],None),
 ('whatsup',['-nyx-screen','tonight','-nyx-state','live','-nyx-link',f'nyx://whatsup?date={today}&park=jotr'],None),
 ('field',['-nyx-screen','field','-nyx-state','live','-nyx-field-minutes','60'],None),
 # A real summer night: 3 July 2027 at Joshua Tree, new Moon, 23:40 (the core near transit, 27° up in the south).
 # Beyond the forecast, so the header's score is labelled moon and darkness only.
 ('compass',['-nyx-screen','field-compass','-nyx-state','live','-nyx-date','2027-07-03','-nyx-field-minutes','225'],None),
 ('calendar',['-nyx-screen','calendar','-nyx-state','live'],None),
 ('trip',['-nyx-screen','trip','-nyx-state','live','-nyx-trip-route'],None),  # scrolled to the route by the DEBUG flag
 ('journal',['-nyx-screen','journal','-nyx-state','populated'],None),
 ('listen',['-nyx-screen','detail','-nyx-state','live','-nyx-listen'],None),  # scrolled and opened by the DEBUG flag
 ('every-sky',['-nyx-screen','light','-nyx-state','live','-nyx-park','deva'],None),
]
run('status_bar',sim,'override','--time','9:41','--batteryState','charged','--batteryLevel','100','--wifiMode','active','--wifiBars','3','--cellularMode','active','--cellularBars','4')
try:
 for index,(name,args,manual) in enumerate(shots,1):
  if only and name not in only: continue
  if manual and os.environ.get('NYX_SKIP_MANUAL'): print(f'skipped {index:02d}-{name}: {manual}',flush=True); continue
  run('launch','--terminate-running-process',sim,'com.harrypakhale.nyx',*args,'-nyx-reduce-motion',*language)
  time.sleep(14 if 'live' in args else 8)
  if manual: input(f'{index:02d}-{name}: {manual} Press Return to capture. ')
  path=folder/f'{index:02d}-{name}-6.9.png'
  # Captured to a temporary file and copied in: simctl may be refused when it overwrites a frame in place.
  raw=pathlib.Path('/tmp')/path.name
  run('io',sim,'screenshot',str(raw))
  subprocess.run(['cp',str(raw),str(path)],check=True); raw.unlink()
  # App Store Connect rejects screenshots with an alpha channel: flatten through JPEG.
  flat=path.with_suffix('.flat.jpg')
  subprocess.run(['sips','-s','format','jpeg','-s','formatOptions','100',str(path),'--out',str(flat)],check=True,capture_output=True)
  subprocess.run(['sips','-s','format','png',str(flat),'--out',str(path)],check=True,capture_output=True)
  flat.unlink()
  # 6.5-inch slot: scale 1320×2868 to width 1284 (2790 tall), trim 6 px top and bottom to 2778.
  six=small/f'{index:02d}-{name}-6.5.png'
  subprocess.run(['sips','-z','2790','1284',str(path),'--out',str(six)],check=True,capture_output=True)
  subprocess.run(['sips','-c','2778','1284',str(six),'--out',str(six)],check=True,capture_output=True)
  print(path,flush=True)
finally:
 run('status_bar',sim,'clear')
