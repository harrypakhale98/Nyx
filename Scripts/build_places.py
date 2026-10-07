#!/usr/bin/env python3
"""
build_places.py -- the offline list of US starting places for Nyx.

Produces Nyx/Resources/places.json: the 1,000 most populous incorporated places in the
50 states and DC, plus every state capital, each with a display name, state code and
an interior point (latitude, longitude). Tonight's starting-point picker and Ask Nyx
search it on the device, so "Chicago, IL" works with location off and no network.
The app never downloads it; this script runs once at build time.

SOURCES (both public domain, U.S. Census Bureau)
    Places and coordinates: 2025 Gazetteer Files, Places (national), INTPTLAT/INTPTLONG
      https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2025_Gazetteer/2025_Gaz_place_national.zip
    Population, to rank them: Vintage 2025 subcounty population estimates (SUB-EST2025)
      https://www2.census.gov/programs-surveys/popest/datasets/2020-2025/cities/totals/sub-est2025.csv
    Joined on the seven-digit place GEOID (state FIPS + place FIPS). Census-designated
    places have no population estimate and are left out, except Urban Honolulu (a capital).

USAGE
    python3 Scripts/build_places.py [--cache DIR] [--count 1000]
Re-running with the same files gives the same output. Coordinates are rounded to
three decimals (about 100 m), more than enough for a straight-line radius.
"""
import argparse, csv, io, json, re, sys, urllib.request, zipfile
from pathlib import Path

GAZETTEER='https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2025_Gazetteer/2025_Gaz_place_national.zip'
POPULATION='https://www2.census.gov/programs-surveys/popest/datasets/2020-2025/cities/totals/sub-est2025.csv'
OUT=Path(__file__).resolve().parent.parent/'Nyx/Resources/places.json'

CAPITALS={'AL':'Montgomery','AK':'Juneau','AZ':'Phoenix','AR':'Little Rock','CA':'Sacramento','CO':'Denver','CT':'Hartford',
 'DE':'Dover','FL':'Tallahassee','GA':'Atlanta','HI':'Honolulu','ID':'Boise','IL':'Springfield','IN':'Indianapolis','IA':'Des Moines',
 'KS':'Topeka','KY':'Frankfort','LA':'Baton Rouge','ME':'Augusta','MD':'Annapolis','MA':'Boston','MI':'Lansing','MN':'Saint Paul',
 'MS':'Jackson','MO':'Jefferson City','MT':'Helena','NE':'Lincoln','NV':'Carson City','NH':'Concord','NJ':'Trenton','NM':'Santa Fe',
 'NY':'Albany','NC':'Raleigh','ND':'Bismarck','OH':'Columbus','OK':'Oklahoma City','OR':'Salem','PA':'Harrisburg','RI':'Providence',
 'SC':'Columbia','SD':'Pierre','TN':'Nashville','TX':'Austin','UT':'Salt Lake City','VT':'Montpelier','VA':'Richmond','WA':'Olympia',
 'WV':'Charleston','WI':'Madison','WY':'Cheyenne','DC':'Washington'}
# Consolidated governments and other official names, as people say them.
RENAME={'Nashville-Davidson':'Nashville','Louisville/Jefferson County':'Louisville','Lexington-Fayette':'Lexington',
 'Athens-Clarke County':'Athens','Augusta-Richmond County':'Augusta','Macon-Bibb County':'Macon','Urban Honolulu':'Honolulu',
 'San Buenaventura (Ventura)':'Ventura','Boise City':'Boise','Columbus-Muscogee':'Columbus','Cusseta-Chattahoochee County':'Cusseta',
 'Indianapolis':'Indianapolis','St. Paul':'Saint Paul'}
SUFFIXES=[' metropolitan government (balance)',' metro government (balance)',' unified government (balance)',
 ' consolidated government (balance)',' city (balance)',' urban county',' city and borough',' municipality',' unified government',
 ' consolidated government',' city',' town',' village',' borough',' CDP',' (balance)']

def fetch(url, cache):
    path=cache/url.rsplit('/',1)[1]
    if not path.exists():
        print('downloading',url,file=sys.stderr)
        with urllib.request.urlopen(url,timeout=120) as response: path.write_bytes(response.read())
    return path.read_bytes()

def clean(name):
    for suffix in SUFFIXES:
        if name.endswith(suffix): name=name[:-len(suffix)]; break
    return RENAME.get(name,name)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--cache',default='/tmp/nyx-places')
    parser.add_argument('--count',type=int,default=1000)
    args=parser.parse_args()
    cache=Path(args.cache); cache.mkdir(parents=True,exist_ok=True)
    archive=zipfile.ZipFile(io.BytesIO(fetch(GAZETTEER,cache)))
    text=archive.read(next(n for n in archive.namelist() if n.endswith('.txt'))).decode('utf-8')
    rows=list(csv.reader(io.StringIO(text),delimiter='|'))
    head=[h.strip() for h in rows[0]]
    col={h:i for i,h in enumerate(head)}
    places={}
    for row in rows[1:]:
        state=row[col['USPS']].strip()
        if state=='PR': continue
        places[row[col['GEOID']].strip()]=(clean(row[col['NAME']].strip()),state,float(row[col['INTPTLAT']]),float(row[col['INTPTLONG']].strip()))
    population={}
    for row in csv.DictReader(io.StringIO(fetch(POPULATION,cache).decode('latin-1'))):
        if row['SUMLEV']!='162': continue
        population[row['STATE']+row['PLACE']]=int(row['POPESTIMATE2025'])
    ranked=sorted((geoid for geoid in places if geoid in population),key=lambda g:(-population[g],g))
    chosen=ranked[:args.count]
    have={(places[g][0],places[g][1]) for g in chosen}
    for state,capital in sorted(CAPITALS.items()):
        if (capital,state) in have: continue
        # The capital's own place (the most populous of that name in the state; Honolulu is a CDP).
        matches=sorted((g for g in places if places[g][1]==state and places[g][0]==capital),key=lambda g:-population.get(g,0))
        if not matches: sys.exit(f'capital not found: {capital}, {state}')
        chosen.append(matches[0]); have.add((capital,state))
    # Two places of one name in one state keep only the larger (the list is already in population order).
    seen=set(); out=[]
    for geoid in chosen:
        name,state,lat,lon=places[geoid]
        if (name,state) in seen: continue
        seen.add((name,state))
        out.append([name,state,round(lat,3),round(lon,3)])
    document={'source':'U.S. Census Bureau: 2025 Gazetteer Files (Places) and Vintage 2025 subcounty population estimates',
              'license':'Public domain, U.S. Census Bureau','built':'Scripts/build_places.py',
              'note':'The most populous incorporated places plus every state capital, largest first. Interior points, not city centers.',
              'places':out}
    OUT.write_text(json.dumps(document,ensure_ascii=False,separators=(',',':'))+'\n')
    print(f'{len(out)} places, {OUT.stat().st_size//1024} KB -> {OUT}')

if __name__=='__main__': main()
