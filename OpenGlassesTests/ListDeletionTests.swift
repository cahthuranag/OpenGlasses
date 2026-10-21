import XCTest
@testable import OpenGlasses

/// A swipe-to-delete on the conversation list crashed: the offsets SwiftUI hands back index the
/// rows as drawn, and the handler re-read the live store, which a background turn had re-sorted or
/// shrunk in between. `ListDeletion` maps offsets through the rendered snapshot and drops any it no
/// longer has.
final class ListDeletionTests: XCTestCase {

    private struct Row: Identifiable, Equatable {
        let id: String
        let updatedAt: Int
    }

    private let rows = [
        Row(id: "thread-a", updatedAt: 30),
        Row(id: "thread-b", updatedAt: 20),
        Row(id: "thread-c", updatedAt: 10),
    ]

    func testInRangeOffsetsMapToIdsInOffsetOrder() {
        XCTAssertEqual(ListDeletion.ids(at: IndexSet([0, 2]), in: rows), ["thread-a", "thread-c"])
        XCTAssertEqual(ListDeletion.ids(at: IndexSet(integer: 1), in: rows), ["thread-b"])
    }

    func testAnOffsetPastTheEndIsDroppedNotTrapped() {
        // The crash: the row was drawn at offset 2, then the list shrank to two before the swipe.
        let shrunk = Array(rows.prefix(2))
        XCTAssertEqual(ListDeletion.ids(at: IndexSet(integer: 2), in: shrunk), [])
        XCTAssertEqual(ListDeletion.ids(at: IndexSet([1, 5]), in: shrunk), ["thread-b"])
        XCTAssertEqual(ListDeletion.ids(at: IndexSet(integer: 0), in: [Row]()), [])
    }

    func testEmptyOffsetsGiveNoIds() {
        XCTAssertEqual(ListDeletion.ids(at: IndexSet(), in: rows), [])
    }

    func testTheRenderedSnapshotYieldsTheSwipedRowAfterTheStoreReSorts() {
        // Drawn newest-first; the wearer swipes "thread-c" at offset 2.
        let rendered = rows.sorted { $0.updatedAt > $1.updatedAt }
        let swiped = IndexSet(integer: 2)

        // Before the delete lands, a background turn bumps "thread-c" to the top.
        var live = rows
        live[2] = Row(id: "thread-c", updatedAt: 40)
        let resorted = live.sorted { $0.updatedAt > $1.updatedAt }

        XCTAssertEqual(ListDeletion.ids(at: swiped, in: rendered), ["thread-c"])
        // Re-reading the live order would have taken a different conversation.
        XCTAssertEqual(ListDeletion.ids(at: swiped, in: resorted), ["thread-b"])
    }

    func testKeyPathOverloadForRowsThatAreNotIdentifiable() {
        let books: [(id: String, title: String)] = [(id: "book-1", title: "First"),
                                                    (id: "book-2", title: "Second")]
        XCTAssertEqual(ListDeletion.ids(at: IndexSet([1, 3]), in: books, id: \.id), ["book-2"])
    }
}
