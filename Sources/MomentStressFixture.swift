import Foundation

/// Local-only Moments feed used by the device scroll stress harness.
enum MomentStressFixture {
    static let count = StressTestConfiguration.momentCount

    static let isActive = count > 0
    private static let base = Date()

    static func moments(prefix: Int) -> [Moment] {
        guard isActive else { return [] }
        let upper = max(0, min(count, prefix))
        let iso = ISO8601DateFormatter()
        let bodySamples = [
            "生活圈原生滚动压力测试。",
            "这是一条用于验证 4000 条生活圈卡片复用的测试内容，滚动时不应该出现重排、跳动或掉帧。",
            "连续多行文本用来检查高度缓存是否稳定。\n第二行继续验证长文本的换行和布局。\n第三行只参与高度测量，不会影响滚动位置。",
            "记录一下今天的测试结果：文字、图片网格、点赞摘要和评论都应该在同一个原生 cell 中稳定复用。"
        ]
        return (0..<upper).map { index in
            let stamp = iso.string(from: base.addingTimeInterval(-Double(index) * 300))
            let author = User(
                id: "moment-stress-author-\(index % 24)",
                nickname: "星友 \(index % 24 + 1)",
                avatar: ""
            )
            var images: [String] = []
            if index % 9 == 0 {
                images = Array(repeating: "", count: (index % 5) + 1)
            }
            let likeCount = index % 8
            let likes = (0..<likeCount).map {
                MomentLike(
                    userId: "moment-stress-like-\(index)-\($0)",
                    nickname: "点赞星友 \($0 + 1)",
                    at: stamp
                )
            }
            let commentCount = index % 4
            let comments = (0..<commentCount).map {
                MomentComment(
                    id: "moment-stress-comment-\(index)-\($0)",
                    userId: "moment-stress-commenter-\($0)",
                    nickname: "评论星友 \($0 + 1)",
                    replyToName: nil,
                    content: "这是第 \($0 + 1) 条评论，用来验证评论区和卡片高度稳定。",
                    at: stamp
                )
            }
            return Moment(
                id: "moment-stress-\(index)",
                authorId: author.id,
                author: author,
                content: "#\(index + 1) · \(bodySamples[index % bodySamples.count])",
                images: images.isEmpty ? nil : images,
                imageSizes: nil,
                video: nil,
                videoCover: nil,
                videoSeconds: nil,
                videoW: nil,
                videoH: nil,
                location: index % 6 == 0 ? "上海" : nil,
                pinned: false,
                createdAt: stamp,
                likes: likes,
                likedByMe: index % 11 == 0,
                comments: comments,
                mine: false
            )
        }
    }
}
