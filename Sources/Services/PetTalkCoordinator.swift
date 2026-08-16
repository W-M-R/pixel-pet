import Foundation
import Observation

/// 宠物说话的调度器。
///
/// 职责很小：选台词、防刷屏、给 UI 一个可观察的 `currentLine`。
///
/// 台词内容本身由 `PetLines` 按状态查表决定 —— 那是纯函数，
/// 调度器只管「什么时候说」。
///
/// 曾经这里还负责调度设备端 AI 生成台词（350M 模型），
/// 结构是「预写台词立刻出，AI 后到就替换」。已整个移除：
/// 模型 175MB、常驻内存 1.4GB，而预写台词在这个体量的 app 里
/// 表现并不差 —— 收益完全撑不起成本。
@Observable
@MainActor
final class PetTalkCoordinator {

    /// 当前要显示的台词。nil = 不显示气泡。
    private(set) var currentLine: String?

    private var lastSpokeAt: Date?

    /// 台词最短间隔。防止连续戳宠物时气泡刷屏。
    private let cooldown: TimeInterval = 4

    /// 触发说话。
    /// - Parameters:
    ///   - context: 宠物状态快照
    ///   - absentDays: 距上次打开过了几天，用于"久别重逢"台词
    ///   - force: 无视冷却（比如用户主动点击时）
    @discardableResult
    func speak(_ context: PetLineContext, absentDays: Int = 0, force: Bool = false) -> Bool {
        if !force, let last = lastSpokeAt,
           Date().timeIntervalSince(last) < cooldown {
            return false
        }
        lastSpokeAt = Date()
        currentLine = PetLines.line(for: context, absentDays: absentDays)
        return true
    }

    /// 气泡显示完毕后清掉，避免旧台词残留。
    func clearLine() {
        currentLine = nil
    }
}
