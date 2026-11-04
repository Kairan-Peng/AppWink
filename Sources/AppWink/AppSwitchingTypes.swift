enum FrontmostWindowPresentation: Equatable {
    case normal
    case immersive
}

enum ApplicationToggleDecision: Equatable {
    case hide
    case noOpFrontmostImmersiveWindow
    case systemEquivalentActivate
}

enum ApplicationToggleDecisionSnapshot: Equatable {
    case backgroundTarget
    case frontmostImmersive
    case frontmostNormalWithVisibleRegularWindow
    case frontmostNormalWithoutVisibleRegularWindow
}
