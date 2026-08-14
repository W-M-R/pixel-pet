import SwiftUI
import SpriteKit

struct PetHomeView: View {
    @State private var store = PetStore()
    @State private var scene = PetScene()
    @State private var showDebug = false
    @Environment(\.scenePhase) private var scenePhase

    private var now: Date { store.tick }

    var body: some View {
        ZStack {
            // 房间由 PetScene 自己画（墙/地板/家具），这样家具与地面的
            // 相对位置只有一处真相，不会 SwiftUI 和 SpriteKit 两边对不上。
            Color(red: 0.30, green: 0.33, blue: 0.46).ignoresSafeArea()

            SpriteView(scene: scene, options: [.allowsTransparency])
                .ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                Spacer()
                actionBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .onAppear {
            scene.scaleMode = .resizeFill
            scene.configure(species: store.pet.species, colorIndex: store.pet.colorIndex)
            scene.onPetTouched = { store.play() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
        .onChange(of: store.tick) { _, _ in
            // 精力见底就趴下睡，恢复了自己起来
            scene.setSleeping(store.pet.energy(at: store.tick) < 0.12)
        }
        .onChange(of: store.pet.species) { _, s in
            scene.configure(species: s, colorIndex: store.pet.colorIndex)
        }
        .onChange(of: store.pet.colorIndex) { _, c in
            scene.configure(species: store.pet.species, colorIndex: c)
        }
        .sheet(isPresented: $showDebug) {
            DebugPanel(store: store)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.pet.name.isEmpty
                         ? String(localized: store.pet.species.displayNameKey)
                         : store.pet.name)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                    Text(String(format: String(localized: "home.age"), store.pet.ageInDays))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.pet.dominantNeed(at: now).emoji)
                    .font(.system(size: 26))
                Button {
                    showDebug = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            HStack(spacing: 8) {
                StatBar(labelKey: "stat.satiety", value: store.pet.satiety(at: now), tint: .orange)
                StatBar(labelKey: "stat.mood",    value: store.pet.mood(at: now),    tint: .pink)
                StatBar(labelKey: "stat.hygiene", value: store.pet.hygiene(at: now), tint: .cyan)
            }

            Text(String(localized: store.pet.dominantNeed(at: now).messageKey))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 8)
    }

    // MARK: - 操作栏

    private var actionBar: some View {
        HStack(spacing: 10) {
            ActionButton(titleKey: "action.feed", emoji: "🍖") {
                store.feed()
                scene.triggerEat()
            }
            ActionButton(titleKey: "action.play", emoji: "🎾") {
                store.play()
                scene.triggerPlay()
            }
            ActionButton(titleKey: "action.clean", emoji: "🛁") {
                store.clean()
                scene.triggerClean()
            }
        }
    }
}

// MARK: - 子视图

private struct StatBar: View {
    let labelKey: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(String(localized: labelKey))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(value < 0.3 ? Color.red : tint)
                        .frame(width: max(3, geo.size.width * value))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct ActionButton: View {
    let titleKey: String
    let emoji: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(emoji).font(.system(size: 22))
                Text(String(localized: titleKey))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// 调试面板。用来验证「时间戳驱动」是否正确——把时间往前推，
/// 数值应该立刻跟着掉，而不需要 app 在后台跑任何东西。
private struct DebugPanel: View {
    let store: PetStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("模拟时间流逝") {
                    Button("前进 1 小时") { store.debugAge(by: 3600) }
                    Button("前进 4 小时") { store.debugAge(by: 4 * 3600) }
                    Button("前进 1 天")  { store.debugAge(by: 86400) }
                }
                Section("宠物") {
                    Picker("种类", selection: Binding(
                        get: { store.pet.species },
                        set: { store.choose(species: $0, colorIndex: store.pet.colorIndex) }
                    )) {
                        ForEach(PetSpecies.allCases) { s in
                            Text(String(localized: s.displayNameKey)).tag(s)
                        }
                    }
                    Picker("毛色", selection: Binding(
                        get: { store.pet.colorIndex },
                        set: { store.choose(species: store.pet.species, colorIndex: $0) }
                    )) {
                        ForEach(0..<PetSpriteSheet.colorCount, id: \.self) { i in
                            Text("毛色 \(i + 1)").tag(i)
                        }
                    }
                }
                Section {
                    Button("重置状态", role: .destructive) { store.resetAll() }
                }
                Section("素材授权") {
                    NavigationLink("Credits") { CreditsView() }
                }
            }
            .navigationTitle("调试")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

extension String {
    /// 简写：走 Localizable，key 不存在时回退到 key 本身。
    init(localized key: String) {
        self = NSLocalizedString(key, comment: "")
    }
}

#Preview {
    PetHomeView()
}
