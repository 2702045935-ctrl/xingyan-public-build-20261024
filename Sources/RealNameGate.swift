import SwiftUI

final class RealNameGate: ObservableObject {
    static let shared = RealNameGate()

    @Published var alert = false

    @Published var openPage = false

    private init() { }

    func prompt() {
        if Thread.isMainThread { alert = true }
        else { DispatchQueue.main.async { self.alert = true } }
    }
}
