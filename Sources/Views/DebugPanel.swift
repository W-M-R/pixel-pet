import SwiftUI

#if DEBUG

/// 调试面板。用来验证「时间戳驱动」是否正确——把时间往前推，
/// 数值应该立刻跟着掉，而不需要 app 在后台跑任何东西。
///
/// **只在 Debug 编译。** 正式版没有入口，也没有这些符号。
struct DebugPanel: View {
    let store: PetStore
    let talk: PetTalkCoordinator
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
