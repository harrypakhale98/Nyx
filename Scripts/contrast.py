"""WCAG relative luminance for design tokens; not a substitute for UI sampling.

Each palette is measured for typical colour vision and, with Machado, Oliveira and Fernandes
(2009) full-severity matrices applied in linear RGB, for protanopia and deuteranopia. The Swift
side (`ColorVision` in NyxTheme.swift) uses the same matrices, and AccessLaneTests asserts the
brighter red's text stays at or above 4.5:1 for all three.
"""
import json
from pathlib import Path

MATRICES={
 'typical':[[1,0,0],[0,1,0],[0,0,1]],
 'protan':[[0.152286,1.052583,-0.204868],[0.114503,0.786281,0.099216],[-0.003882,-0.048116,1.051998]],
 'deutan':[[0.367322,0.860646,-0.227968],[0.280085,0.672501,0.047413],[-0.011820,0.042940,0.968881]],
}
def linear(v): return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4
def luminance(c,vision='typical'):
 l=[linear(v) for v in c]
 seen=[min(1,max(0,sum(m*x for m,x in zip(row,l)))) for row in MATRICES[vision]]
 return sum(a*b for a,b in zip(seen,[.2126,.7152,.0722]))
def contrast(a,b,vision='typical'):
 x,y=sorted([luminance(a,vision),luminance(b,vision)])
 return (y+.05)/(x+.05)
def measured(name,ink,bg,alpha):
 muted=tuple(a*alpha+b*(1-alpha) for a,b in zip(ink,bg))
 row={'palette':name}
 for vision in MATRICES:
  suffix='' if vision=='typical' else vision.capitalize()
  row['primaryOnPanel'+suffix]=round(contrast(ink,bg,vision),2)
  row['secondaryOnPanel'+suffix]=round(contrast(muted,bg,vision),2)
  row['primaryOnBlack'+suffix]=round(contrast(ink,(0,0,0),vision),2)
 return row

rows=[]
# Night vision draws everything in grey, then multiplies by the red: white text becomes the red itself,
# the night panel (0.07, 0.008, 0.005) its grey times the red.
panelGrey=.2126*.07+.7152*.008+.0722*.005
STANDARD=(1,.27,.23)
BRIGHTER=(1,.36,.31)
for name,ink,bg,alpha in [('Normal',(0.961,.945,.902),(.043,.063,.149),.72),
                          ('Night vision',STANDARD,tuple(panelGrey*c for c in STANDARD),.96),
                          ('Night vision, brighter red',BRIGHTER,tuple(panelGrey*c for c in BRIGHTER),.96)]:
 rows.append(measured(name,ink,bg,alpha))
 assert rows[-1]['secondaryOnPanel']>=4.5
# The brighter red (Increase Contrast, or chosen) passes for protan and deutan eyes too.
for key in ['primaryOnPanel','secondaryOnPanel','primaryOnBlack']:
 for suffix in ['','Protan','Deutan']:
  assert rows[2][key+suffix]>=4.5, (key+suffix,rows[2][key+suffix])
rows.append({'palette':'Filled controls','blackOnAmber':round(contrast((0,0,0),(1,.706,.329)),2),'blackOnSignalRed':round(contrast((0,0,0),STANDARD),2),'redThumbOnDarkTrack':round(contrast(STANDARD,(.22,.0594,.0506)),2)})
assert min(rows[-1][key] for key in ['blackOnAmber','blackOnSignalRed','redThumbOnDarkTrack'])>=4.5
# Hairlines and tracks (WCAG 1.4.11 asks 3:1 for graphical objects): starlight at 40% by default,
# 70% through night vision's red.
lines={'palette':'Lines (graphical objects)',
       'starlight40OnBlack':round(contrast(tuple(.4*c for c in (0.961,.945,.902)),(0,0,0)),2),
       'starlight40OnPanel':round(contrast(tuple(.4*c+.6*b for c,b in zip((0.961,.945,.902),(.043,.063,.149))),(.043,.063,.149)),2),
       'nightRed70OnBlack':round(contrast(tuple(.7*c for c in STANDARD),(0,0,0)),2)}
assert min(v for k,v in lines.items() if k!='palette')>=3
rows.append(lines)
Path('Research/contrast.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows,indent=1))
