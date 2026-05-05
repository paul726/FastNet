import Foundation
import Network

class SOCKS5Connection {
    private static let bufferSize = 262_144
    private static let queues: [DispatchQueue] = (0..<4).map {
        DispatchQueue(label: "com.fastnet.io.\($0)", qos: .userInitiated)
    }
    private static let queueLock = os_unfair_lock_t.allocate(capacity: 1)
    private static var queueIdx = 0
    private static var _queueLockInit: Void = { queueLock.initialize(to: os_unfair_lock()) }()

    static func ioQueue() -> DispatchQueue {
        _ = _queueLockInit
        os_unfair_lock_lock(queueLock)
        let q = queues[queueIdx % queues.count]
        queueIdx += 1
        os_unfair_lock_unlock(queueLock)
        return q
    }

    private let client: NWConnection
    private var remote: NWConnection?
    private let ioQueue: DispatchQueue
    private weak var server: SOCKS5Server?
    private let onComplete: () -> Void
    private var closed = false
    private let closeLock = os_unfair_lock_t.allocate(capacity: 1)

    init(connection: NWConnection, server: SOCKS5Server, onComplete: @escaping () -> Void) {
        self.client = connection
        self.ioQueue = Self.ioQueue()
        self.server = server
        self.onComplete = onComplete
        closeLock.initialize(to: os_unfair_lock())
    }

    deinit {
        closeLock.deallocate()
        client.cancel()
        remote?.cancel()
    }

    func start() {
        client.start(queue: ioQueue)
        receiveGreeting()
    }

    func handleAsClient() {
        receiveGreeting()
    }

    func cancel() {
        os_unfair_lock_lock(closeLock)
        closed = true
        os_unfair_lock_unlock(closeLock)
        client.cancel()
        remote?.cancel()
    }

    private func close() {
        os_unfair_lock_lock(closeLock)
        guard !closed else { os_unfair_lock_unlock(closeLock); return }
        closed = true
        os_unfair_lock_unlock(closeLock)
        client.cancel()
        remote?.cancel()
        onComplete()
    }

    // MARK: - SOCKS5

    private func receiveGreeting() {
        server?.log("Waiting for SOCKS greeting...")
        client.receive(minimumIncompleteLength: 3, maximumLength: 257) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.server?.log("Greeting receive error: \(error)")
                self.close(); return
            }
            guard let data, data.count >= 3, data[0] == 0x05 else {
                self.server?.log("Invalid greeting: \(data?.count ?? 0) bytes")
                self.close(); return
            }
            self.server?.log("Got greeting, \(data[1]) methods")
            self.client.send(content: Data([0x05, 0x00]), completion: .contentProcessed { [weak self] err in
                if err != nil { self?.server?.log("Greeting reply failed"); self?.close(); return }
                self?.receiveRequest()
            })
        }
    }

    private func receiveRequest() {
        client.receive(minimumIncompleteLength: 4, maximumLength: 512) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.server?.log("Request receive error: \(error)")
                self.close(); return
            }
            guard let data, data.count >= 4, data[0] == 0x05, data[1] == 0x01 else {
                self.server?.log("Invalid request: \(data?.count ?? 0) bytes, cmd=\(data.map { String($0[1]) } ?? "nil")")
                self.close(); return
            }

            let atyp = data[3]
            var off = 4
            var host: String?

            switch atyp {
            case 0x01:
                guard data.count >= off + 6 else { self.close(); return }
                host = (0..<4).map { String(data[off + $0]) }.joined(separator: ".")
                off += 4
            case 0x03:
                guard data.count > off else { self.close(); return }
                let len = Int(data[off]); off += 1
                guard data.count >= off + len + 2 else { self.close(); return }
                host = String(data: data[off..<off + len], encoding: .utf8)
                off += len
            case 0x04:
                guard data.count >= off + 18 else { self.close(); return }
                var p: [String] = []
                for i in stride(from: off, to: off + 16, by: 2) {
                    p.append(String(format: "%x", UInt16(data[i]) << 8 | UInt16(data[i + 1])))
                }
                host = p.joined(separator: ":")
                off += 16
            default:
                self.reply(0x08); return
            }

            guard data.count >= off + 2 else { self.close(); return }
            let port = UInt16(data[off]) << 8 | UInt16(data[off + 1])
            guard let host, port > 0 else { self.reply(0x01); return }
            self.server?.log("CONNECT \(host):\(port)")
            self.connectRemote(host: host, port: port)
        }
    }

    private func connectRemote(host: String, port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { reply(0x01); return }

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableFastOpen = true
        tcp.connectionTimeout = 10
        let params = NWParameters(tls: nil, tcp: tcp)
        let conn = NWConnection(to: .hostPort(host: .init(host), port: nwPort), using: params)
        self.remote = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.server?.log("Remote ready → \(host):\(port)")
                self.reply(0x00)
                self.startRelay()
            case .failed(let err):
                self.server?.log("Remote failed → \(host):\(port) \(err)")
                self.reply(0x05)
            default: break
            }
        }
        conn.start(queue: ioQueue)
    }

    private func reply(_ rep: UInt8) {
        var d = Data([0x05, rep, 0x00, 0x01])
        d.append(contentsOf: [0, 0, 0, 0, 0, 0])
        client.send(content: d, completion: .contentProcessed { [weak self] _ in
            if rep != 0x00 { self?.close() }
        })
    }

    // MARK: - Relay

    private func startRelay() {
        guard let remote else { close(); return }
        relay(from: client, to: remote)
        relay(from: remote, to: client)
    }

    private func relay(from src: NWConnection, to dst: NWConnection) {
        src.receive(minimumIncompleteLength: 1, maximumLength: Self.bufferSize) { [weak self] data, _, fin, err in
            guard let self, !self.closed else { return }

            if let data, !data.isEmpty {
                self.server?.addBytes(data.count)
                dst.send(content: data, completion: .contentProcessed { [weak self] e in
                    if e != nil { self?.close() }
                })
                if !fin { self.relay(from: src, to: dst); return }
            }
            if fin || err != nil { self.close() }
        }
    }
}
