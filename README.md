# FastNet

iOS SOCKS5 proxy app — route Mac traffic through iPhone's cellular network to bypass hotspot throttling.

## How It Works

Mac connects to iPhone's hotspot. Instead of traffic going directly through the throttled hotspot path, it goes through a SOCKS5 proxy on the iPhone, which forwards via the cellular network. The carrier sees it as the phone's own traffic, avoiding speed limits.

Two connection modes are available:

| Mode | Connection | Best For |
|------|-----------|----------|
| **Listen** | iproxy USB tunnel | Wired (USB), lowest latency |
| **Tunnel** | WiFi reverse tunnel | Wireless, no USB needed |

## Mode 1: Listen (USB + iproxy)

The iPhone listens for SOCKS5 connections. iproxy creates a USB tunnel from Mac to iPhone.

### Setup

1. Connect iPhone to Mac via USB cable
2. Install iproxy on Mac:
   ```
   brew install libusbmuxd
   ```
3. Start USB tunnel:
   ```
   iproxy 1082 1082
   ```
4. Open FastNet app on iPhone, select **Listen** mode, port `1082`, tap **Start**
5. On Mac, set SOCKS proxy:
   - System Settings → Network → Wi-Fi → Details → Proxies
   - Enable **SOCKS proxy**: `127.0.0.1`, port `1082`

### Traffic Flow

```
Mac app → 127.0.0.1:1082 → iproxy (USB) → iPhone:1082 → cellular → internet
```

## Mode 2: Tunnel (WiFi)

The iPhone connects outbound to a relay running on the Mac. No USB cable needed.

### Setup

1. Connect Mac to iPhone's WiFi hotspot
2. Note the Mac's IP address (e.g. `192.0.0.2`)
3. On Mac, start the relay:
   ```
   python3 relay.py 1080 1083
   ```
   - `1080` = SOCKS5 port (Mac proxy points here)
   - `1083` = tunnel port (iPhone connects here)
4. Open FastNet app on iPhone, select **Tunnel** mode:
   - Mac IP: `192.0.0.2` (your Mac's IP)
   - Tunnel Port: `1083`
   - Tap **Start**
5. On Mac, set SOCKS proxy:
   - System Settings → Network → Wi-Fi → Details → Proxies
   - Enable **SOCKS proxy**: `127.0.0.1`, port `1080`

### Traffic Flow

```
Mac app → 127.0.0.1:1080 → relay.py ←WiFi← iPhone:tunnel → cellular → internet
```

## Running Both Modes Together

Use different SOCKS ports to avoid conflicts:

| Mode | SOCKS Port | Command |
|------|-----------|---------|
| Listen (USB) | 1082 | `iproxy 1082 1082` |
| Tunnel (WiFi) | 1080 | `python3 relay.py 1080 1083` |

Switch your Mac's SOCKS proxy between `127.0.0.1:1082` and `127.0.0.1:1080` to choose which mode to use.

## App Interface

- **Status indicator**: green = running, gray = stopped
- **Mode picker**: switch between Listen and Tunnel
- **Statistics**: active connections, total connections, bytes transferred, pool size (tunnel mode)
- **Logging toggle**: enable to see detailed SOCKS5 handshake and relay logs (off by default for performance)

## relay.py Reference

```
python3 relay.py [socks_port] [tunnel_port]
```

| Argument | Default | Description |
|----------|---------|-------------|
| socks_port | 1082 | Mac SOCKS proxy port |
| tunnel_port | 1083 | iPhone tunnel connection port |

The relay prints live stats every 5 seconds:
```
FastNet Relay
  SOCKS5:  127.0.0.1:1080  (set Mac proxy here)
  Tunnel:  0.0.0.0:1083  (iPhone connects here)
  Waiting for iPhone...

  pool=8  active=3  total=42  traffic=156.2 MB
```

## Troubleshooting

**iproxy: command not found**
```
brew install libusbmuxd
```

**Tunnel mode not connecting**
- Verify relay.py is running on Mac
- Check Mac IP is correct in the app (run `ifconfig` on Mac)
- Make sure iproxy is not using the same SOCKS port as relay.py

**Slow speed in USB mode (~300Mbps cap)**
- This is a USB 2.0 (Lightning) hardware limit, not a software issue

**App shows no connections**
- Confirm Mac SOCKS proxy is set to the correct IP and port
- Try `curl --proxy socks5://127.0.0.1:1080 https://httpbin.org/ip` to test
