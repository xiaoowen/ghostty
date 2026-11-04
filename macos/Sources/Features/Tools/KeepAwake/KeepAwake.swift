import Foundation
import OSLog

/// Keeps the display awake by running `/usr/bin/caffeinate -d` as a child process.
///
/// The process is always started with `-w <our pid>` so it exits by itself if
/// Ghostty quits or crashes, and with `-t <seconds>` for timed sessions. Our
/// published state follows whether that process is alive, so a timer running
/// out or someone killing caffeinate is reflected everywhere automatically.
/// Use from the main thread only.
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake(defaults: .ghostty)

    /// Durations offered in the menus. A `nil` duration runs until turned off.
    enum Preset: CaseIterable, Identifiable {
        case indefinite
        case minutes30
        case hour1
        case hours2

        var id: Self { self }

        var seconds: TimeInterval? {
            switch self {
            case .indefinite: nil
            case .minutes30: 30 * 60
            case .hour1: 60 * 60
            case .hours2: 2 * 60 * 60
            }
        }

        var title: String {
            switch self {
            case .indefinite: "不限时"
            case .minutes30: "30 分钟"
            case .hour1: "1 小时"
            case .hours2: "2 小时"
            }
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "KeepAwake"
    )

    private static let preventSystemSleepKey = "KeepAwakePreventSystemSleep"

    /// Whether a caffeinate process is currently running.
    @Published private(set) var isOn = false

    /// When the current session ends, or nil if it runs until turned off.
    @Published private(set) var endDate: Date?

    /// Also pass `-i` so idle system sleep is prevented, not just display sleep.
    /// Changing this while on restarts caffeinate with the remaining time.
    @Published var preventSystemSleep: Bool {
        didSet {
            guard preventSystemSleep != oldValue else { return }
            defaults.set(preventSystemSleep, forKey: Self.preventSystemSleepKey)
            if isOn { start(seconds: remainingSeconds) }
        }
    }

    private let defaults: UserDefaults
    private let executableURL: URL
    private var process: Process?

    init(
        defaults: UserDefaults,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    ) {
        self.defaults = defaults
        self.executableURL = executableURL
        self.preventSystemSleep = defaults.bool(forKey: Self.preventSystemSleepKey)
    }

    /// Seconds left in a timed session, or nil when off or untimed.
    var remainingSeconds: TimeInterval? {
        guard isOn, let endDate else { return nil }
        return max(1, endDate.timeIntervalSinceNow)
    }

    /// Short status, e.g. "剩余 42 分钟" or "不限时". Nil when off.
    var remainingText: String? {
        guard isOn else { return nil }
        guard let remainingSeconds else { return "不限时" }
        return "剩余 \(Self.format(remainingSeconds))"
    }

    func toggle() {
        if isOn {
            stop()
        } else {
            start(seconds: nil)
        }
    }

    func start(_ preset: Preset) {
        start(seconds: preset.seconds)
    }

    /// Start, or restart with new settings. `seconds == nil` keeps the display
    /// awake until `stop()` is called or Ghostty quits.
    func start(seconds: TimeInterval?) {
        terminateProcess()

        var args = ["-d"]
        if preventSystemSleep { args.append("-i") }
        args += ["-w", String(ProcessInfo.processInfo.processIdentifier)]
        if let seconds { args += ["-t", String(Int(seconds.rounded(.up)))] }

        let p = Process()
        p.executableURL = executableURL
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            let pid = proc.processIdentifier
            DispatchQueue.main.async { self?.processDidExit(pid: pid) }
        }

        do {
            try p.run()
        } catch {
            Self.logger.warning("failed to start caffeinate: \(error.localizedDescription, privacy: .public)")
            isOn = false
            endDate = nil
            return
        }

        process = p
        isOn = true
        endDate = seconds.map { Date().addingTimeInterval($0) }
    }

    func stop() {
        terminateProcess()
        isOn = false
        endDate = nil
    }

    /// Add time to a timed session. Starts a timed session if off, and does
    /// nothing for an untimed one since it already runs until turned off.
    func extend(by seconds: TimeInterval) {
        guard isOn else {
            start(seconds: seconds)
            return
        }
        guard let remainingSeconds else { return }
        start(seconds: remainingSeconds + seconds)
    }

    /// Formats a duration as "42 分钟", "1 小时" or "1 小时 5 分钟".
    static func format(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分钟"
    }

    private func terminateProcess() {
        guard let p = process else { return }
        process = nil
        if p.isRunning { p.terminate() }
    }

    private func processDidExit(pid: Int32) {
        // Exits from a process we already replaced or stopped are expected.
        guard let process, process.processIdentifier == pid else { return }
        self.process = nil
        isOn = false
        endDate = nil
    }
}
