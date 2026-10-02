"""WCAG relative luminance for design tokens; not a substitute for UI sampling."""
import json
from pathlib import Path
def luminance(c):
 rgb=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in c]
 return sum(a*b for a,b in zip(rgb,[.2126,.7152,.0722]))
def contrast(a,b):
 x,y=sorted([luminance(a),luminance(b)])
 return (y+.05)/(x+.05)
rows=[]
for name,ink,bg,alpha in [('Normal',(0.961,.945,.902),(.043,.063,.149),.72),('Night vision',(1,.27,.23),(.12,.032,.028),.96)]:
 muted=tuple(a*alpha+b*(1-alpha) for a,b in zip(ink,bg))
 rows.append({'palette':name,'primaryOnPanel':round(contrast(ink,bg),2),'secondaryOnPanel':round(contrast(muted,bg),2),'primaryOnBlack':round(contrast(ink,(0,0,0)),2)})
 assert rows[-1]['secondaryOnPanel']>=4.5
rows.append({'palette':'Filled controls','blackOnAmber':round(contrast((0,0,0),(1,.706,.329)),2),'blackOnSignalRed':round(contrast((0,0,0),(1,.27,.23)),2),'redThumbOnDarkTrack':round(contrast((1,.27,.23),(.22,.0594,.0506)),2)})
assert min(rows[-1][key] for key in ['blackOnAmber','blackOnSignalRed','redThumbOnDarkTrack'])>=4.5
Path('Research/contrast.json').write_text(json.dumps(rows,indent=2)+'\n')
print(rows)
