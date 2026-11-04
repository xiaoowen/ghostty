import AppKit

extension NSWorkspace {
    /// Opens a file in the default app for its extension, falling back to the
    /// default text editor, the same way Ghostty opens its config file.
    func openInTextEditor(_ url: URL) {
        if let editor = defaultApplicationURL(forExtension: url.pathExtension) ?? defaultTextEditor {
            open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            open(url)
        }
    }
}
