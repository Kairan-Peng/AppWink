import Foundation
import AppWinkCore

/// 集中管理品牌文案，避免 UI 和运行时逻辑散落硬编码字符串。
enum AppBrand {
    static let fallbackDisplayName = "AppWink"

    static var tagline: String {
        LocalizationManager.shared.string(for: .tagline)
    }

    /// 优先读取 Bundle 中的展示名称，缺失时再回退到工程默认值。
    static var displayName: String {
        if let bundleDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !bundleDisplayName.isEmpty {
            return bundleDisplayName
        }

        if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty {
            return bundleName
        }

        return fallbackDisplayName
    }
}
