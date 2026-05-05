import Foundation

enum NetworkUtils {

    static func getGatewayAddresses() -> [(interface: String, address: String)] {
        getAllIPAddresses().filter { $0.interface != "lo0" }
    }

    static func getAllIPAddresses() -> [(interface: String, address: String)] {
        var result: [(interface: String, address: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                ptr.pointee.ifa_addr,
                socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            ) == 0 {
                result.append((interface: name, address: String(cString: hostname)))
            }
        }

        return result
    }
}
