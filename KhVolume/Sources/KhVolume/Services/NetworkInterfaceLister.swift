import Darwin
import Foundation
import SystemConfiguration

/// Lists hardware network ports (what `networksetup -listallhardwareports` shows) with link state.
enum NetworkInterfaceLister {
    static func list() -> [NetworkInterfaceInfo] {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let flags = interfaceFlags()
        return interfaces.compactMap { interface in
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String? else { return nil }
            let label = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? name
            let active = isActive(name, flags: flags[name])
            return NetworkInterfaceInfo(name: name, label: label, status: active ? "active" : "inactive")
        }
    }

    /// Link state as `ifconfig` reports it: media status when the driver has one, else UP+RUNNING.
    static func isActive(_ name: String, flags: UInt32?) -> Bool {
        if let mediaActive = mediaStatus(name) { return mediaActive }
        guard let flags else { return false }
        if flags & UInt32(IFF_LOOPBACK) != 0 { return false }
        return flags & UInt32(IFF_UP) != 0 && flags & UInt32(IFF_RUNNING) != 0
    }

    private static func interfaceFlags() -> [String: UInt32] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [:] }
        defer { freeifaddrs(head) }
        var flags: [String: UInt32] = [:]
        var cursor = head
        while let entry = cursor {
            flags[String(cString: entry.pointee.ifa_name)] = entry.pointee.ifa_flags
            cursor = entry.pointee.ifa_next
        }
        return flags
    }

    /// `SIOCGIFMEDIA`: true/false when the driver reports link validity, nil otherwise.
    private static func mediaStatus(_ name: String) -> Bool? {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var request = ifmediareq()
        withUnsafeMutableBytes(of: &request.ifm_name) { buffer in
            buffer.copyBytes(from: name.utf8.prefix(buffer.count - 1))
        }
        guard ioctl(sock, siocgifmedia, &request) == 0, request.ifm_status & IFM_AVALID != 0 else {
            return nil
        }
        return request.ifm_status & IFM_ACTIVE != 0
    }

    /// `_IOWR('i', 56, struct ifmediareq)`; the macro is not imported into Swift.
    private static let siocgifmedia: UInt = {
        let inout_: UInt = 0x8000_0000 | 0x4000_0000
        let size = UInt(MemoryLayout<ifmediareq>.size) & 0x1FFF
        return inout_ | (size << 16) | (UInt(UInt8(ascii: "i")) << 8) | 56
    }()
}
