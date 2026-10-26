import Foundation

struct ClassicEmoji {

    let code: String

    let glyph: String
}

enum ClassicEmojiSet {

    static let all: [ClassicEmoji] = [
        ClassicEmoji(code: "[微笑]", glyph: "🙂"),
        ClassicEmoji(code: "[撇嘴]", glyph: "😕"),
        ClassicEmoji(code: "[色]", glyph: "😍"),
        ClassicEmoji(code: "[发呆]", glyph: "😳"),
        ClassicEmoji(code: "[得意]", glyph: "😏"),
        ClassicEmoji(code: "[流泪]", glyph: "😢"),
        ClassicEmoji(code: "[害羞]", glyph: "☺️"),
        ClassicEmoji(code: "[闭嘴]", glyph: "🤐"),

        ClassicEmoji(code: "[睡]", glyph: "😴"),
        ClassicEmoji(code: "[大哭]", glyph: "😭"),
        ClassicEmoji(code: "[尴尬]", glyph: "😅"),
        ClassicEmoji(code: "[发怒]", glyph: "😡"),
        ClassicEmoji(code: "[调皮]", glyph: "😛"),
        ClassicEmoji(code: "[呲牙]", glyph: "😁"),
        ClassicEmoji(code: "[惊讶]", glyph: "😲"),
        ClassicEmoji(code: "[难过]", glyph: "😔"),

        ClassicEmoji(code: "[酷]", glyph: "😎"),
        ClassicEmoji(code: "[冷汗]", glyph: "😰"),
        ClassicEmoji(code: "[抓狂]", glyph: "😫"),
        ClassicEmoji(code: "[吐]", glyph: "🤢"),
        ClassicEmoji(code: "[偷笑]", glyph: "🤭"),
        ClassicEmoji(code: "[可爱]", glyph: "😊"),
        ClassicEmoji(code: "[白眼]", glyph: "🙄"),
        ClassicEmoji(code: "[傲慢]", glyph: "😤"),

        ClassicEmoji(code: "[饥饿]", glyph: "🤤"),
        ClassicEmoji(code: "[困]", glyph: "😪"),
        ClassicEmoji(code: "[惊恐]", glyph: "😱"),
        ClassicEmoji(code: "[流汗]", glyph: "😅"),
        ClassicEmoji(code: "[憨笑]", glyph: "😃"),
        ClassicEmoji(code: "[大兵]", glyph: "🫡"),
        ClassicEmoji(code: "[奋斗]", glyph: "💪"),
        ClassicEmoji(code: "[咒骂]", glyph: "🤬"),

        ClassicEmoji(code: "[疑问]", glyph: "🤔"),
        ClassicEmoji(code: "[嘘]", glyph: "🤫"),
        ClassicEmoji(code: "[晕]", glyph: "😵"),
        ClassicEmoji(code: "[折磨]", glyph: "😩"),
        ClassicEmoji(code: "[衰]", glyph: "😞"),
        ClassicEmoji(code: "[骷髅]", glyph: "💀"),
        ClassicEmoji(code: "[敲打]", glyph: "🔨"),
        ClassicEmoji(code: "[再见]", glyph: "👋"),

        ClassicEmoji(code: "[擦汗]", glyph: "😓"),
        ClassicEmoji(code: "[抠鼻]", glyph: "🤧"),
        ClassicEmoji(code: "[鼓掌]", glyph: "👏"),
        ClassicEmoji(code: "[糗大了]", glyph: "😳"),
        ClassicEmoji(code: "[坏笑]", glyph: "😏"),
        ClassicEmoji(code: "[左哼哼]", glyph: "😤"),
        ClassicEmoji(code: "[右哼哼]", glyph: "😤"),
        ClassicEmoji(code: "[哈欠]", glyph: "🥱"),

        ClassicEmoji(code: "[鄙视]", glyph: "😒"),
        ClassicEmoji(code: "[委屈]", glyph: "🥺"),
        ClassicEmoji(code: "[快哭了]", glyph: "😢"),
        ClassicEmoji(code: "[阴险]", glyph: "😏"),
        ClassicEmoji(code: "[亲亲]", glyph: "😘"),
        ClassicEmoji(code: "[吓]", glyph: "😨"),
        ClassicEmoji(code: "[可怜]", glyph: "🥺"),
        ClassicEmoji(code: "[菜刀]", glyph: "🔪"),

        ClassicEmoji(code: "[西瓜]", glyph: "🍉"),
        ClassicEmoji(code: "[啤酒]", glyph: "🍺"),
        ClassicEmoji(code: "[篮球]", glyph: "🏀"),
        ClassicEmoji(code: "[乒乓]", glyph: "🏓"),
        ClassicEmoji(code: "[咖啡]", glyph: "☕"),
        ClassicEmoji(code: "[饭]", glyph: "🍚"),
        ClassicEmoji(code: "[猪头]", glyph: "🐷"),
        ClassicEmoji(code: "[玫瑰]", glyph: "🌹"),

        ClassicEmoji(code: "[凋谢]", glyph: "🥀"),
        ClassicEmoji(code: "[示爱]", glyph: "😘"),
        ClassicEmoji(code: "[爱心]", glyph: "❤️"),
        ClassicEmoji(code: "[心碎]", glyph: "💔"),
        ClassicEmoji(code: "[蛋糕]", glyph: "🎂"),
        ClassicEmoji(code: "[闪电]", glyph: "⚡"),
        ClassicEmoji(code: "[炸弹]", glyph: "💣"),
        ClassicEmoji(code: "[刀]", glyph: "🗡️"),

        ClassicEmoji(code: "[足球]", glyph: "⚽"),
        ClassicEmoji(code: "[瓢虫]", glyph: "🐞"),
        ClassicEmoji(code: "[便便]", glyph: "💩"),
        ClassicEmoji(code: "[月亮]", glyph: "🌙"),
        ClassicEmoji(code: "[太阳]", glyph: "☀️"),
        ClassicEmoji(code: "[礼物]", glyph: "🎁"),
        ClassicEmoji(code: "[拥抱]", glyph: "🤗"),
        ClassicEmoji(code: "[强]", glyph: "👍"),

        ClassicEmoji(code: "[弱]", glyph: "👎"),
        ClassicEmoji(code: "[握手]", glyph: "🤝"),
        ClassicEmoji(code: "[胜利]", glyph: "✌️"),
        ClassicEmoji(code: "[抱拳]", glyph: "🙏"),
        ClassicEmoji(code: "[勾引]", glyph: "😉"),
        ClassicEmoji(code: "[拳头]", glyph: "👊"),
        ClassicEmoji(code: "[差劲]", glyph: "👎"),
        ClassicEmoji(code: "[爱你]", glyph: "🥰"),

        ClassicEmoji(code: "[NO]", glyph: "🙅"),
        ClassicEmoji(code: "[OK]", glyph: "👌"),
        ClassicEmoji(code: "[爱情]", glyph: "💑"),
        ClassicEmoji(code: "[飞吻]", glyph: "😘"),
        ClassicEmoji(code: "[跳跳]", glyph: "🕺"),
        ClassicEmoji(code: "[发抖]", glyph: "🥶"),
        ClassicEmoji(code: "[怄火]", glyph: "😤"),
        ClassicEmoji(code: "[转圈]", glyph: "🌀"),

        ClassicEmoji(code: "[磕头]", glyph: "🙇"),
        ClassicEmoji(code: "[回头]", glyph: "🔄"),
        ClassicEmoji(code: "[跳绳]", glyph: "🏃"),
        ClassicEmoji(code: "[挥手]", glyph: "👋"),
        ClassicEmoji(code: "[激动]", glyph: "🤩"),
        ClassicEmoji(code: "[街舞]", glyph: "🕺"),
        ClassicEmoji(code: "[献吻]", glyph: "😘"),
        ClassicEmoji(code: "[饭团]", glyph: "🍙"),

        ClassicEmoji(code: "[左太极]", glyph: "☯️"),
        ClassicEmoji(code: "[右太极]", glyph: "☯️"),

        ClassicEmoji(code: "[奸笑]", glyph: "😏"),
        ClassicEmoji(code: "[机智]", glyph: "🤓"),
        ClassicEmoji(code: "[耶]", glyph: "✌️"),
        ClassicEmoji(code: "[加油]", glyph: "💪"),
        ClassicEmoji(code: "[汗]", glyph: "😅"),
        ClassicEmoji(code: "[皱眉]", glyph: "🙁"),
        ClassicEmoji(code: "[吃瓜]", glyph: "🍉"),
        ClassicEmoji(code: "[握手言和]", glyph: "🤝"),

        ClassicEmoji(code: "[捂脸]", glyph: "🤦"),
        ClassicEmoji(code: "[嘿哈]", glyph: "😆"),
        ClassicEmoji(code: "[旺柴]", glyph: "🐶"),
        ClassicEmoji(code: "[让我看看]", glyph: "👀"),
        ClassicEmoji(code: "[叹气]", glyph: "😮‍💨"),
        ClassicEmoji(code: "[裂开]", glyph: "🫠"),
        ClassicEmoji(code: "[无语]", glyph: "😑"),
        ClassicEmoji(code: "[哇]", glyph: "😮"),
        ClassicEmoji(code: "[打脸]", glyph: "😖"),
        ClassicEmoji(code: "[哇塞]", glyph: "🤩"),
        ClassicEmoji(code: "[Emm]", glyph: "🤨"),
        ClassicEmoji(code: "[社会社会]", glyph: "🫡"),
        ClassicEmoji(code: "[好的]", glyph: "👌"),
        ClassicEmoji(code: "[666]", glyph: "💯"),
        ClassicEmoji(code: "[冲鸭]", glyph: "🏃"),
        ClassicEmoji(code: "[庆祝]", glyph: "🎉"),
        ClassicEmoji(code: "[烟花]", glyph: "🎆"),
        ClassicEmoji(code: "[破涕为笑]", glyph: "😂"),
        ClassicEmoji(code: "[思考]", glyph: "🤔"),
        ClassicEmoji(code: "[比心]", glyph: "🫶"),
        ClassicEmoji(code: "[一起加油]", glyph: "✊"),
        ClassicEmoji(code: "[苦涩]", glyph: "😣"),
        ClassicEmoji(code: "[睡啦]", glyph: "😴"),
        ClassicEmoji(code: "[摊手]", glyph: "🤷"),
        ClassicEmoji(code: "[握草]", glyph: "😱"),
        ClassicEmoji(code: "[赞]", glyph: "👍"),
        ClassicEmoji(code: "[踩]", glyph: "👎"),
        ClassicEmoji(code: "[给力]", glyph: "💪"),
        ClassicEmoji(code: "[no]", glyph: "🙅"),
        ClassicEmoji(code: "[ok]", glyph: "👌"),
        ClassicEmoji(code: "[呵呵]", glyph: "🙂"),
        ClassicEmoji(code: "[哈哈]", glyph: "😄"),
        ClassicEmoji(code: "[微笑脸]", glyph: "🙂"),
        ClassicEmoji(code: "[躺平]", glyph: "🛌"),
        ClassicEmoji(code: "[溜了]", glyph: "🏃"),
        ClassicEmoji(code: "[石化]", glyph: "😵"),
        ClassicEmoji(code: "[灵魂出窍]", glyph: "👻"),
        ClassicEmoji(code: "[我酸了]", glyph: "🍋"),
        ClassicEmoji(code: "[吃柠檬]", glyph: "🍋"),
        ClassicEmoji(code: "[菜]", glyph: "🥬"),
        ClassicEmoji(code: "[卑微]", glyph: "🙇"),
        ClassicEmoji(code: "[快跑]", glyph: "🏃"),
        ClassicEmoji(code: "[委屈巴巴]", glyph: "🥺")
    ]

    private static let byCode: [String: String] = {
        var m: [String: String] = [:]
        for e in all { m[e.code] = e.glyph }
        return m
    }()

    static func glyph(for code: String) -> String? { byCode[code] }

    static func expand(_ text: String) -> String {
        guard text.contains("["), text.contains("]") else { return text }
        var out = ""
        out.reserveCapacity(text.count)
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "[",
               let close = text[i...].firstIndex(of: "]"),
               text.distance(from: i, to: close) <= 6,
               let glyph = byCode[String(text[i...close])] {
                out += glyph
                i = text.index(after: close)
                continue
            }
            out.append(text[i])
            i = text.index(after: i)
        }
        return out
    }
}

enum EmojiThemes {
    struct Theme {
        let name: String
        let list: [String]
    }

    static let all: [Theme] = [
        Theme(name: "心情", list: [
            "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🥲", "☺️", "😊", "😇", "🙂", "🙃", "😉", "😌",
            "😍", "🥰", "😘", "😗", "😙", "😚", "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🥸",
            "🤩", "🥳", "😏", "😒", "😞", "😔", "😟", "😕", "🙁", "☹️", "😣", "😖", "😫", "😩", "🥺", "😢",
            "😭", "😤", "😠", "😡", "🤬", "🤯", "😳", "🥵", "🥶", "😱", "😨", "😰", "😥", "😓", "🤗", "🤔",
            "🤭", "🤫", "🤥", "😶", "😐", "😑", "😬", "🙄", "😯", "😦", "😧", "😮", "😲", "🥱", "😴", "🤤",
            "😪", "😵", "🤐", "🥴", "🤢", "🤮", "🤧", "😷", "🤒", "🤕", "🤑", "🤠", "😈", "👿", "💩", "👻"
        ]),

        Theme(name: "手势", list: [
            "👋", "🤚", "🖐", "✋", "🖖", "👌", "🤌", "🤏", "✌️", "🤞", "🫰", "🤟", "🤘", "🤙", "👈", "👉",
            "👆", "👇", "☝️", "👍", "👎", "✊", "👊", "🤛", "🤜", "👏", "🫶", "🙌", "👐", "🤲", "🤝", "🙏",
            "✍️", "💅", "🤳", "💪", "🦾", "🦵", "🦶", "👂", "👃", "🫀", "🦷", "🦴", "👀", "👁", "👅", "👄"
        ]),

        Theme(name: "人物", list: [
            "👶", "🧒", "👦", "👧", "🧑", "👱", "👨", "🧔", "👩", "🧓", "👴", "👵", "🙍", "🙎", "🙅", "🙆",
            "💁", "🙋", "🧏", "🙇", "🤦", "🤷", "👮", "🕵", "💂", "👷", "🤴", "👸", "👳", "👲", "🧕", "🤵",
            "👰", "🤰", "🤱", "🎅", "🤶", "🦸", "🦹", "🧙", "🧚", "🧛", "🧜", "🧝", "🧞", "🧟", "💆", "💇",
            "🚶", "🧍", "🧎", "🏃", "💃", "🕺", "👯", "🧖", "🧗", "🏇", "🏂", "🏄", "🚣", "🏊", "🏋", "🚴"
        ]),

        Theme(name: "动物", list: [
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐽", "🐸", "🐵",
            "🙈", "🙉", "🙊", "🐒", "🐔", "🐧", "🐦", "🐤", "🐣", "🐥", "🦆", "🦅", "🦉", "🦇", "🐺", "🐗",
            "🐴", "🦄", "🐝", "🐛", "🦋", "🐌", "🐞", "🐜", "🦗", "🕷", "🦂", "🐢", "🐍", "🦎", "🦖", "🦕",
            "🐙", "🦑", "🦐", "🦞", "🦀", "🐡", "🐠", "🐟", "🐬", "🐳", "🐋", "🦈", "🐊", "🐅", "🐆", "🦓"
        ]),

        Theme(name: "美食", list: [
            "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥",
            "🥝", "🍅", "🥑", "🥦", "🥬", "🥒", "🌶", "🌽", "🥕", "🧄", "🧅", "🥔", "🍞", "🥐", "🥨", "🧀",
            "🥚", "🍳", "🥞", "🥓", "🥩", "🍗", "🍖", "🌭", "🍔", "🍟", "🍕", "🥪", "🌮", "🌯", "🥗", "🍝",
            "🍜", "🍲", "🍛", "🍣", "🍱", "🥟", "🍤", "🍙", "🍚", "🍘", "🍥", "🍢", "🍡", "🍧", "🍨", "🍦",
            "🥧", "🧁", "🍰", "🎂", "🍮", "🍭", "🍬", "🍫", "🍿", "🍩", "🍪", "🌰", "🥜", "🍯", "🥛", "🍼",
            "☕", "🍵", "🧃", "🥤", "🧋", "🍶", "🍺", "🍻", "🥂", "🍷", "🥃", "🍸", "🍹", "🍾", "🧊", "🍽"
        ]),

        Theme(name: "节日", list: [
            "🎉", "🎊", "🎈", "🎁", "🎀", "🎂", "🕯", "🎃", "🎄", "🎋", "🎍", "🎑", "🧧", "🎇", "🎆", "✨",
            "🎐", "🎏", "🎎", "🧨", "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "💕", "💞",
            "💓", "💗", "💖", "💘", "💝", "💟", "☮️", "🕉", "☸️", "✡️", "🔯", "🕎", "☯️", "⛎", "♈", "♉",
            "♊", "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓", "🆔", "⚛️", "🉑", "💮", "🉐", "㊙️"
        ]),

        Theme(name: "符号", list: [
            "➕", "➖", "➗", "✖️", "♾️", "💲", "💱", "™️", "©️", "®️", "〰️", "➰", "➿", "🔚", "🔙", "🔛",
            "🔝", "🔜", "✔️", "☑️", "🔘", "🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "⚫", "⚪", "🟤", "🔺", "🔻",
            "🔸", "🔹", "🔶", "🔷", "🔳", "🔲", "▪️", "▫️", "◾", "◽", "◼️", "◻️", "🟥", "🟧", "🟨", "🟩",
            "🟦", "🟪", "⬛", "⬜", "🟫", "🔈", "🔇", "🔉", "🔊", "🔔", "🔕", "📣", "📢", "💬", "💭", "🗯",
            "♠️", "♣️", "♥️", "♦️", "🃏", "🎴", "🀄", "❌", "⭕", "🛑", "⛔", "📛", "🚫", "💯", "❗", "❓"
        ])
    ]
}

struct BuiltinPack {
    let id: String
    let name: String
    let icon: String
    let stickers: [String]
}

enum BuiltinPacks {
    static let all: [BuiltinPack] = [
        BuiltinPack(id: "b1", name: "小黄脸", icon: "😀", stickers: [
            "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇", "🙂", "😉", "😍", "🥰", "😘", "😋",
            "😜", "🤪", "🤗", "🤔", "🤨", "😐", "😏", "😒", "🙄", "😴", "😷", "🤒", "🥳", "😎", "🤓", "😭"
        ]),
        BuiltinPack(id: "b2", name: "手势", icon: "👍", stickers: [
            "👍", "👎", "👌", "✌️", "🤞", "🤟", "🤘", "👏", "🙌", "🙏", "💪", "👊", "✊", "🤝", "👋", "☝️",
            "👆", "👇", "👈", "👉", "🖐️", "✋", "🤙", "🫰"
        ]),
        BuiltinPack(id: "b3", name: "爱心", icon: "❤️", stickers: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘",
            "💝", "💟", "😻", "🫶"
        ]),
        BuiltinPack(id: "b4", name: "动物", icon: "🐱", stickers: [
            "🐱", "🐶", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔",
            "🐧", "🐦", "🦄", "🐝"
        ]),
        BuiltinPack(id: "b5", name: "猫猫狗狗", icon: "🐶", stickers: [
            "🐶", "🐱", "🐕", "🐈", "🐩", "🦮", "🐾", "🐇", "🐹", "🐭", "🐿️", "🦔", "🐻", "🐼", "🐨", "🦊"
        ]),
        BuiltinPack(id: "b6", name: "开心日常", icon: "🎉", stickers: [
            "🎉", "🎊", "🎁", "🎂", "🍰", "🍺", "🥳", "🍀", "🌈", "☀️", "🌙", "⚡", "🔥", "✨", "💯", "🆗",
            "🙆", "🙅", "💃", "🕺"
        ]),
        BuiltinPack(id: "b7", name: "美食", icon: "🍜", stickers: [
            "🍜", "🍲", "🍛", "🍣", "🍱", "🥟", "🍤", "🍙", "🍚", "🍘", "🍥", "🍢", "🍡", "🍧", "🍨", "🍦",
            "🥧", "🧁", "🍭", "🍬", "🍫", "🍿", "🍩", "🍪"
        ]),
        BuiltinPack(id: "b8", name: "饮料甜点", icon: "🧋", stickers: [
            "🧋", "🥛", "🍼", "🍵", "☕", "🧃", "🥤", "🍶", "🍺", "🍻", "🥂", "🍷", "🥃", "🍸", "🍹", "🍾",
            "🧊", "🍽", "🥄", "🍴"
        ]),
        BuiltinPack(id: "b9", name: "天气自然", icon: "⛅", stickers: [
            "☀️", "🌤", "⛅", "🌥", "☁️", "🌦", "🌧", "⛈", "🌩", "🌨", "❄️", "☃️", "⛄", "🌬", "💨", "🌈",
            "☔", "💧", "🌊", "⭐"
        ]),
        BuiltinPack(id: "b10", name: "节日", icon: "🎄", stickers: [
            "🎄", "🎃", "🎋", "🎍", "🎑", "🧧", "🎇", "🎆", "🎐", "🎏", "🎎", "🧨", "🕯", "🎈", "🎀", "🥮"
        ]),
        BuiltinPack(id: "b11", name: "星座", icon: "♈", stickers: [
            "♈", "♉", "♊", "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓", "⛎", "🔮", "🌠", "🌌"
        ]),
        BuiltinPack(id: "b12", name: "运动", icon: "⚽", stickers: [
            "⚽", "🏀", "🏈", "⚾", "🎾", "🏐", "🏉", "🎱", "🏓", "🏸", "🥊", "🥋", "⛳", "⛸", "🎿", "🛷",
            "🏂", "🏋️", "🤸", "🚴", "🏊", "🏃", "🧘", "🤺"
        ]),
        BuiltinPack(id: "b13", name: "职业人物", icon: "👮", stickers: [
            "👮", "🕵️", "💂", "👷", "🧑‍⚕️", "🧑‍🍳", "🧑‍🏫", "🧑‍🎓", "🧑‍💻", "🧑‍🔧", "🧑‍🌾", "🧑‍✈️", "🧑‍🚀", "🧑‍🚒", "🤴", "👸",
            "🦸", "🦹", "🧙", "🧚"
        ]),
        BuiltinPack(id: "b14", name: "表情符号", icon: "💯", stickers: [
            "💯", "❗", "❓", "‼️", "⁉️", "✅", "❌", "⭕", "🚫", "⚠️", "🔔", "📢", "📣", "💬", "💭", "🎵",
            "🎶", "💤", "♨️", "🔰"
        ])
    ]
}
