import AppKit
import Testing
@testable import ZephInk

/// Page sizes, and the bands text skips at page breaks.
@MainActor
struct PageGeometryTests {
    private let letter = NSSize(width: 612, height: 792)
    private let custom = NSSize(width: 432, height: 648)

    /// The page geometry at the default 12-point text (the real app's text size setting is shared with
    /// the tests, so it's set for the moment and put back).
    private func make(_ style: Preferences.PageStyle, width: CGFloat = 1000) -> PageGeometry {
        let previous = UserDefaults.standard.object(forKey: Preferences.Key.textSize)
        UserDefaults.standard.set(12.0, forKey: Preferences.Key.textSize)
        defer { UserDefaults.standard.set(previous, forKey: Preferences.Key.textSize) }
        return PageGeometry.make(style: style, margins: .normal, paper: letter, custom: custom, viewWidth: width)
    }

    private var pageMaxWidth: CGFloat { 612 }

    @Test func continuousIsOnePageWithoutBreaks() {
        let page = make(.continuous)
        #expect(!page.isPaged)
        #expect(page.pageSize.width == pageMaxWidth)
        #expect(page.breaks(pages: 3, width: 500).isEmpty)
        #expect(page.pageCount(forTextHeight: 50_000) == 1)
    }

    @Test func paperPagesAreRealSizeWithMarginsOnEverySide() {
        let page = make(.paper)
        #expect(page.isPaged)
        #expect(page.pageSize == letter)
        #expect(page.contentHeight == CGFloat(792 - 72 * 2))
        #expect(page.pageStride == 792 + PageGeometry.gap)
    }

    @Test func breaksCoverTheMarginsAndTheGap() {
        let page = make(.paper)
        let breaks = page.breaks(pages: 2, width: 468)
        #expect(breaks.count == 2)
        #expect(breaks[0].minY == page.contentHeight)
        #expect(breaks[0].maxY == page.pageStride)                    // the next page's text starts here
        #expect(breaks[1].minY == page.pageStride + page.contentHeight)
    }

    @Test func pagesAreCountedFromTheTextHeight() {
        let page = make(.paper)
        #expect(page.pageCount(forTextHeight: 10) == 1)
        #expect(page.pageCount(forTextHeight: page.pageStride + 10) == 2)
    }

    @Test func squareAndCustomUseTheirSizes() {
        #expect(make(.square).pageSize == NSSize(width: pageMaxWidth, height: pageMaxWidth))
        #expect(make(.custom).pageSize == custom)
    }

    @Test func aPageWiderThanTheWindowNarrows() {
        let page = make(.paper, width: 500)
        #expect(page.pageSize.width < letter.width)
        #expect(page.pageSize.height == letter.height)
    }
}

/// Zoom steps and Fit Page Width.
@MainActor
struct ZoomTests {
    @Test func zoomMovesThroughSteps() {
        #expect(Zoom.step(from: 1, up: true) == 1.1)
        #expect(Zoom.step(from: 1, up: false) == 0.9)
        #expect(Zoom.step(from: 1.33, up: true) == 1.5)    // from between steps, after a pinch
        #expect(Zoom.step(from: 3, up: true) == 3)
        #expect(Zoom.step(from: 0.5, up: false) == 0.5)
    }

    @Test func fitPageWidthFillsTheView() {
        // A 720-point page with 28 points of desk either side, in a 2,000-point-wide pane.
        let zoom = Zoom.fitting(pageWidth: 720, desk: 28, in: 2000)
        #expect(abs(zoom * (720 + 56) - 2000) < 1)
        #expect(Zoom.fitting(pageWidth: 720, desk: 28, in: 100_000) == Preferences.maxZoom)
    }
}
