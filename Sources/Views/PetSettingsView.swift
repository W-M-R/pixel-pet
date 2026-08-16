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
    @State private var aiOn: Bool = PetChatEngine.isEnabled

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
                aiSection

                Section {
                    NavigationLink {
                        ShopView(store: store)
                    } label: {
                        HStack {
                            Text(verbatim: L("shop.title"))
                            Spacer()
                            // 显示已拥有 / 总数，让玩家知道还有多少可解锁
                            Text(verbatim: "\(PetBreed.all.filter { store.owns($0) }.count)"
                                 + " / \(PetBreed.all.count)")
                                .font(Pixel.mono(Pixel.labelSize))
                                .foregroundStyle(Pixel.textDim.color)
                        }
                    }
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
            // 像素化：List 的系统灰底换成木色，行背景换成按钮色。
            // 保留 List/Toggle/TextField 的原生行为（无障碍、键盘、滚动），
            // 只换配色和字体 —— 自绘这些控件的收益远小于风险。
            .scrollContentBackground(.hidden)
            .background(Pixel.panel.color)
            .listRowBackgroundPixel()
            .font(Pixel.mono(Pixel.bodySize))
            .foregroundStyle(Pixel.text.color)
            .tint(Pixel.satiety.color)
            .toolbarBackground(Pixel.panelDark.color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) { commitName(); dismiss() }
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.coin.color)
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
            // 只列**已拥有**的品种 —— 未购买的不该出现在这里，
            // 否则玩家点了没反应（choose 会返回 false）。
            // 想要更多品种走商店（见 ShopView）。
            let owned = PetBreed.all.filter { store.owns($0) }
            Picker(L("settings.breed"), selection: Binding(
                get: { pet.breedID },
                set: { store.choose(breedID: $0, colorIndex: 0) }   // 换品种时毛色归零
            )) {
                ForEach(owned) { b in
                    Text(verbatim: L(b.nameKey)).tag(b.id)
                }
            }
            .pickerStyle(.segmented)
            .disabled(owned.count < 2)

            // 毛色用色块选，比下拉直观
            HStack(spacing: 10) {
                ForEach(0..<pet.breed.colorCount, id: \.self) { i in
                    Button {
                        store.choose(breedID: pet.breedID, colorIndex: i)
                    } label: {
                        ZStack {
                            Rectangle().fill(Pixel.slotEmpty.color)
                            if pet.colorIndex == i {
                                // 选中框用像素描边，不用圆角
                                Rectangle()
                                    .strokeBorder(Pixel.coin.color,
                                                  lineWidth: Pixel.u(1))
                            }
                            Text(verbatim: "\(i + 1)")
                                .font(Pixel.mono(Pixel.bodySize, .medium))
                                .foregroundStyle(pet.colorIndex == i
                                                 ? Pixel.coin.color
                                                 : Pixel.textDim.color)
                        }
                        .frame(height: Pixel.u(9))
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
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.textDim.color)
                    PixelBar(value: stageProgress, tint: Pixel.satiety, slots: 20)
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

    // MARK: - AI 台词

    /// **默认关闭。** 两个代价都写在 footer 里让用户自己权衡：
    /// 内存约 1.4 GB（实测，CoreML 把量化权重解压成 fp16 常驻，改不了），
    /// 以及中文质量不如英文（350M 规模的局限）。
    ///
    /// 不按语言拦截 —— 用户既然主动开了，就不替他做决定。
    private var aiSection: some View {
        Section {
            Toggle(L("settings.ai"), isOn: Binding(
                get: { aiOn },
                set: { on in
                    aiOn = on
                    talk.aiEnabled = on
                }))
            if aiOn, !talk.aiIsHighQualityLanguage {
                Text(verbatim: L("settings.ai.quality_warning"))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if aiOn, case .modelMissing = talk.aiAvailability {
                Text(verbatim: L("settings.ai.model_missing"))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(verbatim: L("settings.ai.header"))
        } footer: {
            Text(verbatim: L("settings.ai.footer"))
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
