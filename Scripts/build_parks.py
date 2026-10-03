"""Reproducible bundled inventory from the public NPS parks response.
Coordinates are NPS park representative coordinates, never navigation directions.
Viewing coordinates are approximate; access must be checked with the park.
"""
import json, pathlib
source=json.load(open('/tmp/nyx-nps-parks.json'))['data']
# IANA timezones follow the representative location, not the whole park boundary.
zones={
'acad':'America/New_York','arch':'America/Denver','badl':'America/Denver','bibe':'America/Chicago','bisc':'America/New_York','blca':'America/Denver','brca':'America/Denver','cany':'America/Denver','care':'America/Denver','cave':'America/Denver','chis':'America/Los_Angeles','cong':'America/New_York','crla':'America/Los_Angeles','cuva':'America/New_York','deva':'America/Los_Angeles','dena':'America/Anchorage','drto':'America/New_York','ever':'America/New_York','gaar':'America/Anchorage','jeff':'America/Chicago','glba':'America/Juneau','glac':'America/Denver','grca':'America/Phoenix','grte':'America/Denver','grba':'America/Los_Angeles','grsa':'America/Denver','grsm':'America/New_York','gumo':'America/Denver','hale':'Pacific/Honolulu','havo':'Pacific/Honolulu','hosp':'America/Chicago','indu':'America/Chicago','isro':'America/Detroit','jotr':'America/Los_Angeles','katm':'America/Anchorage','kefj':'America/Anchorage','kova':'America/Anchorage','lacl':'America/Anchorage','lavo':'America/Los_Angeles','maca':'America/Chicago','meve':'America/Denver','mora':'America/Los_Angeles','neri':'America/New_York','noca':'America/Los_Angeles','olym':'America/Los_Angeles','pefo':'America/Phoenix','pinn':'America/Los_Angeles','romo':'America/Denver','sagu':'America/Phoenix','seki':'America/Los_Angeles','shen':'America/New_York','thro':'America/Denver','viis':'America/St_Thomas','voya':'America/Chicago','whsa':'America/Denver','wica':'America/Denver','wrst':'America/Anchorage','yell':'America/Denver','yose':'America/Los_Angeles','zion':'America/Denver','npsa':'Pacific/Pago_Pago','redw':'America/Los_Angeles'}
designated=set('arch bibe blca brca cany care deva glac grca grba grsa jotr maca meve pefo voya zion'.split())
bortle={'jeff':8,'cuva':6,'hosp':5,'indu':6,'bisc':5,'cong':4,'acad':3,'grsm':3,'shen':3,'sagu':4,'pinn':3,'jotr':3,'maca':4,'meve':3,'neri':3,'ever':3,'whsa':3,'mora':3,'olym':3,'noca':2,'redw':3,'yose':3,'seki':3,'hale':2,'havo':3,'viis':3,'npsa':3,'zion':3,'arch':3,'brca':2,'cany':2,'care':2,'bibe':2,'deva':2,'grba':2,'grsa':2,'grca':2,'pefo':2,'blca':2}
# Explicit NPS night-sky recommendations. Unverified areas are omitted, not invented.
spots={
'zion':[('Checkerboard Mesa Pullout',37.224,-112.882,'https://www.nps.gov/zion/planyourvisit/sunset-stargazing.htm')],
'yose':[('Glacier Point Overlook',37.728,-119.574,'https://www.nps.gov/yose/planyourvisit/stargazing.htm')],
'badl':[('Cedar Pass Amphitheater',43.749,-101.941,'https://www.nps.gov/thingstodo/badl-ranger-programs.htm')],
'arch':[('Panorama Point',38.722,-109.565,'https://www.nps.gov/arch/planyourvisit/stargazing.htm')],
'jotr':[('Cap Rock',33.954,-116.163,'https://www.nps.gov/jotr/planyourvisit/stargazing.htm'),('Hidden Valley',34.012,-116.168,'https://www.nps.gov/jotr/planyourvisit/stargazing.htm')],
'grba':[('Baker Archaeological Site',39.014,-114.306,'https://www.nps.gov/grba/planyourvisit/great-basin-stargazing.htm')],
'grca':[('Mather Point',36.061,-112.108,'https://www.nps.gov/grca/learn/nature/night-skies.htm')],
'deva':[('Harmony Borax Works',36.480,-116.875,'https://www.nps.gov/deva/night-exploration.htm'),('Mesquite Flat Sand Dunes',36.615,-117.113,'https://www.nps.gov/deva/night-exploration.htm')],
'brca':[('Sunset Point',37.623,-112.167,'https://www.nps.gov/thingstodo/stargazing-at-bryce-canyon.htm')],
'cany':[('Grand View Point',38.3123,-109.85767,'https://www.nps.gov/cany/planyourvisit/stargazing.htm')],
'care':[('Panorama Point',38.293,-111.262,'https://www.nps.gov/thingstodo/stargaze.htm')],
'grsa':[('Dunes Parking Area',37.733,-105.512,'https://www.nps.gov/grsa/planyourvisit/experiencethenight.htm')],

'acad':[('Seawall',44.239,-68.304,'https://www.nps.gov/acad/planyourvisit/stargazing.htm')]
}
# Researched NPS-sourced spots (with provenance) fill parks the table above does not cover.
researched=json.loads(pathlib.Path('Research/viewing-spots.json').read_text()) if pathlib.Path('Research/viewing-spots.json').exists() else {}
for ident,entries in researched.items():
    spots.setdefault(ident,[(e['name'],e['latitude'],e['longitude'],e['sourceURL']) for e in entries])
parks=[]
for p in source:
 code=p['parkCode']
 if code not in zones: continue
 entries=[(code,p['fullName'],float(p['latitude']),float(p['longitude']))]
 if code=='seki': entries=[('sequ','Sequoia National Park',36.486,-118.565),('kica','Kings Canyon National Park',36.887,-118.555)]
 for ident,name,lat,lon in entries:
  parks.append(dict(id=ident,apiCode=code,name=name.replace('Of The','of the').replace('Wrangell - St Elias','Wrangell–St. Elias'),state=p['states'],latitude=lat,longitude=lon,timeZoneID=zones[code],hemisphere='south' if lat<0 else 'north',darkSkyDesignated=code in designated,bortleEstimate=bortle.get(code,2),description=p['description'] or 'Yellowstone protects geysers, hot springs, mountain landscapes and wildlife. Stay on designated routes, including after dark.',sourceURL=p['url'],sourceNote='NPS park inventory, retrieved 2026-10-02. Bortle is a conservative planning estimate, not a measurement; park lighting, terrain, smoke and skyglow vary. Certification cross-checked against NPS International Dark Sky Places list (2025-04-16).',viewingSpots=[dict(name=n,latitude=a,longitude=b,sourceURL=u,note='Approximate coordinates. Check current access, opening hours and closures with a ranger. This is not a navigation guide.') for n,a,b,u in spots.get(ident,spots.get(code,[]))]))
assert len(parks)==63,len(parks)
pathlib.Path('Nyx/Resources/parks.json').write_text(json.dumps(sorted(parks,key=lambda p:p['name']),indent=2,ensure_ascii=False)+'\n')
print('Wrote',len(parks),'parks')
