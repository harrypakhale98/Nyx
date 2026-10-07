#!/usr/bin/env python3
"""
build_cloud_climate.py -- offline cloud climatology for Nyx.

Reads ERA5 hourly total cloud cover (Copernicus Climate Change Service, CC BY 4.0;
Hersbach et al. 2020) for each park's coordinates over ten full years and produces
Nyx/Resources/cloud-climate.json: per park and calendar month, the typical cloud
over a night's true-dark hours and how often those hours were mostly clear.

The app uses it only beyond the forecast horizon, to rank nights fairly and to say
"November nights here are clear about 3 in 4". It is never shown as a forecast and
never changes a night's Darkness Score.

USAGE
    python3 -m venv <env> && <env>/bin/pip install cdsapi
    <env>/bin/python Scripts/build_cloud_climate.py [--cache DIR] [--years 2015 2024] [--skip-download]

AUTHENTICATION (downloads only)
    cdsapi reads ~/.cdsapirc (url and personal key from your Climate Data Store
    profile, mode 600). The ERA5 licence must be accepted once on the dataset's
    Download page. The key is never read, printed or written by this script.

PIPELINE
    1. Download: dataset reanalysis-era5-single-levels-timeseries, variable
       total_cloud_cover, one request per park at the park's own latitude and
       longitude (the coordinates the app sends to Open-Meteo; ERA5 snaps to the
       nearest 0.25 degree grid point). CSV, hourly, UTC. Cached per park.
    2. Night window, the app's own rule (SkyConditions.cloudWindow): each night is
       local noon to local noon in the park's IANA zone; its window is the hours of
       astronomical darkness (Sun below -18 deg); without any, sunset to sunrise
       (Sun below -0.833 deg); under the midnight sun, the four hours around the
       Sun's lowest point. Solar altitude uses the same low-precision formulae as
       AstronomyEngine (Meeus ch. 25 apparent longitude, mean sidereal time).
    3. Night value: mean of the hourly instant values whose timestamps fall in the
       window (a window shorter than an hour takes the nearest hour).
    4. Month summary over all nights of that calendar month in the period:
           cloud = mean night value, percent (rounded)
           clear = share of nights whose value is below 30 percent ("mostly clear")
       A night belongs to the month of its evening.
"""
import argparse, csv, glob, io, json, math, os, sys, zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARKS = os.path.join(ROOT, "Nyx", "Resources", "parks.json")
OUT = os.path.join(ROOT, "Nyx", "Resources", "cloud-climate.json")
CLEAR_BELOW = 30.0
RAD = math.pi / 180


def download(park, cache, years):
    path = os.path.join(cache, f"{park['id']}.csv")
    if os.path.exists(path):
        return path
    import cdsapi
    client = cdsapi.Client(quiet=True, progress=False)
    result = client.retrieve("reanalysis-era5-single-levels-timeseries", {
        "variable": ["total_cloud_cover"],
        "location": {"longitude": park["longitude"], "latitude": park["latitude"]},
        "date": [f"{years[0]}-01-01/{years[1] + 1}-01-02"],
        "data_format": "csv",
    })
    archive = path + ".zip"
    result.download(archive)
    with zipfile.ZipFile(archive) as z:
        name = next(n for n in z.namelist() if n.endswith(".csv"))
        data = z.read(name)
    with open(path + ".part", "wb") as f:
        f.write(data)
    os.replace(path + ".part", path)
    os.remove(archive)
    return path


def read_hours(path):
    """{utc hour (datetime): cloud percent}, plus the grid point used."""
    hours, point = {}, None
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            if row.get("tcc") in (None, ""):
                continue
            t = datetime.strptime(row["valid_time"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
            hours[t] = max(0.0, min(100.0, float(row["tcc"]) * 100))
            point = (float(row["latitude"]), float(row["longitude"]))
    return hours, point


def solar_altitude(t, lat, lon):
    """Degrees; the formulae of AstronomyEngine.solarPosition and hourAngle."""
    jd = t.timestamp() / 86400 + 2440587.5
    T = (jd - 2451545) / 36525
    l = (280.46646 + T * (36000.76983 + T * 0.0003032)) % 360
    m = 357.52911 + T * (35999.05029 - 0.0001537 * T)
    c = math.sin(m * RAD) * (1.914602 - T * (0.004817 + 0.000014 * T)) + math.sin(2 * m * RAD) * (0.019993 - 0.000101 * T) + math.sin(3 * m * RAD) * 0.000289
    omega = 125.04 - 1934.136 * T
    lam = (l + c - 0.00569 - 0.00478 * math.sin(omega * RAD)) * RAD
    eps = (23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60 + 0.00256 * math.cos(omega * RAD)) * RAD
    ra = math.atan2(math.cos(eps) * math.sin(lam), math.cos(lam))
    dec = math.asin(math.sin(eps) * math.sin(lam))
    sidereal = (280.46061837 + 360.98564736629 * (jd - 2451545) + 0.000387933 * T * T - T ** 3 / 38710000) % 360
    h = (sidereal + lon) * RAD - ra
    phi = lat * RAD
    return math.asin(max(-1, min(1, math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(h)))) / RAD


def night_window(evening_noon, lat, lon):
    """(start, end) in UTC, sampled every 10 minutes, following SkyConditions.cloudWindow."""
    steps = [evening_noon + timedelta(minutes=10 * i) for i in range(145)]
    alts = [solar_altitude(t, lat, lon) for t in steps]
    for limit in (-18.0, -0.833):
        inside = [t for t, a in zip(steps, alts) if a < limit]
        if inside:
            # The first continuous run (the night itself), not a sliver at either noon.
            start = inside[0]
            run = [start]
            for t in inside[1:]:
                if (t - run[-1]) <= timedelta(minutes=10):
                    run.append(t)
                else:
                    break
            return run[0], run[-1]
    lowest = steps[min(range(len(steps)), key=lambda i: alts[i])]
    return lowest - timedelta(hours=2), lowest + timedelta(hours=2)


def night_value(hours, start, end):
    first = start.replace(minute=0, second=0, microsecond=0)
    values, t = [], first
    while t <= end + timedelta(minutes=30):
        if start - timedelta(minutes=30) <= t <= end + timedelta(minutes=30) and t in hours:
            values.append(hours[t])
        t += timedelta(hours=1)
    if not values:
        middle = start + (end - start) / 2
        nearest = middle.replace(minute=0, second=0, microsecond=0) + (timedelta(hours=1) if middle.minute >= 30 else timedelta())
        return hours.get(nearest)
    return sum(values) / len(values)


def summarise(park, path, years):
    hours, point = read_hours(path)
    zone = ZoneInfo(park["timeZoneID"])
    by_month = {m: [] for m in range(1, 13)}
    day = date(years[0], 1, 1)
    while day <= date(years[1], 12, 31):
        noon = datetime(day.year, day.month, day.day, 12, tzinfo=zone).astimezone(timezone.utc)
        start, end = night_window(noon, park["latitude"], park["longitude"])
        value = night_value(hours, start, end)
        if value is not None:
            by_month[day.month].append(value)
        day += timedelta(days=1)
    cloud = [round(sum(v) / len(v)) if v else None for v in (by_month[m] for m in range(1, 13))]
    clear = [round(100 * sum(1 for x in v if x < CLEAR_BELOW) / len(v)) if v else None for v in (by_month[m] for m in range(1, 13))]
    nights = [len(by_month[m]) for m in range(1, 13)]
    return {"cloud": cloud, "clear": clear}, point, nights


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.expanduser("~/Library/Caches/nyx-era5"))
    ap.add_argument("--years", nargs=2, type=int, default=[2015, 2024])
    ap.add_argument("--skip-download", action="store_true")
    ap.add_argument("--workers", type=int, default=4)
    args = ap.parse_args()
    os.makedirs(args.cache, exist_ok=True)
    parks = json.load(open(PARKS))

    if not args.skip_download:
        failed = []
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            jobs = {pool.submit(download, p, args.cache, args.years): p for p in parks}
            for done, job in enumerate(as_completed(jobs), 1):
                park = jobs[job]
                try:
                    job.result()
                    print(f"[{done}/{len(parks)}] {park['id']} downloaded", flush=True)
                except Exception as error:  # noqa: BLE001 - report and continue
                    failed.append(park["id"])
                    print(f"[{done}/{len(parks)}] {park['id']} FAILED: {type(error).__name__}: {str(error)[:200]}", flush=True)
        if failed:
            print("Failed:", " ".join(failed), "- run again to retry (finished parks are cached).")
            sys.exit(1)

    result, report = {}, []
    for park in parks:
        summary, point, nights = summarise(park, os.path.join(args.cache, f"{park['id']}.csv"), args.years)
        result[park["id"]] = summary
        report.append((park["id"], point, min(nights), summary))
    out = {
        "source": f"ERA5 hourly total cloud cover, {args.years[0]}-{args.years[1]}, Copernicus Climate Change Service (CC BY 4.0)",
        "method": "Per calendar month: mean cloud over each night's true-dark hours (the app's cloud window), percent; and the share of nights under 30 percent (mostly clear).",
        "clearBelow": CLEAR_BELOW,
        "parks": result,
    }
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1, separators=(",", ": "))
        f.write("\n")
    for pid, point, fewest, s in report:
        print(f"{pid:5} grid {point}  fewest nights {fewest:3}  cloud {s['cloud']}  clear {s['clear']}")
    print("Wrote", OUT)


if __name__ == "__main__":
    main()
