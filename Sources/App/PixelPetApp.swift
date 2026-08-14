import SwiftUI

@main
struct PixelPetApp: App {
    @State private var localization = LocalizationManager.shared

    init() {
        // 必须在这里调：既做进程内 Bundle 重定向（当前进程即时生效），
        // 也写 AppleLanguages（下次启动兜底）。
        LocalizationManager.shared.applyStoredLanguageAtLaunch()
    }

    var body: some Scene {
        WindowGroup {
            PetHomeView()
                .environment(localization)                    // 供 LanguagePickerView 读写
                .environment(\.locale, localization.locale)   // SwiftUI 格式化 / Text
                .id(localization.refreshID)                   // 切换语言时整树刷新
        }
    }
}
