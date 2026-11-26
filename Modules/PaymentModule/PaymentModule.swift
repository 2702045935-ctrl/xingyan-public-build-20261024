import Foundation

public enum PaymentModule {
    public static let identifier = "xingyan.payment"
}

public enum PaymentTransferLifecycle: String, Codable, CaseIterable, Sendable {
    case pending
    case received
    case refunded

    public var canAcceptFunds: Bool { self == .pending }
    public var isSettled: Bool { self != .pending }
}

public enum PaymentTransferDirection: String, Codable, Sendable {
    case incoming
    case outgoing
}

public struct PaymentMoney: Codable, Hashable, Comparable, Sendable {
    public let cents: Int64

    public init(cents: Int64) {
        self.cents = cents
    }

    public init?(decimalString: String) {
        let clean = decimalString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !clean.isEmpty else { return nil }
        let pieces = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2 else { return nil }
        let whole = String(pieces[0])
        var fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard whole.allSatisfy(\.isNumber),
              fraction.allSatisfy(\.isNumber) else { return nil }
        if fraction.count > 2 { return nil }
        if fraction.count == 1 { fraction += "0" }
        if fraction.isEmpty { fraction = "00" }
        guard let units = Int64(whole.isEmpty ? "0" : whole),
              let centsPart = Int64(fraction),
              units <= Int64.max / 100 else { return nil }
        self.cents = units * 100 + centsPart
    }

    public static let zero = PaymentMoney(cents: 0)

    public var amount: Double {
        Double(cents) / 100
    }

    public var formatted: String {
        let sign = cents < 0 ? "-" : ""
        let value = abs(cents)
        return sign + String(value / 100) + "."
            + String(format: "%02lld", value % 100)
    }

    public static func < (lhs: PaymentMoney, rhs: PaymentMoney) -> Bool {
        lhs.cents < rhs.cents
    }
}

public enum PaymentApplePaySection: Int, CaseIterable, Sendable {
    case identity
    case amount
    case method
    case details
    case authorization
}

public enum PaymentApplePayLayout {
    public static let horizontalInset: Double = 20
    public static let sectionSpacing: Double = 18
    public static let cardRadius: Double = 18
    public static let primaryControlHeight: Double = 54
    public static let sectionOrder = PaymentApplePaySection.allCases
}

public struct PaymentReceiptModel: Hashable, Sendable {
    public var amount: PaymentMoney
    public var lifecycle: PaymentTransferLifecycle
    public var direction: PaymentTransferDirection

    public init(amount: PaymentMoney,
                lifecycle: PaymentTransferLifecycle,
                direction: PaymentTransferDirection) {
        self.amount = amount
        self.lifecycle = lifecycle
        self.direction = direction
    }

    public var requiresRecipientAction: Bool {
        lifecycle == .pending && direction == .incoming
    }
}
