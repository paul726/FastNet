import SwiftUI

@main
struct FastNetConnectApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: model.isForwarding
                  ? "antenna.radiowaves.left.and.right"
                  : "antenna.radiowaves.left.and.right.slash")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Device status
            HStack(spacing: 6) {
                Circle()
                    .fill(model.device != nil ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(model.device != nil ? "iPhone connected" : "No device")
                    .font(.headline)
            }

            Divider()

            // Port
            HStack {
                Text("Port")
                Spacer()
                TextField("1082", text: $model.portText)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }
            .disabled(model.isForwarding)

            // Start / Stop
            Button {
                if model.isForwarding { model.stopForwarding() } else { model.startForwarding() }
            } label: {
                HStack {
                    Spacer()
                    Text(model.isForwarding ? "Stop" : "Start")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(model.device == nil)
            .controlSize(.large)

            if model.isForwarding {
                Divider()

                LabeledContent("Active", value: "\(model.activeConnections)")
                LabeledContent("Total", value: "\(model.totalConnections)")
                LabeledContent("Transferred", value: formatBytes(model.totalBytes))

                Divider()

                Toggle("System SOCKS Proxy", isOn: Binding(
                    get: { model.proxyEnabled },
                    set: { _ in model.toggleProxy() }
                ))
            }

            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Divider()

            Button("Quit") {
                model.stopForwarding()
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 240)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}
