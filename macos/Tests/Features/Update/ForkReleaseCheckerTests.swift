import Foundation
import Testing
@testable import Ghostty

@Suite
struct ForkReleaseCheckerTests {
    private func payload(tag: String) -> Data {
        Data("""
        {"tag_name": "\(tag)", "name": " Ghostty \(tag)", "html_url": "https://github.com/xiaoowen/ghostty/releases/tag/\(tag)", "draft": false}
        """.utf8)
    }

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: ForkReleaseChecker.latestReleaseURL, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    @Test func parsesTagAndPage() {
        let release = ForkReleaseChecker.parse(payload(tag: "v1.4.1-tools.2"))
        #expect(release == ForkReleaseChecker.Release(
            version: "1.4.1-tools.2",
            page: URL(string: "https://github.com/xiaoowen/ghostty/releases/tag/v1.4.1-tools.2")!
        ))
        #expect(ForkReleaseChecker.parse(Data("{}".utf8)) == nil)
        #expect(ForkReleaseChecker.parse(payload(tag: "v")) == nil)
    }

    @Test(arguments: [
        ("1.4.1-tools.2", "1.4.1-tools.1", ComparisonResult.orderedDescending),
        ("1.4.1-tools.10", "1.4.1-tools.9", .orderedDescending),
        ("1.5.0-tools.1", "1.4.1-tools.9", .orderedDescending),
        ("1.4.1-tools.1", "1.4.1", .orderedDescending),
        ("1.4.1-tools.1", "1.4.1-tools.1", .orderedSame),
        ("1.4.1-tools.1", "1.4.2", .orderedAscending),
    ])
    func compare(a: String, b: String, expected: ComparisonResult) {
        #expect(ForkReleaseChecker.compare(a, b) == expected)
    }

    @Test func outcomes() {
        let current = "1.4.1-tools.2"
        func outcome(_ data: Data?, _ status: Int?, _ error: Error? = nil) -> ForkReleaseChecker.Outcome {
            ForkReleaseChecker.outcome(data: data, response: status.map(response), error: error, current: current)
        }

        if case .newer(let release) = outcome(payload(tag: "v1.4.1-tools.3"), 200) {
            #expect(release.version == "1.4.1-tools.3")
        } else {
            Issue.record("expected a newer release")
        }
        #expect(outcome(payload(tag: "v1.4.1-tools.2"), 200) == .upToDate)
        // A build newer than the latest release isn't offered a downgrade.
        #expect(outcome(payload(tag: "v1.4.1-tools.1"), 200) == .upToDate)

        #expect(outcome(Data(), 404) == .failed("GitHub 上还没有发布版本"))
        #expect(outcome(Data(), 403) == .failed("GitHub 暂时限制了请求次数，请稍后再试"))
        #expect(outcome(Data(), 500) == .failed("GitHub 返回了 HTTP 500"))
        #expect(outcome(Data("not json".utf8), 200) == .failed("无法识别 GitHub 返回的版本信息"))
        #expect(outcome(nil, nil, URLError(.notConnectedToInternet))
            == .failed(URLError(.notConnectedToInternet).localizedDescription))
    }
}
