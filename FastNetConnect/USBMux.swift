import Foundation

struct USBDevice: Identifiable {
    let id: Int
    let serialNumber: String
    let productID: Int
}

class USBMux {
    static let shared = USBMux()

    private let socketPath = "/var/run/usbmuxd"
    private var listenFD: Int32 = -1
    private var nextTag: UInt32 = 0
    private let tagLock = NSLock()
    private let queue = DispatchQueue(label: "com.fastnet.usbmux")
    private var readSource: DispatchSourceRead?
    private var listening = false

    var onDeviceAttached: ((USBDevice) -> Void)?
    var onDeviceDetached: ((Int) -> Void)?
    var onError: ((String) -> Void)?

    private func newTag() -> UInt32 {
        tagLock.lock()
        nextTag += 1
        let t = nextTag
        tagLock.unlock()
        return t
    }

    func startListening() {
        queue.async { [self] in
            guard !listening else { return }

            let fd = connectSocket()
            guard fd >= 0 else {
                onError?("Cannot connect to usbmuxd")
                return
            }
            listenFD = fd

            let msg: [String: Any] = [
                "MessageType": "Listen",
                "ProgName": "FastNetConnect",
                "ClientVersionString": "1.0",
                "kLibUSBMuxVersion": 3
            ]

            guard sendPlist(msg, on: fd),
                  let result = readPlist(from: fd),
                  (result["Number"] as? Int) == 0 else {
                Darwin.close(fd)
                listenFD = -1
                onError?("usbmuxd Listen command failed")
                return
            }

            listening = true

            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.handleMuxEvent()
            }
            source.setCancelHandler { [weak self] in
                if let fd = self?.listenFD, fd >= 0 {
                    Darwin.close(fd)
                    self?.listenFD = -1
                }
            }
            readSource = source
            source.resume()
        }
    }

    func stopListening() {
        queue.async { [self] in
            listening = false
            readSource?.cancel()
            readSource = nil
        }
    }

    private func handleMuxEvent() {
        guard let plist = readPlist(from: listenFD) else {
            listening = false
            readSource?.cancel()
            readSource = nil
            return
        }

        switch plist["MessageType"] as? String {
        case "Attached":
            if let props = plist["Properties"] as? [String: Any],
               let deviceID = props["DeviceID"] as? Int,
               let serial = props["SerialNumber"] as? String,
               let productID = props["ProductID"] as? Int {
                onDeviceAttached?(USBDevice(id: deviceID, serialNumber: serial, productID: productID))
            }
        case "Detached":
            if let deviceID = plist["DeviceID"] as? Int {
                onDeviceDetached?(deviceID)
            }
        default:
            break
        }
    }

    func connect(deviceID: Int, port: UInt16) -> Int32 {
        let fd = connectSocket()
        guard fd >= 0 else { return -1 }

        let msg: [String: Any] = [
            "MessageType": "Connect",
            "DeviceID": deviceID,
            "PortNumber": Int(CFSwapInt16HostToBig(port)),
            "ProgName": "FastNetConnect",
            "ClientVersionString": "1.0",
            "kLibUSBMuxVersion": 3
        ]

        guard sendPlist(msg, on: fd),
              let result = readPlist(from: fd),
              (result["Number"] as? Int) == 0 else {
            Darwin.close(fd)
            return -1
        }

        return fd
    }

    // MARK: - Socket

    private func connectSocket() -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { src in
                memcpy(ptr, src, socketPath.count + 1)
            }
        }

        let rc = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if rc != 0 {
            Darwin.close(fd)
            return -1
        }
        return fd
    }

    // MARK: - Protocol

    @discardableResult
    private func sendPlist(_ dict: [String: Any], on fd: Int32) -> Bool {
        guard let xml = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        ) else { return false }

        let totalLen = UInt32(16 + xml.count)
        let tag = newTag()
        var header = Data(count: 16)
        header.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: totalLen.littleEndian, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: UInt32(1).littleEndian, toByteOffset: 4, as: UInt32.self)
            buf.storeBytes(of: UInt32(8).littleEndian, toByteOffset: 8, as: UInt32.self)
            buf.storeBytes(of: tag.littleEndian, toByteOffset: 12, as: UInt32.self)
        }

        let h = header.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, 16) }
        guard h == 16 else { return false }
        let p = xml.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, xml.count) }
        return p == xml.count
    }

    private func readPlist(from fd: Int32) -> [String: Any]? {
        var header = [UInt8](repeating: 0, count: 16)
        guard recv(fd, &header, 16, MSG_WAITALL) == 16 else { return nil }

        let length = header.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self).littleEndian
        }

        let payloadLen = Int(length) - 16
        guard payloadLen > 0 else { return nil }

        var payload = [UInt8](repeating: 0, count: payloadLen)
        guard recv(fd, &payload, payloadLen, MSG_WAITALL) == payloadLen else { return nil }

        return try? PropertyListSerialization.propertyList(
            from: Data(payload), options: [], format: nil
        ) as? [String: Any]
    }
}
