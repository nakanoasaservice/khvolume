import Foundation
import Testing
@testable import KhVolume

@Suite("AppConfig — maxLevel")
struct AppConfigTests {

    @Test("maxLevel is capped at 120", arguments: [
        (120.0, 120.0),
        (150.0, 120.0),
        (200.0, 120.0),
    ] as [(Double, Double)])
    func maxLevelCappedAt120(limit: Double, expected: Double) {
        var config = AppConfig()
        config.levelLimit = limit
        #expect(config.maxLevel == expected)
    }

    @Test("maxLevel floors at 0", arguments: [
        (0.0, 0.0),
        (-1.0, 0.0),
        (-100.0, 0.0),
    ] as [(Double, Double)])
    func maxLevelFloorsAtZero(limit: Double, expected: Double) {
        var config = AppConfig()
        config.levelLimit = limit
        #expect(config.maxLevel == expected)
    }

    @Test("maxLevel passes through valid range", arguments: [
        (1.0, 1.0),
        (50.0, 50.0),
        (100.0, 100.0),
        (119.9, 119.9),
    ] as [(Double, Double)])
    func maxLevelPassesThrough(limit: Double, expected: Double) {
        var config = AppConfig()
        config.levelLimit = limit
        #expect(config.maxLevel == expected)
    }
}
