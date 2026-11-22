import Foundation
import Network
import Testing
@testable import KhVolume

@Suite("SSCBrowser — interface selection")
struct SSCBrowserTests {

    /// Bonjour reports a service advertised by this Mac on loopback and on every active LAN
    /// interface, which stands in for speakers reachable over both Ethernet and Wi-Fi.
    @Test("resolves on the selected interface when the service is seen on several")
    func resolvesOnSelectedInterface() async throws {
        let name = "khvolume-test-\(UUID().uuidString.prefix(8))"
        let listener = try NWListener(using: .tcp)
        listener.service = NWListener.Service(name: name, type: "_ssc._tcp")
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: .global())
        defer { listener.cancel() }

        let found = await SSCBrowser.scan(interface: "lo0", browseDuration: .seconds(2))
        #expect(found.first { $0.id == name }?.address == "::1")
    }
}
