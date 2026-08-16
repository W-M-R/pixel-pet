import SwiftUI

/// 成就页。
///
/// 从主页顶栏的星星进来。曾经埋在设置页底部（齿轮 → 滚到最下），
/// 而它是主要的金币来源（30 天内可得 7050 枚，见 docs/07-shop.md），
/// 藏那么深不合理。
///
/// 未达成的显示进度条，比单纯的"未完成"更有推动力。
struct AchievementsView: View {
    let store: PetStore

    @Environment(\.dismiss) private var dismiss

    private var claimedCount: Int {
        AchievementRule.all.filter { store.isClaimed($0) }.count
    }

    var body: some View {
        // 自带 NavigationStack —— 它现在是 sheet 而不是 NavigationLink 的目标，
        // 没有外层导航容器就没有标题栏，也没法关掉。
        NavigationStack {
            ZStack {
                Pixel.panel.color.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Pixel.u(3)) {
                        summary

                        ForEach(AchievementRule.Group.allCases, id: \.self) { group in
                            let items = AchievementRule.all.filter { $0.group == group }
                            if !items.isEmpty {
                                section(title: L(group.nameKey), items: items)
                            }
                        }
                    }
                    .padding(Pixel.u(3))
                }
            }
            .navigationTitle(L("achv.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Pixel.panelDark.color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) { dismiss() }
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.coin.color)
                }
            }
        }
    }

    private var summary: some View {
        HStack {
            PixelIconView(icon: .star, size: Pixel.u(5))
            Text(verbatim: String(format: L("achv.summary"),
                                  claimedCount, AchievementRule.all.count))
                .font(Pixel.mono(Pixel.bodySize, .semibold))
                .foregroundStyle(Pixel.text.color)
            Spacer()
            HStack(spacing: Pixel.u(1)) {
                PixelIconView(icon: .coin, size: Pixel.u(4))
                Text(verbatim: "\(store.wallet.coins)")
                    .font(Pixel.mono(Pixel.numberSize, .semibold))
                    .foregroundStyle(Pixel.coin.color)
            }
        }
        .padding(Pixel.u(2.5))
        .background(PixelPanel(fill: Pixel.button,
                               lite: Pixel.buttonLite,
                               dark: Pixel.buttonDark))
    }

    private func section(title: String, items: [AchievementRule]) -> some View {
        VStack(alignment: .leading, spacing: Pixel.u(1.5)) {
            Text(verbatim: title)
                .font(Pixel.mono(Pixel.labelSize, .bold))
                .foregroundStyle(Pixel.textDim.color)

            VStack(spacing: Pixel.u(1)) {
                ForEach(items, id: \.id) { rule in
                    row(rule)
                }
            }
        }
    }

    private func row(_ rule: AchievementRule) -> some View {
        let claimed = store.isClaimed(rule)
        let progress = store.achievementProgress(rule)

        return HStack(spacing: Pixel.u(2)) {
            // 已达成打勾，未达成留空框 —— 用方块而非 SF Symbol 的圆圈
            ZStack {
                Rectangle()
                    .fill(claimed ? Pixel.satiety.color : Pixel.slotEmpty.color)
                    .frame(width: Pixel.u(3), height: Pixel.u(3))
                if claimed {
                    Text(verbatim: "✓")
                        .font(Pixel.mono(Pixel.labelSize, .bold))
                        .foregroundStyle(Pixel.panel.color)
                }
            }

            VStack(alignment: .leading, spacing: Pixel.u(0.75)) {
                Text(verbatim: L(rule.nameKey))
                    .font(Pixel.mono(Pixel.bodySize, claimed ? .regular : .medium))
                    .foregroundStyle(claimed ? Pixel.textDim.color : Pixel.text.color)

                if let p = progress, p.target > 1, !claimed {
                    HStack(spacing: Pixel.u(1.5)) {
                        PixelBar(value: Double(p.current) / Double(p.target),
                                 tint: Pixel.satiety, slots: 12)
                            .frame(width: Pixel.u(24))
                        Text(verbatim: "\(p.current) / \(p.target)")
                            .font(Pixel.mono(Pixel.labelSize))
                            .foregroundStyle(Pixel.textDim.color)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: Pixel.u(0.75)) {
                PixelIconView(icon: .coin, size: Pixel.u(3))
                Text(verbatim: "\(rule.coins)")
                    .font(Pixel.mono(Pixel.bodySize, .semibold))
                    .foregroundStyle(claimed ? Pixel.textDim.color : Pixel.coin.color)
            }
        }
        .padding(Pixel.u(2))
        .background(PixelPanel(fill: claimed ? Pixel.buttonDark : Pixel.button,
                               lite: claimed ? Pixel.buttonDark : Pixel.buttonLite,
                               dark: Pixel.buttonDark))
        .opacity(claimed ? 0.7 : 1)
    }
}
