import SwiftUI

/// 语言选择器。
///
/// **从 LocalizationManager 搬出来的原因**：那是 `Core/` 的基础设施层，
/// 不该住 View。搬到 `Views/` 后依赖方向才是单一的
/// （Views → Core，而不是 Core 内部混着 UI）。
///
/// 注意 `"Follow System"` / `"Language"` 是**英文原文当 key** ——
/// 项目其余地方用 `L("settings.xxx")` 的点分 key，这里沿用原文是因为
/// SwiftUI 的 `Text("...")` 走 LocalizedStringKey，原文本身就是 key。
/// 两种 key 风格混用不理想，但改动要同步 xcstrings，收益不大。
struct LanguagePickerView: View {
    @Environment(LocalizationManager.self) private var manager

    var body: some View {
        List {
            // 「跟随系统」永远第一项。key "Follow System" 需进 Localizable.xcstrings 翻译。
            Button {
                manager.setLanguage("")
            } label: {
                row(title: Text("Follow System"), selected: manager.isFollowingSystem)
            }

            Section {
                ForEach(AppLanguage.all) { lang in
                    Button {
                        manager.setLanguage(lang.code)
                    } label: {
                        row(title: Text(verbatim: lang.endonym),
                            selected: manager.selectedCode == lang.code)
                    }
                }
            }
        }
        .navigationTitle(Text("Language"))   // key "Language" 需进 Localizable.xcstrings
    }

    @ViewBuilder
    private func row(title: Text, selected: Bool) -> some View {
        HStack {
            title.foregroundStyle(.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
