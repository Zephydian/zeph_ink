import AppKit
import Testing
@testable import ZephInk

/// Page sizes, and the bands text skips at page breaks.
@MainActor
struct PageGeometryTests {
    private let letter = NSSize(width: 612, height: 792)
    private let custom = NSSize(width: 432, height: 648)

    private func make(_ style: Preferences.PageStyle, width: CGFloat = 1000) -> PageGeometry {
        PageGeometry.make(style: style, margins: .normal, paper: letter, custom: custom, viewWidth: width)
    }

    @Test func continuousIsOnePageWithoutBreaks() {
        let page = make(.continuous)
        #expect(!page.isPaged)
        #expect(page.pageSize.width == Theme.pageMaxWidth)
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
        #expect(make(.square).pageSize == NSSize(width: Theme.pageMaxWidth, height: Theme.pageMaxWidth))
        #expect(make(.custom).pageSize == custom)
    }

    @Test func aPageWiderThanTheWindowNarrows() {
        let page = make(.paper, width: 500)
        #expect(page.pageSize.width < letter.width)
        #expect(page.pageSize.height == letter.height)
    }
}
