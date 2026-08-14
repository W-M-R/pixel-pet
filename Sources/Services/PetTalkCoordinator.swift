import Foundation
import Observation

/// 宠物说话的调度器。
///
/// 核心设计：**预写台词立刻出，AI 台词后到就替换。**
///
/// 原因是 AI 首句要 2-6 秒（350M 模型 + 无状态推理），
/// 不能让宠物在那儿干等。所以流程是：
///   1. 触发 → 立刻显示预写台词
///   2. 英文环境下同时启动 AI 生成
///   3. AI 出结果且气泡还在显示 → 换成 AI 台词
///
/// 中文环境根本不启动 AI（350M 中文不成句，实测见凭证），
/// 只用预写台词。
@Observable
final class PetTalkCoordinator {

    /// 当前要显示的台词。nil = 不显示气泡。
    private(set) var currentLine: String?
    /// 是否正在后台生成 AI 台词（可以给 UI 做个小指示）
    private(set) var isGenerating = false

    private let engine = PetChatEngine()
    private var generationTask: Task<Void, Never>?
    private var lineToken = 0
    private var lastSpokeAt: Date?

    /// 台词最短间隔。防止连续戳宠物时气泡刷屏。
    private let cooldown: TimeInterval = 4

    var aiAvailability: PetChatEngine.Availability {
        PetChatEngine.availability()
    }

    /// 开关状态。关闭时顺便卸载模型，把内存还回去。
    var aiEnabled: Bool {
        get { PetChatEngine.isEnabled }
        set {
            PetChatEngine.isEnabled = newValue
            if !newValue {
                generationTask?.cancel()
                isGenerating = false
                Task { await engine.unload() }
            }
        }
    }

    /// 收到内存警告时主动卸载 —— 宠物 app 长期挂后台，
    /// 与其被系统整个杀掉，不如先放掉模型。
    func handleMemoryWarning() {
        generationTask?.cancel()
        isGenerating = false
        Task { await engine.unload() }
    }

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
        lineToken += 1
        let token = lineToken

        // 1) 预写台词立刻显示
        currentLine = PetLines.line(for: context, absentDays: absentDays)

        // 2) 英文环境才启动 AI
        generationTask?.cancel()
        guard case .ready = PetChatEngine.availability() else { return true }

        isGenerating = true
        generationTask = Task { [weak self] in
            guard let self else { return }
            let ai = await engine.generateLine(for: context)
            await MainActor.run {
                self.isGenerating = false
                // 只有还是同一次触发才替换，避免旧结果覆盖新台词
                guard token == self.lineToken, self.currentLine != nil,
                      let ai, !Task.isCancelled else { return }
                self.currentLine = ai
            }
        }
        return true
    }

    /// 气泡显示完毕后清掉，避免旧台词残留。
    func clearLine() {
        currentLine = nil
        generationTask?.cancel()
        isGenerating = false
    }

    deinit { generationTask?.cancel() }
}
