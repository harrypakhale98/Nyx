import subprocess,time,pathlib,sys
sim=sys.argv[1] if len(sys.argv)>1 else '4B98F460-8228-4B8B-8626-2BE43641E876'
label=sys.argv[2] if len(sys.argv)>2 else '26'
cases=[('tonight','offline',[]),('parks','offline',[]),('detail','offline',[]),('calendar','offline',[]),('journal','empty',[]),('editor','offline',[]),('entry','offline',[]),('onboarding','offline',[]),('learn','offline',[]),('article','offline',[]),('settings','offline',[]),('privacy','offline',[]),('data','offline',[]),('breakdown','offline',[]),('share','offline',[]),('ask','offline',[]),('tonight','no-location',[]),('tonight','empty',[]),('tonight','error',[]),('parks','loading',[]),('detail','polar',[]),('tonight','night-vision',[]),('detail','night-vision',[]),('calendar','night-vision',[]),('tonight','offline',['-nyx-ax5']),('parks','offline',['-nyx-ax5']),('calendar','offline',['-nyx-ax5']),('editor','offline',['-nyx-ax5']),('onboarding','offline',['-nyx-ax5']),('article','offline',['-nyx-ax5']),('detail','offline',['-nyx-reduce-motion']),('tonight','offline',['-nyx-contrast'])]
folder=pathlib.Path('Research/Screenshots')
for screen,state,extra in cases:
 subprocess.run(['xcrun','simctl','terminate',sim,'com.harrypakhale.nyx'],capture_output=True)
 subprocess.run(['xcrun','simctl','launch',sim,'com.harrypakhale.nyx','-nyx-screen',screen,'-nyx-state',state]+extra,check=True,capture_output=True)
 time.sleep(2.5)
 name=f'{screen}-{state}{"-"+extra[0][5:] if extra else ""}-{label}.png'
 subprocess.run(['xcrun','simctl','io',sim,'screenshot',str(folder/name)],check=True,capture_output=True)
 print(name,flush=True)
