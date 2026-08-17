import SwiftUI

/// 关于页：应用介绍 + 隐私说明。
///
/// **隐私部分逐条对应代码事实**，不是套模板：
/// - 无网络请求 —— 全项目零 `URLSession`/`URLRequest`
/// - 数据只在本机 —— `Application Support/{pet,wallet,room}.json` + `UserDefaults`
/// - 唯一权限是通知，且默认关闭
///
/// 这几条由 `PrivacyClaimTests` 扫源码守着 ——
/// 万一将来有人加了网络请求，说明就变成谎话了，测试会失败。
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return [v, b].compactMap { $0 }.joined(separator: " (") + (b == nil ? "" : ")")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Pixel.u(3)) {
                header
                card(titleKey: "about.what.title", bodyKey: "about.what.body")
                card(titleKey: "about.how.title", bodyKey: "about.how.body")
                privacyCard
                card(titleKey: "about.assets.title", bodyKey: "about.assets.body")
            }
            .padding(Pixel.u(3))
        }
        .background(Pixel.panel.color)
        .navigationTitle(L("about.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Pixel.panelDark.color, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: Pixel.u(1.5)) {
            PixelIconView(icon: .paw, size: Pixel.u(12))
            Text(verbatim: L("about.app_name"))
                .font(Pixel.mono(Pixel.titleSize, .bold))
                .foregroundStyle(Pixel.text.color)
            Text(verbatim: version)
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
            Text(verbatim: L("about.tagline"))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }

    private func card(titleKey: String, bodyKey: String) -> some View {
        VStack(alignment: .leading, spacing: Pixel.u(1.5)) {
            Text(verbatim: L(titleKey))
                .font(Pixel.mono(Pixel.bodySize, .semibold))
                .foregroundStyle(Pixel.text.color)
            Text(verbatim: L(bodyKey))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }

    /// 隐私说明。四条各自对应一个可验证的代码事实。
    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: Pixel.u(2)) {
            Text(verbatim: L("about.privacy.title"))
                .font(Pixel.mono(Pixel.bodySize, .semibold))
                .foregroundStyle(Pixel.text.color)

            ForEach(["about.privacy.offline",
                     "about.privacy.local",
                     "about.privacy.no_account",
                     "about.privacy.notify",
                     "about.privacy.delete"], id: \.self) { key in
                HStack(alignment: .top, spacing: Pixel.u(1.5)) {
                    PixelIconView(icon: .check, size: Pixel.u(3.5))
                    Text(verbatim: L(key))
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.textDim.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Pixel.u(3))
        .background(PixelPanel())
    }
}
