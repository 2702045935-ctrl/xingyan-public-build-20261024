import Foundation
import Speech

enum FileSpeech {

    static func requestAuth() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    static func authorize() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { st in
                cont.resume(returning: st == .authorized)
            }
        }
    }

    static func recognize(url: URL, timeout: TimeInterval = 12) async -> String {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer(),
              rec.isAvailable else { return "" }
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false

        if #available(iOS 16.0, *) { req.addsPunctuation = true }

        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            var finished = false
            let done: (String) -> Void = { text in
                if finished { return }
                finished = true
                cont.resume(returning: text)
            }
            rec.recognitionTask(with: req) { result, err in
                if let r = result, r.isFinal {
                    done(r.bestTranscription.formattedString)
                } else if err != nil {
                    done("")
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { done("") }
        }
    }
}
