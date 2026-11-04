import Foundation
import ServiceManagement

/// 描述登录项在当前构建和系统状态下的可用性。
enum LaunchAtLoginState: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var isEnabled: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .unavailable:
            return false
        }
    }
}

@MainActor
/// 抽象开机自启控制器，便于 `AppModel` 注入假对象做测试。
protocol LaunchAtLoginControlling: AnyObject {
    func status() -> LaunchAtLoginState
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
/// 基于 `SMAppService.mainApp` 管理登录项注册。
final class LaunchAtLoginController: LaunchAtLoginControlling {
    private let service = SMAppService.mainApp

    /// 将 `ServiceManagement` 的原始状态收敛为更稳定的 UI 语义。
    nonisolated static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            // 在部分真实签名主程序上，首次注册前也可能先读到 `.notFound`。
            // 这里优先允许用户触发一次真实注册，而不是把开关永久灰掉。
            return .disabled
        @unknown default:
            return .unavailable
        }
    }

    /// 将系统原始状态映射为 UI 可消费的语义化枚举。
    func status() -> LaunchAtLoginState {
        Self.state(for: service.status)
    }

    /// 注册或移除登录项，错误直接向上抛给上层统一提示。
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
