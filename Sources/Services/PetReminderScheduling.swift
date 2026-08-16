import Foundation

/// 提醒调度。
///
/// **为什么要这个协议**：`PetNotifications` 是全静态 enum，
/// `PetStore.persist()` 直接调它。后果是每次状态变更都会真去碰
/// `UNUserNotificationCenter` —— 测试里既慢又有系统副作用，
/// 所以 init 加了个 `schedulesNotifications: Bool` 开关来绕过。
///
/// 用 bool 开关表达「要不要真的排通知」是把两件事混在一起：
/// 「是否启用提醒」是产品设置，「用哪个实现」是依赖注入。
/// 协议让后者变成显式的。
@MainActor
protocol PetReminderScheduling {
    func reschedule(for pet: PetState, petName: String)
    func cancelAll()
}

/// 真实实现，转发给 `PetNotifications`。
///
/// `@MainActor` 是必需的 —— `PetNotifications` 是 `@MainActor enum`，
/// 而 `PetStore` 也在主 actor 上，所以这个约束不带来额外成本。
struct SystemReminders: PetReminderScheduling {
    func reschedule(for pet: PetState, petName: String) {
        PetNotifications.reschedule(for: pet, petName: petName)
    }
    func cancelAll() {
        PetNotifications.cancelAll()
    }
}

/// 空实现。测试用 —— 什么都不做，但记下调用次数。
@MainActor
final class NoopReminders: PetReminderScheduling {
    private(set) var rescheduleCount = 0
    private(set) var cancelCount = 0

    func reschedule(for pet: PetState, petName: String) {
        rescheduleCount += 1
    }
    func cancelAll() {
        cancelCount += 1
    }
}
