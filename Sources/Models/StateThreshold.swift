import Foundation

/// 状态阈值。
///
/// **建这层的原因**：「多饿才算饿」原来散在 4 个地方各写一份 ——
/// `PetState.dominantNeed`(0.35)、`PetLines.pickCategory`(0.15/0.4)、
/// `PetLineContext.chineseStateDescription`(0.25/0.5)、
/// 以及 `englishStateDescription`(0.25/0.5)。
///
/// 最后两处尤其危险：**中英文 prompt 各写一份，必须手动保持同步**。
/// 改了中文忘了英文，AI 台词在两种语言下会描述出不同的宠物状态。
///
/// 现在集中在一处，并提供 `level(_:)` 把连续值映射成离散档位 ——
/// 描述文案按档位查表，就不会出现「中文说很饿、英文说有点饿」。
enum StateThreshold {

    /// 状态档位。从坏到好。
    enum Level: Int, Comparable, CaseIterable {
        case critical = 0   // 告急
        case low            // 偏低
        case ok             // 正常
        case high           // 良好

        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// 把 0...1 的状态值映射成档位。
    ///
    /// 分界点沿用原来 AI prompt 的 0.25/0.5/0.8，那套是最细的。
    static func level(_ value: Double) -> Level {
        if value < critical { return .critical }
        if value < low { return .low }
        if value < high { return .ok }
        return .high
    }

    /// 告急线。低于此值算「很饿/很脏/很无聊」。
    static let critical = 0.25
    /// 偏低线
    static let low = 0.5
    /// 良好线。高于此值算「开心」。
    static let high = 0.8

    // MARK: - 各处的专用阈值
    //
    // 这些和上面的通用档位是不同的判断，**不该强行合并** ——
    // 「HUD 该不该报警」和「AI 该怎么描述」本来就是两个问题，
    // 硬凑成一套会让某一边的手感变差。

    /// HUD 报警线：三维里最低的一维低于此值才显示需求图标。
    ///
    /// 比 `low` 宽松（0.35 vs 0.5）—— 状态栏一直报警会让人焦虑，
    /// 只在确实需要照顾时提示。
    static let hudAlert = 0.35

    /// 台词「极度」档。比 `critical` 更严 —— 台词是低频触发，
    /// 只在真的很惨时才说重话。
    static let lineUrgent = 0.15
    /// 台词「一般」档
    static let lineMild = 0.4
    /// 台词「开心」档
    static let lineHappy = 0.75
}
