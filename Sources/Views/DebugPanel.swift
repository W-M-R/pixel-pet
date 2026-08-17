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
                Section {
                    Button("前进 1 小时") { store.debugAge(by: 3600) }
                    Button("前进 4 小时") { store.debugAge(by: 4 * 3600) }
                    Button("前进 1 天")   { store.debugAge(by: 86400) }
                    Button("前进 3 天")   { store.debugAge(by: 3 * 86400) }
                    Button("前进 1 周")   { store.debugAge(by: 7 * 86400) }
                    Button("前进 30 天")  { store.debugAge(by: 30 * 86400) }
                } header: {
                    Text("模拟时间流逝")
                } footer: {
                    Text("同时推进全部宠物的状态、年龄和上次结算时间。"
                         + "回到主页会触发离线收益结算。")
                }

                Section {
                    Button("+1000 金币")  { store.debugAddCoins(1000) }
                    Button("+10000 金币") { store.debugAddCoins(10000) }
                    Button("清空成就记录", role: .destructive) {
                        store.debugResetAchievements()
                    }
                } header: {
                    Text("金币与成就")
                } footer: {
                    Text("发钱走账本记 debugGrant，账目仍然平、流水里查得到。"
                         + "清空成就后可以重新触发，用于验证文案和金额。")
                }

                Section {
                    Button("饿透") { store.debugSetStats(satiety: 0) }
                    Button("心情见底") { store.debugSetStats(mood: 0) }
                    Button("脏透") { store.debugSetStats(hygiene: 0) }
                    Button("三维拉满") {
                        store.debugSetStats(satiety: 1, mood: 1, hygiene: 1)
                    }
                    Button("全部压到一半") {
                        store.debugSetStats(satiety: 0.5, mood: 0.5, hygiene: 0.5)
                    }
                } header: {
                    Text("状态（作用于选中那只）")
                } footer: {
                    Text("用于看不同状态下的台词、HUD 报警色、达成率。")
                }
                Section("宠物") {
                    // 选中哪只。品种和毛色不能在这里改 ——
                    // 毛色购买时就定死了，改它会和玩法规则矛盾。
                    Picker("选中", selection: Binding(
                        get: { store.selectedPetID },
                        set: { store.select(petID: $0) }
                    )) {
                        ForEach(store.pets) { p in
                            Text(verbatim: (p.name.isEmpty ? L(p.breed.nameKey) : p.name)
                                 + "（\(L(p.breed.nameKey))）").tag(p.id)
                        }
                    }
                    LabeledContent("共养了") {
                        Text(verbatim: "\(store.pets.count) 只")
                    }
                    Button("白送一只狗") {
                        store.debugAddCoins(PetBreed.dog.price)
                        store.purchase(.dog, colorIndex: 1)
                    }
                    Button("白送一只猫") {
                        store.debugAddCoins(PetBreed.cat.price)
                        store.purchase(.cat, colorIndex: 2)
                    }
                    Button("删掉选中那只", role: .destructive) {
                        store.debugRemoveSelectedPet()
                    }
                    .disabled(store.pets.count < 2)
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
                             : "不平！\(l.totalIn) - \(l.totalOut) != \(l.balance)")
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
        case .furniture:      return "买家具"
        case .debugGrant:     return "调试发钱"
        }
    }
}
