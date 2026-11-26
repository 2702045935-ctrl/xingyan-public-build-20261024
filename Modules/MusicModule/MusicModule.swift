import Foundation

public enum MusicModule {
    public static let identifier = "xingyan.music"
}

public enum MusicPlaybackState: String, Codable, CaseIterable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case interrupted
    case recovering
    case unavailable
}

public struct MusicPlaybackPolicy: Hashable, Sendable {
    public var networkConstrained: Bool
    public var networkExpensive: Bool

    public init(networkConstrained: Bool, networkExpensive: Bool) {
        self.networkConstrained = networkConstrained
        self.networkExpensive = networkExpensive
    }

    public var preferredForwardBuffer: Double {
        if networkConstrained { return 8 }
        if networkExpensive { return 5 }
        return 3
    }

    public var waitsToMinimizeStalling: Bool {
        networkConstrained || networkExpensive
    }
}

public struct MusicPlaybackSnapshot: Hashable, Sendable {
    public var position: Double
    public var duration: Double
    public var state: MusicPlaybackState

    public init(position: Double, duration: Double, state: MusicPlaybackState) {
        self.position = max(0, position)
        self.duration = max(0, duration)
        self.state = state
    }

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }
}
