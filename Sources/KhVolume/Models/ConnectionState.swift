enum ConnectionState: Equatable {
    /// Nothing has been read from the speakers yet.
    case disconnected
    /// Looking for speakers; this takes seconds, so controls are disabled meanwhile.
    case searching
    case connected
    case failed(SpeakerError)
}
