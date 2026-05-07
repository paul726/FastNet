import Foundation

class AppModel: ObservableObject {
    @Published var device: USBDevice?
    @Published var isForwarding = false
    @Published var proxyEnabled = false
    @Published var activeConnections = 0
    @Published var totalConnections = 0
    @Published var totalBytes: Int64 = 0
    @Published var portText = "1082"
    @Published var error: String?

    private let mux = USBMux.shared
    private var forwarder: PortForwarder?
    private var statsTimer: Timer?

    init() {
        mux.onDeviceAttached = { [weak self] device in
            DispatchQueue.main.async { self?.device = device }
        }
        mux.onDeviceDetached = { [weak self] deviceID in
            DispatchQueue.main.async {
                guard let self, self.device?.id == deviceID else { return }
                self.device = nil
                self.stopForwarding()
            }
        }
        mux.onError = { [weak self] msg in
            DispatchQueue.main.async { self?.error = msg }
        }
        mux.startListening()
    }

    func startForwarding() {
        guard let device else { return }
        let port = UInt16(portText) ?? 1082

        let fw = PortForwarder(deviceID: device.id, remotePort: port)
        guard fw.start(port: port) else {
            error = "Cannot listen on port \(port)"
            return
        }

        forwarder = fw
        isForwarding = true
        error = nil

        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let fw = self.forwarder else { return }
            self.activeConnections = fw.activeConnections
            self.totalConnections = fw.totalConnections
            self.totalBytes = fw.totalBytes
        }
    }

    func stopForwarding() {
        forwarder?.stop()
        forwarder = nil
        isForwarding = false
        statsTimer?.invalidate()
        statsTimer = nil
        activeConnections = 0
        totalConnections = 0
        totalBytes = 0

        if proxyEnabled { toggleProxy() }
    }

    func toggleProxy() {
        if proxyEnabled {
            SystemProxy.disable()
            proxyEnabled = false
        } else {
            let port = UInt16(portText) ?? 1082
            if SystemProxy.enable(port: port) {
                proxyEnabled = true
            } else {
                error = "Failed to set system proxy"
            }
        }
    }
}
