import Foundation

/// 存档读写。
///
/// **从 `PetStore` 抽出来的原因**：JSON 编解码 + 文件路径是纯技术关注点，
/// 和「宠物状态怎么变」无关。混在一起造成两个具体问题：
///
/// 1. `PetStore.init` 有 30 行是加载逻辑，还要用局部变量绕开
///    「所有 stored property 就位前不能访问 self」的限制
/// 2. 为了让 Store 可测，init 加了 `directory:` 参数 ——
///    但真正该替换的是**存储方式**，不是路径
///
/// 抽出后 `PetStore` 只依赖这个协议，测试可以给内存实现，
/// 不再需要建临时目录、也不用在 tearDown 里清理。
protocol PetPersistence {
    func loadPets() -> [PetState]
    func loadWallet() -> PetWallet?
    func save(pets: [PetState])
    func save(wallet: PetWallet)
}

/// 文件存档。
///
/// JSON 存文件而非 UserDefaults —— 将来要加多只宠物、要导出备份都方便。
struct FilePersistence: PetPersistence {

    private let petURL: URL
    private let walletURL: URL

    /// app 默认的存档目录
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory,
                                 in: .userDomainMask)[0]
    }

    init(directory: URL = FilePersistence.defaultDirectory) {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        petURL = directory.appendingPathComponent("pet.json")
        walletURL = directory.appendingPathComponent("wallet.json")
    }

    /// 读全部宠物。
    ///
    /// 兼容两种格式：新的是数组，旧的是单个对象（单宠时期）。
    /// 先试数组，失败再试单个 —— 反过来的话数组会被当成坏数据丢掉。
    func loadPets() -> [PetState] {
        if let list = decode([PetState].self, from: petURL, label: "pets") {
            return list
        }
        // 旧存档：单个对象。它的 id 会被解码成 `PetState.legacyID`。
        if let one = decodeQuietly(PetState.self, from: petURL) {
            return [one]
        }
        // **两种格式都读不动，而文件确实存在 —— 这是数据损坏，必须吼。**
        //
        // 原来这里直接 `return []`，然后 `PetStore.init` 造一只默认猫：
        // 多宠玩家的存档一旦损坏，全部宠物和养成记录静默消失，
        // 界面上看起来只是"回到了新手状态"，没有任何线索。
        if (try? Data(contentsOf: petURL))?.isEmpty == false {
            assertionFailure("pet.json 存在但两种格式都解不动，数据可能损坏")
            NSLog("[PixelPet] pet.json 损坏，无法解码为数组或单对象")
        }
        return []
    }

    func loadWallet() -> PetWallet? {
        decode(PetWallet.self, from: walletURL, label: "wallet")
    }

    /// 解码存档。
    ///
    /// **文件存在但解码失败要吼出来。** 原来是 `try?` 直接吞掉，
    /// 于是「没有存档」和「存档读不动」表现完全一样 ——
    /// 都静默退回默认值。排查时我手写了一份 JSON，
    /// 因为字段格式不对而整个钱包被重置，界面回到开局流程，
    /// 但没有任何地方提示「你的存档没读进去」，白查了很久。
    ///
    /// 线上仍然降级到默认值（总比崩了好），但 DEBUG 下直接断言。
    /// 静默解码。用于「先试新格式再试旧格式」这种预期会失败的场景 ——
    /// 那种失败不是错误，不该触发 assert。
    private func decodeQuietly<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type,
                                      from url: URL,
                                      label: String) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // pets 数组读失败可能只是旧的单对象格式，调用方会再试一次。
            // 其余情况仍然要吼 —— 静默退回默认值曾让我白查很久。
            if label != "pets" {
                assertionFailure("\(label).json 解码失败，将退回默认值：\(error)")
            }
            NSLog("[PixelPet] %@.json 解码失败：%@", label, "\(error)")
            return nil
        }
    }

    /// 写盘用 `.atomic` —— 中途被杀不会留下半个文件
    func save(pets: [PetState]) {
        write(pets, to: petURL, label: "pets")
    }

    func save(wallet: PetWallet) {
        write(wallet, to: walletURL, label: "wallet")
    }

    /// 写盘。
    ///
    /// **失败不能静默吞掉。** 原来是 `try?`：磁盘满或沙盒权限异常时，
    /// 玩家整个 session 的进度会在重启后消失，而运行期间 UI 一切正常
    /// （内存状态是对的）—— 这是最难查的一类问题，
    /// 因为现象和「存档根本没写」完全一样但代码看起来没问题。
    private func write<T: Encodable>(_ value: T, to url: URL, label: String) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            assertionFailure("\(label).json 写入失败：\(error)")
            NSLog("[PixelPet] %@.json 写入失败：%@", label, "\(error)")
        }
    }
}

/// 内存存档。测试用 —— 不碰文件系统，快且不用清理。
///
/// 还能断言「该落盘的时候真的落盘了」，这是文件实现给不了的。
final class MemoryPersistence: PetPersistence {
    private var pets: [PetState] = []
    private var wallet: PetWallet?

    private(set) var petSaveCount = 0
    private(set) var walletSaveCount = 0

    init(pets: [PetState] = [], wallet: PetWallet? = nil) {
        self.pets = pets
        self.wallet = wallet
    }

    func loadPets() -> [PetState] { pets }
    func loadWallet() -> PetWallet? { wallet }

    func save(pets: [PetState]) {
        self.pets = pets
        petSaveCount += 1
    }

    func save(wallet: PetWallet) {
        self.wallet = wallet
        walletSaveCount += 1
    }
}
