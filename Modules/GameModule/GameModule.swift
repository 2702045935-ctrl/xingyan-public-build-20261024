import Foundation

public enum GameModule {
    public static let identifier = "xingyan.game"
}

public enum GameRuntimeBudget {
    public static let maximumDevicePixelRatio = 2
    public static let assetDownloadConcurrency = 4
    public static let maximumVisibleVideoPlayback = 1
}

public struct GameFocusPolicy: Hashable, Sendable {
    public var minimumVisibleFraction: Double

    public init(minimumVisibleFraction: Double = 0.72) {
        self.minimumVisibleFraction = min(1, max(0, minimumVisibleFraction))
    }

    public func shouldAutoPlay(visibleFraction: Double,
                               userPaused: Bool = false) -> Bool {
        !userPaused && visibleFraction >= minimumVisibleFraction
    }
}
