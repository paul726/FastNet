import SwiftUI

@main
struct FastNetConnectApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.isForwarding
                      ? "bolt.fill"
                      : "bolt.slash")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("FastNet")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                statusBadge
            }

            Divider()

            // Device
            deviceRow

            // Port (when not running)
            if !model.isForwarding {
                HStack {
                    Label("Port", systemImage: "network")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                    TextField("1082", text: $model.portText)
                        .frame(width: 56)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.callout, design: .monospaced))
                }
            }

            // Action
            actionButton

            // Stats
            if model.isForwarding {
                statsRow
            }

            // Error
            if let error = model.error {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Link("Privacy", destination: URL(string: "https://github.com/paul726/FastNet/blob/main/PRIVACY.md")!)
                Link("Terms", destination: URL(string: "https://github.com/paul726/FastNet/blob/main/TERMS.md")!)
                Link("Support", destination: URL(string: "mailto:pjiang726@gmail.com")!)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            Button {
                model.stopForwarding()
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Text("Quit FastNet")
                        .font(.callout)
                    Spacer()
                    Text("Q")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 260)
    }

    // MARK: - Components

    private var statusBadge: some View {
        Text(model.isForwarding ? "ON" : "OFF")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(model.isForwarding ? .green : .secondary)
            .background(
                (model.isForwarding ? Color.green : Color.gray).opacity(0.15),
                in: Capsule()
            )
    }

    private var deviceRow: some View {
        HStack(spacing: 8) {
            Image(systemName: model.device != nil ? "iphone" : "iphone.slash")
                .font(.title3)
                .foregroundStyle(model.device != nil ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.device != nil ? "iPhone Connected" : "No Device")
                    .font(.callout.weight(.medium))
                if model.device != nil {
                    Text("USB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connect via USB cable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Circle()
                .fill(model.device != nil ? .green : .gray.opacity(0.4))
                .frame(width: 8, height: 8)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionButton: some View {
        Button {
            if model.isForwarding { model.stopForwarding() } else { model.startForwarding() }
        } label: {
            HStack {
                Spacer()
                Image(systemName: model.isForwarding ? "stop.fill" : "play.fill")
                    .font(.caption)
                Text(model.isForwarding ? "Stop" : "Start")
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .disabled(model.device == nil)
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(model.isForwarding ? .gray : .accentColor)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(model.activeConnections)", label: "Active", icon: "link")
            Divider().frame(height: 28)
            statCell(value: "\(model.totalConnections)", label: "Total", icon: "number")
            Divider().frame(height: 28)
            statCell(value: formatBytes(model.totalBytes), label: "Traffic", icon: "arrow.up.arrow.down")
        }
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .semibold))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}
