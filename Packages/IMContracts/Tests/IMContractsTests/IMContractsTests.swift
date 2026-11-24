import XCTest
@testable import IMContracts

final class IMContractsTests: XCTestCase {
    func testMessageEnvelopeKeepsStableIdentityAndCursor() {
        let message = IMMessageEnvelope(
            id: "m1",
            clientID: "client-1",
            chatID: "c1",
            senderID: "u1",
            kind: .text,
            body: "hello",
            sequence: 42,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(message.id.rawValue, "m1")
        XCTAssertEqual(message.chatID.rawValue, "c1")
        XCTAssertEqual(message.sequence, 42)
    }

    func testHistoryLimitIsAlwaysPositive() {
        let request = IMHistoryPageRequest(
            chatID: "c1",
            direction: .older,
            cursor: 100,
            limit: 0
        )

        XCTAssertEqual(request.limit, 1)
    }
}
