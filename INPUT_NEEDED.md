# Input needed (owner tasks)

## 1. Choose a signing team
- **What:** In Xcode, open `Nyx.xcodeproj` → target `Nyx` → Signing & Capabilities → Team. Repeat for `NyxWidgets`. Then copy the team ID into `DEVELOPMENT_TEAM` in `project.yml` so regenerating keeps it.
- **Why only you:** it needs your Apple ID / Apple Developer account.
- **When:** before running on a real iPhone or archiving. Simulator builds work without it.
- **Note:** if `group.com.harrypakhale.nyx` or `com.harrypakhale.nyx` is unavailable on your account, change the prefix in `project.yml` and both files in `Config/`.
