import SwiftUI

#if DEBUG

/// 调试面板。用来验证「时间戳驱动」是否正确——把时间往前推，
/// 数值应该立刻跟着掉，而不需要 app 在后台跑任何东西。
///
/// **只在 Debug 编译。** 正式版没有入口，也没有这些符号。
struct DebugPanel: View {
    let store: PetStore
    let onResetRoom: () -> Void

    /// 当前语言的显示名（母语名），跟随系统时显示"跟随系统"。
    private var currentLanguageName: String {
        let m = LocalizationManager.shared
        if m.isFollowingSystem { return L("language.system") }
        return AppLanguage.all.first { $0.code == m.selectedCode }?.endonym
            ?? m.selectedCode
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("模拟时间流逝") {
                    Button("前进 1 小时") { store.debugAge(by: 3600) }
                    Button("前进 4 小时") { store.debugAge(by: 4 * 3600) }
                    Button("前进 1 天")  { store.debugAge(by: 86400) }
                }
                Section("宠物") {
                    Picker("品种", selection: Binding(
                        get: { store.pet.breedID },
                        set: { store.choose(breedID: $0, colorIndex: store.pet.colorIndex) }
                    )) {
                        ForEach(PetBreed.all) { b in
                            Text(verbatim: L(b.nameKey)).tag(b.id)
                        }
                    }
                    Picker("毛色", selection: Binding(
                        get: { store.pet.colorIndex },
                        set: { store.choose(breedID: store.pet.breedID, colorIndex: $0) }
                    )) {
                        ForEach(0..<store.pet.breed.colorCount, id: \.self) { i in
                            Text("毛色 \(i + 1)").tag(i)
                        }
                    }
                    Picker("阶段(调试)", selection: Binding(
                        get: { store.pet.stage },
                        set: { store.debugSetStage($0) }
                    )) {
                        ForEach(PetStage.allCases, id: \.self) { st in
                            Text(verbatim: L(st.displayNameKey)).tag(st)
                        }
                    }
                }
                Section("金币账本") {
                    let l = store.wallet.ledger
                    LabeledContent("余额") { Text(verbatim: "\(l.balance)") }
                    LabeledContent("累计收入") { Text(verbatim: "\(l.totalIn)") }
                    LabeledContent("累计支出") { Text(verbatim: "\(l.totalOut)") }
                    LabeledContent("账目") {
                        Text(verbatim: l.isBalanced
                             ? "平"
                             : "不平！\(l.totalIn) - \(l.totalOut) ≠ \(l.balance)")
                            .foregroundStyle(l.isBalanced ? Color.secondary : Color.red)
                    }
                    NavigationLink("流水（最近 \(l.recent.count) 笔）") {
                        CoinTraceView(entries: l.recent)
                    }
                }
                Section("房间") {
                    Text("长按家具可拖动位置")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("重置家具布局") { onResetRoom() }
                }
                Section {
                    Button("重置状态", role: .destructive) { store.resetAll() }
                }
                Section {
                    NavigationLink {
                        LanguagePickerView()
                    } label: {
                        HStack {
                            Text(verbatim: L("settings.language"))
                            Spacer()
                            Text(verbatim: currentLanguageName)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(verbatim: L("settings.language"))
                } footer: {
                    Text(verbatim: L("settings.language.footer"))
                        .font(.caption2)
                }

                Section("素材授权") {
                    NavigationLink("Credits") { CreditsView() }
                }
            }
            .navigationTitle("调试")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#endif

/// 金币流水（调试）。
///
/// 存在的理由很具体：用户问「为什么我有 10098 金币」时，
/// 之前只能靠翻 claimedRewards 人肉推断。现在直接看这一页。
struct CoinTraceView: View {
    let entries: [CoinEntry]

    var body: some View {
        List {
            if entries.isEmpty {
                Text("暂无流水").foregroundStyle(.secondary)
            }
            // 倒序 —— 最近的在最上面
            ForEach(Array(entries.enumerated().reversed()), id: \.offset) { _, e in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(verbatim: label(e.reason))
                        Spacer()
                        Text(verbatim: e.signed > 0 ? "+\(e.amount)" : "-\(e.amount)")
                            .foregroundStyle(e.reason.isIncome ? .green : .red)
                            .monospacedDigit()
                    }
                    HStack(spacing: 6) {
                        Text(e.at, format: .dateTime.month().day().hour().minute())
                        if let n = e.note { Text(verbatim: n) }
                        Spacer()
                        Text(verbatim: "余 \(e.balance)").monospacedDigit()
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("金币流水")
    }

    private func label(_ r: CoinReason) -> String {
        switch r {
        case .offlineCare:    return "看家收益"
        case .loginBonus:     return "上线奖励"
        case .achievement:    return "成就"
        case .initialGrant:   return "启动资金"
        case .food:           return "买食物"
        case .starterPet:     return "首只宠物"
        case .breedPurchase:  return "买品种"
        case .debugGrant:     return "调试发钱"
        }
    }
}
