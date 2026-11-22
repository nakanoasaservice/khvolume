import Testing
@testable import KhVolume

@Suite("SpeakerError — errorDescription")
struct SpeakerErrorTests {

    @Test("every error has a message for the popover", arguments: [
        (SpeakerError.noInterface, "No network interface selected"),
        (.noSpeakersFound(interface: "en15"), "No speakers found on en15"),
        (.unreachable(speaker: "Left"), "Left is not responding"),
        (.rejected(speaker: "Left", reply: #"{"osc":{"error":[400]}}"#), #"Left: {"osc":{"error":[400]}}"#),
        (.unexpectedReply(speaker: "Left"), "Left: unexpected reply"),
    ] as [(SpeakerError, String)])
    func descriptions(error: SpeakerError, expected: String) {
        #expect(error.errorDescription == expected)
    }
}
