import CoreGraphics

struct AccessibilityWindowIdentityCandidate: Equatable {
    let windowNumber: Int
    let title: String?
    let bounds: CGRect?
}

enum AccessibilityWindowIdentityResolver {
    static func resolveWindowNumber(
        directWindowNumber: Int?,
        title: String?,
        bounds: CGRect?,
        preferredWindowNumbers: Set<Int>,
        candidates: [AccessibilityWindowIdentityCandidate]
    ) -> Int? {
        if let directWindowNumber {
            return directWindowNumber
        }

        if let bounds {
            let matchingCandidates = candidates.filter { candidate in
                guard let candidateBounds = candidate.bounds else {
                    return false
                }

                return approximatelyEqual(candidateBounds, bounds)
            }

            if matchingCandidates.count == 1 {
                return matchingCandidates[0].windowNumber
            }

            let preferredMatches = matchingCandidates.filter {
                preferredWindowNumbers.contains($0.windowNumber)
            }

            if preferredMatches.count == 1 {
                return preferredMatches[0].windowNumber
            }
        }

        if let title {
            let matchingCandidates = candidates.filter { $0.title == title }
            if matchingCandidates.count == 1 {
                return matchingCandidates[0].windowNumber
            }

            let preferredMatches = matchingCandidates.filter {
                preferredWindowNumbers.contains($0.windowNumber)
            }

            if preferredMatches.count == 1 {
                return preferredMatches[0].windowNumber
            }
        }

        return nil
    }
}

private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
        abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
        abs(lhs.size.width - rhs.size.width) <= tolerance &&
        abs(lhs.size.height - rhs.size.height) <= tolerance
}
