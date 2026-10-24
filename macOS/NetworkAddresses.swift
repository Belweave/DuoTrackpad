import Foundation
import Darwin

enum NetworkAddresses {
    static var localIPv4: [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return [] }
        defer { freeifaddrs(interfaces) }
        var result: [(String, String)] = []
        var cursor = interfaces
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  item.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append((String(cString: item.pointee.ifa_name), String(cString: host)))
            }
        }
        // Prefer physical network interfaces over VPN tunnels; show an address, never assume Wi-Fi.
        return result.sorted { a, b in
            if a.0.hasPrefix("en") != b.0.hasPrefix("en") { return a.0.hasPrefix("en") }
            return a.0 < b.0
        }.map(\.1)
    }
}
