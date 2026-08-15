import SwiftUI

/// 宠物设置页：起名、选品种/毛色、看成长与统计、通知开关。
///
/// 这是玩法的主入口 —— 之前这些只能在调试面板里改，
/// 而「给宠物起名」是产生依恋的第一步，不该藏在调试里。
struct PetSettingsView: View {
    let store: PetStore
    let talk: PetTalkCoordinator

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String = ""
    @State private var notifyOn: Bool = PetNotifications.isEnabled
    @State private var notifyDenied = false

    private var pet: PetState { store.pet }

    private var claimedCount: Int {
        AchievementRule.all.filter { store.isClaimed($0) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                nameSection
                breedSection
                growthSection
                statsSection
                notificationSection

                Section {
                    NavigationLink {
                        AchievementsView(store: store)
                    } label: {
                        HStack {
                            Text(verbatim: L("achv.title"))
                            Spacer()
                            Text(verbatim: "\(claimedCount) / \(AchievementRule.all.count)")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink(L("settings.language")) { LanguagePickerView() }
                    NavigationLink(L("credits.title")) { CreditsView() }
                }
            }
            .navigationTitle(L("settings.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) { commitName(); dismiss() }
                }
            }
            .onAppear { draftName = pet.name }
        }
    }

    // MARK: - 起名

    private var nameSection: some View {
        Section {
            TextField(L("settings.name.placeholder"), text: $draftName)
                .submitLabel(.done)
                .onSubmit { commitName() }
        } header: {
            Text(verbatim: L("settings.name"))
        } footer: {
            Text(verbatim: L("settings.name.footer"))
        }
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != pet.name else { return }
        store.rename(String(trimmed.prefix(12)))
    }

    // MARK: - 品种与毛色

    private var breedSection: some View {
        Section(L("settings.breed")) {
            Picker(L("settings.breed"), selection: Binding(
                get: { pet.breedID },
                set: { store.choose(breedID: $0, colorIndex: 0) }   // 换品种时毛色归零
            )) {
                ForEach(PetBreed.all) { b in
                    Text(verbatim: L(b.nameKey)).tag(b.id)
                }
            }
            .pickerStyle(.segmented)

            // 毛色用色块选，比下拉直观
            HStack(spacing: 10) {
                ForEach(0..<pet.breed.colorCount, id: \.self) { i in
                    Button {
                        store.choose(breedID: pet.breedID, colorIndex: i)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.12))
                            if pet.colorIndex == i {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                            Text(verbatim: "\(i + 1)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                        .frame(height: 38)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 成长

    private var growthSection: some View {
        Section {
            LabeledContent(L("settings.stage")) {
                Text(verbatim: L(pet.stage.displayNameKey))
                    .foregroundStyle(Color.accentColor)
            }
            LabeledContent(L("settings.age")) {
                Text(verbatim: String(format: L("settings.age.value"), pet.ageInDays))
            }
            if let left = pet.stage.daysToNext(from: pet.ageInDays) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: String(format: L("settings.stage.next"), left))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ProgressView(value: stageProgress)
                }
            } else {
                Text(verbatim: L("settings.stage.final"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: L("settings.growth"))
        } footer: {
            Text(verbatim: L("settings.growth.footer"))
        }
    }

    /// 当前阶段内的进度 0...1
    private var stageProgress: Double {
        let all = PetStage.allCases.sorted { $0.minDays < $1.minDays }
        guard let idx = all.firstIndex(of: pet.stage), idx + 1 < all.count else { return 1 }
        let lo = Double(all[idx].minDays)
        let hi = Double(all[idx + 1].minDays)
        guard hi > lo else { return 1 }
        return min(1, max(0, (Double(pet.ageInDays) - lo) / (hi - lo)))
    }

    // MARK: - 统计

    private var statsSection: some View {
        Section(L("settings.stats")) {
            LabeledContent(L("wallet.coins")) {
                HStack(spacing: 4) {
                    Text(verbatim: "🪙")
                    Text(verbatim: "\(store.wallet.coins)")
                        .font(.system(.body, design: .monospaced))
                }
            }
            statRow("stats.streak", value: pet.streakDays ?? 1, unit: "unit.day")
            statRow("stats.feed", value: pet.totalFeedCount ?? 0, unit: "unit.times")
            statRow("stats.play", value: pet.totalPlayCount ?? 0, unit: "unit.times")
            statRow("stats.clean", value: pet.totalCleanCount ?? 0, unit: "unit.times")
        }
    }

    private func statRow(_ key: String, value: Int, unit: String) -> some View {
        LabeledContent(L(key)) {
            Text(verbatim: "\(value) \(L(unit))")
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - 通知

    private var notificationSection: some View {
        Section {
            Toggle(L("settings.notify"), isOn: Binding(
                get: { notifyOn },
                set: { on in
                    notifyOn = on
                    Task { await applyNotify(on) }
                }))
            if notifyDenied {
                Text(verbatim: L("settings.notify.denied"))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(verbatim: L("settings.notify.header"))
        } footer: {
            Text(verbatim: L("settings.notify.footer"))
        }
    }

    private func applyNotify(_ on: Bool) async {
        guard on else {
            PetNotifications.isEnabled = false
            PetNotifications.cancelAll()
            notifyDenied = false
            return
        }
        let granted = await PetNotifications.requestAuthorization()
        PetNotifications.isEnabled = granted
        notifyOn = granted
        notifyDenied = !granted
        if granted {
            let name = pet.name.isEmpty ? L(pet.breed.nameKey) : pet.name
            PetNotifications.reschedule(for: pet, petName: name)
        }
    }
}
