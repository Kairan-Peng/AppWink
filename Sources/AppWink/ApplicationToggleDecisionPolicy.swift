struct ApplicationToggleDecisionPolicy {
    func decision(for snapshot: ApplicationToggleDecisionSnapshot) -> ApplicationToggleDecision {
        switch snapshot {
        case .backgroundTarget, .frontmostNormalWithoutVisibleRegularWindow:
            return .systemEquivalentActivate
        case .frontmostImmersive:
            return .noOpFrontmostImmersiveWindow
        case .frontmostNormalWithVisibleRegularWindow:
            return .hide
        }
    }
}
