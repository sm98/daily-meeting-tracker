# Daily Meeting Tracker

A lightweight macOS menu bar app that keeps your next meeting one glance away. It pulls events from one or more Google Calendar accounts, shows a live countdown in the menu bar, and lets you jump into a Google Meet call with a single click.

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey) ![swift](https://img.shields.io/badge/Swift-5.9-orange) ![license](https://img.shields.io/badge/license-MIT-blue)

## Features

- **Live countdown in the menu bar** — e.g. `Design sync · in 1h 5m` or `Standup · 12m left`
- **Translucent dropdown** with three sections: next/current meeting, the rest of today, and actions
- **Multiple Google accounts** — add or remove accounts at any time from Settings
- **Custom labels per account** (e.g. "Work", "Personal") shown next to meeting times instead of email addresses
- **One-click join** — click a meeting to open its Google Meet link
- **Open Granola** shortcut that copies the current meeting title to your clipboard
- **Launch at Login** toggle
- **Private by design** — OAuth 2.0 with PKCE, read-only calendar scope, refresh tokens stored in the macOS Keychain; no server, no analytics

## Requirements

- macOS 13 or later
- Xcode command line tools (Swift 5.9+): `xcode-select --install`
- A Google account and a free Google Cloud project (for your own OAuth credentials)

## Setup

### 1. Create Google OAuth credentials

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and create a project.
2. Enable the **Google Calendar API**.
3. Under **APIs & Services → OAuth consent screen**, choose **External**, fill in the basics, and add the Google accounts you'll use as **Test users**.
4. Under **APIs & Services → Credentials**, create an **OAuth client ID** with application type **Desktop app**.
5. Copy the **Client ID** and **Client Secret**.

> The app requests the read-only `calendar.readonly` scope (plus `openid email` to identify the account). While your consent screen is in "Testing" mode, only listed test users can sign in — that's fine for personal use.

### 2. Configure and run

```bash
git clone https://github.com/sm98/daily-meeting-tracker.git
cd daily-meeting-tracker
cp Sources/MenuBarCalendar/GoogleOAuthConfig.swift.example Sources/MenuBarCalendar/GoogleOAuthConfig.swift
# edit GoogleOAuthConfig.swift and paste in your Client ID / Secret
swift run
```

`GoogleOAuthConfig.swift` is gitignored so your credentials never get committed.

### 3. Connect your calendars

Click the menu bar item → **Settings** → **+ Add Google Account**. Your browser opens Google's consent screen; approve and you're done. Repeat for each account, and press Return in a label field to rename it.

## Install as a regular app

```bash
./scripts/build-app.sh
```

This builds a release binary, packages it as `/Applications/MenuBar Calendar.app`, and ad-hoc signs it. Launch it from Spotlight ("MenuBar Calendar"), then enable **Launch at Login** in Settings.

Because the app is only ad-hoc signed, rebuilding changes its code signature and macOS may ask you to re-approve Keychain access or Login Items afterward.

## How it works

| Piece | File |
| --- | --- |
| Status item, floating panel, timers | `AppDelegate.swift`, `FloatingPanel.swift` |
| Dropdown UI (translucent vibrancy) | `ContentView.swift`, `VisualEffectView.swift` |
| OAuth 2.0 + PKCE, multi-account tokens | `GoogleAuthManager.swift`, `LoopbackServer.swift` |
| Keychain storage | `KeychainStore.swift` |
| Google Calendar API client | `CalendarService.swift` |
| Event model and merging across accounts | `Models/Event.swift` |
| Settings window (accounts, labels, login item) | `SettingsView.swift` |

Sign-in uses Google's loopback redirect flow: the app briefly listens on `http://127.0.0.1:8991/` to receive the authorization code. Events refresh every 5 minutes and on account changes; the countdown ticks every 30 seconds.

## Roadmap

- Refresh immediately on wake from sleep
- Incremental sync with Calendar `syncToken`
- Pull events from all of an account's calendars (currently the primary calendar only)
- Menu bar icon and truncation for long titles
- Proper code signing and notarization

## Contributing

Issues and pull requests are welcome. Please never commit real OAuth credentials.

## License

[MIT](LICENSE) © 2026 Sanoop Menon
