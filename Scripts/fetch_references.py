import json,urllib.request,concurrent.futures,pathlib
parks=json.load(open('Nyx/Resources/parks.json'))
cases=[(p,d) for p in parks if p['id'] in ['jotr','grca','grba'] for d in ['2026-01-15','2026-03-20','2026-07-15']]
def fetch(case):
 p,d=case; tz=-7 if p['id']=='grca' or (p['id'] in ['jotr','grba'] and d>'2026-03-01') else -8
 url=f"https://aa.usno.navy.mil/api/rstt/oneday?date={d}&coords={p['latitude']},{p['longitude']}&tz={tz}"
 data=json.load(urllib.request.urlopen(url,timeout=30))
 return dict(park=p['id'],date=d,tz=tz,sourceURL=url,reference=data)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool: refs=list(pool.map(fetch,cases))
pathlib.Path('Research/usno-reference.json').write_text(json.dumps(refs,indent=2))
pathlib.Path('NyxTests/usno-reference.json').write_text(json.dumps(refs,indent=2))
print([(r['park'],r['date'],r['reference'].get('properties',{}).get('data',{}).get('sundata')) for r in refs])
