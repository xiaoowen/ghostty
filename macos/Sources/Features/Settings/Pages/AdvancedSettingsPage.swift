import AppKit
import SwiftUI

/// 高级: config files, current configuration errors and resetting.
struct AdvancedSettingsPage: View {
    @ObservedObject var model: SettingsModel

    @State private var confirmingResetAll = false

    var body: some View {
        Form {
            Section {
                FileRow(title: "主配置", url: model.mainConfigURL)
                FileRow(title: "设置页的修改", url: model.guiConfigURL)
                LabeledContent("引用") {
                    if model.includeMissing {
                        HStack(spacing: 10) {
                            Label("未引用", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .fixedSize()
                            Button("添加引用") { model.addInclude() }
                        }
                    } else {
                        Label("已引用", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            } header: {
                Text("配置文件")
            } footer: {
                Text("设置页只写 \(GUIConfigFile.fileName)。它在主配置之后加载，所以同名选项以设置页为准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if model.configErrors.isEmpty {
                    Label("当前配置没有错误", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.configErrors.enumerated()), id: \.offset) { _, error in
                        Text(error)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Spacer()
                    Button("重新加载配置") { model.reloadConfiguration() }
                }
            } header: {
                Text("配置错误")
            }

            Section {
                LabeledContent {
                    Button("恢复全部…") { confirmingResetAll = true }
                        .disabled(model.overrides.isEmpty)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("恢复设置页的全部修改")
                        Text(model.overrides.isEmpty
                             ? "设置页目前没有修改任何选项"
                             : "共 \(model.overrides.count) 项，恢复后使用主配置中的值")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("恢复")
            }
        }
        .formStyle(.grouped)
        .alert("恢复全部设置？", isPresented: $confirmingResetAll) {
            Button("全部恢复", role: .destructive) { model.resetAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空 \(GUIConfigFile.fileName) 中由设置页写入的全部修改，恢复为主配置中的值。")
        }
    }
}

private struct FileRow: View {
    let title: String
    let url: URL

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: url.path)
        LabeledContent {
            HStack(spacing: 8) {
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(exists ? HierarchicalShapeStyle.primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button("打开") { NSWorkspace.shared.openInTextEditor(url) }
                    .disabled(!exists)
                Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .disabled(!exists)
            }
        } label: {
            Text(title)
        }
    }
}
