import SwiftUI

/// 收支明细。
///
/// 主页金币旁边点进来。回答三个问题：
/// **钱从哪来、花到哪去、今天还能赚多少。**
///
/// 数据全部来自 `CoinLedger` —— 之前只有一个余额数字，
/// 想知道构成只能翻存档人肉推断。
struct EarningsView: View {
    let store: PetStore

    @Environment(\.dismiss) private var dismiss

    private var ledger: CoinLedger { store.wallet.ledger }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Pixel.u(3)) {
                    balanceCard
                    capCard
                    if !ledger.incomeBreakdown.isEmpty {
                        section(titleKey: "earn.income",
                                items: ledger.incomeBreakdown,
                                tint: Pixel.coin)
                    }
                    if !ledger.spendBreakdown.isEmpty {
                        section(titleKey: "earn.spend",
                                items: ledger.spendBreakdown,
                                tint: Pixel.mood)
                    }
                    traceCard
                }
                .padding(Pixel.u(3))
            }
            .background(Pixel.panel.color)
            .navigationTitle(L("earn.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) { dismiss() }
                }
            }
        }
    }

    // MARK: - 余额

    private var balanceCard: some View {
        VStack(spacing: Pixel.u(2)) {
            HStack(spacing: Pixel.u(1.5)) {
                PixelIconView(icon: .coin, size: Pixel.u(7))
                Text(verbatim: "\(store.wallet.coins)")
                    .font(Pixel.mono(28, .bold))
                    .foregroundStyle(Pixel.coin.color)
            }
            HStack(spacing: Pixel.u(4)) {
                stat(labelKey: "earn.total_in", value: ledger.totalIn)
                stat(labelKey: "earn.total_out", value: ledger.totalOut)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }

    private func stat(labelKey: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: L(labelKey))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
            Text(verbatim: "\(value)")
                .font(Pixel.mono(Pixel.bodySize, .semibold))
                .foregroundStyle(Pixel.text.color)
        }
    }

    // MARK: - 今日额度

    /// 今日额度进度。
    ///
    /// 这是玩家最需要但之前完全看不到的信息 ——
    /// 额度制下「今天还能赚多少」直接决定了要不要再照顾一次。
    private var capCard: some View {
        let stage = store.pet.stage
        let cap = stage.dailyCap
        let remaining = store.wallet.remainingCap(stage: stage,
                                                  petID: store.pet.id)
        let used = cap - remaining

        return VStack(alignment: .leading, spacing: Pixel.u(1.5)) {
            HStack {
                Text(verbatim: L("earn.today_cap"))
                    .font(Pixel.mono(Pixel.bodySize, .semibold))
                    .foregroundStyle(Pixel.text.color)
                Spacer()
                Text(verbatim: "\(used) / \(cap)")
                    .font(Pixel.mono(Pixel.bodySize, .semibold))
                    .foregroundStyle(Pixel.coin.color)
            }
            PixelBar(value: cap > 0 ? Double(used) / Double(cap) : 0,
                     tint: Pixel.coin, slots: 20)
            Text(verbatim: remaining > 0
                 ? L("earn.cap_remaining", remaining)
                 : L("earn.cap_full"))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
        }
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }

    // MARK: - 分项

    private func section(titleKey: String,
                         items: [(reason: CoinReason, amount: Int)],
                         tint: Pixel.RGB) -> some View {
        let total = items.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: Pixel.u(2)) {
            HStack {
                Text(verbatim: L(titleKey))
                    .font(Pixel.mono(Pixel.bodySize, .semibold))
                    .foregroundStyle(Pixel.text.color)
                Spacer()
                Text(verbatim: "\(total)")
                    .font(Pixel.mono(Pixel.bodySize, .semibold))
                    .foregroundStyle(tint.color)
            }
            ForEach(items, id: \.reason) { item in
                VStack(alignment: .leading, spacing: Pixel.u(0.75)) {
                    HStack {
                        Text(verbatim: L(item.reason.labelKey))
                            .font(Pixel.mono(Pixel.labelSize))
                            .foregroundStyle(Pixel.textDim.color)
                        Spacer()
                        Text(verbatim: "\(item.amount)")
                            .font(Pixel.mono(Pixel.labelSize, .medium))
                            .foregroundStyle(Pixel.text.color)
                    }
                    // 占比条 —— 一眼看出主要来源
                    PixelBar(value: total > 0
                             ? Double(item.amount) / Double(total) : 0,
                             tint: tint, slots: 16)
                }
            }
        }
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }

    // MARK: - 流水

    private var traceCard: some View {
        VStack(alignment: .leading, spacing: Pixel.u(2)) {
            Text(verbatim: L("earn.recent"))
                .font(Pixel.mono(Pixel.bodySize, .semibold))
                .foregroundStyle(Pixel.text.color)

            if ledger.recent.isEmpty {
                Text(verbatim: L("earn.no_trace"))
                    .font(Pixel.mono(Pixel.labelSize))
                    .foregroundStyle(Pixel.textDim.color)
            }

            // 倒序，最近的在上面
            ForEach(Array(ledger.recent.enumerated().reversed()),
                    id: \.offset) { _, e in
                HStack(spacing: Pixel.u(1.5)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: L(e.reason.labelKey))
                            .font(Pixel.mono(Pixel.labelSize))
                            .foregroundStyle(Pixel.text.color)
                        Text(e.at, format: .dateTime.month().day()
                                            .hour().minute())
                            .font(Pixel.mono(Pixel.labelSize))
                            .foregroundStyle(Pixel.textDim.color)
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: e.reason.isIncome
                         ? "+\(e.amount)" : "-\(e.amount)")
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(e.reason.isIncome
                                         ? Pixel.coin.color : Pixel.mood.color)
                }
                .padding(.vertical, Pixel.u(0.5))
            }
        }
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }
}
