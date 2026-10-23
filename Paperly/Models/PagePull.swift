import Foundation

public enum PageScrollDirection: String, CaseIterable, Identifiable, Sendable {
    case vertical = "Vertical", horizontal = "Horizontal"
    public var id: String { rawValue }
}

/// A deliberate overscroll, measured in viewport points rather than zoomed page units.
public enum PagePullAction: Equatable, Sendable {
    case previous, next, add

    public static func resolve(offset: Double, minimum: Double, maximum: Double,
                               crossOverscroll: Double, pageIndex: Int, pageCount: Int,
                               threshold: Double = 72) -> Self? {
        guard offset.isFinite, minimum.isFinite, maximum.isFinite,
              crossOverscroll.isFinite, threshold.isFinite, threshold > 0,
              maximum >= minimum, pageIndex >= 0, pageIndex < pageCount else { return nil }
        let forward = offset - maximum, backward = minimum - offset
        let distance = max(forward, backward)
        guard distance >= threshold, distance > abs(crossOverscroll) * 1.25 else { return nil }
        if backward > forward { return pageIndex > 0 ? .previous : nil }
        return pageIndex + 1 < pageCount ? .next : .add
    }
}

public enum PagePresentation: String, CaseIterable, Identifiable, Sendable {
    case paged = "Page by page", continuous = "Continuous"
    public var id: String { rawValue }
}
