import SwiftUI

/// 宠物页。
///
/// 主页爪印图标点进来。这里是**关于这只宠物的一切**：
/// 状态、起名、品种与毛色、成长进度、陪伴记录、去商店收养更多。
///
/// 之前这些散在设置页（起名/品种/成长/统计四个 section）——
/// 给宠物改个名要先点齿轮，而且改完看不到它长什么样。
/// 现在立绘就在上面，换毛色立刻看见。
struct PetsView: View {
    let store: PetStore

    @Environment(\.dismiss) private var dismiss

    @State private var now = Date()
    @State private var showShop = false
    @State private var draftName = ""

    private var pet: PetState { store.pet }

    /// 我养的全部宠物。顺序与主页一致。
    private var myPets: [PetState] { store.pets }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Pixel.u(3)) {
                    currentCard
                    nameCard
                    growthCard
                    recordCard
                    rosterCard
                    shopEntry
                }
                .padding(Pixel.u(3))
            }
            .background(Pixel.panel.color)
            .navigationTitle(L("pets.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Pixel.panelDark.color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) { commitName(); dismiss() }
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.coin.color)
                }
            }
            .sheet(isPresented: $showShop) { ShopView(store: store) }
            // 状态是时间戳算出来的，进来时刷一次就够 ——
            // 这个页面不需要每秒跳动。
            .onAppear {
                now = Date()
                draftName = pet.name
            }
        }
    }

    // MARK: - 当前状态

    private var currentCard: some View {
        VStack(spacing: Pixel.u(2)) {
            BreedPortrait(breed: pet.breed,
                          colorIndex: pet.colorIndex,
                          size: Pixel.u(20))

            Text(verbatim: pet.name.isEmpty ? L(pet.breed.nameKey) : pet.name)
                .font(Pixel.mono(Pixel.titleSize, .bold))
                .foregroundStyle(Pixel.text.color)

            Text(verbatim: L("pets.stage_age",
                             L(pet.stage.displayNameKey), pet.ageInDays))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)

            // 三维状态。和主页 HUD 同一张表，不重复定义。
            VStack(spacing: Pixel.u(1.5)) {
                ForEach(StatDimension.all) { dim in
                    let v = dim.value(pet, now)
                    VStack(alignment: .leading, spacing: Pixel.u(0.75)) {
                        HStack {
                            Text(verbatim: L(dim.labelKey))
                                .font(Pixel.mono(Pixel.labelSize))
                                .foregroundStyle(Pixel.textDim.color)
                            Spacer()
                            Text(verbatim: "\(Int(v * 100))%")
                                .font(Pixel.mono(Pixel.labelSize, .medium))
                                .foregroundStyle(dim.tint.color)
                        }
                        PixelBar(value: v, tint: dim.tint, slots: 20)
                    }
                }
            }
            .padding(.top, Pixel.u(1))

            Text(verbatim: L(pet.dominantNeed(at: now).messageKey))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
                .padding(.top, Pixel.u(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }

    // MARK: - 起名

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: Pixel.u(1.5)) {
            Text(verbatim: L("settings.name"))
                .font(Pixel.mono(Pixel.bodySize, .semibold))
                .foregroundStyle(Pixel.text.color)

            TextField(L("settings.name.placeholder"), text: $draftName)
                .textFieldStyle(.plain)
                .font(Pixel.mono(Pixel.bodySize))
                .foregroundStyle(Pixel.text.color)
                .tint(Pixel.coin.color)
                .submitLabel(.done)
                .onSubmit { commitName() }
                .padding(Pixel.u(2))
                .background(PixelPanel(fill: Pixel.buttonDark,
                                       lite: Pixel.button,
                                       dark: Pixel.panelDark))

            Text(verbatim: L("pets.name_footer"))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
        }
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }

    /// 提交改名。两个时机：键盘 Done、页面右上角完成。
    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != pet.name else { return }
        store.rename(String(trimmed.prefix(12)))
    }

    // MARK: - 成长

    private var growthCard: some View {
        VStack(alignment: .leading, spacing: Pixel.u(1.5)) {
            HStack {
                Text(verbatim: L("settings.growth"))
                    .font(Pixel.mono(Pixel.bodySize, .semibold))
                    .foregroundStyle(Pixel.text.color)
                Spacer()
                Text(verbatim: L(pet.stage.displayNameKey))
                    .font(Pixel.mono(Pixel.bodySize, .semibold))
                    .foregroundStyle(Pixel.satiety.color)
            }

            if let left = pet.stage.daysToNext(from: pet.ageInDays) {
                Text(verbatim: String(format: L("settings.stage.next"), left))
                    .font(Pixel.mono(Pixel.labelSize))
                    .foregroundStyle(Pixel.textDim.color)
                PixelBar(value: stageProgress, tint: Pixel.satiety, slots: 20)
            } else {
                Text(verbatim: L("settings.stage.final"))
                    .font(Pixel.mono(Pixel.labelSize))
                    .foregroundStyle(Pixel.textDim.color)
            }
        }
        .padding(Pixel.u(3))
        .background(PixelPanel())
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

    // MARK: - 陪伴记录

    /// 累计互动次数。
    ///
    /// 放在这里而不是设置页：它是养成感的一部分（"第 9 天、喂了 62 次"），
    /// 属于"关于这只宠物"，不属于"应用偏好"。
    private var recordCard: some View {
        VStack(alignment: .leading, spacing: Pixel.u(2)) {
            Text(verbatim: L("pets.record"))
                .font(Pixel.mono(Pixel.bodySize, .semibold))
                .foregroundStyle(Pixel.text.color)

            recordRow(icon: .heart, labelKey: "stats.streak",
                      value: pet.streakDays ?? 1, unitKey: "unit.day")
            recordRow(icon: .meat, labelKey: "stats.feed",
                      value: pet.totalFeedCount ?? 0, unitKey: "unit.times")
            recordRow(icon: .ball, labelKey: "stats.play",
                      value: pet.totalPlayCount ?? 0, unitKey: "unit.times")
            recordRow(icon: .bath, labelKey: "stats.clean",
                      value: pet.totalCleanCount ?? 0, unitKey: "unit.times")
        }
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }

    private func recordRow(icon: PixelIcon, labelKey: String,
                           value: Int, unitKey: String) -> some View {
        HStack(spacing: Pixel.u(1.5)) {
            PixelIconView(icon: icon, size: Pixel.u(4))
            Text(verbatim: L(labelKey))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
            Spacer(minLength: 0)
            Text(verbatim: "\(value) \(L(unitKey))")
                .font(Pixel.mono(Pixel.bodySize, .semibold))
                .foregroundStyle(Pixel.text.color)
        }
    }

    // MARK: - 花名册

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: Pixel.u(2)) {
            HStack {
                Text(verbatim: L("pets.roster"))
                    .font(Pixel.mono(Pixel.bodySize, .semibold))
                    .foregroundStyle(Pixel.text.color)
                Spacer()
                Text(verbatim: "\(myPets.count)")
                    .font(Pixel.mono(Pixel.labelSize))
                    .foregroundStyle(Pixel.textDim.color)
            }

            // 每只宠物一行，点一下切换查看。
            // ⚠️ 用 `p.id` 而非 breedID 区分 —— 可以养两只同品种不同色的。
            ForEach(myPets) { p in
                let isCurrent = p.id == store.selectedPetID
                Button {
                    store.select(petID: p.id)
                    draftName = p.name
                    now = Date()
                } label: {
                    HStack(spacing: Pixel.u(2)) {
                        BreedPortrait(breed: p.breed, colorIndex: p.colorIndex,
                                      size: Pixel.u(10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: p.name.isEmpty
                                 ? L(p.breed.nameKey) : p.name)
                                .font(Pixel.mono(Pixel.bodySize, .semibold))
                                .foregroundStyle(Pixel.text.color)
                            Text(verbatim: L("pets.stage_age",
                                             L(p.stage.displayNameKey), p.ageInDays))
                                .font(Pixel.mono(Pixel.labelSize))
                                .foregroundStyle(Pixel.textDim.color)
                        }
                        Spacer(minLength: 0)
                        Text(verbatim: L(isCurrent ? "pets.current" : "pets.switch"))
                            .font(Pixel.mono(Pixel.labelSize, .medium))
                            .foregroundStyle(isCurrent ? Pixel.coin.color
                                                       : Pixel.hygiene.color)
                    }
                    .padding(Pixel.u(2))
                    .background(
                        PixelPanel(fill: isCurrent ? Pixel.buttonLite : Pixel.button,
                                   lite: Pixel.buttonLite,
                                   dark: Pixel.buttonDark)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }

    // MARK: - 商店入口

    private var shopEntry: some View {
        Button { showShop = true } label: {
            HStack(spacing: Pixel.u(2)) {
                PixelIconView(icon: .paw, size: Pixel.u(6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: L("pets.get_more"))
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.text.color)
                    Text(verbatim: L("pets.get_more_hint"))
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.textDim.color)
                }
                Spacer(minLength: 0)
                HStack(spacing: Pixel.u(1)) {
                    PixelIconView(icon: .coin, size: Pixel.u(3.5))
                    Text(verbatim: "\(store.wallet.coins)")
                        .font(Pixel.mono(Pixel.labelSize, .semibold))
                        .foregroundStyle(Pixel.coin.color)
                }
            }
            .padding(Pixel.u(3))
            .background(PixelPanel())
        }
        .buttonStyle(.plain)
    }
}
