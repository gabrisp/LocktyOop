import ManagedSettings

extension Collection where Element == ApplicationToken {
    /// A Set's iteration order isn't stable, so taking a slice of it directly meant the
    /// previewed icons changed every time the editor re-rendered (typing a name, picking
    /// a weekday). Ordering by hash value is arbitrary but consistent for a given set,
    /// which is what keeps the same apps on screen.
    func stablePrefix(_ count: Int) -> [ApplicationToken] {
        sorted { $0.hashValue < $1.hashValue }.prefix(count).map { $0 }
    }
}
