import SwiftUI
import Network

struct ConnectionTestView: View {
    @State private var targetIP = "172.20.10.2"
    @State private var targetPort = "9090"
    @State private var results: [TestResult] = []
    @State private var testing = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Connection Test")
                .font(.system(.headline, design: .rounded))

            HStack {
                TextField("Mac IP", text: $targetIP)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $targetPort)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }

            Button(testing ? "Testing..." : "Run All Tests") {
                runAllTests()
            }
            .disabled(testing)
            .buttonStyle(.borderedProminent)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(results) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: r.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(r.success ? .green : .red)
                                Text(r.method)
                                    .font(.callout.weight(.medium))
                            }
                            Text(r.detail)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding()
    }

    private func runAllTests() {
        testing = true
        results = []
        let ip = targetIP
        let port = UInt16(targetPort) ?? 9090

        DispatchQueue.global().async {
            // List interfaces first
            let interfaces = NetworkUtils.getAllIPAddresses()
            let ifList = interfaces.map { "\($0.interface): \($0.address)" }.joined(separator: ", ")
            addResult(TestResult(method: "Interfaces", success: true, detail: ifList))

            // Test 1: NWConnection — no interface constraint
            testNWConnection(ip: ip, port: port, label: "NWConnection (default)", interfaceType: nil)

            // Test 2: NWConnection — requiredInterfaceType = .wifi
            testNWConnection(ip: ip, port: port, label: "NWConnection (.wifi)", interfaceType: .wifi)

            // Test 3: NWConnection — requiredInterfaceType = .other (bridge100 might be .other)
            testNWConnection(ip: ip, port: port, label: "NWConnection (.other)", interfaceType: .other)

            // Test 4: BSD socket — plain connect
            testBSDSocket(ip: ip, port: port, label: "BSD socket (default)", bindAddr: nil)

            // Test 5: BSD socket — bind to hotspot gateway IP
            let hotspotAddr = interfaces.first(where: { $0.interface.hasPrefix("bridge") })?.address
                ?? interfaces.first(where: { $0.address.hasPrefix("172.20.10.") })?.address
            if let addr = hotspotAddr {
                testBSDSocket(ip: ip, port: port, label: "BSD socket (bind \(addr))", bindAddr: addr)
            }

            DispatchQueue.main.async { testing = false }
        }
    }

    private func testNWConnection(ip: String, port: UInt16, label: String, interfaceType: NWInterface.InterfaceType?) {
        let semaphore = DispatchSemaphore(value: 0)
        var resultStr = ""
        var success = false

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)

        if let ifType = interfaceType {
            params.requiredInterfaceType = ifType
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            addResult(TestResult(method: label, success: false, detail: "Invalid port"))
            return
        }

        let conn = NWConnection(to: .hostPort(host: .init(ip), port: nwPort), using: params)
        let queue = DispatchQueue(label: "test.\(label)")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5)
        timer.setEventHandler {
            resultStr = "Timeout (5s) — state: \(conn.state)"
            conn.cancel()
            semaphore.signal()
        }
        timer.resume()

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                timer.cancel()
                let path = conn.currentPath
                let ifName = path?.availableInterfaces.first?.name ?? "unknown"
                let ifType = path?.availableInterfaces.first?.type.debugDescription ?? "unknown"

                conn.send(content: "HELLO FROM IPHONE\n".data(using: .utf8), contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed({ _ in
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                        let resp = data.flatMap { String(data: $0, encoding: .utf8) } ?? "(no data)"
                        resultStr = "Connected via \(ifName) (\(ifType)), received: \(resp.trimmingCharacters(in: .whitespacesAndNewlines))"
                        success = true
                        conn.cancel()
                        semaphore.signal()
                    }
                }))

            case .failed(let err):
                timer.cancel()
                resultStr = "Failed: \(err.localizedDescription)"
                semaphore.signal()

            case .waiting(let err):
                resultStr = "Waiting: \(err.localizedDescription)"

            default:
                break
            }
        }

        conn.start(queue: queue)
        semaphore.wait()
        addResult(TestResult(method: label, success: success, detail: resultStr))
    }

    private func testBSDSocket(ip: String, port: UInt16, label: String, bindAddr: String?) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            addResult(TestResult(method: label, success: false, detail: "socket() failed: \(errno)"))
            return
        }
        defer { Darwin.close(fd) }

        var one: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))

        // Set non-blocking for timeout
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        if let bindAddr = bindAddr {
            var bindSA = sockaddr_in()
            bindSA.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            bindSA.sin_family = sa_family_t(AF_INET)
            bindSA.sin_port = 0
            inet_pton(AF_INET, bindAddr, &bindSA.sin_addr)
            let bindResult = withUnsafePointer(to: &bindSA) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindResult != 0 {
                addResult(TestResult(method: label, success: false, detail: "bind() failed: errno=\(errno)"))
                return
            }
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, ip, &addr.sin_addr)

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult != 0 && errno != EINPROGRESS {
            addResult(TestResult(method: label, success: false, detail: "connect() failed: errno=\(errno)"))
            return
        }

        // poll for connect completion with 5s timeout
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pfd, 1, 5000)

        if pollResult <= 0 {
            addResult(TestResult(method: label, success: false, detail: pollResult == 0 ? "Timeout (5s)" : "poll() error: errno=\(errno)"))
            return
        }

        // Check if connect succeeded
        var soError: Int32 = 0
        var soLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &soLen)
        if soError != 0 {
            addResult(TestResult(method: label, success: false, detail: "connect error: \(soError)"))
            return
        }

        // Connected — send and receive
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) // back to blocking
        let msg = "HELLO FROM IPHONE\n"
        _ = msg.withCString { Darwin.write(fd, $0, Int(strlen($0))) }

        var buf = [UInt8](repeating: 0, count: 1024)
        let n = Darwin.read(fd, &buf, buf.count)
        let resp = n > 0 ? String(bytes: buf[..<n], encoding: .utf8) ?? "(decode err)" : "(no data)"

        addResult(TestResult(method: label, success: true, detail: "Connected! Received: \(resp.trimmingCharacters(in: .whitespacesAndNewlines))"))
    }

    private func addResult(_ result: TestResult) {
        DispatchQueue.main.async {
            results.append(result)
        }
        Thread.sleep(forTimeInterval: 0.3)
    }
}

struct TestResult: Identifiable {
    let id = UUID()
    let method: String
    let success: Bool
    let detail: String
}

extension NWInterface.InterfaceType: @retroactive CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "cellular"
        case .wiredEthernet: return "ethernet"
        case .loopback: return "loopback"
        case .other: return "other"
        @unknown default: return "unknown"
        }
    }
}
