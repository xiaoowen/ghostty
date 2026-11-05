import SwiftUI

extension ToolsToastMessage {
    /// The toast for a keep-awake change.
    static func keepAwake(_ event: KeepAwake.Event, now: Date = Date()) -> ToolsToastMessage {
        let on = "cup.and.saucer.fill"
        let off = "cup.and.saucer"
        func left(_ date: Date) -> String { KeepAwake.format(date.timeIntervalSince(now)) }

        switch event {
        case .started(nil, false):
            return .init(symbol: on, title: "防息屏已开启", detail: "不限时", tint: .orange)
        case .started(let endDate?, false):
            return .init(symbol: on, title: "防息屏已开启", detail: "\(left(endDate))后自动关闭", tint: .orange)
        case .started(nil, true):
            return .init(symbol: on, title: "防息屏改为不限时", tint: .orange)
        case .started(let endDate?, true):
            return .init(symbol: on, title: "防息屏已重新计时", detail: "\(left(endDate))后自动关闭", tint: .orange)
        case .extended(let seconds, let endDate):
            return .init(symbol: on, title: "防息屏已延长 \(KeepAwake.format(seconds))", detail: "剩余 \(left(endDate))", tint: .orange)
        case .systemSleepChanged(true):
            return .init(symbol: on, title: "已同时阻止系统休眠", tint: .orange)
        case .systemSleepChanged(false):
            return .init(symbol: on, title: "不再阻止系统休眠", detail: "仅保持屏幕常亮", tint: .orange)
        case .stopped:
            return .init(symbol: off, title: "防息屏已关闭")
        case .ended(true):
            return .init(symbol: off, title: "防息屏已到时关闭")
        case .ended(false):
            return .init(symbol: off, title: "防息屏已结束", detail: "caffeinate 进程已退出")
        case .failed:
            return .init(symbol: "exclamationmark.triangle.fill", title: "无法开启防息屏", detail: "caffeinate 启动失败", tint: .orange)
        }
    }
}
