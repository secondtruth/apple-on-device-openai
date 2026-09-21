import Foundation

/// The IPv4 addresses this Mac can bind a server to.
enum NetworkInterfaces {
    static let loopback = "127.0.0.1"
    static let allInterfaces = "0.0.0.0"

    /// Loopback first, then every interface, then the assigned addresses.
    static func bindableAddresses() -> [String] {
        [loopback, allInterfaces] + assignedAddresses()
    }

    /// An address other machines can reach when the server listens on all
    /// interfaces. Link-local addresses (169.254/16) are skipped: they mean the
    /// interface got no real address.
    static func primaryLANAddress() -> String? {
        assignedAddresses().first { !$0.hasPrefix("169.254.") }
    }

    private static func assignedAddresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }

        var addresses: Set<String> = []
        for interface in sequence(first: first, next: { $0?.pointee.ifa_next }) {
            guard let address = interface?.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            if getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.insert(String(cString: host))
            }
        }
        return addresses.subtracting([loopback]).sorted()
    }
}
