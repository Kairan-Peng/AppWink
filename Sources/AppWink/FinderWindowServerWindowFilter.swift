import CoreGraphics

struct FinderWindowServerWindowFilter {
    private let minimumBrowserWindowWidth: CGFloat
    private let minimumBrowserWindowHeight: CGFloat

    init(
        minimumBrowserWindowWidth: CGFloat = 200,
        minimumBrowserWindowHeight: CGFloat = 120
    ) {
        self.minimumBrowserWindowWidth = minimumBrowserWindowWidth
        self.minimumBrowserWindowHeight = minimumBrowserWindowHeight
    }

    func isBrowserWindow(bounds: CGRect?) -> Bool {
        guard let bounds else {
            return false
        }

        let size = bounds.standardized.size
        return size.width >= minimumBrowserWindowWidth &&
            size.height >= minimumBrowserWindowHeight
    }
}
