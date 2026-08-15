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
        NavigationStack {
            VStack(spacing: 14) {
                satietyBar

                ForEach(FoodItem.all) { food in
                    row(food)
                }

                if let toast {
                    Text(verbatim: toast)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle(L("food.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { coinBadge }
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.done")) { dismiss() }
                }
            }
        }
    }

    private var coinBadge: some View {
        HStack(spacing: 4) {
            Text(verbatim: "🪙")
            Text(verbatim: "\(store.wallet.coins)")
                .font(.system(.body, design: .monospaced))
        }
    }

    /// 当前饱食度，让玩家判断该吃哪档
    private var satietyBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: L("stat.satiety"))
                    .font(.caption)
                Spacer()
                Text(verbatim: "\(Int(satiety * 100))%")
                    .font(.system(.caption, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(satiety < 0.3 ? Color.red : Color.orange)
                        .frame(width: max(3, geo.size.width * satiety))
                }
            }
            .frame(height: 6)
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
            HStack(spacing: 12) {
                Text(verbatim: food.emoji)
                    .font(.system(size: 30))

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: L(food.nameKey))
                        .font(.system(size: 15, weight: .semibold))

                    // 动态显示「实际能管多久」而非标称值 ——
                    // 恢复是加到当前值并封顶，半饱时吃罐头只补一半。
                    // 价格也按量走，所以半饱时吃好东西不再「浪费」。
                    Text(verbatim: durationText(hours))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if food.moodBonus > 0 {
                        Text(verbatim: String(format: L("food.mood_bonus"),
                                              Int(food.moodBonus * 100)))
                            .font(.caption2)
                            .foregroundStyle(.pink)
                    }
                    if food.grantsBoost {
                        Text(verbatim: L("food.boost"))
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                Spacer()

                priceLabel(price: price, isFree: food.isFree, affordable: affordable)
            }
            .padding(12)
            .background(.white.opacity(affordable ? 0.10 : 0.04),
                        in: RoundedRectangle(cornerRadius: 12))
            .opacity(affordable ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    /// 价格标签。按量计价，所以传算好的 price 而非 FoodItem。
    @ViewBuilder
    private func priceLabel(price: Int, isFree: Bool, affordable: Bool) -> some View {
        if isFree {
            Text(verbatim: L("food.free"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
        } else {
            HStack(spacing: 3) {
                Text(verbatim: "🪙")
                    .font(.system(size: 12))
                Text(verbatim: "\(price)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(affordable ? Color.primary : Color.red)
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
