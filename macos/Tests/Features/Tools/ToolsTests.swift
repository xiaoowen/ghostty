import Foundation
import Testing
@testable import Ghostty

@Suite
struct KeepAwakeTests {
    @Test(arguments: [
        (10.0, "1 分钟"),
        (30 * 60.0, "30 分钟"),
        (60 * 60.0, "1 小时"),
        (65 * 60.0, "1 小时 5 分钟"),
    ])
    func format(seconds: Double, expected: String) {
        #expect(KeepAwake.format(seconds) == expected)
    }

    @Test func offHasNoRemainingTime() {
        let defaults = UserDefaults(suiteName: "KeepAwakeTests-\(UUID().uuidString)")!
        let keepAwake = KeepAwake(defaults: defaults)
        #expect(!keepAwake.isOn)
        #expect(keepAwake.remainingSeconds == nil)
        #expect(keepAwake.remainingText == nil)
    }
}
