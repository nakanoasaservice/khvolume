struct NetworkInterface: Identifiable, Equatable {
    let name: String
    let label: String
    /// Whether the port has link.
    let isActive: Bool

    var id: String { name }
}
