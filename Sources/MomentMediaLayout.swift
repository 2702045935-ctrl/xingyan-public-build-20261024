import CoreGraphics

enum MomentMediaLayout {
    static let gap: CGFloat = 5
    static let gridRadius: CGFloat = 2
    static let singleRadius: CGFloat = 12
    static let gridCellMax: CGFloat = 86

    static func columns(for count: Int) -> Int {
        switch count {
        case 0, 1:
            return 1
        case 2, 4:
            return 2
        default:
            return 3
        }
    }

    static func gridCellSize(count: Int, width: CGFloat) -> CGSize {
        let columns = max(1, columns(for: count))
        let usable = max(1, width - gap * CGFloat(columns - 1))
        let side = min(gridCellMax, usable / CGFloat(columns))
        return CGSize(width: side, height: side)
    }

    static func singleImageSize(knownRatio: CGFloat?, width: CGFloat) -> CGSize {
        let ratio = min(1.55, max(0.78, knownRatio ?? 1.25))
        let singleWidth = min(width, max(184, width * 0.62))
        return CGSize(
            width: singleWidth,
            height: min(290, max(148, singleWidth / ratio))
        )
    }

    /// WeChat-style single video: preserve the source aspect ratio, use the
    /// full content width for landscape clips, and cap tall clips at 4:5.
    static func singleVideoSize(knownRatio: CGFloat?, width: CGFloat) -> CGSize {
        let ratio = min(2.0, max(0.5, knownRatio ?? 1.25))
        let maxHeight = width * 1.25
        let naturalHeight = width / ratio
        if naturalHeight <= maxHeight {
            return CGSize(width: width, height: max(150, naturalHeight))
        }
        return CGSize(width: maxHeight * ratio, height: maxHeight)
    }
}
