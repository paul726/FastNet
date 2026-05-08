#!/usr/bin/env python3
"""Minimal TCP listener for testing iPhone → Mac connectivity over hotspot."""

import socket
import sys
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9090

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", PORT))
srv.listen(5)

# Show all local IPs so user knows what to enter on iPhone
import subprocess
result = subprocess.run(["ifconfig"], capture_output=True, text=True)
print("=== Local IPs ===")
for line in result.stdout.split("\n"):
    if "inet " in line and "127.0.0.1" not in line:
        print(" ", line.strip())
print(f"\n=== Listening on 0.0.0.0:{PORT} ===")
print("Waiting for iPhone connection...\n")

while True:
    conn, addr = srv.accept()
    print(f"[CONNECTED] {addr[0]}:{addr[1]}")
    try:
        conn.sendall(b"HELLO FROM MAC\n")
        data = conn.recv(1024)
        if data:
            print(f"[RECEIVED]  {data.decode(errors='replace').strip()}")
        conn.close()
        print(f"[CLOSED]    {addr[0]}:{addr[1]}\n")
    except Exception as e:
        print(f"[ERROR]     {e}\n")
