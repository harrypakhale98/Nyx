#!/usr/bin/env python3
"""
build_skyglow.py -- offline sky-glow dataset for Nyx.

Reads NASA Black Marble VNP46A4 (VIIRS yearly nighttime lights, 15 arc-second,
collection 5200, HDF5; public domain, Roman et al. 2018) and produces
Nyx/Resources/skyglow.json: per park and per viewing spot a relative artificial
sky-glow index, an estimated Bortle class, a 36-bin "light dome" azimuth
profile with named dominant sources, and a 2013 -> 2025 trend.

USAGE
    export PYTHONPATH=<scratch>/pylib        # python3 -m pip install --target <scratch>/pylib h5py numpy
    python3 Scripts/build_skyglow.py [--cache DIR] [--years 2013 2025] [--skip-download]

AUTHENTICATION (downloads only)
    The Earthdata Cloud endpoint needs a NASA Earthdata user token. The script
    reads it at run time from the file ~/.earthdata_token (mode 600) or, if that
    does not exist, from the environment variable EARTHDATA_TOKEN. The token is
    handed to curl through stdin (never argv, never logged, never written out).
    Create a free account at https://urs.earthdata.nasa.gov and generate a token
    under "Generate Token". Tile files are fetched one at a time, reduced to ~2 km
    cells (cache/agg/<year>_hXXvYY.npy) and the raw .h5 is deleted immediately.

PIPELINE
    1. Tile set: every 10x10 degree tile (hXXvYY, h=(lon+180)/10, v=(90-lat)/10)
       that touches a park or viewing spot plus a 300 km (+margin) window.
    2. Layer: NearNadir_Composite_Snow_Free (view zenith 0-20 deg: least angular
       and building-shadow bias; snow-free period so snow albedo does not inflate
       the signal). Fill value (-999.9) is masked. Quality flag (0 good >3 obs,
       1 poor <=3 obs, 2 gap-filled, 255 fill) is respected: where the near-nadir
       value is fill, or flagged poor while the all-angle composite is good, the
       AllAngle_Composite_Snow_Free value is used instead. Remaining fill = 0.
    3. Aggregation: 4x4 pixel block means -> cells of 1/60 degree (~1.85 km).
    4. Model (Walker's law, as used in light-pollution work since the 1970s):
           G(site) = sum_i L_i * A_i * d_i ** -2.5      for 1 km <= d_i <= 300 km
       L_i radiance (nW cm^-2 sr^-1), A_i cell area (km^2), d_i great-circle
       distance site -> cell centre in km (d < 1 km is treated as 1 km).
       The same contributions binned by azimuth (36 bins of 10 deg, bin 0
       centred on north, clockwise) give the light-dome profile.
       G is normalised so the median national-park centre has glow = 1.0.
    5. Calibration: bortle = a + b * log10(glow + g0), clipped to [1, 9], b > 0.
       Fitted by least squares against the hand `bortleEstimate` of the park
       centres (parks.json); g0 is a small "natural floor" found by grid search
       so that pristine sites saturate near Bortle 1-2 instead of running off.
       The hand estimates are integers and conservative, so the fit quality is
       reported honestly in Research/skyglow.md.
    6. Light domes: smooth the 36-bin profile with a 3-bin (30 deg) window, take
       up to 3 circular maxima (suppressing +/-30 deg around each) whose window
       holds >= 8% of the site's total. bearing = contribution-weighted circular
       mean in the window; share = window / total. The dominant source is the
       strongest cell in that +/-15 deg sector; the cluster is all lit cells in
       the sector within 20 km of it; the cluster's L*A-weighted centroid is
       matched to the METROS list below and the name is accepted ONLY if the
       centroid is within 40 km of that metro (else null).
    7. Trend: sum of L*A (nW cm^-2 sr^-1 km^2) within 150 km of each park centre,
       early vs late year, and percent change.

KNOWN LIMITS (also in Research/skyglow.md)
    VIIRS DNB is blind below ~500 nm: white/blue LEDs are under-detected, and
    LED conversions can read as DECREASES. Radiance is not zenith brightness; no
    atmospheric propagation, terrain, aerosols or light-spectrum is modelled.
    Output is a relative index calibrated to hand estimates, not a measurement.
"""

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
PARKS_JSON = REPO / "Nyx/Resources/parks.json"
OUT_JSON = REPO / "Nyx/Resources/skyglow.json"
OUT_CSV = REPO / "Research/skyglow-calibration.csv"

LISTING = "https://ladsweb.modaps.eosdis.nasa.gov/archive/allData/5200/VNP46A4/{year}/001.json"
CLOUD = "https://data.laadsdaac.earthdatacloud.nasa.gov/prod-lads/VNP46A4/{name}"
GROUP = "HDFEOS/GRIDS/VIIRS_Grid_DNB_2d/Data Fields/"

RADIUS_KM = 300.0
TREND_RADIUS_KM = 150.0
BLOCK = 4                              # 4x4 pixels of 15" -> 1/60 degree
CELL_DEG = BLOCK / 240.0
CELL_KM = CELL_DEG * math.pi / 180.0 * 6371.0088
TILE_CELLS = 2400 // BLOCK             # 600
EARTH_R = 6371.0088
WALKER_EXP = 2.5
MIN_D_KM = 1.0
DOME_MIN_SHARE = 0.08
CITY_MATCH_KM = 40.0
CLUSTER_KM = 20.0
DOME_LOG = []   # (centroid lat, lon, nearest metro, km) for every dome; printed with --debug-domes

# --------------------------------------------------------------------------
# Hand-written metro list: (name, lat, lon). Used only to NAME light domes;
# a name is accepted only when the source cluster centroid is within 40 km.
# --------------------------------------------------------------------------
METROS = [
    # --- California / Southwest ---
    ("Los Angeles", 34.05, -118.24), ("San Diego", 32.72, -117.16), ("San Francisco", 37.77, -122.42),
    ("Oakland", 37.80, -122.27), ("San Jose", 37.34, -121.89), ("Sacramento", 38.58, -121.49),
    ("Fresno", 36.74, -119.79), ("Bakersfield", 35.37, -119.02), ("Riverside", 33.95, -117.40),
    ("San Bernardino", 34.11, -117.29), ("Palm Springs", 33.83, -116.55), ("Indio", 33.72, -116.22),
    ("Santa Barbara", 34.42, -119.70), ("Oxnard", 34.20, -119.18), ("Santa Maria", 34.95, -120.44),
    ("San Luis Obispo", 35.28, -120.66), ("Visalia", 36.33, -119.29), ("Modesto", 37.64, -121.00),
    ("Stockton", 37.96, -121.29), ("Santa Rosa", 38.44, -122.71), ("Redding", 40.59, -122.39),
    ("Chico", 39.73, -121.84), ("Eureka", 40.80, -124.16), ("Crescent City", 41.76, -124.20),
    ("Monterey", 36.60, -121.89), ("Salinas", 36.68, -121.66), ("Hollister", 36.85, -121.40),
    ("Mammoth Lakes", 37.65, -118.97), ("Bishop", 37.36, -118.40), ("Ridgecrest", 35.62, -117.67),
    ("Barstow", 34.90, -117.02), ("Victorville", 34.54, -117.29), ("Lancaster", 34.70, -118.14),
    ("Yucca Valley", 34.11, -116.43), ("Twentynine Palms", 34.14, -116.05), ("El Centro", 32.79, -115.56),
    ("Yuma", 32.69, -114.63), ("Mexicali", 32.66, -115.47), ("Tijuana", 32.51, -117.04),
    ("Ensenada", 31.87, -116.60), ("Susanville", 40.42, -120.65), ("Truckee", 39.33, -120.18),
    ("South Lake Tahoe", 38.94, -119.98), ("Placerville", 38.73, -120.80), ("Merced", 37.30, -120.48),
    # --- Nevada / Utah / Arizona / NM / Colorado ---
    ("Las Vegas", 36.17, -115.14), ("Henderson", 36.04, -114.98), ("Pahrump", 36.21, -115.98),
    ("Mesquite", 36.80, -114.07), ("Reno", 39.53, -119.81), ("Carson City", 39.16, -119.77),
    ("Elko", 40.83, -115.76), ("Ely", 39.25, -114.89), ("Winnemucca", 40.97, -117.74),
    ("Tonopah", 38.07, -117.23), ("Fallon", 39.47, -118.78), ("Salt Lake City", 40.76, -111.89),
    ("Provo", 40.23, -111.66), ("Ogden", 41.22, -111.97), ("Logan", 41.74, -111.83),
    ("St. George", 37.10, -113.58), ("Cedar City", 37.68, -113.06), ("Moab", 38.57, -109.55),
    ("Price", 39.60, -110.81), ("Richfield", 38.77, -112.08), ("Vernal", 40.46, -109.53),
    ("Kanab", 37.05, -112.53), ("Page", 36.91, -111.46), ("Blanding", 37.62, -109.48),
    ("Green River", 38.99, -110.16), ("Phoenix", 33.45, -112.07), ("Tucson", 32.22, -110.97),
    ("Flagstaff", 35.20, -111.65), ("Prescott", 34.54, -112.47), ("Sedona", 34.87, -111.76),
    ("Kingman", 35.19, -114.05), ("Lake Havasu City", 34.48, -114.32), ("Bullhead City", 35.15, -114.57),
    ("Sierra Vista", 31.55, -110.30), ("Nogales", 31.34, -110.93), ("Casa Grande", 32.88, -111.76),
    ("Yuma", 32.69, -114.63), ("Show Low", 34.25, -110.03), ("Winslow", 35.02, -110.70),
    ("Gallup", 35.53, -108.74), ("Farmington", 36.73, -108.22), ("Albuquerque", 35.08, -106.65),
    ("Santa Fe", 35.69, -105.94), ("Las Cruces", 32.31, -106.78), ("El Paso", 31.76, -106.49),
    ("Ciudad Juarez", 31.69, -106.42), ("Carlsbad NM", 32.42, -104.23), ("Hobbs", 32.70, -103.14),
    ("Roswell", 33.39, -104.52), ("Alamogordo", 32.90, -105.96), ("Silver City", 32.77, -108.28),
    ("Taos", 36.41, -105.57), ("Denver", 39.74, -104.99), ("Boulder", 40.01, -105.27),
    ("Fort Collins", 40.59, -105.08), ("Greeley", 40.42, -104.71), ("Colorado Springs", 38.83, -104.82),
    ("Pueblo", 38.25, -104.61), ("Grand Junction", 39.06, -108.55), ("Montrose", 38.48, -107.88),
    ("Durango", 37.27, -107.88), ("Cortez", 37.35, -108.59), ("Alamosa", 37.47, -105.87),
    ("Salida", 38.53, -106.00), ("Glenwood Springs", 39.55, -107.32), ("Vail", 39.64, -106.37),
    ("Estes Park", 40.38, -105.52), ("Steamboat Springs", 40.48, -106.83), ("Craig", 40.52, -107.55),
    ("Telluride", 37.94, -107.81), ("Gunnison", 38.55, -106.93), ("Rifle", 39.53, -107.78),
    # --- Texas / South Plains ---
    ("Dallas", 32.78, -96.80), ("Fort Worth", 32.75, -97.33), ("Houston", 29.76, -95.37),
    ("San Antonio", 29.42, -98.49), ("Austin", 30.27, -97.74), ("Midland", 32.00, -102.08),
    ("Odessa", 31.85, -102.37), ("Lubbock", 33.58, -101.86), ("Amarillo", 35.22, -101.83),
    ("Laredo", 27.51, -99.51), ("Nuevo Laredo", 27.48, -99.52), ("McAllen", 26.20, -98.23),
    ("Reynosa", 26.08, -98.28), ("Brownsville", 25.90, -97.50), ("Matamoros", 25.87, -97.50),
    ("Corpus Christi", 27.80, -97.40), ("Del Rio", 29.36, -100.90), ("Eagle Pass", 28.71, -100.50),
    ("Piedras Negras", 28.70, -100.52), ("Alpine TX", 30.36, -103.66), ("Fort Stockton", 30.89, -102.88),
    ("Pecos", 31.42, -103.49), ("San Angelo", 31.46, -100.44), ("Abilene", 32.45, -99.73),
    ("Wichita Falls", 33.91, -98.49), ("Waco", 31.55, -97.15), ("Tyler", 32.35, -95.30),
    ("Beaumont", 30.08, -94.13), ("Monterrey", 25.69, -100.32), ("Chihuahua", 28.63, -106.07),
    ("Ojinaga", 29.56, -104.41), ("Hermosillo", 29.07, -110.96), ("Saltillo", 25.42, -101.00),
    ("Monclova", 26.91, -101.42), ("Acuna", 29.32, -100.95), ("Santa Rosalia", 27.34, -105.07),
    ("Odessa-Midland", 31.93, -102.22),
    # --- Plains / Midwest ---
    ("Oklahoma City", 35.47, -97.52), ("Tulsa", 36.15, -95.99), ("Wichita", 37.69, -97.34),
    ("Kansas City", 39.10, -94.58), ("Omaha", 41.26, -95.93), ("Lincoln", 40.81, -96.70),
    ("Des Moines", 41.59, -93.62), ("Minneapolis", 44.98, -93.27), ("St. Paul", 44.95, -93.09),
    ("Duluth", 46.79, -92.10), ("Fargo", 46.88, -96.79), ("Sioux Falls", 43.55, -96.73),
    ("Rapid City", 44.08, -103.23), ("Bismarck", 46.81, -100.78), ("Minot", 48.23, -101.30),
    ("Williston", 48.15, -103.62), ("Dickinson", 46.88, -102.79), ("Watford City", 47.80, -103.28),
    ("Grand Forks", 47.93, -97.03), ("Pierre", 44.37, -100.35), ("Aberdeen SD", 45.46, -98.49),
    ("Chamberlain", 43.81, -99.33), ("Hot Springs SD", 43.43, -103.47), ("Spearfish", 44.49, -103.86),
    ("Gillette", 44.29, -105.50), ("Cheyenne", 41.14, -104.82), ("Casper", 42.85, -106.31),
    ("Laramie", 41.31, -105.59), ("Rock Springs", 41.59, -109.20), ("Sheridan", 44.80, -106.96),
    ("Cody", 44.53, -109.06), ("Jackson", 43.48, -110.76), ("Lander", 42.83, -108.73),
    ("Scottsbluff", 41.87, -103.67), ("North Platte", 41.12, -100.77), ("Grand Island", 40.92, -98.34),
    ("Topeka", 39.05, -95.68), ("Joplin", 37.08, -94.51), ("Springfield MO", 37.21, -93.29),
    ("Columbia MO", 38.95, -92.33), ("Jefferson City", 38.58, -92.17), ("St. Louis", 38.63, -90.20),
    ("Rolla", 37.95, -91.77), ("Cape Girardeau", 37.31, -89.52), ("Little Rock", 34.75, -92.29),
    ("Fort Smith", 35.39, -94.40), ("Fayetteville AR", 36.06, -94.16), ("Hot Springs AR", 34.50, -93.06),
    ("Pine Bluff", 34.23, -92.00), ("Jonesboro", 35.84, -90.70), ("Texarkana", 33.43, -94.05),
    ("Shreveport", 32.53, -93.75), ("Chicago", 41.88, -87.63), ("Gary", 41.59, -87.35),
    ("Milwaukee", 43.04, -87.91), ("Madison", 43.07, -89.40), ("Green Bay", 44.52, -88.02),
    ("Rockford", 42.27, -89.09), ("South Bend", 41.68, -86.25), ("Fort Wayne", 41.08, -85.14),
    ("Indianapolis", 39.77, -86.16), ("Louisville", 38.25, -85.76), ("Evansville", 37.97, -87.57),
    ("Bowling Green", 36.99, -86.44), ("Elizabethtown KY", 37.69, -85.86), ("Nashville", 36.16, -86.78),
    ("Lexington", 38.04, -84.50), ("Cincinnati", 39.10, -84.51), ("Dayton", 39.76, -84.19),
    ("Columbus", 39.96, -83.00), ("Toledo", 41.65, -83.54), ("Detroit", 42.33, -83.05),
    ("Cleveland", 41.50, -81.69), ("Akron", 41.08, -81.52), ("Canton", 40.80, -81.38),
    ("Youngstown", 41.10, -80.65), ("Grand Rapids", 42.96, -85.67), ("Lansing", 42.73, -84.56),
    ("Kalamazoo", 42.29, -85.59), ("Marquette", 46.54, -87.40), ("Sault Ste. Marie", 46.50, -84.35),
    ("Traverse City", 44.76, -85.62), ("Houghton", 47.12, -88.57), ("Ashland WI", 46.59, -90.88),
    ("Eau Claire", 44.81, -91.50), ("La Crosse", 43.80, -91.24), ("Rochester MN", 44.02, -92.47),
    ("International Falls", 48.60, -93.41), ("Thunder Bay", 48.38, -89.25), ("Ely MN", 47.90, -91.87),
    ("Grand Marais", 47.75, -90.33), ("Cedar Rapids", 41.98, -91.67), ("Davenport", 41.52, -90.58),
    # --- Northwest / Mountain West ---
    ("Seattle", 47.61, -122.33), ("Tacoma", 47.25, -122.44), ("Olympia", 47.04, -122.90),
    ("Everett", 47.98, -122.20), ("Bellingham", 48.75, -122.48), ("Port Angeles", 48.12, -123.43),
    ("Aberdeen WA", 46.98, -123.81), ("Spokane", 47.66, -117.43), ("Yakima", 46.60, -120.51),
    ("Wenatchee", 47.42, -120.31), ("Tri-Cities WA", 46.23, -119.14), ("Ellensburg", 46.99, -120.55),
    ("Bellevue", 47.61, -122.20), ("Portland", 45.52, -122.68), ("Salem", 44.94, -123.04),
    ("Eugene", 44.05, -123.09), ("Medford", 42.33, -122.87), ("Klamath Falls", 42.22, -121.78),
    ("Bend", 44.06, -121.31), ("Roseburg", 43.22, -123.34), ("Coos Bay", 43.37, -124.22),
    ("Pendleton", 45.67, -118.79), ("Boise", 43.62, -116.20), ("Idaho Falls", 43.49, -112.04),
    ("Pocatello", 42.87, -112.45), ("Twin Falls", 42.56, -114.46), ("Coeur d'Alene", 47.68, -116.78),
    ("Lewiston", 46.42, -117.02), ("Missoula", 46.87, -114.00), ("Kalispell", 48.20, -114.31),
    ("Whitefish", 48.41, -114.34), ("Great Falls", 47.50, -111.30), ("Helena", 46.59, -112.04),
    ("Bozeman", 45.68, -111.04), ("Butte", 45.99, -112.53), ("Billings", 45.78, -108.50),
    ("Livingston", 45.66, -110.56), ("West Yellowstone", 44.66, -111.10), ("Cut Bank", 48.63, -112.33),
    ("Havre", 48.55, -109.68), ("Sandpoint", 48.28, -116.55), ("Hamilton MT", 46.25, -114.16),
    # --- Southeast ---
    ("Atlanta", 33.75, -84.39), ("Birmingham", 33.52, -86.80), ("Chattanooga", 35.05, -85.31),
    ("Knoxville", 35.96, -83.92), ("Gatlinburg", 35.71, -83.51), ("Pigeon Forge", 35.79, -83.55),
    ("Sevierville", 35.87, -83.56), ("Maryville TN", 35.76, -83.97), ("Asheville", 35.60, -82.55),
    ("Cherokee NC", 35.48, -83.31), ("Waynesville", 35.49, -82.99), ("Bryson City", 35.43, -83.45),
    ("Greenville SC", 34.85, -82.40), ("Spartanburg", 34.95, -81.93), ("Columbia SC", 34.00, -81.03),
    ("Charleston SC", 32.78, -79.93), ("Sumter", 33.92, -80.34), ("Orangeburg", 33.49, -80.86),
    ("Charlotte", 35.23, -80.84), ("Raleigh", 35.78, -78.64), ("Durham", 35.99, -78.90),
    ("Greensboro", 36.07, -79.79), ("Winston-Salem", 36.10, -80.24), ("Wilmington NC", 34.23, -77.94),
    ("Savannah", 32.08, -81.09), ("Augusta", 33.47, -81.97), ("Macon", 32.84, -83.63),
    ("Jacksonville", 30.33, -81.66), ("Tallahassee", 30.44, -84.28), ("Orlando", 28.54, -81.38),
    ("Tampa", 27.95, -82.46), ("St. Petersburg", 27.77, -82.64), ("Fort Myers", 26.64, -81.87),
    ("Naples", 26.14, -81.79), ("Miami", 25.76, -80.19), ("Fort Lauderdale", 26.12, -80.14),
    ("West Palm Beach", 26.72, -80.05), ("Homestead", 25.47, -80.48), ("Key West", 24.56, -81.78),
    ("Marathon", 24.71, -81.09), ("Key Largo", 25.09, -80.45), ("Pensacola", 30.42, -87.22),
    ("Mobile", 30.69, -88.04), ("Montgomery", 32.38, -86.30), ("Huntsville", 34.73, -86.59),
    ("Jackson MS", 32.30, -90.18), ("Memphis", 35.15, -90.05), ("New Orleans", 29.95, -90.07),
    ("Baton Rouge", 30.45, -91.19), ("Lafayette LA", 30.22, -92.02), ("Lake Charles", 30.23, -93.22),
    ("Gulfport", 30.37, -89.09), ("Tuscaloosa", 33.21, -87.57), ("Dothan", 31.22, -85.39),
    ("Gainesville FL", 29.65, -82.32), ("Daytona Beach", 29.21, -81.02), ("Cape Coral", 26.56, -81.95),
    ("Sarasota", 27.34, -82.53), ("Lakeland", 28.04, -81.95), ("Homestead-Florida City", 25.45, -80.48),
    # --- Mid-Atlantic / Northeast ---
    ("Washington DC", 38.91, -77.04), ("Baltimore", 39.29, -76.61), ("Richmond", 37.54, -77.44),
    ("Norfolk", 36.85, -76.29), ("Virginia Beach", 36.85, -75.98), ("Roanoke", 37.27, -79.94),
    ("Charlottesville", 38.03, -78.48), ("Harrisonburg", 38.45, -78.87), ("Staunton", 38.15, -79.07),
    ("Winchester VA", 39.19, -78.16), ("Front Royal", 38.92, -78.19), ("Lynchburg", 37.41, -79.14),
    ("Culpeper", 38.47, -77.99), ("Fredericksburg", 38.30, -77.46), ("Waynesboro VA", 38.07, -78.89),
    ("Charleston WV", 38.35, -81.63), ("Beckley", 37.78, -81.19), ("Huntington WV", 38.42, -82.45),
    ("Morgantown", 39.63, -79.96), ("Pittsburgh", 40.44, -80.00), ("Philadelphia", 39.95, -75.17),
    ("Allentown", 40.60, -75.47), ("Harrisburg", 40.27, -76.88), ("Scranton", 41.41, -75.66),
    ("State College", 40.79, -77.86), ("Wilmington DE", 39.74, -75.55), ("Newark", 40.74, -74.17),
    ("New York", 40.71, -74.01), ("Bridgeport", 41.19, -73.20), ("New Haven", 41.31, -72.92),
    ("Hartford", 41.77, -72.68), ("Providence", 41.82, -71.41), ("Boston", 42.36, -71.06),
    ("Worcester", 42.26, -71.80), ("Springfield MA", 42.10, -72.59), ("Albany", 42.65, -73.76),
    ("Syracuse", 43.05, -76.15), ("Rochester NY", 43.16, -77.61), ("Buffalo", 42.89, -78.88),
    ("Burlington VT", 44.48, -73.21), ("Manchester NH", 42.99, -71.46), ("Portland ME", 43.66, -70.26),
    ("Bangor", 44.80, -68.77), ("Bar Harbor", 44.39, -68.20), ("Ellsworth", 44.54, -68.42),
    ("Augusta ME", 44.31, -69.78), ("Presque Isle", 46.68, -68.02), ("Lewiston ME", 44.10, -70.21),
    ("Concord NH", 43.21, -71.54), ("Montpelier", 44.26, -72.58), ("Watertown NY", 43.97, -75.91),
    # --- Canada ---
    ("Toronto", 43.65, -79.38), ("Hamilton ON", 43.26, -79.87), ("Kitchener", 43.45, -80.49),
    ("London ON", 42.98, -81.25), ("Windsor ON", 42.32, -83.04), ("Sarnia", 42.97, -82.41),
    ("Niagara Falls", 43.09, -79.08), ("Ottawa", 45.42, -75.70), ("Montreal", 45.50, -73.57),
    ("Quebec City", 46.81, -71.21), ("Sherbrooke", 45.40, -71.89), ("Sudbury", 46.49, -81.00),
    ("Sault Ste. Marie ON", 46.52, -84.35), ("Thunder Bay", 48.38, -89.25), ("Fredericton", 45.96, -66.64),
    ("Saint John", 45.27, -66.06), ("Moncton", 46.09, -64.78), ("Halifax", 44.65, -63.58),
    ("Charlottetown", 46.24, -63.13), ("Winnipeg", 49.90, -97.14), ("Regina", 50.45, -104.62),
    ("Saskatoon", 52.13, -106.67), ("Calgary", 51.05, -114.07), ("Edmonton", 53.55, -113.49),
    ("Lethbridge", 49.69, -112.84), ("Medicine Hat", 50.04, -110.68), ("Cranbrook", 49.51, -115.77),
    ("Kelowna", 49.89, -119.50), ("Vancouver", 49.28, -123.12), ("Victoria", 48.43, -123.37),
    ("Nanaimo", 49.17, -123.94), ("Abbotsford", 49.06, -122.30), ("Prince George", 53.92, -122.75),
    ("Whitehorse", 60.72, -135.06), ("Estevan", 49.14, -102.99), ("Brandon", 49.85, -99.95),
    ("Kenora", 49.77, -94.49), ("Fort Frances", 48.61, -93.41), ("Whitehorse YT", 60.72, -135.06),
    # --- Alaska ---
    ("Anchorage", 61.22, -149.90), ("Wasilla", 61.58, -149.44), ("Palmer", 61.60, -149.11),
    ("Fairbanks", 64.84, -147.72), ("Juneau", 58.30, -134.42), ("Homer", 59.64, -151.54),
    ("Kenai", 60.55, -151.26), ("Soldotna", 60.49, -151.06), ("Seward", 60.10, -149.44),
    ("Kodiak", 57.79, -152.41), ("Cordova", 60.54, -145.76), ("Valdez", 61.13, -146.35),
    ("Glennallen", 62.11, -145.55), ("Gustavus", 58.41, -135.74), ("Sitka", 57.05, -135.33),
    ("Haines", 59.24, -135.45), ("Skagway", 59.46, -135.31), ("Kotzebue", 66.90, -162.60),
    ("Bethel", 60.79, -161.76), ("King Salmon", 58.69, -156.65), ("Delta Junction", 64.04, -145.73),
    ("Tok", 63.34, -142.99), ("Healy", 63.86, -148.97), ("Talkeetna", 62.32, -150.11),
    ("Nome", 64.50, -165.41), ("Utqiagvik", 71.29, -156.79), ("Dillingham", 59.04, -158.46),
    ("Nenana", 64.56, -149.09), ("McCarthy", 61.43, -142.92), ("Chitina", 61.52, -144.44),
    ("Bettles", 66.92, -151.52), ("Anaktuvuk Pass", 68.14, -151.74), ("Tanana", 65.17, -152.08),
    ("Coldfoot", 67.25, -150.18), ("Prudhoe Bay", 70.26, -148.34), ("Cantwell", 63.39, -148.95),
    ("Port Alsworth", 60.20, -154.32), ("Iliamna", 59.75, -154.91), ("Naknek", 58.73, -157.02),
    ("Hoonah", 58.11, -135.44), ("Yakutat", 59.55, -139.73), ("Ketchikan", 55.34, -131.64),
    ("Wrangell", 56.47, -132.38), ("Petersburg", 56.81, -132.96), ("Whittier", 60.77, -148.68),
    ("Seldovia", 59.44, -151.71), ("Nikiski", 60.69, -151.29), ("Big Lake", 61.52, -149.95),
    # --- Hawaii ---
    ("Honolulu", 21.31, -157.86), ("Kahului", 20.89, -156.47), ("Wailuku", 20.89, -156.50),
    ("Kihei", 20.76, -156.45), ("Lahaina", 20.88, -156.68), ("Hilo", 19.72, -155.09),
    ("Kailua-Kona", 19.64, -155.99), ("Waimea HI", 20.02, -155.67), ("Pahoa", 19.49, -154.95),
    ("Volcano HI", 19.44, -155.24), ("Pahala", 19.20, -155.48), ("Kapolei", 21.34, -158.06),
    ("Lihue", 21.98, -159.37), ("Makawao", 20.86, -156.31), ("Paia", 20.90, -156.37),
    # --- gateway villages / park lodging clusters (they dominate several parks' local glow) ---
    ("Grand Canyon Village", 36.06, -112.14), ("Tusayan", 35.97, -112.13), ("Furnace Creek", 36.46, -116.87),
    ("Stovepipe Wells", 36.60, -117.15), ("Bryce Canyon City", 37.67, -112.15), ("Torrey", 38.30, -111.42),
    ("Springdale", 37.19, -112.99), ("Yosemite Valley", 37.75, -119.59), ("Terlingua", 29.32, -103.61),
    ("Lajitas", 29.26, -103.77), ("Marathon TX", 30.20, -103.24), ("Boquillas del Carmen", 29.19, -102.91),
    ("Medora", 46.92, -103.52), ("Tuba City", 36.13, -111.24), ("Chinle", 36.15, -109.55),
    ("Holbrook", 34.90, -110.16), ("Wawona", 37.54, -119.66), ("Lake Louise AK", 62.28, -146.54),
    ("Kantishna", 63.53, -150.98), ("Ambler", 67.09, -157.86), ("Kiana", 66.97, -160.43),
    ("Nuiqsut", 70.22, -151.00), ("Kobuk", 66.91, -156.89), ("Shungnak", 66.89, -157.15),
    ("Inuvik", 68.36, -133.72), ("Stehekin", 48.31, -120.66), ("Paradise", 46.79, -121.74),
    # --- Territories ---
    ("Pago Pago", -14.28, -170.70), ("Tafuna", -14.33, -170.72), ("Apia", -13.83, -171.76),
    ("Charlotte Amalie", 18.34, -64.93), ("Cruz Bay", 18.33, -64.79), ("Christiansted", 17.75, -64.70),
    ("Road Town", 18.43, -64.62), ("San Juan", 18.47, -66.11), ("Fajardo", 18.33, -65.65),
    ("Culebra", 18.31, -65.30),
]

# --------------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------------

def tile_of(lat, lon):
    return int(math.floor((lon + 180.0) / 10.0)), int(math.floor((90.0 - lat) / 10.0))


def sites_of(parks):
    pts = []
    for p in parks:
        pts.append((p["latitude"], p["longitude"]))
        for s in p.get("viewingSpots", []):
            pts.append((s["latitude"], s["longitude"]))
    return pts


def needed_tiles(parks, radius_km=RADIUS_KM):
    tiles = set()
    for lat, lon in sites_of(parks):
        dl = radius_km / 111.2 + 0.2
        dn = dl / max(0.2, math.cos(math.radians(min(abs(lat) + dl, 89.0))))
        for a in (lat - dl, lat, lat + dl):
            for b in (lon - dn, lon, lon + dn):
                tiles.add(tile_of(a, b))
    return sorted(tiles)


def haversine_bearing(lat0, lon0, lat, lon):
    """Distance (km) and initial bearing (deg, 0=N clockwise) from site to arrays."""
    p0 = math.radians(lat0)
    p = np.radians(lat)
    dl = np.radians(lon - lon0)
    a = np.sin((p - p0) / 2) ** 2 + math.cos(p0) * np.cos(p) * np.sin(dl / 2) ** 2
    d = 2 * EARTH_R * np.arcsin(np.sqrt(np.clip(a, 0, 1)))
    y = np.sin(dl) * np.cos(p)
    x = math.cos(p0) * np.sin(p) - math.sin(p0) * np.cos(p) * np.cos(dl)
    az = (np.degrees(np.arctan2(y, x)) + 360.0) % 360.0
    return d, az


def hav_km(lat1, lon1, lat2, lon2):
    d, _ = haversine_bearing(lat1, lon1, np.asarray(lat2), np.asarray(lon2))
    return d


# --------------------------------------------------------------------------
# Download + aggregate (tile by tile; raw .h5 deleted immediately)
# --------------------------------------------------------------------------

def read_token():
    path = Path.home() / ".earthdata_token"
    if path.exists():
        return path.read_text().strip()
    tok = os.environ.get("EARTHDATA_TOKEN", "").strip()
    if not tok:
        sys.exit("No Earthdata token: put it in ~/.earthdata_token or set EARTHDATA_TOKEN.")
    return tok


def listing(year, cache):
    f = cache / f"listing_{year}.json"
    if not f.exists():
        with urllib.request.urlopen(LISTING.format(year=year), timeout=120) as r:
            f.write_bytes(r.read())
    entries = json.loads(f.read_text())["content"]
    return {e["name"].split(".")[2]: e["name"] for e in entries}


def curl_download(url, dest, token):
    # Token goes via stdin config so it never appears in the process list.
    cfg = f'header = "Authorization: Bearer {token}"\n'
    r = subprocess.run(
        ["curl", "-sS", "-L", "--fail", "--retry", "3", "-K", "-", "-o", str(dest), url],
        input=cfg.encode(), capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("curl failed (%d): %s" % (r.returncode, r.stderr.decode()[:200].replace(token, "***")))


def block_mean(a):
    n = a.shape[0] // BLOCK
    return a.reshape(n, BLOCK, n, BLOCK).mean(axis=(1, 3)).astype(np.float32)


def aggregate_tile(h5path):
    import h5py
    with h5py.File(h5path, "r") as f:
        g = f[GROUP]
        nn, nq = g["NearNadir_Composite_Snow_Free"][:], g["NearNadir_Composite_Snow_Free_Quality"][:]
        aa, aq = g["AllAngle_Composite_Snow_Free"][:], g["AllAngle_Composite_Snow_Free_Quality"][:]
    nn_ok = (nn >= 0) & (nq != 255)
    aa_ok = (aa >= 0) & (aq != 255)
    use_aa = aa_ok & (~nn_ok | ((nq == 1) & (aq == 0)))
    out = np.where(nn_ok, nn, 0.0)
    out = np.where(use_aa, aa, out)
    out = np.clip(out, 0, None).astype(np.float32)
    stats = {"fill_frac": float(1 - (nn_ok | aa_ok).mean()), "aa_frac": float(use_aa.mean())}
    return block_mean(out), stats


def ensure_tiles(parks, years, cache, skip_download):
    agg = cache / "agg"
    agg.mkdir(parents=True, exist_ok=True)
    tiles = needed_tiles(parks)
    token = None
    for year in years:
        names = None
        for (h, v) in tiles:
            out = agg / f"{year}_h{h:02d}v{v:02d}.npy"
            if out.exists():
                continue
            if skip_download:
                sys.exit(f"missing {out}")
            if names is None:
                names = listing(year, cache)
            token = token or read_token()
            name = names[f"h{h:02d}v{v:02d}"]
            raw = cache / "raw.h5"
            print(f"  {year} h{h:02d}v{v:02d} ...", flush=True)
            curl_download(CLOUD.format(name=name), raw, token)
            arr, st = aggregate_tile(raw)
            np.save(out, arr)
            raw.unlink()
            print(f"    done, fill={st['fill_frac']:.3f} allangle_used={st['aa_frac']:.3f}", flush=True)
    return tiles


class Mosaic:
    """Global (lat/lon) grid of aggregated cells, only the needed tiles filled."""

    def __init__(self, year, tiles, cache):
        hs = [t[0] for t in tiles]
        vs = [t[1] for t in tiles]
        self.h0, self.v0 = min(hs), min(vs)
        self.nh, self.nv = max(hs) - self.h0 + 1, max(vs) - self.v0 + 1
        self.a = np.zeros((self.nv * TILE_CELLS, self.nh * TILE_CELLS), np.float32)
        for (h, v) in tiles:
            t = np.load(cache / "agg" / f"{year}_h{h:02d}v{v:02d}.npy")
            r, c = (v - self.v0) * TILE_CELLS, (h - self.h0) * TILE_CELLS
            self.a[r:r + TILE_CELLS, c:c + TILE_CELLS] = t

    def window(self, lat, lon, radius_km):
        """Cells in a bounding window around the site: lat, lon, radiance, area arrays (flattened)."""
        dl = radius_km / 111.0 + 0.1
        dn = dl / max(0.05, math.cos(math.radians(min(abs(lat) + dl, 89.0))))
        # global row/col index; row 0 = lat 90
        def row(la): return (90.0 - la) / CELL_DEG
        def col(lo): return (lo + 180.0) / CELL_DEG
        R0 = max(int(math.floor(row(lat + dl))), self.v0 * TILE_CELLS)
        R1 = min(int(math.ceil(row(lat - dl))), (self.v0 + self.nv) * TILE_CELLS)
        C0 = max(int(math.floor(col(lon - dn))), self.h0 * TILE_CELLS)
        C1 = min(int(math.ceil(col(lon + dn))), (self.h0 + self.nh) * TILE_CELLS)
        sub = self.a[R0 - self.v0 * TILE_CELLS:R1 - self.v0 * TILE_CELLS,
                     C0 - self.h0 * TILE_CELLS:C1 - self.h0 * TILE_CELLS]
        rr, cc = np.meshgrid(np.arange(R0, R1), np.arange(C0, C1), indexing="ij")
        la = 90.0 - (rr + 0.5) * CELL_DEG
        lo = -180.0 + (cc + 0.5) * CELL_DEG
        area = CELL_KM * CELL_KM * np.cos(np.radians(la))
        return la.ravel(), lo.ravel(), sub.ravel().astype(np.float64), area.ravel()


# --------------------------------------------------------------------------
# Model
# --------------------------------------------------------------------------

def site_model(mos, lat, lon):
    la, lo, L, A = mos.window(lat, lon, RADIUS_KM)
    d, az = haversine_bearing(lat, lon, la, lo)
    keep = (d <= RADIUS_KM) & (L > 0)
    la, lo, L, A, d, az = la[keep], lo[keep], L[keep], A[keep], d[keep], az[keep]
    contrib = L * A * np.maximum(d, MIN_D_KM) ** (-WALKER_EXP)
    bins = (((az + 5.0) % 360.0) // 10.0).astype(int) % 36
    prof = np.bincount(bins, weights=contrib, minlength=36)
    return {"G": float(contrib.sum()), "profile": prof, "la": la, "lo": lo, "L": L, "A": A,
            "d": d, "az": az, "contrib": contrib}


def circ_diff(a, b):
    return (a - b + 180.0) % 360.0 - 180.0


def find_domes(m):
    prof = m["profile"]
    total = prof.sum()
    if total <= 0:
        return []
    win = np.array([prof[(i - 1) % 36] + prof[i] + prof[(i + 1) % 36] for i in range(36)])
    alive = np.ones(36, bool)
    domes = []
    for _ in range(3):
        cand = np.where(alive, win, -1.0)
        i = int(np.argmax(cand))
        if cand[i] / total < DOME_MIN_SHARE:
            break
        centre = i * 10.0
        sel = np.abs(circ_diff(m["az"], centre)) <= 15.0
        # bearing = contribution-weighted circular mean
        w = m["contrib"][sel]
        rad = np.radians(m["az"][sel])
        bearing = (math.degrees(math.atan2((w * np.sin(rad)).sum(), (w * np.cos(rad)).sum())) + 360.0) % 360.0
        share = float(w.sum() / total)
        city = name_source(m, sel)
        domes.append({"bearing": int(round(bearing)) % 360, "share": round(share, 3), "city": city})
        for k in range(-3, 4):
            alive[(i + k) % 36] = False
    return domes


def name_source(m, sel):
    idx = np.where(sel)[0]
    if idx.size == 0:
        return None
    c = m["contrib"][idx]
    seed = idx[int(np.argmax(c))]
    near = hav_km(m["la"][seed], m["lo"][seed], m["la"][idx], m["lo"][idx]) <= CLUSTER_KM
    cl = idx[near]
    w = m["L"][cl] * m["A"][cl]
    clat = float((m["la"][cl] * w).sum() / w.sum())
    clon = float((m["lo"][cl] * w).sum() / w.sum())
    best, bd = None, 1e9
    for name, la, lo in METROS:
        dist = float(hav_km(clat, clon, np.array([la]), np.array([lo]))[0])
        if dist < bd:
            best, bd = name, dist
    DOME_LOG.append((round(clat, 2), round(clon, 2), best, round(bd)))
    if bd <= CITY_MATCH_KM:
        parts = best.rsplit(" ", 1)
        # trailing 2-letter code (e.g. "Jackson MS", "London ON") only disambiguates the list entry
        if len(parts) == 2 and len(parts[1]) == 2 and parts[1].isupper() and parts[1] != "DC":
            return parts[0]
        return best
    return None


def profile_bytes(prof):
    mx = prof.max()
    if mx <= 0:
        return [0] * 36
    return [int(round(255.0 * v / mx)) for v in prof]


def sig(x, n=3):
    if x == 0 or not math.isfinite(x):
        return 0.0
    return float(f"{x:.{n}g}")


# --------------------------------------------------------------------------
# Calibration
# --------------------------------------------------------------------------

def fit_bortle(glows, hand):
    """bortle = a + b*log10(glow + g0), b>0; g0 chosen by grid search."""
    glows, hand = np.asarray(glows, float), np.asarray(hand, float)
    best = None
    for g0 in np.logspace(-3.0, 2.0, 201):
        x = np.log10(glows + g0)
        A = np.vstack([np.ones_like(x), x]).T
        coef, *_ = np.linalg.lstsq(A, hand, rcond=None)
        if coef[1] <= 0:
            continue
        pred = np.clip(A @ coef, 1, 9)
        sse = float(((pred - hand) ** 2).sum())
        if best is None or sse < best[0]:
            best = (sse, g0, coef[0], coef[1])
    return best[1], best[2], best[3]


def predict(g, g0, a, b):
    return float(np.clip(a + b * math.log10(g + g0), 1.0, 9.0))


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=str(Path(tempfile.gettempdir()) / "nyx_blackmarble"))
    ap.add_argument("--years", nargs=2, type=int, default=[2013, 2025])
    ap.add_argument("--skip-download", action="store_true")
    ap.add_argument("--debug-domes", action="store_true", help="print centroid/nearest metro of every dome")
    args = ap.parse_args()
    cache = Path(args.cache)
    cache.mkdir(parents=True, exist_ok=True)
    early, late = args.years

    parks = json.loads(PARKS_JSON.read_text())
    tiles = ensure_tiles(parks, [early, late], cache, args.skip_download)
    print("loading mosaics", flush=True)
    mos_e, mos_l = Mosaic(early, tiles, cache), Mosaic(late, tiles, cache)

    # --- per-site raw G (late year) ---
    results = {}
    for p in parks:
        pm = site_model(mos_l, p["latitude"], p["longitude"])
        spots = [(s, site_model(mos_l, s["latitude"], s["longitude"])) for s in p.get("viewingSpots", [])]
        results[p["id"]] = (pm, spots)

    norm = float(np.median([results[p["id"]][0]["G"] for p in parks]))
    glow = {pid: results[pid][0]["G"] / norm for pid in results}
    g0, a, b = fit_bortle([glow[p["id"]] for p in parks], [p["bortleEstimate"] for p in parks])
    print(f"normaliser (median park G) = {norm:.6g}; fit: bortle = {a:.3f} + {b:.3f}*log10(glow+{g0:.4g})")

    out = {}
    rows = []
    for p in parks:
        pm, spots = results[p["id"]]
        # trend
        trend = {}
        sums = []
        for mos in (mos_e, mos_l):
            la, lo, L, A = mos.window(p["latitude"], p["longitude"], TREND_RADIUS_KM)
            d = hav_km(p["latitude"], p["longitude"], la, lo)
            sums.append(float((L * A)[d <= TREND_RADIUS_KM].sum()))
        pct = None if sums[0] <= 0 else round((sums[1] - sums[0]) / sums[0] * 100.0, 1)
        trend = {"early": round(sums[0], 1), "late": round(sums[1], 1), "percent": pct}
        g = glow[p["id"]]
        bt = predict(g, g0, a, b)
        entry = {
            "glow": sig(g), "bortle": round(bt, 1), "trend": trend,
            "profile": profile_bytes(pm["profile"]), "domes": find_domes(pm), "spots": [],
        }
        for s, sm in spots:
            gs = sm["G"] / norm
            entry["spots"].append({
                "name": s["name"], "glow": sig(gs), "bortle": round(predict(gs, g0, a, b), 1),
                "profile": profile_bytes(sm["profile"]), "domes": find_domes(sm),
            })
        out[p["id"]] = entry
        rows.append((p["id"], p["name"], p["bortleEstimate"], round(bt, 2), sig(g), p["darkSkyDesignated"]))

    model = (f"Walker's law G = sum L*A*d^-2.5 over 2 km cells, 1 km <= d <= 300 km (d<1 km counted as 1 km), "
             f"VNP46A4 NearNadir_Composite_Snow_Free (AllAngle fallback), {late}; glow = G / {norm:.6g} "
             f"(median national-park centre = 1). bortle = {a:.3f} + {b:.3f}*log10(glow + {g0:.4g}) clipped to 1-9, "
             f"fitted to hand estimates; an index, not a measurement. profile: 36 bins of 10 deg, bin 0 centred on "
             f"north, clockwise, 255 = brightest bin. trend: sum of L*A within 150 km of the park centre.")
    doc = {
        "source": "NASA Black Marble VNP46A4 (VIIRS yearly nighttime lights, collection 5200), Roman et al. 2018; "
                  "public domain. https://ladsweb.modaps.eosdis.nasa.gov/missions-and-measurements/products/VNP46A4/",
        "years": [early, late],
        "model": model,
        "parks": out,
    }
    OUT_JSON.write_text(json.dumps(doc, separators=(",", ":"), ensure_ascii=False))
    OUT_CSV.parent.mkdir(exist_ok=True)
    with open(OUT_CSV, "w") as f:
        f.write("id,name,hand_bortle,computed_bortle,glow,dark_sky_designated\n")
        for r in rows:
            f.write(",".join(str(x).replace(",", "") for x in r) + "\n")
    if args.debug_domes:
        for row in DOME_LOG:
            print("dome", row)
    hand = np.array([r[2] for r in rows], float)
    comp = np.array([r[3] for r in rows], float)
    ss_res = ((hand - comp) ** 2).sum()
    ss_tot = ((hand - hand.mean()) ** 2).sum()
    print(f"R2={1 - ss_res / ss_tot:.3f} maxres={np.abs(hand - comp).max():.2f} rmse={math.sqrt(ss_res / len(hand)):.2f}")
    print(f"wrote {OUT_JSON} ({OUT_JSON.stat().st_size} bytes), {OUT_CSV}")


if __name__ == "__main__":
    main()
