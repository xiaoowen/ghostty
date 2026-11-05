import AppKit

/// "Check for Updates…" in this fork. Upstream's Sparkle updater reads the
/// official appcast, so it would replace the fork with official Ghostty, and
/// it couldn't verify the fork's builds anyway since they aren't notarized.
/// The fork never starts Sparkle; this asks GitHub for the fork's latest
/// release instead and offers its download page. Nothing is downloaded or
/// installed. Use from the main thread only.
final class ForkReleaseChecker {
    static let shared = ForkReleaseChecker()

    /// The fork's GitHub repository.
    static let repository = "xiaoowen/ghostty"

    static var releasesPage: URL {
        URL(string: "https://github.com/\(repository)/releases")!
    }

    /// The latest published release; GitHub leaves out drafts and pre-releases.
    static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    struct Release: Equatable {
        /// Without the leading "v", e.g. "1.4.1-tools.2".
        var version: String
        var page: URL
    }

    enum Outcome: Equatable {
        case newer(Release)
        case upToDate
        case failed(String)
    }

    private var isChecking = false

    /// Asks GitHub and reports the result in an alert.
    func check() {
        guard !isChecking else { return }
        isChecking = true
        ToolsToast.shared.show(.init(symbol: "arrow.triangle.2.circlepath", title: "正在检查更新…"))

        var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ghostty-fork-update-check", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let outcome = Self.outcome(data: data, response: response, error: error, current: Self.currentVersion)
            DispatchQueue.main.async {
                self.isChecking = false
                Self.present(outcome)
            }
        }.resume()
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func outcome(data: Data?, response: URLResponse?, error: Error?, current: String) -> Outcome {
        if let error { return .failed(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse, let data else {
            return .failed("没有收到 GitHub 的响应")
        }
        switch http.statusCode {
        case 200: break
        case 404: return .failed("GitHub 上还没有发布版本")
        case 403, 429: return .failed("GitHub 暂时限制了请求次数，请稍后再试")
        default: return .failed("GitHub 返回了 HTTP \(http.statusCode)")
        }
        guard let release = parse(data) else {
            return .failed("无法识别 GitHub 返回的版本信息")
        }
        return compare(release.version, current) == .orderedDescending ? .newer(release) : .upToDate
    }

    /// Reads `tag_name` and `html_url` from GitHub's release JSON.
    static func parse(_ data: Data) -> Release? {
        struct Payload: Decodable {
            var tag: String
            var page: String

            enum CodingKeys: String, CodingKey {
                case tag = "tag_name"
                case page = "html_url"
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let page = URL(string: payload.page) else { return nil }

        var version = payload.tag.trimmingCharacters(in: .whitespaces)
        if version.first == "v" || version.first == "V" { version.removeFirst() }
        guard !version.isEmpty else { return nil }
        return Release(version: version, page: page)
    }

    /// Compares the numbers in two versions in order, so 1.4.1-tools.10 is
    /// newer than 1.4.1-tools.9, and 1.5.0-tools.1 newer than both. Missing
    /// numbers count as 0.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func numbers(_ s: String) -> [Int] {
            s.split(whereSeparator: { !("0"..."9").contains($0) }).compactMap { Int($0) }
        }
        let x = numbers(a)
        let y = numbers(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func present(_ outcome: Outcome) {
        let alert = NSAlert()
        switch outcome {
        case .newer(let release):
            alert.messageText = "发现新版本 \(release.version)"
            alert.informativeText = "当前版本 \(currentVersion)。请在 GitHub 下载安装包，替换「应用程序」里的 Ghostty。"
            alert.addButton(withTitle: "前往下载")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.page)
            }

        case .upToDate:
            alert.messageText = "已是最新版本"
            alert.informativeText = "当前版本 \(currentVersion)。"
            alert.addButton(withTitle: "好")
            alert.addButton(withTitle: "查看发布页")
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.open(releasesPage)
            }

        case .failed(let reason):
            alert.alertStyle = .warning
            alert.messageText = "检查更新失败"
            alert.informativeText = reason
            alert.addButton(withTitle: "打开发布页")
            alert.addButton(withTitle: "好")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releasesPage)
            }
        }
    }
}
