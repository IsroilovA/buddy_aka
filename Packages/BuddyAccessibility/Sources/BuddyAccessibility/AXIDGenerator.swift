import Foundation

// Deterministic e_N ids in walk order. One generator per snapshot.
struct AXIDGenerator {
    private var counter: Int = 0

    mutating func next() -> String {
        counter += 1
        return "e_\(counter)"
    }
}
