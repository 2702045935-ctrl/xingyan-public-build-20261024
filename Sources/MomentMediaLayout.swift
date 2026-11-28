import CoreGraphics

enum MomentMediaLayout {
    static let gap: CGFloat = 5
    static let gridRadius: CGFloat = 5
    static let singleRadius: CGFloat = 5
    static let singleMaxWidth: CGFloat = 220
    static let singleMaxHeight: CGFloat = 300

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
            gridWidth = min(width, 177)
        default:
            gridWidth = min(width, 269)
        }
        let usable = max(1, gridWidth - gap * CGFloat(columns - 1))
        let side = usable / CGFloat(columns)
        return CGSize(width: side, height: side)
    }

    static func singleImageSize(knownSize: CGSize?,
                                width: CGFloat,
                                fallbackRatio: CGFloat = 4.0 / 3.0) -> CGSize {
        let maxWidth = max(1, min(width, singleMaxWidth))
        guard let knownSize,
              knownSize.width > 0,
              knownSize.height > 0 else {
            let ratio = min(3, max(0.33, fallbackRatio))
            let fallbackWidth = ratio >= 1
                ? maxWidth
                : min(maxWidth, singleMaxHeight * ratio)
            return CGSize(width: fallbackWidth, height: fallbackWidth / ratio)
        }
        let scale = min(
            1,
            maxWidth / knownSize.width,
            singleMaxHeight / knownSize.height
        )
        return CGSize(
            width: max(1, (knownSize.width * scale).rounded(.down)),
            height: max(1, (knownSize.height * scale).rounded(.down))
        )
    }
}
