import Foundation

public enum Direction: String, CaseIterable, Sendable {
    case chineseToForeign
    case foreignToChinese
}

public enum Focus: Equatable, Sendable {
    case candidates
    case translation
}

public enum Key: Equatable, Sendable {
    case character(Character)
    case space, backspace, enter, tab, shiftTab, up, down, left, right, escape
}

public enum ComposerAction: Equatable, Sendable {
    case passThrough
    case update
    case commit(String)
    /// 译文可能尚未就绪，由调用方决定等待还是立即提交。
    case commitTranslation
    case cancel
}

public enum TranslationState: Equatable, Sendable {
    case none
    case done(source: String, text: String)
    case failed(source: String, message: String)
}

public struct EngineState: Equatable, Sendable {
    /// 用户实际敲下的按键（双拼时是双拼字母，不是 preedit 里的全拼）
    public var rawInput = ""
    public var preedit = ""
    /// 已确认的分段（preedit 中 sel_start 之前的部分）
    public var confirmedText = ""
    public var candidates: [String] = []
    public var highlightedIndex = 0
    public var isLastPage = true

    public init(
        rawInput: String = "",
        preedit: String = "",
        confirmedText: String = "",
        candidates: [String] = [],
        highlightedIndex: Int = 0,
        isLastPage: Bool = true
    ) {
        self.rawInput = rawInput
        self.preedit = preedit
        self.confirmedText = confirmedText
        self.candidates = candidates
        self.highlightedIndex = highlightedIndex
        self.isLastPage = isLastPage
    }

    public var isComposing: Bool { !preedit.isEmpty }
}

/// 拼音转换引擎（rime）的抽象，便于用假引擎测试 Composer。
@MainActor
public protocol ConversionEngine: AnyObject {
    var state: EngineState { get }
    /// 返回引擎是否消费了该按键
    func process(_ key: Key) -> Bool
    /// 取出并清空引擎产生的上屏文本
    func takeCommit() -> String?
    func selectCandidate(at index: Int)
    func highlightCandidate(at index: Int)
    func changePage(backward: Bool)
    /// 强制结束输入，返回应上屏的文本
    func commitComposition() -> String?
    func clear()
}

/// 输入状态机。中→英模式由 ConversionEngine 提供候选；英→中模式唯一候选就是原始英文。
@MainActor
public struct Composer {
    public let direction: Direction
    private let engine: (any ConversionEngine)?
    private var englishInput = ""
    public private(set) var focus: Focus = .candidates
    public private(set) var translation: TranslationState = .none

    /// engine 为 nil 时为英→中模式
    public init(engine: (any ConversionEngine)? = nil) {
        self.engine = engine
        direction = engine == nil ? .foreignToChinese : .chineseToForeign
    }

    public var isComposing: Bool { engine?.state.isComposing ?? !englishInput.isEmpty }

    public var markedText: String { engine?.state.preedit ?? englishInput }

    /// 原样按键，切到直接英文时上屏（拼音模式下误打的英文单词可以这样直接出）
    public var rawInput: String { engine?.state.rawInput ?? englishInput }

    public var candidates: [String] {
        if let engine { return engine.state.candidates }
        return englishInput.isEmpty ? [] : [englishInput]
    }

    public var highlightedIndex: Int { engine?.state.highlightedIndex ?? 0 }

    /// 待提交文本 = 已确认分段 + 当前高亮候选，也是译文行翻译的对象。
    public var pendingText: String {
        guard let state = engine?.state else { return englishInput }
        let highlighted = state.candidates.indices.contains(state.highlightedIndex)
            ? state.candidates[state.highlightedIndex] : ""
        return state.confirmedText + highlighted
    }

    public var freshTranslation: String? {
        if case let .done(source, text) = translation, source == pendingText { return text }
        return nil
    }

    public var freshTranslationError: String? {
        if case let .failed(source, message) = translation, source == pendingText { return message }
        return nil
    }

    public mutating func handle(_ key: Key) -> ComposerAction {
        guard let engine else { return handleEnglish(key) }
        return handlePinyin(key, engine: engine)
    }

    public mutating func selectCandidate(at index: Int) -> ComposerAction {
        guard let engine else {
            guard candidates.indices.contains(index) else { return .update }
            return .commit(candidates[index])
        }
        focus = .candidates
        engine.selectCandidate(at: index)
        return afterEngine(engine, handled: true)
    }

    /// 系统要求结束输入（如点击别处）时应上屏的文本。
    public mutating func forceCommitText() -> String {
        guard let engine else { return englishInput }
        return engine.commitComposition() ?? ""
    }

    /// 异步翻译结果回来时调用；原文已变化的过期结果直接丢弃。
    public mutating func applyTranslation(_ text: String, for source: String) {
        guard source == pendingText else { return }
        translation = .done(source: source, text: text)
    }

    public mutating func applyTranslationFailure(_ message: String, for source: String) {
        guard source == pendingText else { return }
        translation = .failed(source: source, message: message)
    }

    public mutating func reset() {
        englishInput = ""
        focus = .candidates
        translation = .none
        engine?.clear()
    }

    // MARK: 中→英

    private mutating func handlePinyin(_ key: Key, engine: any ConversionEngine) -> ComposerAction {
        if focus == .translation {
            switch key {
            case .space, .enter:
                return .commitTranslation
            case .escape, .up, .shiftTab:
                focus = .candidates
                return .update
            case .tab, .down, .left, .right:
                return .update
            case .character, .backspace:
                focus = .candidates
            }
        }

        // 空闲时全部交给 rime：字母开始输入，标点转成中文标点直接上屏
        guard engine.state.isComposing else {
            return afterEngine(engine, handled: engine.process(key))
        }

        switch key {
        case .tab, .down:
            focus = .translation
            return .update
        case .up, .shiftTab:
            return .update
        case .left:
            moveHighlight(engine, by: -1)
            return .update
        case .right:
            moveHighlight(engine, by: 1)
            return .update
        default:
            return afterEngine(engine, handled: engine.process(key))
        }
    }

    private func moveHighlight(_ engine: any ConversionEngine, by offset: Int) {
        let state = engine.state
        let target = state.highlightedIndex + offset
        if target < 0 {
            engine.changePage(backward: true)
            engine.highlightCandidate(at: engine.state.candidates.count - 1)
        } else if target >= state.candidates.count {
            guard !state.isLastPage else { return }
            engine.changePage(backward: false)
            engine.highlightCandidate(at: 0)
        } else {
            engine.highlightCandidate(at: target)
        }
    }

    private mutating func afterEngine(_ engine: any ConversionEngine, handled: Bool) -> ComposerAction {
        if let text = engine.takeCommit() {
            return .commit(text)
        }
        if engine.state.isComposing {
            return .update
        }
        return handled ? .cancel : .passThrough
    }

    // MARK: 英→中

    private mutating func handleEnglish(_ key: Key) -> ComposerAction {
        guard isComposing else {
            if case let .character(c) = key, c.isASCII, c.isLetter {
                englishInput.append(c)
                return .update
            }
            return .passThrough
        }

        switch key {
        case let .character(c):
            englishInput.append(c)
            focus = .candidates
            return .update
        case .space:
            if focus == .translation { return .commitTranslation }
            englishInput.append(" ")
            return .update
        case .backspace:
            englishInput.removeLast()
            focus = .candidates
            if englishInput.isEmpty {
                reset()
                return .cancel
            }
            return .update
        case .enter:
            return focus == .translation ? .commitTranslation : .commit(pendingText)
        case .tab, .down:
            focus = .translation
            return .update
        case .shiftTab, .up:
            focus = .candidates
            return .update
        case .escape:
            if focus == .translation {
                focus = .candidates
                return .update
            }
            reset()
            return .cancel
        case .left, .right:
            return .update
        }
    }
}
