import XCTest
@testable import DuoCore

final class MailboxTests: XCTestCase {
    func testHandoffCoalescesAndSchedulesOnlyOneDrain() throws {
        let mailbox = InputMailbox()
        XCTAssertTrue(mailbox.submit(.init(.move, x: 1)))
        for _ in 0..<1000 { XCTAssertFalse(mailbox.submit(.init(.move, x: 1))) }
        XCTAssertEqual(try mailbox.next()?.x, 1001)
        XCTAssertNil(try mailbox.next())
        XCTAssertTrue(mailbox.submit(.init(.stop)))
        XCTAssertEqual(try mailbox.next()?.kind, .stop)
        XCTAssertNil(try mailbox.next())
    }
    func testConcurrentProducersPreserveTotalWithoutUnboundedBlocks() throws {
        let mailbox = InputMailbox()
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in _ = mailbox.submit(.init(.move, x: 1)) }
        XCTAssertEqual(try mailbox.next()?.x, 1000)
        XCTAssertNil(try mailbox.next())
    }
    func testOverflowFailsClosedAndCloseRejectsSubmissions() {
        let mailbox = InputMailbox()
        for _ in 0..<65 { _ = mailbox.submit(.init(.leftClick)) }
        XCTAssertThrowsError(try mailbox.next())
        mailbox.close()
        XCTAssertFalse(mailbox.submit(.init(.leftClick)))
    }
}
