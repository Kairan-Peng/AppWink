import Foundation

/// 基于 `UserDefaults` 的默认配置存储，同时负责兼容旧版持久化键的迁移。
public final class UserDefaultsAppConfigurationStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey: String
    private let legacyStorageKeys: [String]
    private let legacyPersistentDomains: [String]
    private let saveQueue: DispatchQueue

    /// 允许同时注入当前键和历史键，方便本地迁移验证与单元测试覆盖。
    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.kairanpeng.appwink.configuration",
        legacyStorageKeys: [String] = ["com.kairanpeng.mytool.configuration"],
        legacyPersistentDomains: [String] = ["com.kairanpeng.mytool"]
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.legacyStorageKeys = legacyStorageKeys
        self.legacyPersistentDomains = legacyPersistentDomains
        self.saveQueue = DispatchQueue(
            label: "com.kairanpeng.appwink.configuration-store.save",
            qos: .utility
        )
    }

    /// 先读取当前配置；若不存在，则尝试迁移旧版数据并立即写回新键。
    public func load() throws -> AppConfiguration {
        if let data = defaults.data(forKey: storageKey) {
            return try decodeConfiguration(from: data)
        }

        if let legacyConfiguration = try loadLegacyConfiguration() {
            try save(legacyConfiguration)
            return legacyConfiguration
        }

        return AppConfiguration()
    }

    public func save(_ configuration: AppConfiguration) throws {
        var saveError: Error?

        saveQueue.sync {
            do {
                let data = try JSONEncoder().encode(configuration)
                defaults.set(data, forKey: storageKey)
            } catch {
                saveError = error
            }
        }

        if let saveError {
            throw saveError
        }
    }

    /// 排序保存不需要阻塞主线程，放到串行队列异步写回以减少 drop 释放时的卡顿。
    public func saveAsync(
        _ configuration: AppConfiguration,
        completion: (@MainActor @Sendable (Error?) -> Void)? = nil
    ) {
        saveQueue.async { [self] in
            let saveError: Error?

            do {
                let data = try JSONEncoder().encode(configuration)
                defaults.set(data, forKey: storageKey)
                saveError = nil
            } catch {
                saveError = error
            }

            guard let completion else {
                return
            }

            Task { @MainActor in
                completion(saveError)
            }
        }
    }

    /// 兼容两类历史数据来源：
    /// 1. 直接保存在旧 key 下的数据
    /// 2. 残留在旧 persistent domain 中的数据
    private func loadLegacyConfiguration() throws -> AppConfiguration? {
        for legacyStorageKey in legacyStorageKeys {
            if let data = defaults.data(forKey: legacyStorageKey) {
                return try decodeConfiguration(from: data)
            }
        }

        for domainName in legacyPersistentDomains {
            guard let domain = defaults.persistentDomain(forName: domainName) else {
                continue
            }

            for legacyStorageKey in legacyStorageKeys {
                if let data = domain[legacyStorageKey] as? Data {
                    return try decodeConfiguration(from: data)
                }
            }
        }

        return nil
    }

    /// 将底层 JSON 数据统一解码为配置模型，集中收敛解析入口。
    private func decodeConfiguration(from data: Data) throws -> AppConfiguration {
        try JSONDecoder().decode(AppConfiguration.self, from: data)
    }
}
