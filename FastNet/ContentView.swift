import SwiftUI

struct ContentView: View {
    @StateObject private var server = SOCKS5Server()
    @State private var portText = "1082"
    @State private var loggingEnabled = false
    @State private var showConnectionTest = false

    var body: some View {
        VStack(spacing: 0) {
            headerView
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    if server.isRunning { statsCard }
                    if !server.isRunning { settingsCard }
                    actionButton
                    if loggingEnabled && !server.logs.isEmpty { logCard }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .alert("Error", isPresented: hasError) {
            Button("OK") { server.lastError = nil }
        } message: {
            Text(server.lastError ?? "")
        }
        .sheet(isPresented: $showConnectionTest) {
            ConnectionTestView()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("FastNet")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Network Proxy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Toggle("Debug Log", isOn: $loggingEnabled)
                    .onChange(of: loggingEnabled) { server.loggingEnabled = $0 }
                Button("Connection Test") { showConnectionTest = true }
                Divider()
                Link("Privacy Policy", destination: URL(string: "https://github.com/paul726/FastNet/blob/main/PRIVACY.md")!)
                Link("Terms of Use", destination: URL(string: "https://github.com/paul726/FastNet/blob/main/TERMS.md")!)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Status

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(server.isRunning
                          ? Color.green.opacity(0.15)
                          : Color.gray.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: server.isRunning ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title2)
                    .foregroundStyle(server.isRunning ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(server.isRunning ? "Active" : "Inactive")
                    .font(.headline)
                if server.isRunning {
                    Text("Port \(portText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ready to connect")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Stats

    private var statsCard: some View {
        VStack(spacing: 0) {
            HStack {
                statItem(
                    icon: "link",
                    label: "Active",
                    value: "\(server.activeConnections)",
                    color: .blue
                )
                Spacer()
                statItem(
                    icon: "arrow.triangle.branch",
                    label: "Total",
                    value: "\(server.totalConnections)",
                    color: .purple
                )
                Spacer()
                statItem(
                    icon: "arrow.up.arrow.down",
                    label: "Traffic",
                    value: formatBytes(server.totalBytesTransferred),
                    color: .orange
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func statItem(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Configuration", systemImage: "gearshape")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack {
                Text("Port")
                Spacer()
                TextField("1082", text: $portText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 80)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }

            let addrs = NetworkUtils.getGatewayAddresses()
            if !addrs.isEmpty {
                Divider()
                ForEach(addrs, id: \.interface) { a in
                    HStack {
                        Text(a.interface)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(a.address)
                            .font(.system(.callout, design: .monospaced))
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Action

    private var actionButton: some View {
        Button(action: toggle) {
            HStack {
                Spacer()
                Image(systemName: server.isRunning ? "stop.fill" : "play.fill")
                Text(server.isRunning ? "Stop Proxy" : "Start Proxy")
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                server.isRunning
                    ? Color(.systemGray)
                    : Color.accentColor,
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Log", systemImage: "text.alignleft")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { server.logs.removeAll() }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(server.logs.suffix(50).enumerated().reversed()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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
            server.start(port: UInt16(portText) ?? 1082)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}
