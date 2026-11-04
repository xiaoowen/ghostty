import AppKit
import SwiftUI

/// 高级: config files, current configuration errors and resetting.
struct AdvancedSettingsPage: View {
    @ObservedObject var model: SettingsModel

    @State private var confirmingResetAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(
                "配置文件",
                footer: "设置页只写 \(GUIConfigFile.fileName)。它在主配置之后加载，所以同名选项以设置页为准。"
            ) {
                FileRow(title: "主配置", symbol: "doc.text.fill", url: model.mainConfigURL)
                SettingsDivider()
                FileRow(title: "设置页的修改", symbol: "slider.horizontal.3", url: model.guiConfigURL)
                SettingsDivider()
                SettingsRow(title: "引用", note: "主配置里的 \(GUIConfigFile.includeDirective)") {
                    if model.includeMissing {
                        CapsuleLabel(text: "未引用", symbol: "exclamationmark.triangle.fill", tint: .orange)
                        Button("添加引用") { model.addInclude() }
                    } else {
                        CapsuleLabel(text: "已引用", symbol: "checkmark.circle.fill", tint: .green)
                    }
                }
            }

            SettingsSection("配置错误") {
                if model.configErrors.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text("当前配置没有错误")
                        Spacer()
                        reloadButton
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(model.configErrors.enumerated()), id: \.offset) { _, error in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text(error)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsDivider()
                    HStack {
                        Text("共 \(model.configErrors.count) 个错误")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        reloadButton
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            SettingsSection("恢复") {
                SettingsRow(
                    title: "恢复设置页的全部修改",
                    note: model.overrides.isEmpty
                        ? "设置页目前没有修改任何选项"
                        : "共 \(model.overrides.count) 项，恢复后使用主配置中的值"
                ) {
                    Button("恢复全部…") { confirmingResetAll = true }
                        .disabled(model.overrides.isEmpty)
                }
            }
        }
        .alert("恢复全部设置？", isPresented: $confirmingResetAll) {
            Button("全部恢复", role: .destructive) { model.resetAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空 \(GUIConfigFile.fileName) 中由设置页写入的全部修改，恢复为主配置中的值。")
        }
    }

    private var reloadButton: some View {
        Button {
            model.reloadConfiguration()
        } label: {
            Label("重新加载配置", systemImage: "arrow.clockwise")
        }
    }
}

private struct FileRow: View {
    let title: String
    let symbol: String
    let url: URL

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: url.path)
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            if !exists {
                CapsuleLabel(text: "尚未创建")
            }
            Button("打开") { NSWorkspace.shared.openInTextEditor(url) }
                .disabled(!exists)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .disabled(!exists)
            .help("在访达中显示")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
