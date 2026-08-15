import SwiftUI

/// 成就页。
///
/// 独立页面而非塞进设置 —— 19 条会让设置页太长。
/// 未达成的显示进度条，比单纯的"未完成"更有推动力。
struct AchievementsView: View {
    let store: PetStore

    private var claimedCount: Int {
        AchievementRule.all.filter { store.isClaimed($0) }.count
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(verbatim: String(format: L("achv.summary"),
                                          claimedCount, AchievementRule.all.count))
                        .font(.system(.subheadline, design: .monospaced))
                    Spacer()
                    HStack(spacing: 4) {
                        Text(verbatim: "🪙")
                        Text(verbatim: "\(store.wallet.coins)")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            ForEach(AchievementRule.Group.allCases, id: \.self) { group in
                let items = AchievementRule.all.filter { $0.group == group }
                if !items.isEmpty {
                    Section(L(group.nameKey)) {
                        ForEach(items, id: \.id) { rule in
                            row(rule)
                        }
                    }
                }
            }
        }
        .navigationTitle(L("achv.title"))
    }

    private func row(_ rule: AchievementRule) -> some View {
        let claimed = store.isClaimed(rule)
        let progress = store.achievementProgress(rule)

        return HStack(spacing: 10) {
            Image(systemName: claimed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(claimed ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: L(rule.nameKey))
                    .font(.system(size: 15, weight: claimed ? .regular : .medium))
                    .foregroundStyle(claimed ? .secondary : .primary)

                if let p = progress, p.target > 1, !claimed {
                    HStack(spacing: 6) {
                        ProgressView(value: Double(p.current), total: Double(p.target))
                            .frame(maxWidth: 110)
                        Text(verbatim: "\(p.current) / \(p.target)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 3) {
                Text(verbatim: "🪙").font(.system(size: 11))
                Text(verbatim: "\(rule.coins)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(claimed ? .secondary : .primary)
        }
        .opacity(claimed ? 0.6 : 1)
    }
}
