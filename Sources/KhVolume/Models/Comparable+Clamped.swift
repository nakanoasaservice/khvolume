extension Comparable {
    /// The value itself, or the nearest bound of `range` when it lies outside.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
