import AppKit

/// The zoom steps the status bar's menu and View → Zoom In and Zoom Out move through.
nonisolated enum Zoom {
    static let steps: [CGFloat] = [0.5, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    /// The next step up or down from a zoom (which may sit between steps after a pinch).
    static func step(from zoom: CGFloat, up: Bool) -> CGFloat {
        if up { return steps.first { $0 > zoom + 0.001 } ?? steps.last! }
        return steps.last { $0 < zoom - 0.001 } ?? steps.first!
    }

    /// The zoom at which a page this wide (with the desk around it) fills a view this wide.
    static func fitting(pageWidth: CGFloat, desk: CGFloat, in viewWidth: CGFloat) -> CGFloat {
        guard pageWidth > 0 else { return 1 }
        return min(max(viewWidth / (pageWidth + desk * 2), Preferences.minZoom), Preferences.maxZoom)
    }
}
