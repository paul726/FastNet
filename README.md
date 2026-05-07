# FastNet

iOS SOCKS5 proxy app + Mac companion — route Mac traffic through iPhone's cellular network to bypass hotspot throttling.

## How It Works

Mac connects to iPhone's hotspot. Instead of traffic going directly through the throttled hotspot path, it goes through a SOCKS5 proxy on the iPhone, which forwards via the cellular network. The carrier sees it as the phone's own traffic, avoiding speed limits.

## Components

| App | Platform | Role |
|-----|----------|------|
| **FastNet** | iOS | SOCKS5 proxy server on iPhone |
| **FastNet Connect** | macOS | USB tunnel + one-click proxy setup |

## Setup

1. Connect iPhone to Mac via USB cable
2. Open **FastNet** on iPhone, set port to `1082`, tap **Start**
3. Open **FastNet Connect** on Mac — it auto-detects the iPhone
4. Click **Start** to open the USB tunnel
5. Toggle **System SOCKS Proxy** to route all Mac traffic through iPhone

That's it. No terminal commands, no iproxy, no manual proxy configuration.

## Traffic Flow

```
Mac app → 127.0.0.1:1082 → FastNet Connect (USB) → iPhone:1082 → cellular → internet
```

## FastNet (iOS)

- **Status indicator**: green = running, gray = stopped
- **Port**: configurable listen port (default 1082)
- **Statistics**: active connections, total connections, bytes transferred
- **Logging toggle**: enable to see detailed SOCKS5 handshake and relay logs

## FastNet Connect (macOS)

- **Menu bar app**: lives in the system tray, no dock icon
- **Auto-detect**: finds iPhone automatically via USB
- **One-click proxy**: toggle system SOCKS proxy on/off
- **Statistics**: active connections, total connections, bytes transferred

## Manual Setup (without FastNet Connect)

If you prefer command-line tools:

1. Install iproxy: `brew install libusbmuxd`
2. Start USB tunnel: `iproxy 1082 1082`
3. Set Mac SOCKS proxy: System Settings → Network → Wi-Fi → Details → Proxies → SOCKS proxy: `127.0.0.1:1082`

## Troubleshooting

**FastNet Connect shows "No device"**
- Make sure iPhone is connected via USB and unlocked
- Trust the Mac on iPhone if prompted

**Slow speed (~300Mbps cap)**
- This is a USB 2.0 (Lightning) hardware limit, not a software issue

**App shows no connections**
- Confirm Mac SOCKS proxy is set to `127.0.0.1:1082`
- Try `curl --proxy socks5://127.0.0.1:1082 https://httpbin.org/ip` to test
