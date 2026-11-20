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
}
