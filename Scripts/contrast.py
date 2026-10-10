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
# A night's filled mark (NyxPalette.markOpacity): the score's ramp held at 3:1 on black and the panel, amber from
# 50% and night vision's white-then-red from 70% (a poor night's mark is smaller, never fainter than that).
AMBER=(1,.706,.329); PANEL=(.043,.063,.149); NIGHT_PANEL=tuple(panelGrey*c for c in STANDARD)
marks={'palette':'Night marks (graphical objects)',
       'amber50OnBlack':round(contrast(tuple(.5*c for c in AMBER),(0,0,0)),2),
       'amber50OnPanel':round(contrast(tuple(.5*c+.5*b for c,b in zip(AMBER,PANEL)),PANEL),2),
       'nightRed70OnBlack':round(contrast(tuple(.7*c for c in STANDARD),(0,0,0)),2),
       'nightRed70OnPanel':round(contrast(tuple(.7*c+.3*b for c,b in zip(STANDARD,NIGHT_PANEL)),NIGHT_PANEL),2)}
assert min(v for k,v in marks.items() if k!='palette')>=3, marks
rows.append(marks)
# The twilight lift behind a night without true darkness (RealSky.liftColor, at its brightest at the bottom of the
# screen): muted captions keep 4.5:1 over it by default. Under Increase Contrast the lift is off (plain black).
LIFT=(.078,.106,.227)
lift={'palette':'Twilight lift','primaryOnLift':round(contrast((0.961,.945,.902),LIFT),2),
      'secondaryOnLift':round(contrast(tuple(.72*c+.28*b for c,b in zip((0.961,.945,.902),LIFT)),LIFT),2),
      'accentOnLift':round(contrast((1,.706,.329),LIFT),2)}
assert lift['secondaryOnLift']>=4.5 and lift['accentOnLift']>=4.5, lift
rows.append(lift)
# Through night vision the lift is drawn at 60% (RealSky.Visibility), turned grey, then multiplied by the red;
# text is the red itself, muted text 96% of it. With Increase Contrast the lift is off, so the brighter red meets
# it only when chosen by hand: it keeps 4.5:1 for typical, protan and deutan eyes; the standard red for typical
# and deutan eyes (protan eyes get the brighter red's 4.5:1 or better, as on the panel).
liftGrey=.6*(.2126*LIFT[0]+.7152*LIFT[1]+.0722*LIFT[2])
for name,red in [('Twilight lift, night vision',STANDARD),('Twilight lift, night vision, brighter red',BRIGHTER)]:
 bg=tuple(liftGrey*c for c in red); muted=tuple(.96*a+.04*b for a,b in zip(red,bg))
 row={'palette':name}
 for vision in MATRICES:
  suffix='' if vision=='typical' else vision.capitalize()
  row['primaryOnLift'+suffix]=round(contrast(red,bg,vision),2)
  row['secondaryOnLift'+suffix]=round(contrast(muted,bg,vision),2)
 rows.append(row)
assert min(rows[-2]['secondaryOnLift'],rows[-2]['secondaryOnLiftDeutan'])>=4.5, rows[-2]
assert min(rows[-1]['secondaryOnLift'+suffix] for suffix in ['','Protan','Deutan'])>=4.5, rows[-1]
# The sky arc's canvas labels. "Core" (muted) sits over the twilight only after sunset, so its brightest
# sky is the dusk colour at the Sun's -0.833 degrees (SkyArc.skyColor), and in true darkness over black
# lifted by moonlight and the Milky Way's glow. The label stands 5 pt above the band's spine at a peak of at
# least 8 degrees, so about 20 pt above the horizon, where a full Moon's wash (3% at the top to 18% at the
# horizon) is at most 16% starlight; under the label's lower edge the blurred band (16% at its spine) is
# about half as bright, 8%. The arc's vertical
# wash (black at 30% at the top, clear by three quarters down) only darkens behind it, so the label is
# measured without it. "True darkness" (amber) sits on the ridge, at most 6% grey. Night vision turns each
# colour grey and multiplies it by the red, as above.
def mix(a,b,t): return tuple(x*(1-t)+y*t for x,y in zip(a,b))
INK=(0.961,.945,.902); AMBER=(1,.706,.329)
DUSK=mix((0.20,0.23,0.42),(0.165,0.106,0.306),0.833/6)
DUSK_RED=mix((0.30,0.04,0.03),(0.20,0.02,0.015),0.833/6)
def grey(c): return .2126*c[0]+.7152*c[1]+.0722*c[2]
arc={'palette':'Sky arc labels'}
for name,bg in [('coreOnDusk',DUSK),('coreOnMoonlitDark',mix(mix((0,0,0),INK,.16),INK,.08))]:
 arc[name]=round(contrast(mix(bg,INK,.72),bg),2)
arc['trueDarknessOnRidge']=round(contrast(AMBER,(.06,.06,.06)),2)
for name,bg in [('coreOnDuskNightVision',DUSK_RED),('coreOnMoonlitDarkNightVision',mix(mix((0,0,0),(1,1,1),.16),(1,1,1),.08))]:
 floor=tuple(grey(bg)*c for c in STANDARD)
 arc[name]=round(contrast(tuple(.96*a+.04*b for a,b in zip(STANDARD,floor)),floor),2)
arc['trueDarknessOnRidgeNightVision']=round(contrast(STANDARD,tuple(.06*c for c in STANDARD)),2)
assert min(v for k,v in arc.items() if k!='palette')>=4.5, arc
rows.append(arc)
Path('Research/contrast.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows,indent=1))
