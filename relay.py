#!/usr/bin/env python3
"""
FastNet Relay - runs on Mac, pairs SOCKS5 clients with iPhone tunnel connections.

Usage: python3 relay.py [socks_port] [tunnel_port]
Default: python3 relay.py 1082 1083

Mac SOCKS proxy → 127.0.0.1:1082
iPhone connects → 0.0.0.0:1083
"""

import socket
import threading
import sys
import queue
import time

BUFFER_SIZE = 262144
SOCK_BUF = 524288


def _setup(conn):
    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, SOCK_BUF)
    conn.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, SOCK_BUF)


class Relay:
    def __init__(self, socks_port=1082, tunnel_port=1083):
        self.socks_port = socks_port
        self.tunnel_port = tunnel_port
        self.pool = queue.Queue()
        self.lock = threading.Lock()
        self.active = 0
        self.total = 0
        self.bytes = 0

    def start(self):
        threading.Thread(target=self._accept_tunnels, daemon=True).start()
        threading.Thread(target=self._accept_socks, daemon=True).start()

        print(f"FastNet Relay")
        print(f"  SOCKS5:  127.0.0.1:{self.socks_port}  (set Mac proxy here)")
        print(f"  Tunnel:  0.0.0.0:{self.tunnel_port}  (iPhone connects here)")
        print(f"  Waiting for iPhone...")
        print()

        try:
            while True:
                time.sleep(5)
                with self.lock:
                    print(
                        f"  pool={self.pool.qsize()}  "
                        f"active={self.active}  "
                        f"total={self.total}  "
                        f"traffic={self._fmt(self.bytes)}"
                    )
        except KeyboardInterrupt:
            print("\nStopped.")

    def _accept_tunnels(self, backlog=128):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", self.tunnel_port))
        srv.listen(backlog)
        while True:
            conn, _ = srv.accept()
            _setup(conn)
            self.pool.put(conn)

    def _accept_socks(self, backlog=128):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", self.socks_port))
        srv.listen(backlog)
        while True:
            conn, _ = srv.accept()
            _setup(conn)
            threading.Thread(target=self._pair, args=(conn,), daemon=True).start()

    def _pair(self, client):
        try:
            tunnel = self.pool.get(timeout=10)
        except queue.Empty:
            client.close()
            return

        try:
            tunnel.getpeername()
        except OSError:
            tunnel.close()
            client.close()
            return

        with self.lock:
            self.active += 1
            self.total += 1

        t1 = threading.Thread(target=self._relay, args=(client, tunnel), daemon=True)
        t2 = threading.Thread(target=self._relay, args=(tunnel, client), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()

        for s in (client, tunnel):
            try:
                s.close()
            except OSError:
                pass

        with self.lock:
            self.active -= 1

    def _relay(self, src, dst):
        local_bytes = 0
        try:
            while True:
                data = src.recv(BUFFER_SIZE)
                if not data:
                    break
                dst.sendall(data)
                local_bytes += len(data)
        except (ConnectionError, OSError):
            pass
        finally:
            with self.lock:
                self.bytes += local_bytes
            try:
                dst.shutdown(socket.SHUT_WR)
            except OSError:
                pass

    @staticmethod
    def _fmt(b):
        for u in ("B", "KB", "MB", "GB"):
            if b < 1024:
                return f"{b:.1f} {u}"
            b /= 1024
        return f"{b:.1f} TB"


if __name__ == "__main__":
    sp = int(sys.argv[1]) if len(sys.argv) > 1 else 1082
    tp = int(sys.argv[2]) if len(sys.argv) > 2 else 1083
    Relay(sp, tp).start()
