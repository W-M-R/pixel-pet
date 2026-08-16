import SwiftUI

/// 宠物页。
///
/// 主页爪印图标点进来。回答两个问题：
/// **我这只现在怎么样、我还能有哪些。**
///
/// 和设置页里的品种切换器不同 —— 那里是「换装」（一行 picker），
/// 这里是「花名册」：当前宠物的完整状态，加上已拥有/可购买的品种。
/// 一只和多只的展示是同一套 UI，加品种时不用改这里。
struct PetsView: View {
    let store: PetStore

    @Environment(\.dismiss) private var dismiss

    @State private var now = Date()
    @State private var showShop = false

    /// 已拥有的品种。当前这只排在最前。
    private var owned: [PetBreed] {
        PetBreed.all
            .filter { store.wallet.owns($0) }
            .sorted { a, _ in a.id == store.pet.breedID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Pixel.u(3)) {
                    currentCard
                    rosterCard
                    shopEntry
                }
                .padding(Pixel.u(3))
            }
            .background(Pixel.panel.color)
            .navigationTitle(L("pets.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showShop) { ShopView(store: store) }
            // 状态是时间戳算出来的，进来时刷一次就够 ——
            // 这个页面不需要每秒跳动。
            .onAppear { now = Date() }
        }
    }

    // MARK: - 当前宠物

    private var currentCard: some View {
        VStack(spacing: Pixel.u(2)) {
            BreedPortrait(breed: store.pet.breed,
                          colorIndex: store.pet.colorIndex,
                          size: Pixel.u(20))

            Text(verbatim: store.pet.name.isEmpty
                 ? L(store.pet.breed.nameKey)
                 : store.pet.name)
                .font(Pixel.mono(Pixel.titleSize, .bold))
                .foregroundStyle(Pixel.text.color)

            Text(verbatim: L("pets.stage_age",
                             L(store.pet.stage.displayNameKey),
                             store.pet.ageInDays))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)

            // 三维状态。和主页 HUD 同一张表，不重复定义。
            VStack(spacing: Pixel.u(1.5)) {
                ForEach(StatDimension.all) { dim in
                    let v = dim.value(store.pet, now)
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

            Text(verbatim: L(store.pet.dominantNeed(at: now).messageKey))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
                .padding(.top, Pixel.u(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }

    // MARK: - 花名册

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: Pixel.u(2)) {
            HStack {
                Text(verbatim: L("pets.roster"))
                    .font(Pixel.mono(Pixel.bodySize, .semibold))
                    .foregroundStyle(Pixel.text.color)
                Spacer()
                Text(verbatim: "\(owned.count) / \(PetBreed.all.count)")
                    .font(Pixel.mono(Pixel.labelSize))
                    .foregroundStyle(Pixel.textDim.color)
            }

            ForEach(owned) { breed in
                let isCurrent = breed.id == store.pet.breedID
                Button {
                    guard !isCurrent else { return }
                    store.choose(breedID: breed.id, colorIndex: 0)
                    now = Date()
                } label: {
                    HStack(spacing: Pixel.u(2)) {
                        BreedPortrait(breed: breed, colorIndex: 0,
                                      size: Pixel.u(10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: L(breed.nameKey))
                                .font(Pixel.mono(Pixel.bodySize, .semibold))
                                .foregroundStyle(Pixel.text.color)
                            Text(verbatim: L(breed.traitKey))
                                .font(Pixel.mono(Pixel.labelSize))
                                .foregroundStyle(Pixel.textDim.color)
                        }
                        Spacer(minLength: 0)
                        if isCurrent {
                            Text(verbatim: L("pets.current"))
                                .font(Pixel.mono(Pixel.labelSize, .medium))
                                .foregroundStyle(Pixel.coin.color)
                        } else {
                            Text(verbatim: L("pets.switch"))
                                .font(Pixel.mono(Pixel.labelSize))
                                .foregroundStyle(Pixel.hygiene.color)
                        }
                    }
                    .padding(Pixel.u(2))
                    .background(
                        PixelPanel(fill: isCurrent ? Pixel.buttonLite
                                                   : Pixel.button,
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
