import AppKit
import InputMethodKit
import YiKeyCore

/// IMKit 在主线程回调，但 SDK 未标注 actor 隔离，所以覆写方法标 nonisolated 再断言回主线程。
@MainActor
@objc(YiKeyInputController)
final class InputController: IMKInputController {
    private static let debounce: Duration = .milliseconds(250)
    private static let commitWaitTimeout: Duration = .seconds(1)
    private static let notFound = NSRange(location: NSNotFound, length: 0)

    private lazy var rimeEngine = RimeEngine()
    private lazy var composer = makeComposer(for: Self.currentDirection())
    private var translationTask: Task<Void, Never>?
    private var requestedSource: String?
    private var commitWhenTranslated = false
    private var commitTimeoutTask: Task<Void, Never>?
    private var languagePackMissing = false

    /// 直接英文模式在所有输入会话间共享，和系统输入法的中英状态一致
    private static var directEnglish = false
    private static let shiftTapMaxDuration: TimeInterval = 0.5
    private var shiftPressedAt: Date?

    private var panel: CandidatePanel { .shared }

    // MARK: IMKit 回调

    nonisolated override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    nonisolated override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        MainActor.assumeIsolated {
            if event?.type == .flagsChanged {
                return handleFlagsChanged(event, client: sender as? IMKTextInput)
            }
            return handleKeyDown(event, client: sender as? IMKTextInput)
        }
    }

    nonisolated override func commitComposition(_ sender: Any!) {
        MainActor.assumeIsolated {
            guard composer.isComposing, let client = sender as? IMKTextInput else { return reset() }
            commit(composer.forceCommitText(), to: client)
        }
    }

    nonisolated override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        MainActor.assumeIsolated { syncSettings() }
    }

    nonisolated override func menu() -> NSMenu! {
        // NSMenu 不是 Sendable，不能直接作为 assumeIsolated 的返回值
        nonisolated(unsafe) var menu: NSMenu?
        MainActor.assumeIsolated { menu = buildMenu() }
        return menu
    }

    nonisolated override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        MainActor.assumeIsolated { reset() }
        super.deactivateServer(sender)
    }

    // MARK: 按键

    private func handleFlagsChanged(_ event: NSEvent?, client: IMKTextInput?) -> Bool {
        guard let event, let client else { return false }
        switch event.keyCode {
        case Self.keyCodeShiftLeft, Self.keyCodeShiftRight:
            handleShift(event, client: client)
            return false
        case Self.keyCodeCapsLock:
            // 直接英文模式下 Caps Lock 是普通的大写锁定
            guard !Self.directEnglish else { return false }
            return switchDirectionByCapsLock(event, client: client)
        default:
            shiftPressedAt = nil
            return false
        }
    }

    /// 单按 Shift（按下后 0.5s 内松开，中间没有按其他键）切换直接英文
    private func handleShift(_ event: NSEvent, client: IMKTextInput) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if modifiers == .shift {
            shiftPressedAt = Date()
            return
        }
        defer { shiftPressedAt = nil }
        guard modifiers.isEmpty, let pressedAt = shiftPressedAt,
              Date().timeIntervalSince(pressedAt) < Self.shiftTapMaxDuration else { return }
        toggleDirectEnglish(client)
    }

    private func toggleDirectEnglish(_ client: IMKTextInput) {
        if Self.directEnglish {
            Self.directEnglish = false
            let direction = Self.currentDirection()
            switchDirection(to: direction, client: client)
            panel.flash(direction.label, cursorRect: cursorRect(of: client))
        } else {
            if composer.isComposing { commit(composer.rawInput, to: client) }
            Self.directEnglish = true
            panel.flash("英文", cursorRect: cursorRect(of: client))
        }
    }

    /// Caps Lock 灯亮 = 外语→中文（键盘直接打外语），灯灭 = 中文→外语（拼音输入）
    private func switchDirectionByCapsLock(_ event: NSEvent, client: IMKTextInput) -> Bool {
        let direction = Self.direction(capsLockOn: event.modifierFlags.contains(.capsLock))
        guard direction != composer.direction else { return true }
        if composer.isComposing { commit(composer.forceCommitText(), to: client) }
        switchDirection(to: direction, client: client)
        panel.flash(direction.label, cursorRect: cursorRect(of: client))
        return true
    }

    private static func direction(capsLockOn: Bool) -> Direction {
        capsLockOn ? .foreignToChinese : .chineseToForeign
    }

    private static func currentDirection() -> Direction {
        direction(capsLockOn: NSEvent.modifierFlags.contains(.capsLock))
    }

    private func handleKeyDown(_ event: NSEvent?, client: IMKTextInput?) -> Bool {
        shiftPressedAt = nil
        guard let event, event.type == .keyDown, let client, !Self.directEnglish else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !modifiers.isDisjoint(with: [.command, .control, .option]) {
            // 组合键交给 App 处理；正在输入时先把当前内容上屏，避免快捷键作用在 marked text 上
            if composer.isComposing { commit(composer.forceCommitText(), to: client) }
            return false
        }

        guard let key = Self.key(for: event, modifiers: modifiers) else {
            return composer.isComposing
        }
        if composer.direction == .chineseToForeign, !RimeRuntime.shared.isReady,
           case let .character(c) = key, c.isASCII, c.isLetter {
            panel.flash("词库部署中，请稍候…", cursorRect: cursorRect(of: client))
            return true
        }
        return perform(composer.handle(key), client: client)
    }

    private static let keyCodeCapsLock: UInt16 = 57
    private static let keyCodeShiftLeft: UInt16 = 56
    private static let keyCodeShiftRight: UInt16 = 60

    private static func key(for event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Key? {
        let shift = modifiers.contains(.shift)
        switch event.keyCode {
        case 36, 76: return .enter
        case 48: return shift ? .shiftTab : .tab
        case 49: return .space
        case 51: return .backspace
        case 53: return .escape
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default:
            guard let chars = event.characters, chars.count == 1, let c = chars.first,
                  c.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else { return nil }
            // Caps Lock 用来切换方向，不应让英文输入变成大写，大小写只由 Shift 决定
            if modifiers.contains(.capsLock), c.isLetter {
                return .character(Character(shift ? c.uppercased() : c.lowercased()))
            }
            return .character(c)
        }
    }

    @discardableResult
    private func perform(_ action: ComposerAction, client: IMKTextInput) -> Bool {
        switch action {
        case .passThrough:
            return false
        case .update:
            render(client)
            scheduleTranslation()
        case let .commit(text):
            commit(text, to: client)
        case .commitTranslation:
            commitTranslation(client)
        case .cancel:
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: Self.notFound)
            reset()
        }
        return true
    }

    // MARK: 上屏

    private func commit(_ text: String, to client: IMKTextInput) {
        client.insertText(text, replacementRange: Self.notFound)
        reset()
    }

    private func commitTranslation(_ client: IMKTextInput) {
        if let text = composer.freshTranslation {
            return commit(text, to: client)
        }
        if composer.freshTranslationError != nil {
            return translationUnavailable()
        }
        commitWhenTranslated = true
        scheduleTranslation(immediate: true)
        commitTimeoutTask?.cancel()
        commitTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.commitWaitTimeout)
            guard !Task.isCancelled, let self, self.commitWhenTranslated else { return }
            self.commitWhenTranslated = false
            NSSound.beep()
        }
    }

    /// 语言包缺失时打开设置窗口引导下载，其他错误只提示音
    private func translationUnavailable() {
        if languagePackMissing {
            SettingsWindowController.shared.show()
        } else {
            NSSound.beep()
        }
    }

    private func reset() {
        composer.reset()
        translationTask?.cancel()
        translationTask = nil
        requestedSource = nil
        commitWhenTranslated = false
        commitTimeoutTask?.cancel()
        commitTimeoutTask = nil
        panel.hide()
    }

    // MARK: 翻译

    private func scheduleTranslation(immediate: Bool = false) {
        let source = composer.pendingText
        let direction = composer.direction
        guard source != requestedSource else { return }
        requestedSource = source
        translationTask?.cancel()
        if let cached = AppleTranslator.shared.cachedTranslation(source, direction: direction) {
            translationTask = nil
            return didTranslate(.success(cached), for: source)
        }
        translationTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: Self.debounce)
                guard !Task.isCancelled else { return }
            }
            let result: Result<String, Error>
            do {
                result = .success(try await AppleTranslator.shared.translate(source, direction: direction))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            self.didTranslate(result, for: source)
        }
    }

    private func didTranslate(_ result: Result<String, Error>, for source: String) {
        languagePackMissing = false
        switch result {
        case let .success(text):
            composer.applyTranslation(text, for: source)
        case let .failure(error):
            languagePackMissing = error is TranslatorError
            log.error("翻译失败: \(error.localizedDescription, privacy: .public)")
            composer.applyTranslationFailure(error.localizedDescription, for: source)
        }

        guard let client = client() else { return }
        if commitWhenTranslated {
            if let text = composer.freshTranslation {
                return commit(text, to: client)
            }
            if composer.freshTranslationError != nil {
                commitWhenTranslated = false
                translationUnavailable()
            }
        }
        render(client)
    }

    // MARK: 渲染

    private func render(_ client: IMKTextInput) {
        let text = composer.markedText
        client.setMarkedText(
            text,
            selectionRange: NSRange(location: (text as NSString).length, length: 0),
            replacementRange: Self.notFound
        )

        panel.onSelectCandidate = { [weak self] index in self?.selectCandidate(index) }
        panel.onCommitTranslation = { [weak self] in
            guard let self, let client = self.client() else { return }
            self.commitTranslation(client)
        }
        panel.show(panelModel(), cursorRect: cursorRect(of: client))
    }

    private func cursorRect(of client: IMKTextInput) -> NSRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect
    }

    private func selectCandidate(_ index: Int) {
        guard let client = client() else { return }
        perform(composer.selectCandidate(at: index), client: client)
    }

    private func panelModel() -> CandidatePanelModel {
        var model = CandidatePanelModel(
            candidates: composer.candidates,
            highlightedIndex: composer.highlightedIndex,
            focus: composer.focus
        )
        if let text = composer.freshTranslation {
            model.translation = text
            model.translationDimmed = false
        } else if let message = composer.freshTranslationError {
            model.translation = message
        } else if composer.pendingText.isEmpty {
            model.translation = ""
        } else if case let .done(_, staleText) = composer.translation {
            // 新译文到达前保留旧译文并置灰，避免闪烁
            model.translation = staleText
        } else {
            model.translation = "…"
        }
        return model
    }

    // MARK: 设置

    private func makeComposer(for direction: Direction) -> Composer {
        direction == .chineseToForeign ? Composer(engine: rimeEngine) : Composer()
    }

    private func switchDirection(to direction: Direction, client: IMKTextInput?) {
        guard direction != composer.direction else { return }
        if composer.isComposing {
            client?.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: Self.notFound)
        }
        reset()
        composer = makeComposer(for: direction)
    }

    /// 切换 App 期间 Caps Lock 或设置可能变过，激活时同步
    private func syncSettings() {
        let direction = Self.currentDirection()
        switchDirection(to: direction, client: client())
        if direction == .chineseToForeign {
            rimeEngine.selectScheme(Preferences.schemeID)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let current = Self.directEnglish ? "直接英文（Shift 切换）" : "\(composer.direction.label)（Caps Lock 切换）"
        menu.addItem(NSMenuItem(title: "当前：\(current)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(showSettings(_:)), keyEquivalent: ""))
        return menu
    }

    @objc private func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }
}
