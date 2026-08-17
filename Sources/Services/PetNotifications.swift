import Foundation
import UserNotifications

/// 本地通知调度。
///
/// 为什么能只靠本地通知、不需要服务器：宠物状态是**时间戳驱动**的，
/// 所以「什么时候会饿」是可以精确算出来的。喂食后重新排一次即可。
///
/// 只在状态即将见底时提醒，且同一时间只排一条 —— 宠物 app 最容易
/// 招人烦的就是通知刷屏。
@MainActor
enum PetNotifications {

    private static let hungryID = "pet.hungry"
    private static let moodID = "pet.mood"
    private static let hygieneID = "pet.hygiene"

    /// 用户是否开启（默认关，避免一上来就弹系统授权框）
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }

    // MARK: - 提醒阈值

    /// 三维各自的提醒阈值（状态**低于**这个比例时提醒）。
    ///
    /// 曾经写死在 `reschedule` 里（饱食 0.85 周期处、心情 0.8 处），
    /// 而且那两个数是「周期的百分比」不是「状态的百分比」——
    /// 意思正好相反，读代码的人很容易搞错。
    /// 现在统一成「剩余状态比例」，和设置页显示的数字一致。
    enum Threshold {
        /// 0 = 关闭该项提醒
        static var satiety: Double {
            get { read("notifyThresholdSatiety", default: 0.15) }
            set { write("notifyThresholdSatiety", newValue) }
        }
        static var mood: Double {
            get { read("notifyThresholdMood", default: 0.20) }
            set { write("notifyThresholdMood", newValue) }
        }
        static var hygiene: Double {
            get { read("notifyThresholdHygiene", default: 0.0) }   // 默认不提醒
            set { write("notifyThresholdHygiene", newValue) }
        }

        /// 可选档位。0 表示关闭。
        static let options: [Double] = [0, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5]

        private static func read(_ key: String, default d: Double) -> Double {
            let v = UserDefaults.standard.object(forKey: key) as? Double
            return v ?? d
        }
        private static func write(_ key: String, _ v: Double) {
            UserDefaults.standard.set(v, forKey: key)
        }
    }

    /// 请求授权。返回是否获得许可。
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 根据当前状态重排通知。每次互动后调用。
    ///
    /// 三条上限（饱食/心情/清洁），阈值由用户在设置里调，
    /// 设成 0 就不排那一条。
    ///
    /// 都用 `UNTimeIntervalNotificationTrigger` —— 因为触发时刻是从
    /// 时间戳算出来的相对秒数，不是固定钟点。
    static func reschedule(for pet: PetState, petName: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [hungryID, moodID, hygieneID])
        guard isEnabled else { return }

        let now = Date()

        // 状态线性衰减，所以「降到 x 比例」= 经过 (1-x) × 周期。
        // 用剩余比例表达阈值，和设置页显示的数字一致。
        func fireTime(from base: Date, cycle: TimeInterval, level: Double) -> Date {
            base.addingTimeInterval(cycle * (1 - level))
        }

        let sat = Threshold.satiety
        if sat > 0 {
            schedule(id: hungryID,
                     titleKey: "notify.hungry.title",
                     bodyKey: "notify.hungry.body",
                     petName: petName,
                     fireAt: fireTime(from: pet.lastFedAt,
                                      cycle: PetState.Decay.hunger(for: pet.stage),
                                      level: sat),
                     now: now)
        }

        let mood = Threshold.mood
        if mood > 0 {
            schedule(id: moodID,
                     titleKey: "notify.bored.title",
                     bodyKey: "notify.bored.body",
                     petName: petName,
                     fireAt: fireTime(from: pet.lastPlayedAt,
                                      cycle: PetState.Decay.mood(for: pet.breed),
                                      level: mood),
                     now: now)
        }

        let hyg = Threshold.hygiene
        if hyg > 0 {
            schedule(id: hygieneID,
                     titleKey: "notify.dirty.title",
                     bodyKey: "notify.dirty.body",
                     petName: petName,
                     fireAt: fireTime(from: pet.lastCleanedAt,
                                      cycle: PetState.Decay.hygiene(for: pet.breed),
                                      level: hyg),
                     now: now)
        }
    }

    private static func schedule(id: String,
                                 titleKey: String,
                                 bodyKey: String,
                                 petName: String,
                                 fireAt: Date,
                                 now: Date) {
        let delay = fireAt.timeIntervalSince(now)
        // 已经过了就不排（用户打开 app 时自然会看到状态）
        guard delay > 60 else { return }

        // 避开深夜：落在 23:00-07:00 的推迟到早上 8 点
        let adjusted = avoidNight(fireAt)
        let finalDelay = max(60, adjusted.timeIntervalSince(now))

        let content = UNMutableNotificationContent()
        content.title = L(titleKey)
        content.body = String(format: L(bodyKey), petName)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: finalDelay, repeats: false)
        center().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// 深夜不打扰。落在夜间时段的通知推到次日 8 点。
    private static func avoidNight(_ date: Date) -> Date {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        guard hour >= PetState.NightTime.startHour || hour < PetState.NightTime.endHour else {
            return date
        }
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        // 若是凌晨，就当天 8 点；若是 23 点，推到次日 8 点
        if hour >= PetState.NightTime.startHour {
            comps.day = (comps.day ?? 1) + 1
        }
        comps.hour = 8
        comps.minute = 0
        return cal.date(from: comps) ?? date
    }

    static func cancelAll() {
        center().removePendingNotificationRequests(withIdentifiers: [hungryID, moodID])
    }

    private static func center() -> UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }
}
