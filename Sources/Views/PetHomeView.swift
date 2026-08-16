import SwiftUI
import SpriteKit

struct PetHomeView: View {
    @State private var store = PetStore()
    @State private var roomStore = RoomStore()
    @State private var talk = PetTalkCoordinator()
    @State private var scene = PetScene()
    /// 开局流程是否还没走完。
    ///
    /// 读一次存进 @State —— 直接读 store.needsOnboarding 会在
    /// completeOnboarding 后立刻翻转，导致 sheet 关闭动画被打断。
    @State private var needsOnboarding = false
    @State private var showSettings = false
    @State private var showFood = false
    #if DEBUG
    @State private var showDebug = false
    #endif
    @Environment(\.scenePhase) private var scenePhase

    private var now: Date { store.tick }

    var body: some View {
        ZStack {
            // 房间由 PetScene 自己画（墙/地板/家具），这样家具与地面的
            // 相对位置只有一处真相，不会 SwiftUI 和 SpriteKit 两边对不上。
            // 兜底色引用 RoomPalette，不再手抄字面量 ——
            // 原来这里和 RoomPalette.wall 同值但各写一份，改一处忘一处。
            RoomPalette.wall.color.ignoresSafeArea()

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
            // 首启要先走开局。放在最前 —— 后面的结算/台词都依赖
            // 玩家已经选好宠物。
            needsOnboarding = store.needsOnboarding

            scene.scaleMode = .resizeFill
            scene.layout = roomStore.layout
            syncScenePet()

            scene.onPetTouched = {
                // 睡着时戳它 = 叫醒，并维持一段清醒。
                // 否则站起来后下一次心跳又会把它按回去睡。
                let wasDrowsy = store.pet.isDrowsy()
                if wasDrowsy { store.wakeUp() }
                store.stroke()
                say(wasDrowsy ? .wokenUp : .stroked)
            }
            scene.onFurnitureMoved = { id, ratio in
                roomStore.move(id: id, toXRatio: ratio)
                scene.layout = roomStore.layout
            }

            // ⚠️ 开局未完成时不结算 —— 否则新玩家还没选宠物就先收到
            // 一条「我帮你看家赚了 N 枚」，而且会白白消耗掉首日签到。
            if !needsOnboarding { runOpening() }
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
        .onChange(of: store.pet.breedID) { _, _ in syncScenePet() }
        .onChange(of: store.pet.colorIndex) { _, _ in syncScenePet() }
        .onChange(of: store.pet.stage) { _, _ in syncScenePet() }
        .sheet(isPresented: $showFood) {
            FoodPickerView(store: store) { food in
                guard store.feed(food) else { return }
                scene.triggerEat()
                say(.fed, delay: Interaction.Duration.sayAfterEat)
            }
        }
        .sheet(isPresented: $showSettings) {
            PetSettingsView(store: store, talk: talk)
        }
        #if DEBUG
        .sheet(isPresented: $showDebug) {
            DebugPanel(store: store, talk: talk) {
                roomStore.reset()
                scene.layout = roomStore.layout
                scene.rebuildRoom()
            }
        }
        #endif
        .preferredColorScheme(.dark)
        // 开局流程。用 fullScreenCover 而非条件替换整个 body ——
        // 后者会让 PetScene 重建，宠物位置和动画状态都丢。
        .fullScreenCover(isPresented: $needsOnboarding) {
            OnboardingView(store: store) {
                needsOnboarding = false
                // 开局完成后立刻同步场景，否则还显示默认猫
                syncScenePet()
                // 现在才跑开场问候 —— 此时宠物已经选好、名字也有了
                runOpening()
            }
            .interactiveDismissDisabled()
        }
    }

    /// 把宠物的品种/毛色/阶段同步给场景。
    private func syncScenePet() {
        scene.configure(breed: store.pet.breed,
                        colorIndex: store.pet.colorIndex,
                        stage: store.pet.stage)
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

    /// 开场结算与问候。
    ///
    /// 抽成方法是因为有两个调用时机：正常启动（onAppear）
    /// 和开局完成后（fullScreenCover 的回调）。
    private func runOpening() {
        // 时序在 OpeningSequence 里（顺序有硬约束，注释在那边）
        let plan = OpeningSequence.plan(store: store)
        OpeningSequence.announce(
            plan,
            speak: { scene.showSpeech($0) },
            fallback: {
                if talk.speak(store.lineContext(trigger: .appeared),
                              absentDays: plan.absentDays, force: true) {
                    scene.showSpeech(talk.currentLine ?? "")
                }
            })
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        VStack(spacing: Pixel.u(2.5)) {
            HStack(spacing: Pixel.u(2)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.pet.name.isEmpty
                         ? L(store.pet.breed.nameKey)
                         : store.pet.name)
                        .font(Pixel.mono(Pixel.titleSize, .bold))
                        .foregroundStyle(Pixel.text.color)
                    Text(verbatim: L("home.age", store.pet.ageInDays))
                        .font(Pixel.mono(Pixel.labelSize))
                        .foregroundStyle(Pixel.textDim.color)
                }
                Spacer(minLength: 0)

                // 金币：像素图标 + 等宽数字
                HStack(spacing: Pixel.u(1)) {
                    PixelIconView(icon: .coin, size: Pixel.u(4))
                    Text(verbatim: "\(store.wallet.coins)")
                        .font(Pixel.mono(Pixel.numberSize, .semibold))
                        .foregroundStyle(Pixel.coin.color)
                }

                // 当前最紧急的需求
                PixelIconView(icon: .forNeed(store.pet.dominantNeed(at: now)),
                              size: Pixel.u(6))

                Button {
                    showSettings = true
                } label: {
                    // 齿轮暂时留 SF Symbol —— 自绘齿轮在 16px 下辨识度差，
                    // 且它是系统级功能入口，用系统图标反而符合预期。
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Pixel.textDim.color)
                }
                #if DEBUG
                // 长按进调试面板 —— 保留时间快进能力，但不占主界面。
                // Release 不编译，正式版没有这个入口。
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6)
                    .onEnded { _ in showDebug = true })
                #endif
            }

            HStack(spacing: Pixel.u(2)) {
                ForEach(StatDimension.all) { dim in
                    StatBar(labelKey: dim.labelKey,
                            value: dim.value(store.pet, now),
                            tint: dim.tint)
                }
            }

            Text(verbatim: L(store.pet.dominantNeed(at: now).messageKey))
                .font(Pixel.mono(Pixel.bodySize))
                .foregroundStyle(Pixel.textDim.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Pixel.u(3))
        .pixelPanel()
        .padding(.top, Pixel.u(2))
    }

    // MARK: - 操作栏

    private var actionBar: some View {
        HStack(spacing: Pixel.u(2)) {
            ActionButton(titleKey: "action.feed", icon: .meat) {
                showFood = true
            }
            ForEach(Interaction.all) { act in
                ActionButton(titleKey: act.titleKey, icon: act.icon) {
                    store.perform(act)
                    scene.playAnimation(for: act.id)
                    say(act.trigger, delay: act.sayDelay)
                }
            }
        }
    }
}

// MARK: - 子视图

private struct StatBar: View {
    let labelKey: String
    let value: Double
    let tint: Pixel.RGB

    var body: some View {
        VStack(spacing: Pixel.u(1)) {
            Text(verbatim: L(labelKey))
                .font(Pixel.mono(Pixel.labelSize))
                .foregroundStyle(Pixel.textDim.color)
            PixelBar(value: value, tint: tint)
        }
    }
}

/// 像素风操作按钮。
///
/// 用 `PixelIcon` 而非 emoji —— emoji 的渐变高光会把像素感压掉。
/// 按下时面板明暗边互换，模拟凹陷，这是像素 UI 的经典做法。
private struct ActionButton: View {
    let titleKey: String
    let icon: PixelIcon
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Pixel.u(1)) {
                PixelIconView(icon: icon, size: Pixel.u(6))
                Text(verbatim: L(titleKey))
                    .font(Pixel.mono(Pixel.labelSize, .medium))
                    .foregroundStyle(Pixel.text.color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Pixel.u(1.75))
            .background(
                PixelPanel(fill: pressed ? Pixel.buttonPressed : Pixel.button,
                           lite: pressed ? Pixel.buttonDark : Pixel.buttonLite,
                           dark: pressed ? Pixel.buttonLite : Pixel.buttonDark)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

#Preview {
    PetHomeView()
}
