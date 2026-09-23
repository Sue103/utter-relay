import Foundation

// MARK: - LAN IPアドレス取得。en0だけでなくen*全体を見る(このMac miniがen1だった教訓を反映)。
enum NetworkAddress {
    static func currentLANAddress() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var candidates: [(name: String, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee
            guard let ifaAddr = interface.ifa_addr, ifaAddr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var addr = ifaAddr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = withUnsafePointer(to: &addr) { pointer -> Int32 in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    getnameinfo(sockaddrPointer, socklen_t(ifaAddr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                }
            }
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            if ip != "127.0.0.1" {
                candidates.append((name, ip))
            }
        }
        candidates.sort { $0.name < $1.name }
        return candidates.first?.address
    }
}
