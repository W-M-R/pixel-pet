import SwiftUI

/// 应用设置：通知、语言、素材授权。
///
/// **只放"应用级偏好"。** 宠物相关的一切（起名、品种、毛色、成长、
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

    private var pet: PetState { store.pet }

    var body: some View {
        NavigationStack {
            List {
                notificationSection

                Section {
                    NavigationLink(L("settings.language")) { LanguagePickerView() }
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
                    Button(L("common.done")) { dismiss() }
                        .font(Pixel.mono(Pixel.bodySize, .semibold))
                        .foregroundStyle(Pixel.coin.color)
                }
            }
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
