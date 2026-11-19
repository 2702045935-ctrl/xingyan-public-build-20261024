import CoreGraphics

enum MomentMediaLayout {
    static let gap: CGFloat = 4
    static let gridRadius: CGFloat = 11
    static let singleRadius: CGFloat = 14

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
        let gridWidth: CGFloat
        switch columns {
        case 2:
            gridWidth = min(width, max(198, width * 0.64))
        default:
            gridWidth = min(width, max(252, width * 0.80))
        }
        let usable = max(1, gridWidth - gap * CGFloat(columns - 1))
        let side = usable / CGFloat(columns)
        return CGSize(width: side, height: side)
    }

    static func singleImageSize(knownRatio: CGFloat?, width: CGFloat) -> CGSize {
        let ratio = min(1.55, max(0.78, knownRatio ?? 1.25))
        let singleWidth = min(width, max(188, width * 0.66))
        return CGSize(
            width: singleWidth,
            height: min(300, max(150, singleWidth / ratio))
        )
    }
}
