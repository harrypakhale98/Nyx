# Security policy

## Reporting a vulnerability

Please report a security problem privately, not in a public issue. Email [harry.pakhale98@gmail.com](mailto:harry.pakhale98@gmail.com?subject=Nyx%20security) with the subject "Nyx security". You can also use GitHub's private reporting: [Report a vulnerability](https://github.com/harrypakhale98/Nyx/security/advisories/new) on the repository's Security tab.

Include what you found, the steps to reproduce it, the device and software version (iPhone, iPad, Apple Watch or Apple Vision Pro), and the version and build number if you have them. Please do not send private journal entries or photos.

You will get a reply within 7 days. If the report is valid, the fix ships in the next release, and the reporter is credited in the release notes if they wish.

## What is in scope

- The Nyx app for iPhone and iPad, its widgets, Control Center controls and Live Activity.
- The Apple Watch app and its complications.
- The Apple Vision Pro app and its widget.
- The website at [get-nyx.com](https://get-nyx.com) and the files in `docs/`.

Out of scope: the services Nyx reads from (the National Park Service API and Open-Meteo), and Apple's platforms. Report those to their owners.

## Security posture

Nyx has no account, no server and no analytics. Your journal, saved places and photos stay on your device. The app makes requests to three HTTPS hosts only: `developer.nps.gov`, `api.open-meteo.com` and `air-quality-api.open-meteo.com`, each behind its own switch in Your privacy. The NPS API key that ships in the app is a free key for public park data; it opens no personal data. The privacy review is in [PRIVACY.md](PRIVACY.md).
