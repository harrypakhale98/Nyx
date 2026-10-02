"""Capture actual Simulator Dynamic Type and Increase Contrast, then restore settings."""
import os,subprocess,sys
sim,label=sys.argv[1:3]
def ui(option,*args):
 return subprocess.run(['xcrun','simctl','ui',sim,option,*args],check=True,capture_output=True,text=True).stdout.strip()
subprocess.run(['xcrun','simctl','boot',sim],capture_output=True)
subprocess.run(['xcrun','simctl','bootstatus',sim,'-b'],check=True,capture_output=True)
size,contrast=ui('content_size'),ui('increase_contrast')
try:
 ui('increase_contrast','enabled')
 subprocess.run([sys.executable,'Scripts/capture_screens.py',sim,label+'-system-contrast'],check=True,env={**os.environ,'NYX_CAPTURE_FILTER':'^(tonight|settings)-offline-$'})
 ui('increase_contrast',contrast)
 ui('content_size','accessibility-extra-extra-extra-large')
 subprocess.run([sys.executable,'Scripts/capture_screens.py',sim,label+'-system-ax5'],check=True,env={**os.environ,'NYX_CAPTURE_FILTER':'^(tonight|parks|detail|calendar|editor|journal|settings|privacy|data|onboarding|learn|article)-offline-$'})
finally:
 ui('content_size',size)
 ui('increase_contrast',contrast)
