import Foundation

enum CallPrefs {

    static var quality: Int {
        get { UserDefaults.standard.object(forKey: "callVideoQuality") as? Int ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: "callVideoQuality"); changed() }
    }
    static var qualityName: String {
        switch quality {
        case 0:  return "标清"
        case 2:  return "超清"
        default: return "高清"
        }
    }

    static var mirror: Bool {
        get { UserDefaults.standard.object(forKey: "callMirror") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "callMirror"); changed() }
    }

    static var beauty: Int {
        get { UserDefaults.standard.object(forKey: "callBeauty") as? Int ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: "callBeauty"); changed() }
    }
    static var beautyName: String {
        switch beauty {
        case 0:  return "关"
        case 2:  return "中"
        case 3:  return "高"
        default: return "低"
        }
    }

    static func encoderParams() -> (resolution: Int, fps: Int32, bitrate: Int32) {
        switch quality {
        case 0:  return (108, 20, 600)
        case 2:  return (114, 24, 2600)
        default: return (112, 24, 1500)
        }
    }

    private static func changed() {
        NotificationCenter.default.post(name: Notification.Name("chrisCallPrefsChanged"), object: nil)
    }
}
