import Foundation

enum SystemProxy {
    static func enable(port: UInt16) -> Bool {
        var anyOK = false
        for svc in allServices() {
            if shell("-setsocksfirewallproxy", svc, "127.0.0.1", String(port))
                && shell("-setsocksfirewallproxystate", svc, "on") {
                anyOK = true
            }
        }
        return anyOK
    }

    @discardableResult
    static func disable() -> Bool {
        var anyOK = false
        for svc in allServices() {
            if shell("-setsocksfirewallproxystate", svc, "off") {
                anyOK = true
            }
        }
        return anyOK
    }

    private static func allServices() -> [String] {
        let output = shellOutput("-listallnetworkservices")
        return output.components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
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

    private static func shellOutput(_ args: String...) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch { return "" }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
