<h1 align="center">NotchFree</h1>

<p align="center">
  <strong>The MacBook notch, freed.</strong><br>
  A free, open-source Dynamic Island for macOS with a built-in planner, focus toolkit,<br>
  AI-agent bridge, and zero-install phone drop.
</p>

<p align="center">
  <a href="https://github.com/anurag3407/notchfree/stargazers">
    <img src="https://img.shields.io/github/stars/anurag3407/notchfree?style=social" alt="GitHub stars"/>
  </a>
  <a href="https://github.com/anurag3407/notchfree/network/members">
    <img src="https://img.shields.io/github/forks/anurag3407/notchfree?style=social" alt="GitHub forks"/>
  </a>
  <a href="https://github.com/anurag3407/notchfree/actions/workflows/ci.yml">
    <img src="https://github.com/anurag3407/notchfree/actions/workflows/ci.yml/badge.svg?branch=dev" alt="CI"/>
  </a>
  <img src="https://img.shields.io/badge/macOS-14.6%2B-black?logo=apple" alt="macOS 14.6+"/>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="GPL-3.0"/>
  </a>
</p>

NotchFree turns the MacBook notch into a focused command surface: hover to expand it for media controls, system stats, timers, the Shelf, and more. On top of the Atoll foundation it adds **NotchOwl**, a local-first day planner, a **focus toolkit**, a **local MCP server for AI agents**, and **Phone Drop** — two-way file and text transfer with any Android or iPhone on the same Wi-Fi, no app install required.

Everything is native SwiftUI, runs locally, and is free under the GPL.

---

## What's new in NotchFree

| Feature | What it does |
| --- | --- |
| **NotchOwl planner** | Natural-language tasks, voice capture, day planning, wrap-up, week board, daily notepad, and insights — all inside the notch. |
| **Focus toolkit** | Synthesized ambient sounds, distraction nudges, focus shortcuts, and focus-session analytics. |
| **AI-agent bridge** | A local Model Context Protocol server that lets Claude Code, Claude Desktop, and Cursor read and manage your tasks and notes. |
| **Phone Drop** | Scan a QR code and send photos/files/text from Android or iPhone to your Mac Shelf and clipboard — and pull Mac files back to the phone. |
| **LocalSend receiver** | Android's Share → LocalSend can discover the Mac and drop files after an approval prompt in the notch, with remembered trusted devices. |
| **Apple Reminders sync** | Two-way sync with a Reminders list, plus Apple Shortcuts/App Intents for adding and completing tasks. |

All of Atoll's original features remain: media controls, Live Activities, lock-screen widgets, system stats, timers, clipboard history, color picker, calendar previews, the Shelf, terminal, LLM usage monitoring, gestures, and deep customization.

---

## NotchOwl planner

Open the notch and choose the **Planner** tab. It has six tabs: **Today**, **Week**, **Notepad**, **Focus+**, **Insights**, and **Connect**.

### Today
- **Add tasks in plain language.** Examples:
  - `Call mom tomorrow at 5pm !high #family`
  - `Standup every weekday at 9:30am`
  - `Review PR in 2h !p2`
  - `Dentist friday at 10am`
- Supported tokens: `!high`/`!p1`, `!medium`/`!med`/`!p2`, `!low`/`!p3`, `#project`, `today`, `tomorrow`/`tmr`, weekday names, `at 5pm`, `at 17:30`, `in 2h`, `in 30m`, and recurrence phrases such as `daily`, `weekdays`, `weekly`, and `monthly`.
- **Dictate a task** with the microphone button. On-device speech recognition is used when the Mac supports it.
- Tasks carry priority, project, reminder time, and recurrence, and can be reordered, moved, renamed, or deleted.
- Sort by manual order, priority, reminder time, deadline, project, or name.

### Plan
- **Plan** schedules today's untimed open tasks around your real calendar events, fitting them into free windows by priority.
- Turn on **Order only** to rank tasks without assigning times.
- **Apply** writes the plan's reminder times; **Undo** restores the previous snapshot.

### Wrap
- Review completed vs. remaining tasks.
- Write a one-line reflection into the daily notepad.
- Move unfinished work to **Tomorrow** or back to the **Inbox**.

### Week
- An Inbox column plus the next seven days.
- Move tasks between days, back to Inbox, or delete them from the context menu.

### Notepad
- A per-day scratchpad that saves as you type.
- **Turn Last Line into Task** (`⌘↩`) parses the last non-empty line with the same natural-language rules.

### Focus+
- **Ambient sounds** — brown noise, pink noise, rain, and ocean are synthesized live with AVAudioEngine, with no bundled audio files. Adjust the volume in the same panel.
- **Focus monitoring** — pick distracting apps (Discord, Slack, Messages, and Safari by default) and get a "Back to Focus" nudge when one takes over during a focus session.
- **Focus shortcuts** — run any Apple Shortcut when focus starts and ends.

### Insights
- Focus minutes today, current streak, and completed-task count.
- **Best focus hours** derived from recorded focus sessions.

### Connect
- **Apple Reminders** — two-way sync with a chosen list. Optionally only set due dates when a task has a time, so unscheduled tasks don't clutter the iPhone Today view.
- **Local MCP server** — start it and configure Claude Desktop, Claude Code, or Cursor in one click.
- **Phone Drop** — start the server, show the QR code, and watch recent drops.
- **Time to leave** — an Apple Maps driving-ETA toggle for calendar events with an address.
- **Backup** — export tasks, daily notes, and focus sessions as JSON.

### Shortcuts and App Intents
NotchFree exposes App Intents and App Shortcuts for:
- **Add Task** — add a task with natural language.
- **Complete Task** — complete the first open task matching a name.
- **What's on Today** — list today's open tasks.

---

## Phone Drop (Android & iPhone → Mac, no app)

Phone Drop runs a small, token-protected web server on your local network. Any phone browser can use it with no app installed; if you already use the LocalSend app, its share target is supported too.

1. In the notch, open **Planner → Connect**.
2. Under **Drop from Android & iPhone (Wi-Fi)**, press **Start**.
3. Scan the QR code with your phone, or open the displayed URL.
4. On the phone page you can:
   - **Send files or photos** → they land on the Mac **Shelf**.
   - **Send text or links** → they go straight to the Mac **clipboard**.
   - **Pull the Mac clipboard** → copy it on the phone.
   - **Download Shelf files** → pull files from the Mac to the phone.
5. For Android's native share sheet, choose **LocalSend** as the share target and select the Mac. The notch shows the incoming transfer; approve it with **Accept**, **Trust**, or **Decline** in **Planner → Connect**. Trusted devices are remembered and can be revoked in **Settings → Planner & AI**.

Notes:
- The phone and Mac must be on the same Wi-Fi/LAN.
- Each session uses a random token; press **New Token** to invalidate the old QR code.
- Transfers are direct over the LAN. Nothing is uploaded to a cloud service.
- Phone Drop listens on port `38495`; LocalSend discovery uses port `53317`; the MCP server uses `127.0.0.1:38492`.

---

## AI agents: local MCP server

NotchFree can expose your planner to local AI tools through the Model Context Protocol over HTTP, bound to `127.0.0.1` only.

- **Start it** in **Planner → Connect** or **Settings → Planner & AI**.
- **Configure a client** with one click for Claude Desktop, Claude Code, or Cursor. NotchFree writes or merges a `notchfree` entry into that client's MCP config.
- **Endpoint:** `http://127.0.0.1:38492/mcp`
- **Tools exposed:**
  - `list_tasks` — list today's tasks.
  - `add_task` — add a task using natural language.
  - `complete_task` — toggle a task by UUID.
  - `get_daily_note` — read today's notepad.
  - `append_daily_note` — append a line to today's notepad.
  - `get_insights` — focus minutes, streak, and completed-task totals.

The server speaks JSON-RPC 2.0 (`initialize`, `tools/list`, `tools/call`) and never leaves localhost.

---

## Core notch features

- **Media controls** for Apple Music, Spotify, Cider, TIDAL, YouTube Music, and more, with artwork and inline previews.
- **Live Activities** for media playback, Focus, screen recording, privacy indicators, downloads, battery/charging, and connectivity changes.
- **Lock-screen widgets** for media, timers, charging, Bluetooth devices, and weather.
- **System insight** for CPU, GPU, memory, network, disk, battery, and charging power.
- **Productivity tools** including timers, clipboard history, color picker, calendar previews, notes, a file Shelf, and a terminal tab.
- **LLM usage monitoring** for supported providers.
- **Customization** for layouts, animations, hover behavior, gestures, per-app volume, keep-awake, and global shortcut remapping.
- **Shelf** for dragging files and quick actions, with drag-out, Quick Look, and sharing.

---

## Requirements

- macOS **14.6 or later** (optimized for macOS 15 and newer).
- A MacBook with a notch (14/16-inch MacBook Pro across Apple silicon generations).
- **Xcode 16.3 or newer** to build from source; the CI builds with the latest stable Xcode on macOS 15 and macOS 26 runners.
- Permissions, granted as needed:
  - Accessibility
  - Screen Recording
  - Camera
  - Calendar
  - Reminders
  - Speech Recognition (for dictated tasks)
  - Apple Music / Media & Apple Music
  - Audio capture (waveform and per-app volume)
  - Local Network, if macOS prompts for it (Phone Drop and LocalSend)

---

## Installation

### Option A — CI build artifact

Every green CI run produces an app bundle:

1. Open the [CI workflow](https://github.com/anurag3407/notchfree/actions/workflows/ci.yml).
2. Pick the latest successful run on `dev`.
3. Download the `notchfree-app-macos-15` or `notchfree-app-macos-26` artifact (artifacts are kept for 7 days).
4. Unzip `NotchFree.app.zip` and drag **NotchFree.app** into `/Applications`.
5. The artifact is ad-hoc signed and not notarized, so on first launch use **right-click → Open** (or allow it in **System Settings → Privacy & Security**).

The CI workflow can also be started manually from the Actions tab (`workflow_dispatch`).

### Option B — Build from source

```bash
git clone https://github.com/anurag3407/notchfree.git
cd notchfree
open DynamicIsland.xcodeproj
```

In Xcode:

1. Select the **DynamicIsland** scheme.
2. Choose your Mac as the run destination.
3. Under **Signing & Capabilities**, select your development team (or **Sign to Run Locally**).
4. Press **Run**. The built product is named **NotchFree.app**.

### Validation

The repository's CI validations are plain Python and can be run locally:

```bash
python3 -m unittest tests.test_privacy_configuration tests.test_timer_lifecycle
```

`NotchFreeKit` also contains a Swift Testing suite in `NotchFreeKit/Tests/NotchFreeCoreTests`, covering the natural-language parser, day planner, planner store, notepad, insights, calendar payload decoding, MCP JSON-RPC, backups, Phone Drop, and the LocalSend receiver. Open `NotchFreeKit/Package.swift` in Xcode 16.3+ to run it.

---

## First run

1. Launch NotchFree. It lives in the menu bar (mountain icon) and around the notch.
2. Hover or click the notch to expand it.
3. Open **Planner** to create your first task.
4. Open **Settings → Planner & AI** to configure:
   - Reminders list name and due-date behavior
   - Focus start/end shortcuts
   - Distracting apps
   - Calendly and Cal.com credentials (stored in the macOS Keychain)
   - Time-to-leave estimation
   - The local MCP server
   - Trusted LocalSend devices
5. Grant permissions when macOS asks; after granting Accessibility or Screen Recording, quit and relaunch the app.

### Quick recipes

- **Add a task without leaving the keyboard:** open the notch → Planner → type `Ship release friday at 4pm !high #work` → Return.
- **Dictate:** press the microphone, speak, then press it again to submit the transcript.
- **Plan the day:** Planner → **Plan** → review slots → **Apply**.
- **End the day:** Planner → **Wrap** → write a reflection → move leftovers to Tomorrow or Inbox.
- **Send a photo from your phone:** Planner → Connect → Start → scan QR → choose the photo.
- **Let Claude manage your tasks:** Planner → Connect → Start MCP → **Connect Claude Desktop** (or Claude Code/Cursor).

---

## Settings

NotchFree keeps Atoll's settings and adds a **Planner & AI** section:

- **Planner & Reminders** — Reminders list name; due dates only when a task has a time.
- **Focus Automation & Nudges** — focus start/end Shortcuts and the distracting-app list.
- **Calendly, Cal.com & Time to Leave** — API credentials saved to the Keychain and the Apple Maps ETA toggle.
- **AI Agents** — start/stop the local MCP server.
- **Trusted Android / LocalSend Devices** — review and revoke trusted devices.

---

## Privacy

- Planner data — tasks, notes, focus sessions, and trusted-device fingerprints — is stored locally on the Mac.
- Phone Drop and LocalSend traffic stays on the local network. The phone web page is protected by a per-session token.
- The MCP server binds to `127.0.0.1` and is not reachable from other machines.
- Calendly and Cal.com credentials are stored in the macOS Keychain.
- NotchFree includes no account system and no analytics/telemetry SDK.
- Some inherited Atoll features contact third-party services you enable, such as media players, weather, lyrics, pricing data, and Sparkle update checks.

---

## Troubleshooting

- **Metrics are empty** — enable categories in **Settings → Stats**.
- **Phone page won't load** — confirm both devices are on the same Wi-Fi, the server is running, and the macOS firewall allows NotchFree. Try **New Token** and rescan.
- **Android can't find the Mac in LocalSend** — make sure NotchFree is running and Phone Drop has started LocalSend discovery; check that port `53317` is not blocked.
- **Incoming LocalSend transfer shows no prompt** — open the notch's Planner → Connect view, where the Accept/Trust/Decline prompt appears, or check **Settings → Planner & AI** for the trusted-device list.
- **Dictation doesn't start** — grant Speech Recognition and Microphone access, then relaunch.
- **MCP client can't connect** — start the server, confirm `127.0.0.1:38492` is listening, and re-run the one-click client configuration.
- **Media isn't responding** — verify a player is active and Music permission is granted.
- **Reminders aren't syncing** — grant full Reminders access and press **Sync Now** in Planner → Connect.

---

## Fork notes

NotchFree is a fork of [Atoll](https://github.com/Ebullioscopic/Atoll), which is itself built on [Boring.Notch](https://github.com/TheBoredTeam/boring.notch).

A few inherited details are intentional but worth knowing:

- The Xcode target, scheme, and bundle identifiers still use the upstream `DynamicIsland` / `com.Ebullioscopic.Atoll` names for compatibility.
- The Sparkle update feed still points at the upstream Atoll appcast. If you do not want an update to replace NotchFree with upstream Atoll, turn off automatic update checks in Settings until this fork ships its own feed and signing key.
- The upstream release workflow is still Atoll-specific; use the CI artifacts or build locally for NotchFree.

To pull in upstream changes:

```bash
git remote add upstream https://github.com/Ebullioscopic/Atoll.git   # once
git fetch upstream
git merge upstream/main
```

---

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

Good places to start:

- `NotchFreeKit/Sources/NotchFreeCore` — planner models, stores, sync, MCP, Phone Drop, LocalSend receiver.
- `NotchFreeKit/Sources/NotchFreeUI` — Planner and Settings UI.
- `DynamicIsland/components/Shelf/Services` — Shelf, LocalSend, and Phone Drop integration.
- `NotchFreeKit/Tests/NotchFreeCoreTests` — core behavior tests.

Please run the validation commands above and include a short description of the user-visible change in your pull request.

---

## License

NotchFree is released under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full terms.

Because it is derived from Atoll and Boring.Notch, their copyright notices and GPL obligations apply. See [NOTICE](NOTICE), [TRADEMARKS](TRADEMARKS), and [COPYRIGHT_ASSETS](COPYRIGHT_ASSETS).

---

## Acknowledgments

NotchFree stands on the work of the Atoll and Boring.Notch communities, plus the open-source projects below:

- [**Atoll**](https://github.com/Ebullioscopic/Atoll) — the upstream macOS Dynamic Island app this fork is based on. NotchFree inherits its media, Live Activity, lock-screen, stats, and customization foundation.
- [**Boring.Notch**](https://github.com/TheBoredTeam/boring.notch) — foundational codebase for media player integration, AirDrop surface, file dock, and calendar event display.
- [**Alcove**](https://tryalcove.com) — inspiration for the Minimalistic Mode interface and lock-screen widget concepts.
- [**Stats**](https://github.com/exelban/stats) — system metrics architecture, SMC temperature access, IOReport frequency sampling, and per-core CPU tracking.
- [**Open Meteo**](https://open-meteo.com) — weather APIs for lock-screen widgets.
- [**SkyLightWindow**](https://github.com/Lakr233/SkyLightWindow) — lock-screen widget window rendering.
- [**rtaudio**](https://github.com/ZephyrCodesStuff/rtaudio) — live music visualizer.
- [**SwiftTerm**](https://github.com/migueldeicaza/SwiftTerm) — terminal tab.
- [**DynamicNotch**](https://github.com/jackson-storm/DynamicNotch) — battery HUDs.
- **Wick** — iOS-style timer design for the lock-screen widget.
- [**OpenUsage**](https://github.com/robinebers/openusage) — LLM usage tracking.
- [**OpenRouter**](https://openrouter.ai) — automated model pricing data.

Thank you to [TheBoredTeam](https://github.com/TheBoredTeam) and the Atoll contributors for making this foundation possible.

---

## Star history

[![Star History Chart](https://api.star-history.com/svg?repos=anurag3407/notchfree&type=timeline&legend=top-left)](https://www.star-history.com/#anurag3407/notchfree&type=timeline&legend=top-left)
