import SwiftUI

struct ContentView: View {
    @StateObject private var server = SOCKS5Server()
    @State private var mode: ProxyMode = .tunnel
    @State private var portText = "1082"
    @State private var macIP = "192.0.0.2"
    @State private var tunnelPortText = "1083"
    @State private var loggingEnabled = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if !server.isRunning { settingsSection }
                if server.isRunning { statsSection }
                toggleSection
                logToggleSection
                if loggingEnabled && !server.logs.isEmpty { logSection }
            }
            .navigationTitle("FastNet")
            .alert("Error", isPresented: hasError) {
                Button("OK") { server.lastError = nil }
            } message: {
                Text(server.lastError ?? "")
            }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                Circle()
                    .fill(server.isRunning ? .green : .gray)
                    .frame(width: 12, height: 12)
                if server.isRunning {
                    Text(mode == .listen
                         ? "Listening on port \(portText)"
                         : "Tunnel → \(macIP):\(tunnelPortText)")
                        .font(.headline)
                } else {
                    Text("Stopped")
                        .font(.headline)
                }
            }
        }
    }

    private var settingsSection: some View {
        Section("Settings") {
            Picker("Mode", selection: $mode) {
                ForEach(ProxyMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            if mode == .listen {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("1082", text: $portText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                let addrs = NetworkUtils.getGatewayAddresses()
                if !addrs.isEmpty {
                    ForEach(addrs, id: \.interface) { a in
                        HStack {
                            Text(a.interface)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(a.address)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            } else {
                HStack {
                    Text("Mac IP")
                    Spacer()
                    TextField("192.0.0.2", text: $macIP)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                }
                HStack {
                    Text("Tunnel Port")
                    Spacer()
                    TextField("1083", text: $tunnelPortText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mac side: python3 relay.py")
                        .font(.system(.caption, design: .monospaced))
                    Text("Mac proxy: 127.0.0.1:\(portText)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statsSection: some View {
        Section("Statistics") {
            LabeledContent("Active", value: "\(server.activeConnections)")
            LabeledContent("Total", value: "\(server.totalConnections)")
            LabeledContent("Transferred", value: formatBytes(server.totalBytesTransferred))
            if mode == .tunnel {
                LabeledContent("Pool", value: "\(server.poolSize)")
            }
        }
    }

    private var toggleSection: some View {
        Section {
            Button(action: toggle) {
                HStack {
                    Spacer()
                    Text(server.isRunning ? "Stop" : "Start")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .foregroundStyle(server.isRunning ? .red : .blue)
        }
    }

    private var logToggleSection: some View {
        Section {
            Toggle("Logging", isOn: $loggingEnabled)
                .onChange(of: loggingEnabled) { server.loggingEnabled = $0 }
        }
    }

    private var logSection: some View {
        Section("Log") {
            ForEach(Array(server.logs.suffix(50).enumerated().reversed()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Button("Clear") { server.logs.removeAll() }
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private var hasError: Binding<Bool> {
        Binding(
            get: { server.lastError != nil },
            set: { if !$0 { server.lastError = nil } }
        )
    }

    private func toggle() {
        if server.isRunning {
            server.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        } else {
            UIApplication.shared.isIdleTimerDisabled = true
            if mode == .listen {
                server.startListen(port: UInt16(portText) ?? 1082)
            } else {
                server.startTunnel(
                    macIP: macIP,
                    tunnelPort: UInt16(tunnelPortText) ?? 1083
                )
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}
