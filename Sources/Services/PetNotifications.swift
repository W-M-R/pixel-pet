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

    /// 用户是否开启（默认关，避免一上来就弹系统授权框）
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
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
    /// 排两条：
    /// - 饱食降到 15% 时提醒
    /// - 心情降到 20% 时提醒
    ///
    /// 都用 `UNTimeIntervalNotificationTrigger` —— 因为触发时刻是从
    /// 时间戳算出来的相对秒数，不是固定钟点。
    static func reschedule(for pet: PetState, petName: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [hungryID, moodID])
        guard isEnabled else { return }

        let now = Date()

        // 饱食：从 lastFedAt 起 hunger 周期的 85% 处提醒
        let hungryAt = pet.lastFedAt.addingTimeInterval(PetState.Decay.hunger * 0.85)
        schedule(id: hungryID,
                 titleKey: "notify.hungry.title",
                 bodyKey: "notify.hungry.body",
                 petName: petName,
                 fireAt: hungryAt, now: now)

        // 心情：80% 处
        let boredAt = pet.lastPlayedAt.addingTimeInterval(PetState.Decay.mood * 0.8)
        schedule(id: moodID,
                 titleKey: "notify.bored.title",
                 bodyKey: "notify.bored.body",
                 petName: petName,
                 fireAt: boredAt, now: now)
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
