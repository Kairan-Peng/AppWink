struct FinderCurrentSpaceVisibilityPolicy {
    func hasVisibleWindowOnCurrentSpace(
        accessibilityDerivedVisibility: Bool?,
        currentSpaceWindowServerWindowCount: Int
    ) -> Bool {
        if let accessibilityDerivedVisibility {
            return accessibilityDerivedVisibility
        }

        return currentSpaceWindowServerWindowCount > 0
    }
}
