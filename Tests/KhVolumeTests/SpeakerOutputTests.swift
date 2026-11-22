import Testing
@testable import KhVolume

@Suite("SpeakerOutput — values derived for the group")
struct SpeakerOutputTests {

    @Test("levels within the tolerance are balanced")
    func balanced() {
        #expect([SpeakerOutput.stub(id: "l", level: 50), .stub(id: "r", level: 50.02)].isBalanced)
    }

    @Test("levels 0.1 dB apart are unbalanced")
    func unbalanced() {
        #expect(![SpeakerOutput.stub(id: "l", level: 50), .stub(id: "r", level: 50.1)].isBalanced)
    }

    @Test("a single speaker and no speakers are balanced")
    func trivialGroupsAreBalanced() {
        #expect([SpeakerOutput.stub()].isBalanced)
        #expect([SpeakerOutput]().isBalanced)
    }

    @Test("the group is muted when any speaker is")
    func mutedWhenAnyIs() {
        #expect([SpeakerOutput.stub(id: "l", muted: false), .stub(id: "r", muted: true)].isMuted)
        #expect(![SpeakerOutput.stub(id: "l"), .stub(id: "r")].isMuted)
    }

    @Test("the group level is the quietest speaker's")
    func levelIsQuietest() {
        #expect([SpeakerOutput.stub(id: "l", level: 60), .stub(id: "r", level: 40)].level == 40)
    }

    @Test("the group level is 0 when no speaker has reported")
    func levelWithoutSpeakers() {
        #expect([SpeakerOutput]().level == 0)
    }
}
