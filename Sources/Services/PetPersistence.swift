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
    func loadPet() -> PetState?
    func loadWallet() -> PetWallet?
    func save(pet: PetState)
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

    func loadPet() -> PetState? {
        guard let data = try? Data(contentsOf: petURL) else { return nil }
        return try? JSONDecoder().decode(PetState.self, from: data)
    }

    func loadWallet() -> PetWallet? {
        guard let data = try? Data(contentsOf: walletURL) else { return nil }
        return try? JSONDecoder().decode(PetWallet.self, from: data)
    }

    /// 写盘用 `.atomic` —— 中途被杀不会留下半个文件
    func save(pet: PetState) {
        guard let d = try? JSONEncoder().encode(pet) else { return }
        try? d.write(to: petURL, options: .atomic)
    }

    func save(wallet: PetWallet) {
        guard let d = try? JSONEncoder().encode(wallet) else { return }
        try? d.write(to: walletURL, options: .atomic)
    }
}

/// 内存存档。测试用 —— 不碰文件系统，快且不用清理。
///
/// 还能断言「该落盘的时候真的落盘了」，这是文件实现给不了的。
final class MemoryPersistence: PetPersistence {
    private var pet: PetState?
    private var wallet: PetWallet?

    private(set) var petSaveCount = 0
    private(set) var walletSaveCount = 0

    init(pet: PetState? = nil, wallet: PetWallet? = nil) {
        self.pet = pet
        self.wallet = wallet
    }

    func loadPet() -> PetState? { pet }
    func loadWallet() -> PetWallet? { wallet }

    func save(pet: PetState) {
        self.pet = pet
        petSaveCount += 1
    }

    func save(wallet: PetWallet) {
        self.wallet = wallet
        walletSaveCount += 1
    }
}
