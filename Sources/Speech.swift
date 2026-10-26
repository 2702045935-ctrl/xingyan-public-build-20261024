import AVFoundation

final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()

    static var chosenVoice = ""

    static var chosenRate: Float = 0.5

    var isSpeaking: Bool { synth.isSpeaking }

    func speak(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: t)

        if !Speaker.chosenVoice.isEmpty, let v = AVSpeechSynthesisVoice(identifier: Speaker.chosenVoice) {
            u.voice = v
        } else {
            u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
        u.rate = Speaker.chosenRate
        synth.speak(u)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }
}
