"""Raw captures for the In-App Event media in Store/1.1/in-app-events.md. Run after a Debug simulator build
(`xcodebuild build-for-testing … -derivedDataPath /tmp/NyxBuild`), then compose with
`swift Scripts/make_event_media.swift`.

Usage: python3 Scripts/capture_events.py [phone|sky|all] [slug,slug…]
- phone: on the iPhone 18 Pro Max (iOS 27), two real screens per event: `<slug>-card.png` and `<slug>-details.png`.
- sky: on the iPad Pro 13-inch in landscape (through the UI test runner, since simctl cannot turn a simulator),
  the park's computed sky for that night, edge to edge (`-nyx-screen sky`): `<slug>-sky.png`.
Every picture is the app's own render for that park and night (`-nyx-date`, `-nyx-park`): the stars, Milky Way,
planets and radiant are computed, and the scores are the engine's own (moon and darkness only beyond the
forecast). Raw files go to /tmp/NyxEventRaw (or NYX_EVENT_RAW); only the composed media are kept in the repo.
Each simulator is booted only for its own pass and shut down after it.
"""
import subprocess, time, pathlib, sys, os, glob

PHONE = os.environ.get('NYX_PHONE', '2E90D43E-75AD-44AA-AA66-44A4F5155CF5')   # iPhone 18 Pro Max, iOS 27
PAD = os.environ.get('NYX_PAD', '927E7574-9A6E-4C4B-B6AC-BC8BDAD859A8')       # iPad Pro 13-inch (M5), iOS 27
DERIVED = os.environ.get('NYX_DERIVED', '/tmp/NyxBuild')
RAW = pathlib.Path(os.environ.get('NYX_EVENT_RAW', '/tmp/NyxEventRaw'))

def whatsup(date, park): return ['-nyx-screen', 'tonight', '-nyx-date', date, '-nyx-link', f'nyx://whatsup?date={date}&park={park}']
# The calendar opens on the first of the month, so the whole month is ahead (no greyed past nights).
def calendar(date, park): return ['-nyx-screen', 'tonight', '-nyx-date', date[:8] + '01', '-nyx-park', park, '-nyx-link', f'nyx://calendar/{park}?month={date[:7]}']
def detail(date, park): return ['-nyx-screen', 'detail', '-nyx-date', date, '-nyx-park', park]
def tonight(date, park): return ['-nyx-screen', 'tonight', '-nyx-date', date, '-nyx-park', park]

# slug, the evening of the night shown (park-local "tonight"), park, card screen, details screen.
# Meteor nights are the US night of the peak: Geminids Dec 13 to 14, Quadrantids Jan 3 to 4 (peak 10:25 PM EST),
# Eta Aquariids May 5 to 6 (pre-dawn of the new-moon day), Perseids Aug 12 to 13 (peak about 1 to 3 AM PDT).
# New moon weekends show the Saturday of each weekend at a different dark-sky park.
EVENTS = [
    ('geminids-2026', '2026-12-13', 'grba', whatsup, detail),
    ('quadrantids-2027', '2027-01-03', 'voya', whatsup, tonight),
    ('new-moon-2026-11', '2026-11-07', 'grba', calendar, detail),
    ('new-moon-2026-12', '2026-12-05', 'bibe', calendar, detail),
    ('new-moon-2027-01', '2027-01-09', 'deva', calendar, detail),
    ('new-moon-2027-02', '2027-02-06', 'brca', calendar, detail),
    ('new-moon-2027-03', '2027-03-06', 'jotr', calendar, detail),
    ('new-moon-2027-04', '2027-04-03', 'cany', calendar, detail),
    ('new-moon-2027-06', '2027-06-05', 'grca', calendar, detail),
    ('eta-aquariids-2027', '2027-05-05', 'bibe', whatsup, detail),
    ('perseids-2027', '2027-08-12', 'jotr', whatsup, detail),
]

def simctl(*args): return subprocess.run(['xcrun', 'simctl', *args], check=True, capture_output=True)

def flatten(path):
    """App Store Connect wants no alpha: flatten through a lossless-quality JPEG round trip."""
    flat = path.with_suffix('.flat.jpg')
    subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '100', str(path), '--out', str(flat)], check=True, capture_output=True)
    subprocess.run(['sips', '-s', 'format', 'png', str(flat), '--out', str(path)], check=True, capture_output=True)
    flat.unlink()

def phone(events):
    subprocess.run(['xcrun', 'simctl', 'boot', PHONE], capture_output=True)
    simctl('bootstatus', PHONE, '-b')
    simctl('install', PHONE, DERIVED + '/Build/Products/Debug-iphonesimulator/Nyx.app')
    simctl('status_bar', PHONE, 'override', '--time', '9:41', '--batteryState', 'discharging', '--batteryLevel', '100',
           '--wifiMode', 'active', '--wifiBars', '3', '--cellularMode', 'active', '--cellularBars', '4')
    try:
        for slug, date, park, card, details in events:
            for role, screen in (('card', card), ('details', details)):
                simctl('launch', '--terminate-running-process', PHONE, 'com.harrypakhale.nyx', *screen(date, park), '-nyx-reduce-motion')
                time.sleep(9)
                path = RAW / f'{slug}-{role}.png'
                simctl('io', PHONE, 'screenshot', str(path))
                flatten(path)
                print(path, flush=True)
    finally:
        simctl('status_bar', PHONE, 'clear')
        subprocess.run(['xcrun', 'simctl', 'shutdown', PHONE], capture_output=True)

def sky(events):
    runs = sorted(glob.glob(DERIVED + '/Build/Products/Nyx_iphonesimulator*.xctestrun'), key=os.path.getmtime)
    shots = ';'.join(f'{slug}-sky:landscape:-nyx-screen sky -nyx-date {date} -nyx-park {park} -nyx-reduce-motion' for slug, date, park, _, _ in events)
    env = dict(os.environ, TEST_RUNNER_NYX_SHOTS_DIR=str(RAW), TEST_RUNNER_NYX_SHOTS=shots, TEST_RUNNER_NYX_SHOTS_SETTLE='6')
    subprocess.run(['xcrun', 'simctl', 'boot', PAD], capture_output=True)
    try:
        subprocess.run(['xcodebuild', 'test-without-building', '-xctestrun', runs[-1], '-destination', f'platform=iOS Simulator,id={PAD}',
                        '-only-testing:NyxUITests/ScreenshotTests'], env=env, check=True, capture_output=True)
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', PAD], capture_output=True)
    for slug, *_ in events:
        path = RAW / f'{slug}-sky.png'
        flatten(path)
        print(path, flush=True)

if __name__ == '__main__':
    RAW.mkdir(parents=True, exist_ok=True)
    mode = sys.argv[1] if len(sys.argv) > 1 else 'all'
    only = set(sys.argv[2].split(',')) if len(sys.argv) > 2 else None
    events = [e for e in EVENTS if not only or e[0] in only]
    if mode in ('phone', 'all'): phone(events)
    if mode in ('sky', 'all'): sky(events)
