import SwiftUI

enum FileUploadUX {
    static let maxBytes = 100 * 1024 * 1024

    static func progress(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    static func uploading(_ value: Double) -> String {
        let fraction = progress(value)
        if fraction <= 0 { return Tr("准备发送") }
        if fraction >= 0.999 { return Tr("发送中…") }
        return Tr("上传中") + " \(Int(fraction * 100))%"
    }

    static func batchUploading(_ index: Int, of count: Int) -> String {
        let current = min(max(1, index), max(1, count))
        return Tr("上传中") + " \(current)/\(max(1, count))"
    }

    static func failure(_ reason: String) -> String {
        let value = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? Tr("发送失败") : value
    }

    static func exceedsLimit(_ bytes: Int) -> Bool {
        bytes > maxBytes
    }

    static var limitMessage: String {
        Tr("单个文件不能超过 100MB")
    }
}

struct FileUploadProgressBar: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let value = FileUploadUX.progress(progress)
            ZStack(alignment: .leading) {
                Capsule().fill(C.fieldBg)
                Capsule()
                    .fill(tint)
                    .frame(width: value > 0 ? max(height, geo.size.width * value) : 0)
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.16), value: progress)
        .accessibilityHidden(true)
    }
}
