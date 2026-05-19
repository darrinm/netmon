# Netmon (macOS)

Native macOS menubar app for monitoring network connection quality.
Independent of the Node CLI in the parent repo — own SQLite store at
`~/Library/Application Support/Netmon/store.sqlite`.

## Build

```sh
./build.sh
open build/Netmon.app
```

Outputs `build/Netmon.app`, code-signed with the first matching identity in
this order:

1. `Developer ID Application` (set via `SIGN=developer-id ./build.sh`)
2. `Apple Development` (for local dev runs)
3. Ad-hoc (no identity at all)

Requirements: Xcode 16+ command line tools, macOS 15+. Swift Package Manager
fetches GRDB.swift on first build.

## App icon

The icon is generated from an SF Symbol via Core Graphics:

```sh
swift scripts/make-icon.swift
```

Produces `Netmon/Resources/AppIcon.icns`. Already checked in; only re-run if
you want to tweak the design.

## Distribution

Three pieces, in order:

### 1. Issue a `Developer ID Application` certificate

In your Apple Developer account → Certificates → "Developer ID Application".
Download, double-click to install in your login keychain. Your local
`build.sh` will now pick it up when run with `SIGN=developer-id`.

### 2. Local DMG (for testing distribution)

```sh
SIGN=developer-id ./build.sh
scripts/make-dmg.sh
```

Produces `build/Netmon-X.Y.Z.dmg`, signed with the Developer ID cert.

### 3. Notarize

One-time keychain setup (replace with your own credentials — use an
[app-specific password](https://support.apple.com/HT204397)):

```sh
xcrun notarytool store-credentials NetmonNotary \
  --apple-id you@example.com \
  --team-id YOURTEAMID \
  --password APP_SPECIFIC_PASSWORD
```

Then for each release:

```sh
scripts/notarize.sh build/Netmon-X.Y.Z.dmg
```

That submits, waits for Apple's verdict, and staples the ticket on success.
Gatekeeper will be happy after this — users can open the DMG with no
"unidentified developer" prompt.

## CI release

`.github/workflows/release-mac.yml` builds + signs + notarizes on tag push
matching `mac-v*`. Required repo secrets:

| secret | what it is |
| --- | --- |
| `DEVID_CERT_BASE64` | `base64 -i DeveloperID.p12` of your exported cert |
| `DEVID_CERT_PASSWORD` | password you set when exporting the .p12 |
| `KEYCHAIN_PASSWORD` | any string; used to unlock the CI keychain |
| `NOTARY_APPLE_ID` | Apple ID email |
| `NOTARY_TEAM_ID` | 10-character team identifier |
| `NOTARY_PASSWORD` | app-specific password |

Tag with `git tag mac-v0.1.0 && git push --tags` to fire a release.

## Project layout

```
mac/
├── Package.swift            SPM manifest (macOS 15+, GRDB.swift)
├── build.sh                 swift build → .app → codesign
├── scripts/
│   ├── make-icon.swift      generates AppIcon.icns from an SF Symbol
│   ├── make-dmg.sh          hdiutil → signed DMG
│   └── notarize.sh          notarytool submit + stapler
└── Netmon/
    ├── App/                 NetmonApp, AppModel, Info.plist, entitlements
    ├── Engine/              MonitorEngine, OutageTracker, NativePing,
    │                        Notifications, LoginItem
    ├── Storage/             MetricStore (GRDB), Preferences
    ├── MenuBar/             MenuBarLabel, PopoverView, Sparkline
    ├── Window/              MainView, HistoryView, OutagesView, SettingsView
    ├── Models/              NetworkMetric, OutageEvent
    └── Resources/           AppIcon.icns
```

## Ping implementation

By default Netmon shells out to `/sbin/ping` for round-trip measurements.
`NativePing.swift` contains an experimental SOCK_DGRAM/IPPROTO_ICMP path
that avoids the shell-out, but it was unreliable in testing on macOS 15
(non-deterministic reply timing). To opt in, set
`MonitorEngine.Config.useNativeICMP = true`.

DNS timing uses `getaddrinfo` directly, so it includes any system resolver
caching. For pure-wire DNS measurement, a future revision can drop down
to `Network.framework` with a custom DNS endpoint.
