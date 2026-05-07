import Foundation
import Network
import os

class SOCKS5Server: ObservableObject {
    private var listener: NWListener?
    private var connections: [UUID: SOCKS5Connection] = [:]
    private let queue = DispatchQueue(label: "com.fastnet.socks5")
    private let logger = Logger(subsystem: "com.fastnet", category: "server")
    private var statsTimer: Timer?
    private var pendingBytes: Int64 = 0
    private let bytesLock = NSLock()
    private var internalTotal = 0

    @Published var isRunning = false
    @Published var activeConnections = 0
    @Published var totalConnections = 0
    @Published var totalBytesTransferred: Int64 = 0
    @Published var lastError: String?
    @Published var logs: [String] = []
    var loggingEnabled = false

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func log(_ msg: String) {
        logger.info("\(msg)")
        guard loggingEnabled else { return }
        let ts = Self.timeFmt.string(from: Date())
        DispatchQueue.main.async {
            self.logs.append("[\(ts)] \(msg)")
            if self.logs.count > 200 { self.logs.removeFirst() }
        }
    }

    func addBytes(_ count: Int) {
        bytesLock.lock()
        pendingBytes += Int64(count)
        bytesLock.unlock()
    }

    func start(port: UInt16 = 1082) {
        guard !isRunning else { return }

        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            tcp.enableFastOpen = true
            let params = NWParameters(tls: nil, tcp: tcp)
            params.allowLocalEndpointReuse = true

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                DispatchQueue.main.async { self.lastError = "Invalid port" }
                return
            }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
            return
        }

        listener?.newConnectionHandler = { [weak self] nwConn in
            self?.handleIncoming(nwConn)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log("Listener ready on port \(port)")
                DispatchQueue.main.async { self.isRunning = true; self.lastError = nil }
            case .failed(let error):
                self.log("Listener failed: \(error)")
                DispatchQueue.main.async { self.isRunning = false; self.lastError = error.localizedDescription }
            case .cancelled:
                DispatchQueue.main.async { self.isRunning = false }
            default: break
            }
        }

        listener?.start(queue: queue)
        startStatsTimer()
    }

    private func handleIncoming(_ nwConn: NWConnection) {
        log("New connection from \(nwConn.endpoint)")
        let id = UUID()
        let conn = SOCKS5Connection(
            connection: nwConn, server: self,
            onComplete: { [weak self] in self?.removeConnection(id) }
        )
        addConnection(id, conn)
        conn.start()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.statsTimer?.invalidate()
            self.statsTimer = nil
        }
        queue.async { [self] in
            for conn in connections.values { conn.cancel() }
            connections.removeAll()
            internalTotal = 0
            DispatchQueue.main.async {
                self.isRunning = false
                self.activeConnections = 0
                self.totalConnections = 0
                self.totalBytesTransferred = 0
            }
        }
    }

    // MARK: - Helpers

    private func addConnection(_ id: UUID, _ conn: SOCKS5Connection) {
        queue.async { [self] in
            connections[id] = conn
            internalTotal += 1
        }
    }

    private func removeConnection(_ id: UUID) {
        queue.async { [self] in
            connections.removeValue(forKey: id)
        }
    }

    private func startStatsTimer() {
        DispatchQueue.main.async {
            self.statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }

                self.bytesLock.lock()
                let bytes = self.pendingBytes
                self.pendingBytes = 0
                self.bytesLock.unlock()

                self.queue.async {
                    let active = self.connections.count
                    let total = self.internalTotal
                    DispatchQueue.main.async {
                        if bytes > 0 { self.totalBytesTransferred += bytes }
                        self.activeConnections = active
                        self.totalConnections = total
                    }
                }
            }
        }
    }
}
