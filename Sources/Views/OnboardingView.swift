import SwiftUI
import SpriteKit

/// 开局流程：选宠物 → 起名。
///
/// **为什么要有这个**：原来 app 一启动就直接给一只默认猫，
/// 玩家没有「这是我选的」这种归属感。而归属感是养成类留存的核心。
///
/// 两步而非一步：选宠物时要看属性对比（信息量大），起名要专注（输入）。
/// 挤在一屏会让两件事都做不好。
struct OnboardingView: View {
    let store: PetStore
    /// 完成后回调
    let onDone: () -> Void

    @State private var step: Step = .pickBreed
    @State private var breedID: String = PetBreed.cat.id
    @State private var colorIndex: Int = 0
    @State private var draftName: String = ""

    private enum Step { case pickBreed, name }

    private var breed: PetBreed { PetBreed.byID(breedID) }

    var body: some View {
        ZStack {
            Pixel.panel.color.ignoresSafeArea()

            VStack(spacing: Pixel.u(4)) {
                header

                switch step {
                case .pickBreed: breedPicker
                case .name:      namePanel
                }

                Spacer(minLength: 0)
                footer
            }
            .padding(Pixel.u(4))
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: Pixel.u(1.5)) {
            Text(verbatim: L(step == .pickBreed
                             ? "onboard.pick.title" : "onboard.name.title"))
                .font(Pixel.mono(Pixel.titleSize, .bold))
                .foregroundStyle(Pixel.text.color)

            Text(verbatim: L(step == .pickBreed
                             ? "onboard.pick.subtitle" : "onboard.name.subtitle"))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
                .multilineTextAlignment(.center)

            // 钱包：让「花 4000 买宠物」这件事从一开始就可见
            HStack(spacing: Pixel.u(1)) {
                PixelIconView(icon: .coin, size: Pixel.u(4))
                Text(verbatim: "\(store.wallet.coins)")
                    .font(Pixel.mono(Pixel.numberSize, .semibold))
                    .foregroundStyle(Pixel.coin.color)
                Text(verbatim: L("onboard.gift"))
                    .font(Pixel.mono(Pixel.labelSize))
                    .foregroundStyle(Pixel.textDim.color)
            }
            .padding(.top, Pixel.u(1))
        }
    }

    // MARK: - 选宠物

    private var breedPicker: some View {
        VStack(spacing: Pixel.u(3)) {
            // 品种卡片
            HStack(spacing: Pixel.u(2)) {
                ForEach(PetBreed.starters) { b in
                    breedCard(b)
                }
            }

            // 选中品种的属性明细
            statPanel

            // 毛色
            VStack(alignment: .leading, spacing: Pixel.u(1.5)) {
                Text(verbatim: L("settings.color"))
                    .font(Pixel.mono(Pixel.labelSize, .bold))
                    .foregroundStyle(Pixel.textDim.color)
                CoatPicker(breed: breed, colorIndex: $colorIndex)
            }
        }
    }

    private func breedCard(_ b: PetBreed) -> some View {
        let selected = b.id == breedID
        return Button {
            breedID = b.id
            colorIndex = 0        // 换品种时毛色归零
        } label: {
            VStack(spacing: Pixel.u(1.5)) {
                // 用宠物精灵本身当图标，比抽象图形直观
                BreedPortrait(breed: b,
                              colorIndex: selected ? colorIndex : 0,
                              size: Pixel.u(16))

                Text(verbatim: L(b.nameKey))
                    .font(Pixel.mono(Pixel.bodySize, .bold))
                    .foregroundStyle(Pixel.text.color)
                Text(verbatim: L(b.traitKey))
                    .font(Pixel.mono(Pixel.labelSize))
                    .foregroundStyle(Pixel.textDim.color)
            }
            .frame(maxWidth: .infinity)
            .padding(Pixel.u(2))
            .background(
                PixelPanel(fill: selected ? Pixel.button : Pixel.buttonDark,
                           lite: selected ? Pixel.coin : Pixel.button,
                           dark: Pixel.buttonDark)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11y.breedCard(b.id))
        .accessibilityLabel(Text(verbatim: "\(L(b.nameKey))，\(L(b.traitKey))"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// 属性对比面板。实现在 `BreedStatPanel`（商店也用）。
    private var statPanel: some View { BreedStatPanel(breed: breed) }

    // MARK: - 起名

    private var namePanel: some View {
        VStack(spacing: Pixel.u(3)) {
            BreedPortrait(breed: breed, colorIndex: colorIndex,
                          size: Pixel.u(24))

            TextField(L("settings.name.placeholder"), text: $draftName)
                // ⚠️ 这个 id 尤其必要：占位符和页面标题是**同一句文案**，
                // 用文案定位会命中标题，导致键盘没打开、输入落空、
                // 名字存成空字符串（我在 Maestro 上踩过这个坑）。
                .accessibilityIdentifier(A11y.nameField)
                .font(Pixel.mono(Pixel.titleSize))
                .foregroundStyle(Pixel.text.color)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(Pixel.u(2.5))
                .background(PixelPanel(fill: Pixel.slotEmpty,
                                       lite: Pixel.button,
                                       dark: Pixel.panelDark))
                .submitLabel(.done)

            Text(verbatim: L("settings.name.footer"))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
        }
    }

    // MARK: - 底部按钮

    private var footer: some View {
        VStack(spacing: Pixel.u(2)) {
            // 价格提示：明确告诉玩家这一步要花多少
            if step == .pickBreed {
                HStack(spacing: Pixel.u(1)) {
                    Text(verbatim: L("onboard.price"))
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.textDim.color)
                    PixelIconView(icon: .coin, size: Pixel.u(3))
                    Text(verbatim: "\(PetWallet.starterPrice)")
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.coin.color)
                }
            }

            Button {
                if step == .pickBreed {
                    step = .name
                } else {
                    finish()
                }
            } label: {
                Text(verbatim: L(step == .pickBreed
                                 ? "onboard.next" : "onboard.start"))
                    .font(Pixel.mono(Pixel.bodySize, .bold))
                    .foregroundStyle(Pixel.text.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Pixel.u(2.5))
                    .background(PixelPanel(fill: Pixel.button,
                                           lite: Pixel.buttonLite,
                                           dark: Pixel.buttonDark))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11y.onboardNext)

            if step == .name {
                Button {
                    step = .pickBreed
                } label: {
                    Text(verbatim: L("onboard.back"))
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.textDim.color)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11y.onboardBack)
            }
        }
    }

    private func finish() {
        // 名字留空就用品种名，不强迫玩家一定要起名
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        store.completeOnboarding(breedID: breedID,
                                 colorIndex: colorIndex,
                                 name: name)
        onDone()
    }
}
