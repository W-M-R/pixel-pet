import SwiftUI

@main
struct PixelPetApp: App {
    @State private var localization = LocalizationManager.shared

    init() {
        #if DEBUG
        // ⚠️ **必须在这里、且在任何 store 初始化之前。**
        // `PetStore` 在 init 里就读盘了，晚一步铺存档就来不及。
        // 只在带 `-uitest` 启动参数时生效；Release 不编译。
        UITestScene.applyIfNeeded()
        #endif

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
