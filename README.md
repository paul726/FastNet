# FastNet

iOS SOCKS5 proxy app — route Mac traffic through iPhone's cellular network to bypass hotspot throttling.

## How It Works

Mac connects to iPhone's hotspot. Instead of traffic going directly through the throttled hotspot path, it goes through a SOCKS5 proxy on the iPhone, which forwards via the cellular network. The carrier sees it as the phone's own traffic, avoiding speed limits.

Uses USB via iproxy to tunnel SOCKS5 connections from Mac to iPhone.

## Setup

1. Connect iPhone to Mac via USB cable
2. Install iproxy on Mac:
   ```
   brew install libusbmuxd
   ```
3. Start USB tunnel:
   ```
   iproxy 1082 1082
   ```
4. Open FastNet app on iPhone, set port to `1082`, tap **Start**
5. On Mac, set SOCKS proxy:
   - System Settings → Network → Wi-Fi → Details → Proxies
   - Enable **SOCKS proxy**: `127.0.0.1`, port `1082`

## Traffic Flow

```
Mac app → 127.0.0.1:1082 → iproxy (USB) → iPhone:1082 → cellular → internet
```

## App Interface

- **Status indicator**: green = running, gray = stopped
- **Port**: configurable listen port (default 1082)
- **Statistics**: active connections, total connections, bytes transferred
- **Logging toggle**: enable to see detailed SOCKS5 handshake and relay logs (off by default for performance)

## Troubleshooting

**iproxy: command not found**
```
brew install libusbmuxd
```

**Slow speed (~300Mbps cap)**
- This is a USB 2.0 (Lightning) hardware limit, not a software issue

**App shows no connections**
- Confirm Mac SOCKS proxy is set to `127.0.0.1:1082`
- Try `curl --proxy socks5://127.0.0.1:1082 https://httpbin.org/ip` to test
