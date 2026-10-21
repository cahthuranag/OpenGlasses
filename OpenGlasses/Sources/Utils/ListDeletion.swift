import Foundation

/// Turning the offsets a swipe-to-delete hands back into the ids of the rows that were swiped.
///
/// SwiftUI's `onDelete` gives offsets into the rows as they were *rendered*. A list fed from a live
/// store — the conversation list, decks, playbooks — can change between the draw and the swipe: a
/// background turn bumps a thread's `updatedAt` and the sort moves it, a thread is added or pruned.
/// Re-reading the store at delete time then either indexes past the end (an array trap, which is
/// how the chat list crashed) or, when only the order moved, deletes a different row from the one
/// swiped. So the caller takes one snapshot of its rows, draws the `ForEach` from it, and passes the
/// same snapshot here; the store is then changed by id. Pure, so it is tested without a list.
enum ListDeletion {

    /// The ids at `offsets` in `rows`, in offset order. `rows` must be the array the `ForEach`
    /// drew; an offset it no longer has is dropped rather than trapping.
    nonisolated static func ids<Row: Identifiable>(at offsets: IndexSet, in rows: [Row]) -> [Row.ID] {
        ids(at: offsets, in: rows, id: \.id)
    }

    /// The same, for rows that name their id with a key path — `ForEach(rows, id: \.id)` over
    /// tuples or other types that aren't `Identifiable`.
    nonisolated static func ids<Row, ID>(at offsets: IndexSet, in rows: [Row], id: KeyPath<Row, ID>) -> [ID] {
        offsets.compactMap { rows.indices.contains($0) ? rows[$0][keyPath: id] : nil }
    }
}
