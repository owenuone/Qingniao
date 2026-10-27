import AppKit
import SwiftUI
import Translation
import YiKeyCore

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        // 每次打开重建视图，确保显示的是最新设置（输入法菜单里也能改方案）
        let hosting = NSHostingController(rootView: SettingsView())
        window.contentViewController = hosting
        // 先按 SwiftUI 内容定好尺寸再居中，否则用的是 0×0 的初始尺寸
        window.setContentSize(hosting.view.fittingSize)
        // 不用 center()：它会刻意放在中心偏上的位置
        if let visible = NSScreen.main?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        }
        // 从输入法菜单打开时前台是别的 App，系统常会拒绝激活；orderFrontRegardless 保证窗口仍显示在最前
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "译键设置"
        // 标题栏透明，毛玻璃背景延伸到标题栏下面
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // 后台应用激活时系统不会切换桌面空间，所以让窗口出现在当前空间（包括全屏应用之上）。
        // 不要设 hidesOnDeactivate：菜单关闭后焦点回到原 App，窗口会被立刻隐藏
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }
}

/// 透出窗口后面内容的毛玻璃；SwiftUI 的 Material 只模糊窗口内部，做不到这一点
private struct WindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct SettingsView: View {
    private enum PackStatus {
        case checking, installed, missing, downloading
    }

    @State private var schemeID = Preferences.schemeID
    @State private var foreignLanguage = Preferences.foreignLanguage
    @State private var packStatus = PackStatus.checking
    @State private var downloadConfiguration: TranslationSession.Configuration?

    var body: some View {
        Form {
            Section("输入方案") {
                Picker("中文输入", selection: $schemeID) {
                    ForEach(Preferences.schemes, id: \.id) { scheme in
                        Text(scheme.name).tag(scheme.id)
                    }
                }
                .onChange(of: schemeID) { _, id in Preferences.schemeID = id }
            }

            Section {
                Picker("外语", selection: $foreignLanguage) {
                    ForEach(Preferences.foreignLanguages, id: \.self) { code in
                        let name = Preferences.languageName(code)
                        Text(Preferences.latinLanguages.contains(code) ? name : "\(name)（仅 中文→外语）").tag(code)
                    }
                }
                .onChange(of: foreignLanguage) { _, code in Preferences.foreignLanguage = code }
                LabeledContent("中文 ⇄ \(Preferences.languageName(foreignLanguage))语言包") {
                    packStatusView
                }
            } header: {
                Text("翻译语言")
            } footer: {
                Text("日、韩、俄、乌克兰、阿拉伯、泰、印地语用键盘打不出原文，只支持 中文 → 外语；Caps Lock 灯亮时按 英语 → 中文 处理。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("快捷键") {
                LabeledContent("Caps Lock", value: "灯灭 中文→外语 / 灯亮 外语→中文")
                LabeledContent("单按 Shift", value: "切换直接英文")
                LabeledContent("↓ / Tab", value: "选中译文行")
                LabeledContent("← / →", value: "切换高亮候选")
                LabeledContent("- / =", value: "翻页")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(WindowBlur().ignoresSafeArea())
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: foreignLanguage) { await refreshPackStatus() }
        .translationTask(downloadConfiguration) { session in
            // prepareTranslation 会弹出系统的语言包下载确认
            do {
                try await session.prepareTranslation()
            } catch {
                log.error("下载语言包失败: \(error.localizedDescription, privacy: .public)")
            }
            await refreshPackStatus()
        }
    }

    @ViewBuilder
    private var packStatusView: some View {
        switch packStatus {
        case .checking:
            ProgressView().controlSize(.small)
        case .installed:
            Label("已下载", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .downloading:
            ProgressView().controlSize(.small)
        case .missing:
            Button("下载") { startDownload() }
        }
    }

    private func startDownload() {
        packStatus = .downloading
        let (source, target) = AppleTranslator.languages(for: .chineseToForeign, foreign: foreignLanguage)
        if downloadConfiguration?.target == target {
            downloadConfiguration?.invalidate()
        } else {
            downloadConfiguration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    @MainActor
    private func refreshPackStatus() async {
        packStatus = .checking
        let installed = await AppleTranslator.shared.languagesInstalled(foreign: foreignLanguage)
        packStatus = installed ? .installed : .missing
    }
}
