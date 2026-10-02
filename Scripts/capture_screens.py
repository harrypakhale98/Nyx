import subprocess,time,pathlib,sys,os,re
sim=sys.argv[1] if len(sys.argv)>1 else '4B98F460-8228-4B8B-8626-2BE43641E876'
label=sys.argv[2] if len(sys.argv)>2 else '26'
cases=[('tonight','offline',[]),('parks','offline',[]),('detail','offline',[]),('calendar','offline',[]),('journal','empty',[]),('editor','offline',[]),('entry','offline',[]),('onboarding','offline',[]),('learn','offline',[]),('article','offline',[]),('settings','offline',[]),('privacy','offline',[]),('data','offline',[]),('breakdown','offline',[]),('share','offline',[]),('ask','offline',[]),('tonight','no-location',[]),('tonight','empty',[]),('tonight','error',[]),('parks','loading',[]),('detail','polar',[]),('tonight','night-vision',[]),('detail','night-vision',[]),('calendar','night-vision',[]),('tonight','offline',['-nyx-ax5']),('parks','offline',['-nyx-ax5']),('calendar','offline',['-nyx-ax5']),('editor','offline',['-nyx-ax5']),('onboarding','offline',['-nyx-ax5']),('article','offline',['-nyx-ax5']),('detail','offline',['-nyx-reduce-motion']),('tonight','offline',['-nyx-contrast'])]
for screen in ['settings','privacy','editor','learn','article','onboarding','share','breakdown','entry','data']:
 cases.append((screen,'night-vision',[]))
for screen in ['detail','journal','entry','learn','settings','privacy','data','breakdown','skyarc','river','ask','location-explainer','notification-explainer']:
 cases.append((screen,'offline',['-nyx-ax5']))
cases += [('widgets','offline',[]),('widgets-empty','offline',[]),('widgets','night-vision',[]),('skyarc','offline',[]),('skyarc','polar',[]),('river','offline',[]),('loader','offline',[]),('loader','offline',['-nyx-reduce-motion']),('onboarding','offline',['-nyx-onboarding-page','1']),('onboarding','offline',['-nyx-onboarding-page','2']),('detail','offline',['-nyx-bottom']),('detail','no-forecast',[]),('calendar','no-forecast',[]),('journal','populated',[])]
cases += [('share','offline',['-nyx-ax5']),('editor','photo',['-nyx-ax5','-nyx-bottom']),('widgets','offline',['-nyx-ax5']),('detail','polar-night',[]),('skyarc','polar-night',[]),('editor','error',[]),('editor','photo',[]),('editor','photo',['-nyx-ax5']),('river','empty',[])]
folder=pathlib.Path('Research/Screenshots')
subprocess.run(['xcrun','simctl','boot',sim],capture_output=True)
subprocess.run(['xcrun','simctl','bootstatus',sim,'-b'],check=True,capture_output=True)
subprocess.run(['xcrun','simctl','install',sim,'/tmp/NyxBuild/Build/Products/Debug-iphonesimulator/Nyx.app'],check=True,capture_output=True)

for screen,state,extra in cases[int(sys.argv[3]) if len(sys.argv)>3 else 0:]:
 if not re.search(os.environ.get('NYX_CAPTURE_FILTER','.*'),screen+'-'+state+'-'+'-'.join(extra)): continue
 subprocess.run(['xcrun','simctl','launch','--terminate-running-process',sim,'com.harrypakhale.nyx','-nyx-screen',screen,'-nyx-state',state]+extra,check=True,capture_output=True)
 time.sleep(float(os.environ.get("NYX_CAPTURE_WAIT","8")))
 name=f'{screen}-{state}{"-"+"-".join(x.removeprefix("-nyx-") for x in extra) if extra else ""}-{label}.png'
 subprocess.run(['xcrun','simctl','io',sim,'screenshot',str(folder/name)],check=True,capture_output=True)
 print(name,flush=True)
