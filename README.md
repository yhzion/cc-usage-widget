# CCUsageWidget

A lightweight macOS floating panel widget that displays your **Claude Code** API usage and rate limit status in real-time.

![widget](https://github.com/user-attachments/assets/placeholder.png)

## Features

| Feature | Description |
|---------|-------------|
| **Rate Limit Gauges** | 5-hour, 7-day, and Sonnet usage rings |
| **Live Reset Countdown** | Hourglass-style timer showing time until next rate limit reset |
| **Smart Caching** | 10-minute cache to avoid hitting API rate limits |
| **Auto-Refresh** | Refreshes every 10 minutes automatically |
| **Single Instance** | Only one instance runs at a time |
| **Login Item** | Optional "Launch at Login" via right-click menu |

## Requirements

- macOS 14 (Sonoma) or later
- Claude Code authenticated via `claude auth login`
- Swift 5.9+

## Install

### From Source

```bash
git clone https://github.com/yhzion/cc-usage-widget.git
cd cc-usage-widget
swift build -c release
.build/release/cc-usage-widget
```

### Build as .app

```bash
./package-app.sh
open CCUsageWidget.app
```

> **Note:** Since the app is ad-hoc signed, you may need to bypass Gatekeeper on first launch:
> ```bash
> xattr -cr CCUsageWidget.app
> ```

## Usage

- The widget appears as a floating panel on your desktop
- Drag to reposition
- Right-click the **⋮** menu for "Launch at Login" or "Quit"

## How It Works

1. Reads your OAuth token from the macOS Keychain (`Claude Code-credentials`)
2. Calls Anthropic's internal `/api/oauth/usage` endpoint
3. Caches the response for 10 minutes to prevent rate limiting
4. Displays live countdown to your next rate limit reset

## Project Structure

```
cc-usage-widget/
├── Package.swift                          # Swift Package Manager
├── Sources/
│   └── CCUsageWidget/
│       ├── CCUsageWidgetApp.swift         # Main app
│       └── Resources/
│           └── logo.ico                   # Claude favicon
├── build.sh                               # Build script
├── package-app.sh                         # Package as .app
├── .gitignore
└── README.md
```

## Disclaimer

`/api/oauth/usage` is an **unofficial internal endpoint** used by Claude Code. It may change or stop working without notice. This tool is for personal reference only.

## License

MIT License — see [LICENSE](LICENSE) for details.
