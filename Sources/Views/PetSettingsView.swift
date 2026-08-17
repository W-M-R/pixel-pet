import SwiftUI

/// 应用设置：通知与提醒阈值、语言、关于。
///
/// **只放"应用级偏好"。** 宠物相关的一切（起名、品种、成长、
/// 陪伴记录）都在宠物页 —— 那里有立绘和状态条，改完立刻看得见效果。
/// 商店和成就在主页顶栏。
///
/// 曾经这一页塞了七个 section（起名/品种/成长/统计/通知/AI/四个入口），
/// 是"没想清楚放哪就先扔设置里"的产物：
/// 给宠物起名要先点齿轮，成就要先点齿轮再滚到底部。
struct PetSettingsView: View {
    let store: PetStore

    @Environment(\.dismiss) private var dismiss
    @State private var notifyOn: Bool = PetNotifications.isEnabled
    @State private var notifyDenied = false

    /// 三个阈值。改完要重排通知，所以存在 @State 里驱动 UI。
    @State private var satietyLevel = PetNotifications.Threshold.satiety
    @State private var moodLevel = PetNotifications.Threshold.mood
    @State private var hygieneLevel = PetNotifications.Threshold.hygiene

    private var pet: PetState { store.pet }

    var body: some View {
        NavigationStack {
            List {
                notificationSection
                if notifyOn { thresholdSection }

                Section {
                    NavigationLink(L("settings.language")) { LanguagePickerView() }
                    NavigationLink(L("about.title")) { AboutView() }
                }

                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle(L("settings.title"))
            // 不加 .inline 的话大标题会随滚动折叠掉，
            // 而这一页一进来就是滚动状态，标题栏看起来是空的。
            .navigationBarTitleDisplayMode(.inline)
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
                    Button(L("common.done")) { dismiss() }
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.coin.color)
                }
            }
        }
    }

    // MARK: - 通知开关

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

    // MARK: - 提醒阈值

    /// 三维各自的提醒线。
    ///
    /// 阈值用**剩余状态比例**表达（"低于 15% 时提醒"），
    /// 而不是内部曾用的"周期百分比"—— 后者意思正好相反，容易读错。
    private var thresholdSection: some View {
        Section {
            thresholdRow(labelKey: "stat.satiety",
                         icon: .meat, tint: Pixel.satiety,
                         value: $satietyLevel) {
                PetNotifications.Threshold.satiety = $0
            }
            thresholdRow(labelKey: "stat.mood",
                         icon: .ball, tint: Pixel.mood,
                         value: $moodLevel) {
                PetNotifications.Threshold.mood = $0
            }
            thresholdRow(labelKey: "stat.hygiene",
                         icon: .bath, tint: Pixel.hygiene,
                         value: $hygieneLevel) {
                PetNotifications.Threshold.hygiene = $0
            }
        } header: {
            Text(verbatim: L("settings.threshold.header"))
        } footer: {
            Text(verbatim: L("settings.threshold.footer"))
        }
    }

    private func thresholdRow(labelKey: String,
                              icon: PixelIcon,
                              tint: Pixel.RGB,
                              value: Binding<Double>,
                              onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Pixel.u(1.5)) {
            HStack(spacing: Pixel.u(1.5)) {
                PixelIconView(icon: icon, size: Pixel.u(4))
                Text(verbatim: L(labelKey))
                Spacer()
                Text(verbatim: value.wrappedValue <= 0
                     ? L("settings.threshold.off")
                     : "\(Int(value.wrappedValue * 100))%")
                    .font(Pixel.mono(Pixel.bodySize, .semibold))
                    .foregroundStyle(value.wrappedValue <= 0
                                     ? Pixel.textDim.color : tint.color)
            }

            // 用离散档位而非连续 Slider —— 提醒线不需要 1% 精度，
            // 离散档也更符合像素风的"格子"观感。
            HStack(spacing: Pixel.u(1)) {
                ForEach(PetNotifications.Threshold.options, id: \.self) { opt in
                    let picked = abs(opt - value.wrappedValue) < 0.001
                    Button {
                        value.wrappedValue = opt
                        onChange(opt)
                        rescheduleReminders()
                    } label: {
                        Text(verbatim: opt <= 0 ? "×" : "\(Int(opt * 100))")
                            .font(Pixel.mono(Pixel.labelSize, .medium))
                            .foregroundStyle(picked ? Pixel.panel.color
                                                    : Pixel.textDim.color)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Pixel.u(1))
                            .background(picked ? tint.color : Pixel.slotEmpty.color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 阈值改了要立刻重排 —— 否则改动要等下次互动才生效
    private func rescheduleReminders() {
        guard notifyOn else { return }
        let name = pet.name.isEmpty ? L(pet.breed.nameKey) : pet.name
        PetNotifications.reschedule(for: pet, petName: name)
    }

    // MARK: - 调试

    #if DEBUG
    /// 调试段。
    ///
    /// 和长按齿轮进的 `DebugPanel` 是两套：那个是完整面板（含账本流水、
    /// 房间布局、素材信息），这里只放最常用的几个，省得每次长按。
    /// Release 不编译。
    private var debugSection: some View {
        Section {
            NavigationLink("完整调试面板") {
                DebugPanel(store: store) {}
            }
            LabeledContent("金币") {
                Text(verbatim: "\(store.wallet.coins)").monospacedDigit()
            }
            LabeledContent("宠物数") {
                Text(verbatim: "\(store.pets.count)").monospacedDigit()
            }
            Button("+1000 金币") { store.debugAddCoins(1000) }
            Button("+10000 金币") { store.debugAddCoins(10000) }
            Button("前进 1 天") { store.debugAge(by: 86400) }
            Button("前进 1 周") { store.debugAge(by: 7 * 86400) }
            Button("前进 30 天") { store.debugAge(by: 30 * 86400) }
            Button("三维压到 10%") {
                store.debugSetStats(satiety: 0.1, mood: 0.1, hygiene: 0.1)
            }
            Button("三维拉满") {
                store.debugSetStats(satiety: 1, mood: 1, hygiene: 1)
            }
        } header: {
            Text("调试（仅 Debug 版本）")
        } footer: {
            Text("前进时间会同时推进全部宠物的状态、年龄和上次结算时间，"
                 + "回到主页会触发离线收益结算。")
        }
    }
    #endif

    // MARK: - 通知授权

    private func applyNotify(_ on: Bool) async {
        guard on else {
            PetNotifications.isEnabled = false
            PetNotifications.cancelAll()
            notifyDenied = false
            return
        }
        let granted = await PetNotifications.requestAuthorization()
        PetNotifications.isEnabled = granted
        // 用户在系统弹窗里拒了权限，开关要弹回去 ——
        // 否则显示"已开启"但收不到任何提醒。
        notifyOn = granted
        notifyDenied = !granted
        if granted {
            let name = pet.name.isEmpty ? L(pet.breed.nameKey) : pet.name
            PetNotifications.reschedule(for: pet, petName: name)
        }
    }
}
