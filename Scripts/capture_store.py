"""Raw native-resolution submission drafts. Run after a Debug simulator build."""
import subprocess,time,pathlib,sys
sim=sys.argv[1] if len(sys.argv)>1 else '2E90D43E-75AD-44AA-AA66-44A4F5155CF5'
def run(*args): return subprocess.run(['xcrun','simctl',*args],check=True,capture_output=True)
subprocess.run(['xcrun','simctl','boot',sim],capture_output=True)
run('bootstatus',sim,'-b')
run('install',sim,(sys.argv[2] if len(sys.argv)>2 else '/tmp/NyxBuild')+'/Build/Products/Debug-iphonesimulator/Nyx.app')
folder=pathlib.Path('Store/Screenshots');folder.mkdir(parents=True,exist_ok=True)
run('status_bar',sim,'override','--time','9:41','--batteryState','charged','--batteryLevel','100','--wifiMode','active','--wifiBars','3','--cellularMode','active','--cellularBars','4')
try:
 for index,(screen,state) in enumerate([('tonight','live'),('detail','live'),('calendar','live'),('parks','live'),('journal','populated'),('learn','night-vision')],1):
  run('launch','--terminate-running-process',sim,'com.harrypakhale.nyx','-nyx-screen',screen,'-nyx-state',state,'-nyx-reduce-motion')
  time.sleep(14 if state=='live' else 8)
  path=folder/f'{index:02d}-{screen}-6.9.png'
  run('io',sim,'screenshot',str(path));print(path,flush=True)
finally:
 run('status_bar',sim,'clear')
