import Foundation

class PortForwarder {
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
        var opt: Int32 = 1
        setsockopt(clientFD, IPPROTO_TCP, TCP_NODELAY, &opt, socklen_t(MemoryLayout<Int32>.size))

        let deviceFD = USBMux.shared.connect(deviceID: deviceID, port: remotePort)
        guard deviceFD >= 0 else {
            Darwin.close(clientFD)
            return
        }
        setsockopt(deviceFD, IPPROTO_TCP, TCP_NODELAY, &opt, socklen_t(MemoryLayout<Int32>.size))

        let id = UUID()
        statsLock.lock()
        _totalConnections += 1
        statsLock.unlock()

        let relay = TunnelRelay(fd1: clientFD, fd2: deviceFD, onBytes: { [weak self] n in
            self?.statsLock.lock()
            self?._totalBytes += Int64(n)
            self?.statsLock.unlock()
        }, onClose: { [weak self] in
            self?.relayLock.lock()
            self?.relays.removeValue(forKey: id)
            self?.relayLock.unlock()
        })

        relayLock.lock()
        relays[id] = relay
        relayLock.unlock()

        relay.start()
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1

        relayLock.lock()
        let current = Array(relays.values)
        relays.removeAll()
        relayLock.unlock()

        for r in current { r.close() }

        statsLock.lock()
        _totalConnections = 0
        _totalBytes = 0
        statsLock.unlock()
    }
}

private class TunnelRelay {
    private let fd1: Int32
    private let fd2: Int32
    private let onBytes: (Int) -> Void
    private let onClose: () -> Void
    private var didClose = false
    private let lock = NSLock()

    init(fd1: Int32, fd2: Int32, onBytes: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
        self.fd1 = fd1
        self.fd2 = fd2
        self.onBytes = onBytes
        self.onClose = onClose
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { self.pump(from: self.fd1, to: self.fd2) }
        DispatchQueue.global(qos: .userInitiated).async { self.pump(from: self.fd2, to: self.fd1) }
    }

    private func pump(from src: Int32, to dst: Int32) {
        let bufSize = 65536
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 1)
        defer { buf.deallocate() }

        while true {
            let n = Darwin.read(src, buf, bufSize)
            if n <= 0 { break }
            onBytes(n)
            var written = 0
            while written < n {
                let w = Darwin.write(dst, buf.advanced(by: written), n - written)
                if w <= 0 { close(); return }
                written += w
            }
        }
        close()
    }

    func close() {
        lock.lock()
        guard !didClose else { lock.unlock(); return }
        didClose = true
        lock.unlock()

        Darwin.close(fd1)
        Darwin.close(fd2)
        onClose()
    }
}
