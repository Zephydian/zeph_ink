import AppKit

/// Where the pages go in an editor of a given width: their size, the padding around the text, and,
/// for paged styles, the bands between pages that text has to skip.
///
/// Continuous is one page as wide as the text column allows, as tall as the text. Paper, Square and
/// Custom Size are separate pages of a fixed size, one under the other with a gap between them.
/// Their text flows from page to page because each gap (with the bottom margin above it and the top
/// margin below it) is an exclusion path in the text container.
nonisolated struct PageGeometry: Equatable {
    /// Page width and height in points (height nil for Continuous).
    var pageSize: NSSize
    var isPaged: Bool
    /// Space between the page's edges and its text.
    var padding: NSEdgeInsets
    /// The desk around the pages.
    var desk: NSSize

    /// The gap between pages.
    static let gap: CGFloat = 24

    static func == (a: PageGeometry, b: PageGeometry) -> Bool {
        a.pageSize == b.pageSize && a.isPaged == b.isPaged && a.desk == b.desk
            && a.padding.top == b.padding.top && a.padding.left == b.padding.left
            && a.padding.bottom == b.padding.bottom && a.padding.right == b.padding.right
    }

    /// The pages for the current settings, in a view this wide.
    static func current(viewWidth: CGFloat) -> PageGeometry {
        make(style: Preferences.pageStyle, margins: Preferences.margins, paper: Preferences.paperSize.size,
             custom: Preferences.customPageSize, viewWidth: viewWidth)
    }

    static func make(style: Preferences.PageStyle, margins: Preferences.Margins, paper: NSSize, custom: NSSize,
                     viewWidth: CGFloat) -> PageGeometry {
        let isNarrow = viewWidth < Theme.narrowWidth
        let desk = isNarrow ? Theme.narrowDeskMargin : Theme.deskMargin
        let available = max(viewWidth - desk.width * 2, 200)
        let side = isNarrow ? Theme.narrowPagePadding.width : margins.padding

        switch style {
        case .continuous:
            let top = isNarrow ? Theme.narrowPagePadding.height : Theme.pagePadding.height
            return PageGeometry(pageSize: NSSize(width: min(Theme.pageMaxWidth, available), height: 0), isPaged: false,
                                padding: NSEdgeInsets(top: top, left: side, bottom: top, right: side), desk: desk)
        case .paper, .square, .custom:
            var size: NSSize
            switch style {
            case .paper: size = paper
            case .square: size = NSSize(width: Theme.pageMaxWidth, height: Theme.pageMaxWidth)
            default: size = custom
            }
            // A page wider than the window gets narrower (its height stays), so text never hides off the side.
            size.width = min(size.width, available)
            // Margins on all four sides, but never more than a third of the page.
            let vertical = min(margins.padding, size.height / 3)
            let horizontal = min(side, size.width / 3)
            return PageGeometry(pageSize: size, isPaged: true,
                                padding: NSEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal), desk: desk)
        }
    }

    // MARK: - Pages

    /// The height of text a page holds.
    var contentHeight: CGFloat { max(pageSize.height - padding.top - padding.bottom, 40) }

    /// From one page's top to the next's.
    var pageStride: CGFloat { pageSize.height + Self.gap }

    /// How many pages text of this height needs (in the text container's coordinates).
    func pageCount(forTextHeight height: CGFloat) -> Int {
        guard isPaged else { return 1 }
        return max(1, Int(ceil((height - 0.5) / pageStride)))
    }

    /// The bands text skips between pages, in text container coordinates: the bottom margin of each
    /// page, the gap, and the next page's top margin.
    func breaks(pages: Int, width: CGFloat) -> [NSRect] {
        guard isPaged, pages > 0 else { return [] }
        return (0..<pages).map { page in
            NSRect(x: 0, y: CGFloat(page) * pageStride + contentHeight,
                   width: width, height: padding.bottom + Self.gap + padding.top)
        }
    }

    /// The page rectangles in the view, for drawing.
    func pageRects(count: Int, viewWidth: CGFloat, viewHeight: CGFloat) -> [NSRect] {
        let x = ((viewWidth - pageSize.width) / 2).rounded()
        guard isPaged else {
            return [NSRect(x: x, y: desk.height, width: pageSize.width, height: max(viewHeight - desk.height * 2, 0))]
        }
        return (0..<count).map { NSRect(x: x, y: desk.height + CGFloat($0) * pageStride, width: pageSize.width, height: pageSize.height) }
    }

    /// Where the text starts inside the view (the text container inset).
    func textInset(viewWidth: CGFloat) -> NSSize {
        NSSize(width: ((viewWidth - pageSize.width) / 2).rounded() + padding.left, height: desk.height + padding.top)
    }

    /// How tall the view must be to show every page and the desk below the last.
    func viewHeight(pages: Int) -> CGFloat {
        desk.height * 2 + CGFloat(pages) * pageStride - Self.gap
    }
}
