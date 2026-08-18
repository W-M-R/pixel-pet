import SwiftUI

/// 喂食选择器。
///
/// 买不起的档位**置灰但仍可点**（点了提示硬币不够），不直接隐藏 ——
/// 让玩家看到目标才有攒钱动力。
struct FoodPickerView: View {
    let store: PetStore
    /// 选中后回调，参数是实际喂的食物
    let onPick: (FoodItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var toast: String?

    private var satiety: Double { store.pet.satiety(at: store.tick) }

    var body: some View {
        ZStack {
            // 房间墙色打底 —— 原来是系统 sheet 背景，
            // 从像素房间点进来会有强烈的场景断裂
            Pixel.panel.color.ignoresSafeArea()

            VStack(spacing: Pixel.u(3)) {
                header
                satietyBar

                VStack(spacing: Pixel.u(2)) {
                    ForEach(FoodItem.all) { food in
                        row(food)
                    }
                }

                if let toast {
                    Text(verbatim: toast)
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.warn.color)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(Pixel.u(4))
        }
    }

    /// 自绘标题栏。不用 NavigationStack 的原生导航条 ——
    /// 那是这个界面「像原生设置页」的主要来源。
    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text(verbatim: L("common.done"))
                    .font(Pixel.mono(Pixel.bodySize, .medium))
                    .foregroundStyle(Pixel.text.color)
                    .padding(.horizontal, Pixel.u(3))
                    .padding(.vertical, Pixel.u(1.5))
                    .background(PixelPanel(fill: Pixel.button,
                                           lite: Pixel.buttonLite,
                                           dark: Pixel.buttonDark))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11y.done)

            Spacer()

            Text(verbatim: L("food.title"))
                .font(Pixel.mono(Pixel.titleSize, .bold))
                .foregroundStyle(Pixel.text.color)

            Spacer()

            HStack(spacing: Pixel.u(1)) {
                PixelIconView(icon: .coin, size: Pixel.u(4))
                Text(verbatim: "\(store.wallet.coins)")
                    .font(Pixel.mono(Pixel.numberSize, .semibold))
                    .foregroundStyle(Pixel.coin.color)
            }
        }
    }

    /// 当前饱食度，让玩家判断该吃哪档
    private var satietyBar: some View {
        VStack(alignment: .leading, spacing: Pixel.u(1)) {
            HStack {
                Text(verbatim: L("stat.satiety"))
                    .font(Pixel.mono(Pixel.labelSize))
                Spacer()
                Text(verbatim: "\(Int(satiety * 100))%")
                    .font(Pixel.mono(Pixel.labelSize))
            }
            .foregroundStyle(Pixel.textDim.color)
            PixelBar(value: satiety, tint: Pixel.satiety, slots: 20)
        }
    }

    private func row(_ food: FoodItem) -> some View {
        let price = food.cost(currentSatiety: satiety)
        let affordable = store.wallet.coins >= price
        let hours = food.effectiveHours(currentSatiety: satiety,
                                        stage: store.pet.stage)

        return Button {
            guard affordable else {
                showToast(L("food.cannot_afford"))
                return
            }
            onPick(food)
            dismiss()
        } label: {
            HStack(spacing: Pixel.u(3)) {
                PixelIconView(icon: .forFood(food.id), size: Pixel.u(8))

                VStack(alignment: .leading, spacing: Pixel.u(0.5)) {
                    Text(verbatim: L(food.nameKey))
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.text.color)

                    // 动态显示「实际能管多久」而非标称值 ——
                    // 恢复是加到当前值并封顶，半饱时吃罐头只补一半。
                    // 价格也按量走，所以半饱时吃好东西不再「浪费」。
                    Text(verbatim: durationText(hours))
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.textDim.color)

                    if food.moodBonus > 0 {
                        Text(verbatim: String(format: L("food.mood_bonus"),
                                              Int(food.moodBonus * 100)))
                            .font(Pixel.mono(Pixel.labelSize))
                            .foregroundStyle(Pixel.mood.color)
                    }
                    if food.grantsBoost {
                        Text(verbatim: L("food.boost"))
                            .font(Pixel.mono(Pixel.labelSize))
                            .foregroundStyle(Pixel.coin.color)
                    }
                }

                Spacer(minLength: 0)

                priceLabel(price: price, isFree: food.isFree, affordable: affordable)
            }
            .padding(Pixel.u(2.5))
            .background(
                PixelPanel(fill: affordable ? Pixel.button : Pixel.buttonDark,
                           lite: affordable ? Pixel.buttonLite : Pixel.button,
                           dark: Pixel.buttonDark)
            )
            .opacity(affordable ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11y.food(food.id))
        // 买不起时读出原因 —— 光是「变暗」对 VoiceOver 用户不存在
        .accessibilityHint(Text(verbatim:
            affordable ? "" : L("food.cannot_afford")))
    }

    /// 价格标签。按量计价，所以传算好的 price 而非 FoodItem。
    @ViewBuilder
    private func priceLabel(price: Int, isFree: Bool, affordable: Bool) -> some View {
        if isFree {
            Text(verbatim: L("food.free"))
                .font(Pixel.mono(Pixel.bodySize, .medium))
                .foregroundStyle(Pixel.hygiene.color)
        } else {
            HStack(spacing: Pixel.u(0.75)) {
                PixelIconView(icon: .coin, size: Pixel.u(3))
                Text(verbatim: "\(price)")
                    .font(Pixel.mono(Pixel.numberSize, .semibold))
            }
            .foregroundStyle(affordable ? Pixel.coin.color : Pixel.warn.color)
        }
    }

    private func durationText(_ hours: Double) -> String {
        if hours >= 1 {
            let s = hours >= 10 ? String(Int(hours.rounded()))
                                : String(format: "%.1f", hours)
            return String(format: L("food.lasts"), s)
        }
        return String(format: L("food.lasts.min"), Int((hours * 60).rounded()))
    }

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toast == text { toast = nil }
        }
    }
}
