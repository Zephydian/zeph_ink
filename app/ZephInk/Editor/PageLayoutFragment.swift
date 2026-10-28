import AppKit

/// A line laid out on the page, with whatever its `LineDecoration` asks for drawn around the text:
/// a quote bar, a code block's box, a divider, a bullet or a checkbox.
nonisolated final class PageLayoutFragment: NSTextLayoutFragment {
    private var paragraph: NSAttributedString? {
        (textElement as? NSTextParagraph)?.attributedString
    }

    private var decoration: LineDecoration? {
        guard let paragraph, paragraph.length > 0 else { return nil }
        return paragraph.attribute(.lineDecoration, at: 0, effectiveRange: nil) as? LineDecoration
    }

    /// The whole width of the text column, in this fragment's coordinates. The fragment itself starts
    /// at its paragraph's indent, but quote bars and code boxes reach back to the column's edge.
    private var columnBounds: CGRect {
        let width = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        return CGRect(x: -layoutFragmentFrame.minX, y: 0, width: width, height: layoutFragmentFrame.height)
    }

    /// TextKit only draws inside this rectangle, which by default hugs the glyphs.
    override var renderingSurfaceBounds: CGRect {
        guard let decoration else { return super.renderingSurfaceBounds }
        var bounds = super.renderingSurfaceBounds.union(columnBounds)
        if let image = imageRect(for: decoration) { bounds = bounds.union(image) }
        return bounds
    }

    /// Where a line's image (or its prompt) goes, in this fragment's coordinates: below the text.
    func imageRect(for decoration: LineDecoration) -> CGRect? {
        guard decoration.image != nil || decoration.imageNeedsAccess, let line = textLineFragments.last else { return nil }
        let top = line.typographicBounds.maxY + 7
        let x = textLineFragments.first?.typographicBounds.minX ?? 0
        if decoration.imageNeedsAccess {
            return CGRect(x: x, y: top, width: min(columnBounds.width - x, 360), height: LineDecoration.accessPromptHeight)
        }
        return CGRect(origin: CGPoint(x: x, y: top), size: decoration.imageSize)
    }

    /// Whether a point (in this fragment's coordinates) is on an image prompt asking for access.
    func isOnAccessPrompt(_ point: CGPoint) -> Bool {
        guard let decoration, decoration.imageNeedsAccess, let rect = imageRect(for: decoration) else { return false }
        return rect.contains(point)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        guard let decoration else {
            super.draw(at: point, in: context)
            return
        }
        let frame = columnBounds.offsetBy(dx: point.x, dy: point.y)
        context.saveGState()
        clipOutPageBreaks(frame: frame, origin: point, context: context)
        if let code = decoration.code { drawCodeBox(code, in: frame, context: context) }
        if decoration.quoteDepth > 0 { drawQuoteBars(decoration.quoteDepth, in: frame, context: context) }
        context.restoreGState()
        if decoration.isDivider { drawDivider(in: frame, context: context) }
        super.draw(at: point, in: context)
        if let bullet = decoration.bullet { drawBullet(at: bullet, origin: point, context: context) }
        if let task = decoration.task { drawCheckbox(at: task, isChecked: decoration.isChecked, origin: point, context: context) }
        if let rect = imageRect(for: decoration)?.offsetBy(dx: point.x, dy: point.y) {
            if let image = decoration.image {
                drawImage(image, in: rect, context: context)
            } else {
                drawAccessPrompt(in: rect, context: context)
            }
        }
    }

    // MARK: - Images

    private func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.clip()
        // The page is drawn flipped (y grows downwards); images draw the other way up.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// A dashed box in the image's place: the sandbox needs the person's OK to read the folder.
    private func drawAccessPrompt(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(Theme.rule.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.strokePath()
        context.restoreGState()
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let text = NSAttributedString(string: "Click to show images from this folder", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.inkSecondary,
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: rect.minX + 14, y: rect.midY - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A line that wraps across a page break: its code box and quote bar stop at the page's edge
    /// rather than crossing the gap between pages.
    private func clipOutPageBreaks(frame: CGRect, origin: CGPoint, context: CGContext) {
        guard let breaks = textLayoutManager?.textContainer?.exclusionPaths, !breaks.isEmpty else { return }
        let shift = CGPoint(x: origin.x - layoutFragmentFrame.minX, y: origin.y - layoutFragmentFrame.minY)
        let crossing = breaks.map { $0.bounds.offsetBy(dx: shift.x, dy: shift.y) }.filter { $0.intersects(frame) }
        guard !crossing.isEmpty else { return }
        context.addRect(frame.insetBy(dx: -4, dy: -4))
        for band in crossing { context.addRect(band.insetBy(dx: -20, dy: 0)) }
        context.clip(using: .evenOdd)
    }

    // MARK: - Blocks

    /// A code block's lines draw one box between them, rounded at the top and bottom.
    private func drawCodeBox(_ code: MarkdownAnalysis.CodeLine, in frame: CGRect, context: CGContext) {
        let radius: CGFloat = 6
        let rect = frame
        let path = CGMutablePath()
        let top = code.isFirst ? radius : 0, bottom = code.isLast ? radius : 0
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        if top > 0 { path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + top, y: rect.minY), radius: top) }
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        if top > 0 { path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + top), radius: top) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        if bottom > 0 { path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottom, y: rect.maxY), radius: bottom) }
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        if bottom > 0 { path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottom), radius: bottom) }
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(Theme.codeBackground.cgColor)
        context.fillPath()
    }

    /// One accent bar per quote level, down the whole line so a quote's lines join up.
    private func drawQuoteBars(_ depth: Int, in frame: CGRect, context: CGContext) {
        context.setFillColor(Theme.pageAccent.cgColor)
        let step = Theme.bodySize * 1.1
        for level in 0..<depth {
            context.fill(CGRect(x: frame.minX + CGFloat(level) * step, y: frame.minY, width: 3, height: frame.height))
        }
    }

    private func drawDivider(in frame: CGRect, context: CGContext) {
        context.setFillColor(Theme.rule.cgColor)
        context.fill(CGRect(x: frame.minX, y: frame.midY.rounded(), width: frame.width, height: 1))
    }

    // MARK: - List symbols

    /// Where a character of the first line sits: its left edge, the line's baseline, and its font.
    private func position(of offset: Int, origin: CGPoint) -> (x: CGFloat, baseline: CGFloat, font: NSFont)? {
        guard let paragraph, offset < paragraph.length, let line = textLineFragments.first,
              let font = paragraph.attribute(.font, at: offset, effectiveRange: nil) as? NSFont else { return nil }
        let bounds = line.typographicBounds
        let x = origin.x + bounds.minX + line.locationForCharacter(at: offset).x
        let baseline = origin.y + bounds.minY + line.glyphOrigin.y
        return (x, baseline, font)
    }

    private func drawBullet(at offset: Int, origin: CGPoint, context: CGContext) {
        guard let (x, baseline, font) = position(of: offset, origin: origin) else { return }
        let dash = NSAttributedString(string: "-", attributes: [.font: font]).size().width
        let size = font.pointSize * 0.3
        let center = CGPoint(x: x + dash / 2, y: baseline - font.xHeight / 2)
        context.setFillColor(Theme.ink.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
    }

    private func drawCheckbox(at offset: Int, isChecked: Bool, origin: CGPoint, context: CGContext) {
        guard let (x, baseline, font) = position(of: offset, origin: origin) else { return }
        let side = (font.pointSize * 0.95).rounded()
        let box = CGRect(x: x + 1, y: baseline - font.capHeight / 2 - side / 2, width: side, height: side)
        let path = CGPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        if isChecked {
            context.setFillColor(Theme.pageAccent.cgColor)
            context.fillPath()
            // The tick, drawn in the page color so it reads on the accent fill.
            context.setStrokeColor(Theme.page.cgColor)
            context.setLineWidth(2)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: box.minX + side * 0.27, y: box.midY + side * 0.02))
            context.addLine(to: CGPoint(x: box.minX + side * 0.44, y: box.minY + side * 0.7))
            context.addLine(to: CGPoint(x: box.minX + side * 0.74, y: box.minY + side * 0.3))
            context.strokePath()
        } else {
            context.setStrokeColor(Theme.marker.cgColor)
            context.setLineWidth(1.5)
            context.strokePath()
        }
    }
}
