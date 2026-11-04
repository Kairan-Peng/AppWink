enum ToggleInvocationSource {
    case hotKey
    case manual

    var showsStatusBanner: Bool {
        switch self {
        case .hotKey:
            return false
        case .manual:
            return true
        }
    }
}
