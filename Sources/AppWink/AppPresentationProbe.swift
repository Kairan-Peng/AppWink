struct AppPresentationSnapshot: Equatable {
    let isTargetRunning: Bool
    let isTargetFrontmost: Bool
    let frontmostPresentation: FrontmostWindowPresentation
    let hasVisibleRegularWindowOnCurrentSpace: Bool
    let isFinder: Bool

    var applicationToggleDecisionSnapshot: ApplicationToggleDecisionSnapshot {
        guard isTargetRunning, isTargetFrontmost else {
            return .backgroundTarget
        }

        switch frontmostPresentation {
        case .immersive:
            return .frontmostImmersive
        case .normal:
            return hasVisibleRegularWindowOnCurrentSpace
                ? .frontmostNormalWithVisibleRegularWindow
                : .frontmostNormalWithoutVisibleRegularWindow
        }
    }
}

struct AppPresentationProbe {
    typealias BoolProvider = () -> Bool
    typealias FrontmostPresentationProvider = () -> FrontmostWindowPresentation

    private let isTargetFrontmost: BoolProvider
    private let frontmostPresentation: FrontmostPresentationProvider
    private let nonFinderVisibleRegularWindowOnCurrentSpace: BoolProvider
    private let finderVisibleRegularWindowOnCurrentSpace: BoolProvider

    init(
        isTargetFrontmost: @escaping BoolProvider = { false },
        frontmostPresentation: @escaping FrontmostPresentationProvider = { .normal },
        nonFinderVisibleRegularWindowOnCurrentSpace: @escaping BoolProvider = { false },
        finderVisibleRegularWindowOnCurrentSpace: @escaping BoolProvider = { false }
    ) {
        self.isTargetFrontmost = isTargetFrontmost
        self.frontmostPresentation = frontmostPresentation
        self.nonFinderVisibleRegularWindowOnCurrentSpace = nonFinderVisibleRegularWindowOnCurrentSpace
        self.finderVisibleRegularWindowOnCurrentSpace = finderVisibleRegularWindowOnCurrentSpace
    }

    func snapshot(
        isTargetRunning: Bool,
        isFinder: Bool
    ) -> AppPresentationSnapshot {
        guard isTargetRunning else {
            return AppPresentationSnapshot(
                isTargetRunning: false,
                isTargetFrontmost: false,
                frontmostPresentation: .normal,
                hasVisibleRegularWindowOnCurrentSpace: false,
                isFinder: isFinder
            )
        }

        let effectiveIsTargetFrontmost = isTargetFrontmost()
        guard effectiveIsTargetFrontmost else {
            return AppPresentationSnapshot(
                isTargetRunning: true,
                isTargetFrontmost: false,
                frontmostPresentation: .normal,
                hasVisibleRegularWindowOnCurrentSpace: false,
                isFinder: isFinder
            )
        }

        let effectiveFrontmostPresentation = frontmostPresentation()
        let hasVisibleRegularWindowOnCurrentSpace: Bool
        switch effectiveFrontmostPresentation {
        case .immersive:
            hasVisibleRegularWindowOnCurrentSpace = false
        case .normal:
            hasVisibleRegularWindowOnCurrentSpace = isFinder
                ? finderVisibleRegularWindowOnCurrentSpace()
                : nonFinderVisibleRegularWindowOnCurrentSpace()
        }

        return AppPresentationSnapshot(
            isTargetRunning: true,
            isTargetFrontmost: true,
            frontmostPresentation: effectiveFrontmostPresentation,
            hasVisibleRegularWindowOnCurrentSpace: hasVisibleRegularWindowOnCurrentSpace,
            isFinder: isFinder
        )
    }
}
