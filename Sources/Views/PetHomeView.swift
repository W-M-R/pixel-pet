import SwiftUI
import SpriteKit

struct PetHomeView: View {
    @State private var store = PetStore()
    @State private var roomStore = RoomStore()
    @State private var talk = PetTalkCoordinator()
    @State private var scene = PetScene()
    @State private var showDebug = false
    @Environment(\.scenePhase) private var scenePhase

    private var now: Date { store.tick }

    var body: some View {
        ZStack {
            // 房间由 PetScene 自己画（墙/地板/家具），这样家具与地面的
            // 相对位置只有一处真相，不会 SwiftUI 和 SpriteKit 两边对不上。
            Color(red: 0.85, green: 0.78, blue: 0.68).ignoresSafeArea()

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
            // 临时测量钩子：PIXELPET_FORCE_AI=1 时强制开 AI 并切英文。
            // 用于真机内存实测（devicectl 传 UserDefaults 参数不生效）。
            if ProcessInfo.processInfo.environment["PIXELPET_FORCE_AI"] == "1" {
                LocalizationManager.shared.setLanguage("en")
                PetChatEngine.isEnabled = true
            }
            scene.scaleMode = .resizeFill
            scene.layout = roomStore.layout
            scene.configure(species: store.pet.species, colorIndex: store.pet.colorIndex)
            scene.onPetTouched = {
                // 睡着时戳它 = 叫醒，并维持一段清醒。
                // 否则站起来后下一次心跳又会把它按回去睡。
                let wasDrowsy = store.pet.isDrowsy()
                if wasDrowsy { store.wakeUp() }
                store.stroke()
                say(wasDrowsy ? .wokenUp : .stroked)
            }

            // 开场问候。读 daysSinceLastSeen 必须在 markSeen 之前。
            let absent = store.daysSinceLastSeen
            store.markSeen()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                if talk.speak(store.lineContext(trigger: .appeared),
                              absentDays: absent, force: true) {
                    scene.showSpeech(talk.currentLine ?? "")
                }
            }
            scene.onFurnitureMoved = { id, ratio in
                roomStore.move(id: id, toXRatio: ratio)
                scene.layout = roomStore.layout
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            talk.handleMemoryWarning()
        }
        .onChange(of: talk.currentLine) { _, line in
            // AI 台词后到时替换气泡。实测模拟器 CPU-only 要 2-5s，
            // 所以预写台词的气泡时长要够长（见 showSpeech 默认 duration），
            // 否则 AI 结果到达时气泡已经消失了。
            if let line { scene.showSpeech(line) }
        }
        .onChange(of: store.tick) { _, _ in
            // 按自然作息决定睡不睡，与用户互动无关。
            // 曾经用「距上次玩耍的时间」判断，导致一摸就睡（见 PetState.isDrowsy）。
            scene.setSleeping(store.pet.isDrowsy(at: store.tick))
        }
        .onChange(of: store.pet.species) { _, s in
            scene.configure(species: s, colorIndex: store.pet.colorIndex)
        }
        .onChange(of: store.pet.colorIndex) { _, c in
            scene.configure(species: store.pet.species, colorIndex: c)
        }
        .sheet(isPresented: $showDebug) {
            DebugPanel(store: store, talk: talk) {
                roomStore.reset()
                scene.layout = roomStore.layout
                scene.rebuildRoom()
            }
        }
        .preferredColorScheme(.dark)
    }

    /// 触发说话。预写台词立刻出，AI 台词后到会自动替换。
    private func say(_ trigger: PetLineContext.Trigger, delay: TimeInterval = 0) {
        let fire = {
            guard talk.speak(store.lineContext(trigger: trigger)) else { return }
            scene.showSpeech(talk.currentLine ?? "")
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: fire)
        } else {
            fire()
        }
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.pet.name.isEmpty
                         ? L(store.pet.species.displayNameKey)
                         : store.pet.name)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                    Text(verbatim: L("home.age", store.pet.ageInDays))
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

            Text(verbatim: L(store.pet.dominantNeed(at: now).messageKey))
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
                say(.fed, delay: 1.6)     // 等咀嚼动画演完再说话
            }
            ActionButton(titleKey: "action.play", emoji: "🎾") {
                store.play()
                scene.triggerPlay()
                say(.stroked, delay: 0.7)
            }
            ActionButton(titleKey: "action.clean", emoji: "🛁") {
                store.clean()
                scene.triggerClean()
                say(.cleaned, delay: 0.8)
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
            Text(verbatim: L(labelKey))
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
                Text(verbatim: L(titleKey))
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
    let talk: PetTalkCoordinator
    let onResetRoom: () -> Void

    /// 当前语言的显示名（母语名），跟随系统时显示"跟随系统"。
    private var currentLanguageName: String {
        let m = LocalizationManager.shared
        if m.isFollowingSystem { return L("language.system") }
        return AppLanguage.all.first { $0.code == m.selectedCode }?.endonym
            ?? m.selectedCode
    }

    private var aiStatusText: String {
        switch talk.aiAvailability {
        case .ready:              return "状态：可用"
        case .disabled:           return "状态：已关闭（使用预写台词）"
        case .unsupportedLanguage:return "状态：当前语言不支持（模型中文质量不足）"
        case .modelMissing:       return "状态：模型未打包"
        case .loadFailed:         return "状态：模型加载失败"
        }
    }
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
                            Text(verbatim: L(s.displayNameKey)).tag(s)
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
                Section("房间") {
                    Text("长按家具可拖动位置")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("重置家具布局") { onResetRoom() }
                }
                Section {
                    Button("重置状态", role: .destructive) { store.resetAll() }
                }
                Section {
                    NavigationLink {
                        LanguagePickerView()
                    } label: {
                        HStack {
                            Text(verbatim: L("settings.language"))
                            Spacer()
                            Text(verbatim: currentLanguageName)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(verbatim: L("settings.language"))
                } footer: {
                    Text(verbatim: L("settings.language.footer"))
                        .font(.caption2)
                }

                Section {
                    Toggle("AI 台词", isOn: Binding(
                        get: { talk.aiEnabled },
                        set: { talk.aiEnabled = $0 }))
                    Text(aiStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("AI")
                } footer: {
                    Text("开启后宠物的台词由设备端模型生成，完全离线。\n"
                         + "代价是约 1.4 GB 内存占用，且目前只有英文质量可用。")
                        .font(.caption2)
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

#Preview {
    PetHomeView()
}
