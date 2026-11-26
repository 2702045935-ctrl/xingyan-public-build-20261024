import CoreGraphics

enum MultiImageMosaic {
    static let gap: CGFloat = 3

    static func visibleCount(for total: Int) -> Int {
        if total <= 4 { return max(0, total) }
        return 3
    }

    static func containerSize(for total: Int, width: CGFloat) -> CGSize {
        let w = max(1, width)
        if total <= 1 {
            return CGSize(width: w, height: min(188, w * 0.82))
        }
        if total == 2 {
            return CGSize(width: w, height: floor((w - gap) / 2))
        }
        return CGSize(width: w, height: w)
    }

    static func frames(count: Int, in bounds: CGRect) -> [CGRect] {
        let visible = min(visibleCount(for: count), 4)
        guard visible > 0 else { return [] }
        if visible == 1 { return [bounds] }

        let innerW = max(1, bounds.width - gap)
        let innerH = max(1, bounds.height - gap)

        if visible == 2 {
            let leftW = floor((bounds.width - gap) / 2)
            return [
                CGRect(x: bounds.minX, y: bounds.minY,
                       width: leftW, height: bounds.height),
                CGRect(x: bounds.minX + leftW + gap, y: bounds.minY,
                       width: bounds.width - leftW - gap, height: bounds.height)
            ]
        }

        if visible == 3 {
            let heroW = floor(innerW * 0.64)
            let sideW = bounds.width - heroW - gap
            let topH = floor((bounds.height - gap) / 2)
            return [
                CGRect(x: bounds.minX, y: bounds.minY,
                       width: heroW, height: bounds.height),
                CGRect(x: bounds.minX + heroW + gap, y: bounds.minY,
                       width: sideW, height: topH),
                CGRect(x: bounds.minX + heroW + gap,
                       y: bounds.minY + topH + gap,
                       width: sideW,
                       height: bounds.height - topH - gap)
            ]
        }

        let leftW = floor((bounds.width - gap) / 2)
        let topH = floor((bounds.height - gap) / 2)
        return [
            CGRect(x: bounds.minX, y: bounds.minY,
                   width: leftW, height: topH),
            CGRect(x: bounds.minX + leftW + gap, y: bounds.minY,
                   width: bounds.width - leftW - gap, height: topH),
            CGRect(x: bounds.minX, y: bounds.minY + topH + gap,
                   width: leftW, height: bounds.height - topH - gap),
            CGRect(x: bounds.minX + leftW + gap,
                   y: bounds.minY + topH + gap,
                   width: bounds.width - leftW - gap,
                   height: bounds.height - topH - gap)
        ]
    }
}
