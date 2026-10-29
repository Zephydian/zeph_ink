import CoreGraphics

/// Where printed pages break, worked out from the text laid out as one long column.
///
/// The column is made of blocks (a paragraph, a heading, a list item, an image, a code block…). A page
/// takes whole blocks while they fit. When the next one doesn't, the page breaks inside it at a line
/// boundary if it allows that, or before it. Breaking before a block takes any headings above it along,
/// so a heading never sits alone at the bottom of a page. Blank space never starts a page.
nonisolated enum Pagination {
    struct Block: Equatable {
        /// The block's top and bottom in the column.
        var top: CGFloat
        var bottom: CGFloat
        /// Where the page may break inside the block (between its lines), top to bottom.
        var breaks: [CGFloat] = []
        /// A heading: it goes to the next page with the block after it.
        var keepsWithNext = false
        /// A blank line (or another spacer): left out at the top of a page.
        var isBlank = false
    }

    /// A page's slice of the column.
    struct Page: Equatable {
        var top: CGFloat
        var bottom: CGFloat
    }

    /// The pages for blocks in column order, each holding `height` points of the column. Always at
    /// least one page.
    static func pages(for blocks: [Block], height: CGFloat) -> [Page] {
        var pages: [Page] = []
        var top = blocks.first?.top ?? 0
        var index = 0
        while true {
            while index < blocks.count, blocks[index].isBlank, blocks[index].top >= top - 0.5 { index += 1 }
            guard index < blocks.count else { break }
            top = max(top, blocks[index].top)
            let limit = top + height

            var next = index
            while next < blocks.count, blocks[next].bottom <= limit + 0.5 { next += 1 }
            guard next < blocks.count else {
                pages.append(Page(top: top, bottom: blocks[blocks.count - 1].bottom))
                break
            }

            // Break inside the block that doesn't fit, as low as it allows.
            if let cut = blocks[next].breaks.last(where: { $0 > top + 0.5 && $0 <= limit + 0.5 }) {
                pages.append(Page(top: top, bottom: cut))
                top = cut
                index = next
                continue
            }
            // A block taller than a page that can't break: cut it at the page's height.
            guard next > index else {
                pages.append(Page(top: top, bottom: limit))
                top = limit
                continue
            }
            // Break before it, taking the headings (and the blank lines around them) above it along,
            // unless that would leave the page empty.
            var first = next
            while first > index, blocks[first - 1].isBlank || blocks[first - 1].keepsWithNext { first -= 1 }
            if first == index || !blocks[index..<first].contains(where: { !$0.isBlank }) { first = next }
            pages.append(Page(top: top, bottom: blocks[first - 1].bottom))
            top = blocks[first].top
            index = first
        }
        return pages.isEmpty ? [Page(top: 0, bottom: 0)] : pages
    }

    /// The lines a paragraph may break between: never leaving a single line behind or carrying one
    /// over (no widows or orphans), so paragraphs under four lines move whole.
    static func breaks(lineBottoms: [CGFloat]) -> [CGFloat] {
        guard lineBottoms.count >= 4 else { return [] }
        return Array(lineBottoms[1..<(lineBottoms.count - 2)])
    }
}
