import XCTest
import IMContracts
@testable import MessageDomain

final class MessageWindowTests: XCTestCase {
    private func message(_ sequence: Int64) -> IMMessageEnvelope {
        IMMessageEnvelope(
            id: IMMessageID("m\(sequence)"),
            chatID: "c1",
            senderID: "u1",
            kind: .text,
            body: "\(sequence)",
            sequence: sequence,
            createdAt: Date(timeIntervalSince1970: TimeInterval(sequence))
        )
    }

    func testOlderPagePrependsInCursorOrder() async {
        let window = MessageWindow(
            policy: MessageWindowPolicy(pageSize: 3, runwayPages: 1)
        )
        await window.replace(
            with: [message(4), message(5), message(6)],
            hasOlder: true,
            hasNewer: false
        )
        await window.merge(
            [message(3), message(2), message(1)],
            direction: .older,
            reportedHasMore: false,
            nextCursor: 1
        )

        let snapshot = await window.snapshot()
        let sequences = snapshot.compactMap(\.sequence)
        XCTAssertEqual(sequences, [1, 2, 3, 4, 5, 6])
        let hasOlder = await window.hasOlder
        XCTAssertFalse(hasOlder)
    }

    func testDuplicatePagesDoNotDuplicateRows() async {
        let window = MessageWindow(
            policy: MessageWindowPolicy(pageSize: 3, runwayPages: 1)
        )
        await window.replace(
            with: [message(1), message(2), message(3)],
            hasOlder: true,
            hasNewer: false
        )
        let change = await window.merge(
            [message(2), message(3)],
            direction: .older,
            reportedHasMore: true,
            nextCursor: 1
        )

        XCTAssertEqual(change, .noChange)
        let count = await window.snapshot().count
        XCTAssertEqual(count, 3)
    }

    func testWindowLimitKeepsOlderRunway() async {
        let window = MessageWindow(
            policy: MessageWindowPolicy(
                pageSize: 2,
                runwayPages: 1,
                maxMaterialized: 4
            )
        )
        await window.replace(
            with: [message(5), message(6), message(7), message(8)],
            hasOlder: true,
            hasNewer: false
        )
        await window.merge(
            [message(3), message(4)],
            direction: .older,
            reportedHasMore: true,
            nextCursor: 3
        )

        let snapshot = await window.snapshot()
        let sequences = snapshot.compactMap(\.sequence)
        XCTAssertEqual(sequences, [3, 4, 5, 6])
    }
}
