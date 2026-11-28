import Foundation
import Speech

enum NativeSpeech {
    static var localeIdentifier: String {
        switch Lang.code {
        case "en": return "en-US"
        case "ru": return "ru-RU"
        default: return "zh-CN"
        }
    }

    static func recognizer() -> SFSpeechRecognizer? {
        let preferred = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        if let preferred, preferred.isAvailable { return preferred }
        let current = SFSpeechRecognizer(locale: .current)
        if let current, current.isAvailable { return current }
        return SFSpeechRecognizer()
    }

    static func configure(_ request: SFSpeechRecognitionRequest,
                          recognizer: SFSpeechRecognizer,
                          partial: Bool,
                          preferOnDevice: Bool = false) {
        request.shouldReportPartialResults = partial
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        // 文件转写默认交给系统选择设备端或 Apple 在线识别，
        // 避免没有下载离线模型时直接返回空结果。
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
    }
}

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

    static func recognize(url: URL, timeout: TimeInterval = 30) async -> String {
        guard let rec = NativeSpeech.recognizer(),
              rec.isAvailable else { return "" }
        let req = SFSpeechURLRecognitionRequest(url: url)
        NativeSpeech.configure(
            req,
            recognizer: rec,
            partial: false,
            preferOnDevice: false
        )
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
