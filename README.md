# Daily Meeting Tracker

A macOS menu bar app that shows your upcoming meetings from one or more Google Calendar accounts — current/next meeting with a live countdown in the menu bar, today's remaining meetings in a translucent dropdown, and one-click join for Google Meet links.

## Features

- Menu bar countdown ("Standup · in 1h 5m", "… · 12m left")
- Multiple Google accounts, each with a custom label shown next to meeting times
- Click a meeting to open its Google Meet link
- Open Granola from the dropdown (copies the meeting title to the clipboard)
- Launch at Login toggle in Settings
- OAuth 2.0 with PKCE (loopback redirect); refresh tokens stored in the macOS Keychain

## Setup

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project, enable the **Google Calendar API**, configure the OAuth consent screen (add yourself as a test user), and create an **OAuth client ID** of type **Desktop app**.
2. Copy the credentials template and fill it in:
   ```bash
   cp Sources/MenuBarCalendar/GoogleOAuthConfig.swift.example Sources/MenuBarCalendar/GoogleOAuthConfig.swift
   ```
3. Run it:
   ```bash
   swift run
   ```
4. Open the menu bar item → **Settings** → **+ Add Google Account**.

## Install as an app

```bash
./scripts/build-app.sh
```

Builds a release binary, packages `/Applications/MenuBar Calendar.app` and ad-hoc signs it. Then enable **Launch at Login** in Settings.

## Requirements

macOS 13+, Xcode command line tools (Swift 5.9+).
