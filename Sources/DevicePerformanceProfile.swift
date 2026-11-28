import Foundation
import UIKit

enum DevicePerformanceTier: Int {
    case legacy
    case balanced
    case high
}

/// Runtime performance policy shared by rendering, media and scrolling.
/// Hardware only selects the starting tier; low power, thermal pressure and
/// memory warnings can temporarily lower it without removing any data.
final class DevicePerformanceProfile: ObservableObject {
    static let shared = DevicePerformanceProfile()

    @Published private(set) var revision = 0

    private let physicalBytes: UInt64
    private let baseTier: DevicePerformanceTier
    private var reducedUntil = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    private init() {
        physicalBytes = ProcessInfo.processInfo.physicalMemory
        if physicalBytes >= 5_500_000_000 {
            baseTier = .high
        } else if physicalBytes >= 3_500_000_000 {
            baseTier = .balanced
        } else {
            baseTier = .legacy
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })
        observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })
        observers.append(center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            reducedUntil = Date().addingTimeInterval(20)
            refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                self?.refresh()
            }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    var physicalMemoryGB: Double {
        Double(physicalBytes) / 1_000_000_000
    }

    var tier: DevicePerformanceTier {
        var result = baseTier

        if Date() < reducedUntil {
            result = .legacy
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            result = result.degraded
        }

        switch ProcessInfo.processInfo.thermalState {
        case .serious:
            result = result.degraded
        case .critical:
            result = .legacy
        case .nominal, .fair:
            break
        @unknown default:
            result = result.degraded
        }
        return result
    }

    var allowsLiquidGlass: Bool {
        tier == .high
    }

    var allowsBackdropBlur: Bool {
        tier != .legacy
    }

    var allowsDecorativeMotion: Bool {
        tier == .high
    }

    var videoPlayerLimit: Int {
        switch tier {
        case .high: return 4
        case .balanced: return 2
        case .legacy: return 1
        }
    }

    var videoLookAhead: Int {
        tier == .legacy ? 1 : 2
    }

    var imageMaxSide: CGFloat {
        switch tier {
        case .high: return 2_048
        case .balanced: return 1_536
        case .legacy: return 1_024
        }
    }

    var avatarMaxSide: CGFloat {
        tier == .legacy ? 192 : 320
    }

    func limitedImageSide(_ requested: CGFloat) -> CGFloat {
        min(max(64, requested), imageMaxSide)
    }

    func limitedAvatarSide(_ requested: CGFloat) -> CGFloat {
        min(max(48, requested), avatarMaxSide)
    }

    private func refresh() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
            return
        }
        revision &+= 1
    }
}

private extension DevicePerformanceTier {
    var degraded: DevicePerformanceTier {
        switch self {
        case .high: return .balanced
        case .balanced, .legacy: return .legacy
        }
    }
}
