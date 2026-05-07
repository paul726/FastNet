import Foundation

class PortForwarder {
    fileprivate static let bufferSize = 262_144

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.fastnet.forwarder")
    private var relays: [UUID: TunnelRelay] = [:]
    private let relayLock = NSLock()

    let deviceID: Int
    let remotePort: UInt16

    private var _totalConnections = 0
    private var _totalBytes: Int64 = 0
    private let statsLock = NSLock()

    var activeConnections: Int {
        relayLock.lock()
        let c = relays.count
        relayLock.unlock()
        return c
    }

    var totalConnections: Int {
        statsLock.lock()
        let v = _totalConnections
        statsLock.unlock()
        return v
    }

    var totalBytes: Int64 {
        statsLock.lock()
        let v = _totalBytes
        statsLock.unlock()
        return v
    }

    init(deviceID: Int, remotePort: UInt16) {
        self.deviceID = deviceID
        self.remotePort = remotePort
        signal(SIGPIPE, SIG_IGN)
    }

    func start(port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        var opt: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = in_addr_t(INADDR_LOOPBACK).bigEndian

        let bindOK = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        } == 0

        guard bindOK, listen(fd, 128) == 0 else {
            Darwin.close(fd)
            return false
        }

        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let clientFD = accept(self.listenFD, nil, nil)
            if clientFD >= 0 { self.handleClient(clientFD) }
        }
        source.setCancelHandler { Darwin.close(fd) }
        acceptSource = source
        source.resume()
        return true
    }

    private func handleClient(_ clientFD: Int32) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { Darwin.close(clientFD); return }

            let deviceFD = USBMux.shared.connect(deviceID: self.deviceID, port: self.remotePort)
            guard deviceFD >= 0 else {
                Darwin.close(clientFD)
                return
            }

            configureTunnel(clientFD)
            configureTunnel(deviceFD)

            let id = UUID()
            self.statsLock.lock()
            self._totalConnections += 1
            self.statsLock.unlock()

            let relay = TunnelRelay(fd1: clientFD, fd2: deviceFD, onBytes: { [weak self] n in
                self?.statsLock.lock()
                self?._totalBytes += Int64(n)
                self?.statsLock.unlock()
            }, onClose: { [weak self] in
                self?.relayLock.lock()
                self?.relays.removeValue(forKey: id)
                self?.relayLock.unlock()
            })

            self.relayLock.lock()
            self.relays[id] = relay
            self.relayLock.unlock()

            relay.run()
        }
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1

        relayLock.lock()
        let current = Array(relays.values)
        relays.removeAll()
        relayLock.unlock()

        for r in current { r.interrupt() }

        statsLock.lock()
        _totalConnections = 0
        _totalBytes = 0
        statsLock.unlock()
    }
}

private func configureTunnel(_ fd: Int32) {
    var opt: Int32 = 1
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &opt, socklen_t(MemoryLayout<Int32>.size))
    var bufSize: Int32 = 524_288
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))
}

private class TunnelRelay {
    private let fd1: Int32
    private let fd2: Int32
    private let onBytes: (Int) -> Void
    private let onClose: () -> Void

    init(fd1: Int32, fd2: Int32, onBytes: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
        self.fd1 = fd1
        self.fd2 = fd2
        self.onBytes = onBytes
        self.onClose = onClose
    }

    func run() {
        let buf = UnsafeMutableRawPointer.allocate(byteCount: PortForwarder.bufferSize, alignment: 1)
        defer {
            buf.deallocate()
            Darwin.close(fd1)
            Darwin.close(fd2)
            onClose()
        }

        var fds = [
            pollfd(fd: fd1, events: Int16(POLLIN), revents: 0),
            pollfd(fd: fd2, events: Int16(POLLIN), revents: 0)
        ]

        while true {
            fds[0].revents = 0
            fds[1].revents = 0

            let ready = poll(&fds, 2, -1)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }

            if fds[0].revents & Int16(POLLIN) != 0 {
                if !forward(from: fd1, to: fd2, buf: buf) { break }
            }
            if fds[1].revents & Int16(POLLIN) != 0 {
                if !forward(from: fd2, to: fd1, buf: buf) { break }
            }
            if fds[0].revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { break }
            if fds[1].revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { break }
        }
    }

    private func forward(from src: Int32, to dst: Int32, buf: UnsafeMutableRawPointer) -> Bool {
        let n = Darwin.read(src, buf, PortForwarder.bufferSize)
        if n <= 0 { return false }
        onBytes(n)
        var written = 0
        while written < n {
            let w = Darwin.write(dst, buf.advanced(by: written), n - written)
            if w <= 0 {
                if errno == EINTR { continue }
                return false
            }
            written += w
        }
        return true
    }

    func interrupt() {
        Darwin.shutdown(fd1, SHUT_RDWR)
        Darwin.shutdown(fd2, SHUT_RDWR)
    }
}
