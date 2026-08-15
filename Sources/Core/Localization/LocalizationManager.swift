//
//  LocalizationManager.swift
//  In-app language picker — 由 app-i18n skill 提供的落地模板。
//
//  用法：
//   1. 把本文件拷进工程(如 Core/Localization/)。
//   2. 在 @main App 的 init() 里调用 LocalizationManager.shared.applyStoredLanguageAtLaunch()。
//   3. 根视图注入：
//        .environment(\.locale, LocalizationManager.shared.locale)
//        .environment(LocalizationManager.shared)        // 供选择器读写
//        .id(LocalizationManager.shared.refreshID)        // 切换即时重建整树
//   4. 设置页放 LanguagePickerView()。
//   5. 代码里所有「用户可见」字符串统一用本文件的 L("...") 取，而不是
//      String(localized:)（原因见下方「为何需要 L()」）。SwiftUI 的 Text("字面量")
//      因为会读注入的 \.locale 且经过被重定向的 Bundle.main，可保持不变。
//
//  语言列表 AppLanguage.all 必须与工程 CFBundleLocalizations / .xcstrings 实际铺进的语言一致。
//  未翻译的 key 会回退到英文(CFBundleDevelopmentRegion=en)。
//
//  说明：本模板兼容 iOS 17+ (@Observable)。iOS 16 及以下把 @Observable 换成
//  ObservableObject + @Published，@Environment 观察方式相应调整。
//
//  ┌─ 为何需要 L()（本模板与"只写 AppleLanguages"方案的关键区别）────────────────┐
//  │ 常见误区：以为在 init() 里写 UserDefaults["AppleLanguages"]=[code] 就能让       │
//  │ String(localized:) / Bundle.main 在【当前运行的进程内】立刻切到该语言。          │
//  │ 实际上 Foundation 的 String(localized:) 和 Bundle.main 加载哪个 .lproj 是在      │
//  │ 【进程启动时锁定】的——运行中改 AppleLanguages 只对【下次启动】生效，当前进程     │
//  │ 里这些字符串仍是旧语言（这就是"设置里切了语言、很多文案不变"的根因）。            │
//  │ .environment(\.locale) 只影响 SwiftUI Text 的格式化/部分解析，对 String(localized:)│
//  │ 完全无效。                                                                       │
//  │ 正解：把 Bundle.main 的 localizedString(forKey:) 重定向到"所选语言的 .lproj      │
//  │ Bundle"，并让所有代码取字符串走 L()（它经由这条重定向）。这样运行中切换即时生效。 │
//  └──────────────────────────────────────────────────────────────────────────────┘
//

import SwiftUI
import Foundation
import ObjectiveC

// MARK: - 支持的语言（与 skill 默认 20 语言对齐；按需增删，但要和 CFBundleLocalizations 一致）

/// 每种语言用「母语名」(endonym) 展示，方便用户在任何界面语言下找到自己的语言。
struct AppLanguage: Identifiable, Hashable {
    let code: String        // BCP-47 / lproj 语言码，如 "zh-Hans"
    let endonym: String     // 母语显示名，如 "简体中文"
    var id: String { code }

    /// 默认 20 语言（顺序即选择器展示顺序，en 兜底但不必置顶）。
    /// 本 app 目前只有中英两种译文，所以选择器只列这两个 ——
    /// 列出没有译文的语言会让用户切过去看到一堆英文 key，体验更差。
    /// 将来补了译文再往这里加，同时同步 project.yml 的 knownRegions。
    static let all: [AppLanguage] = [
        .init(code: "en",      endonym: "English"),
        .init(code: "zh-Hans", endonym: "简体中文"),
    ]
}

// MARK: - 管理器

@Observable
@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    /// 用户选择的语言码；"" 代表「跟随系统」。
    private(set) var selectedCode: String

    /// 用于强制刷新 SwiftUI 树的 id（切换语言时自增）。
    private(set) var refreshID: Int = 0

    private let storageKey = "app_language"
    private let appleLanguagesKey = "AppleLanguages"

    private init() {
        self.selectedCode = UserDefaults.standard.string(forKey: storageKey) ?? ""
        // 立即把重定向指向当前选择，使 L() 从进程一开始就取对语言。
        Bundle.redirectMain(to: selectedCode)
    }

    /// 是否跟随系统。
    var isFollowingSystem: Bool { selectedCode.isEmpty }

    /// 实际生效的语言码：跟随系统时取系统首选，否则取所选。
    var effectiveLanguageCode: String {
        if selectedCode.isEmpty {
            return Locale.preferredLanguages.first ?? "en"
        }
        return selectedCode
    }

    /// 供 `.environment(\.locale, ...)` 用（影响 SwiftUI 格式化与 Text）。
    var locale: Locale {
        selectedCode.isEmpty ? Locale.autoupdatingCurrent : Locale(identifier: selectedCode)
    }

    /// @main App 的 init() 里调用：既做进程内重定向(当前进程即时)，也写 AppleLanguages(下次启动兜底)。
    func applyStoredLanguageAtLaunch() {
        Bundle.redirectMain(to: selectedCode)
        if selectedCode.isEmpty {
            UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
        } else {
            UserDefaults.standard.set([selectedCode], forKey: appleLanguagesKey)
        }
    }

    /// 运行时切换语言（选择器调用）。传 "" = 跟随系统。
    func setLanguage(_ code: String) {
        selectedCode = code
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
        } else {
            UserDefaults.standard.set(code, forKey: storageKey)
            UserDefaults.standard.set([code], forKey: appleLanguagesKey)
        }
        Bundle.redirectMain(to: code)   // 进程内即时切换（关键）
        refreshID += 1                  // 触发根视图重建，即时刷新
    }
}

// MARK: - 本地化取值：统一走 L()

/// 按当前 App 内选定语言取本地化字符串（支持运行时即时切换）。
///
/// key 即 .xcstrings 里的 key（用英文自然句做 key，见 SKILL 阶段1）。
/// 用它取代 `String(localized:)`——后者锁定进程启动语言、不响应运行时切换。
/// 支持格式参数：`L("Used %1$lld of %2$lld", used, total)`。
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    if args.isEmpty { return format }
    return String(format: format, locale: Locale.current, arguments: args)
}

// MARK: - Bundle 重定向（让运行中切换语言即时生效）

/// 拦截本地化查询，转发到「所选语言的 .lproj Bundle」。
private final class RedirectedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let target = objc_getAssociatedObject(self, &Bundle.redirectKey) as? Bundle {
            return target.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    // `nonisolated(unsafe)` 必须：在 SWIFT_STRICT_CONCURRENCY=complete(Swift 6) 下，
    // 普通 static var 会报 "not concurrency-safe"。此处仅作 objc associated-object 的
    // 地址键、从不并发读写其值，标注 unsafe 安全。
    fileprivate nonisolated(unsafe) static var redirectKey: UInt8 = 0

    /// 首次调用时把 Bundle.main 的类替换为拦截子类（仅一次）。
    private static let installOnce: Void = {
        object_setClass(Bundle.main, RedirectedBundle.self)
    }()

    /// 把 Bundle.main 的本地化查询重定向到指定语言的 .lproj。
    /// 传空 = 跟随系统（清除重定向，走 Bundle.main 原始行为）。
    static func redirectMain(to language: String) {
        _ = installOnce
        var target: Bundle?
        if !language.isEmpty,
           let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let b = Bundle(path: path) {
            target = b
        }
        objc_setAssociatedObject(Bundle.main, &redirectKey, target,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
