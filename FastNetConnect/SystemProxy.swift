import Foundation

enum SystemProxy {
    static func enable(port: UInt16, service: String = "Wi-Fi") -> Bool {
        shell("-setsocksfirewallproxy", service, "127.0.0.1", String(port))
            && shell("-setsocksfirewallproxystate", service, "on")
    }

    @discardableResult
    static func disable(service: String = "Wi-Fi") -> Bool {
        shell("-setsocksfirewallproxystate", service, "off")
    }

    static func networkServices() -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = ["-listallnetworkservices"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch { return [] }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    @discardableResult
    private static func shell(_ args: String...) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}
