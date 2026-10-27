import Foundation
import YiKeyCore

struct PinyinScheme {
    let id: String
    let name: String
}

enum Preferences {
    /// 第一个为默认方案
    static let schemes: [PinyinScheme] = [
        PinyinScheme(id: "rime_ice", name: "全拼"),
        PinyinScheme(id: "double_pinyin_flypy", name: "小鹤双拼"),
        PinyinScheme(id: "double_pinyin_mspy", name: "微软双拼"),
        PinyinScheme(id: "double_pinyin", name: "自然码双拼"),
        PinyinScheme(id: "double_pinyin_sogou", name: "搜狗双拼"),
        PinyinScheme(id: "double_pinyin_abc", name: "智能 ABC 双拼"),
        PinyinScheme(id: "double_pinyin_ziguang", name: "紫光双拼"),
        PinyinScheme(id: "double_pinyin_jiajia", name: "拼音加加双拼"),
    ]

    /// 列表来自 macOS 27 的 LanguageAvailability().supportedLanguages（2026-10-27 核对）
    static let latinLanguages = ["en", "de", "fr", "es", "it", "pt", "nl", "pl", "tr", "id", "vi"]
    /// 键盘打不出这些语言的原文，所以只支持中文→外语；外语→中文方向回退为英语→中文
    static let nonLatinLanguages = ["ja", "ko", "ru", "uk", "ar", "th", "hi"]
    static let foreignLanguages = latinLanguages + nonLatinLanguages

    private static let schemeKey = "pinyinScheme"
    private static let foreignLanguageKey = "foreignLanguage"

    static var foreignLanguage: String {
        get {
            let stored = UserDefaults.standard.string(forKey: foreignLanguageKey)
            return foreignLanguages.contains { $0 == stored } ? stored! : foreignLanguages[0]
        }
        set { UserDefaults.standard.set(newValue, forKey: foreignLanguageKey) }
    }

    /// 外语→中文方向实际使用的源语言
    static func inputLanguage(for foreign: String) -> String {
        latinLanguages.contains(foreign) ? foreign : "en"
    }

    static func languageName(_ code: String) -> String {
        Locale(identifier: "zh-Hans").localizedString(forLanguageCode: code) ?? code
    }

    static var schemeID: String {
        get {
            let stored = UserDefaults.standard.string(forKey: schemeKey)
            return schemes.contains { $0.id == stored } ? stored! : schemes[0].id
        }
        set { UserDefaults.standard.set(newValue, forKey: schemeKey) }
    }
}

extension Direction {
    var label: String {
        let foreign = Preferences.foreignLanguage
        return switch self {
        case .chineseToForeign: "中文 → \(Preferences.languageName(foreign))"
        case .foreignToChinese: "\(Preferences.languageName(Preferences.inputLanguage(for: foreign))) → 中文"
        }
    }
}
