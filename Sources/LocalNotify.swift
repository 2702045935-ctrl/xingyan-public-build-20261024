import SwiftUI
import UIKit
import UserNotifications
import AudioToolbox

enum NotificationQuickReply {
    static let defaultsKey = "chris.notification.quickReply"

    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: defaultsKey)
        LocalNotify.prepareNotificationCategories()
    }
}

enum LocalNotify {
    static var settings = NotifySettings()

    static func prepare() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        prepareNotificationCategories()
    }

    static let callCategory = "chris.call"
    static let messageCategory = "chris.message.quickReply"
    static let replyAction = "message.reply"
    static let markReadAction = "message.markRead"

    static func prepareCallCategory() {
        prepareNotificationCategories()
    }

    /// 旧版只注册来电分类；开启“通知直接回复”后才追加消息分类。
    static func prepareNotificationCategories() {
        let answer = UNNotificationAction(identifier: "call.answer", title: "接听", options: [.foreground])
        let reject = UNNotificationAction(identifier: "call.reject", title: "拒绝", options: [.destructive])
        let call = UNNotificationCategory(identifier: callCategory, actions: [answer, reject],
                                          intentIdentifiers: [], options: [])
        var categories: Set<UNNotificationCategory> = [call]
        if NotificationQuickReply.enabled {
            let reply = UNTextInputNotificationAction(
                identifier: replyAction,
                title: Tr("回复"),
                options: [.authenticationRequired],
                textInputButtonTitle: Tr("发送"),
                textInputPlaceholder: Tr("输入消息")
            )
            let markRead = UNNotificationAction(
                identifier: markReadAction,
                title: Tr("标为已读"),
                options: []
            )
            categories.insert(UNNotificationCategory(
                identifier: messageCategory,
                actions: [reply, markRead],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ))
        }
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    static func incomingCall(callId: String, peerName: String, video: Bool) {
        let c = UNMutableNotificationContent()
        c.title = video ? "视频通话" : "语音通话"
        c.body = (peerName.isEmpty ? "有人" : peerName) + "邀请你" + (video ? "视频" : "语音") + "通话"
        c.sound = .default
        c.categoryIdentifier = callCategory
        c.userInfo = ["callId": callId, "kind": "call"]
        if #available(iOS 15.0, *) { c.interruptionLevel = .timeSensitive }
        let req = UNNotificationRequest(identifier: "call-" + callId, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    static func clearCall(callId: String) {
        guard !callId.isEmpty else { return }
        let ids = ["call-" + callId]
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func refresh() async {
        settings = await API.shared.notifySettings()
    }

    static func mutedNow() -> Bool {
        let a = settings.muteStart, b = settings.muteEnd
        guard !a.isEmpty, !b.isEmpty else { return false }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        guard let s = f.date(from: a), let e = f.date(from: b) else { return false }
        let cal = Calendar.current
        let now = cal.dateComponents([.hour, .minute], from: Date())
        let cur = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let sv = cal.dateComponents([.hour, .minute], from: s)
        let ev = cal.dateComponents([.hour, .minute], from: e)
        let start = (sv.hour ?? 0) * 60 + (sv.minute ?? 0)
        let end = (ev.hour ?? 0) * 60 + (ev.minute ?? 0)
        if start == end { return false }
        return start < end ? (cur >= start && cur < end) : (cur >= start || cur < end)
    }

    static func incoming(title: String, body: String, chatId: String = "", msgId: String = "", badge: Int = 0) {
        guard settings.on else { return }
        guard !mutedNow() else { return }
        if settings.sound { AudioServicesPlaySystemSound(1007) }
        if settings.vibrate { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = settings.showDetail ? body : "你收到一条新消息"
        if settings.sound { c.sound = .default }

        c.badge = NSNumber(value: max(0, min(999, badge)))

        if !chatId.isEmpty {
            var info: [String: Any] = ["chatId": chatId, "kind": "message"]
            if !msgId.isEmpty { info["messageId"] = msgId }
            c.userInfo = info
            if NotificationQuickReply.enabled {
                c.categoryIdentifier = messageCategory
            }
        }

        if !chatId.isEmpty { c.threadIdentifier = chatId }
        let id: String
        if !msgId.isEmpty { id = "msg-" + msgId }
        else if !chatId.isEmpty { id = "chat-" + chatId }
        else { id = UUID().uuidString }
        let req = UNNotificationRequest(identifier: id, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private static var lastNotified: [String: String] = [:]
    private static var lastNotifiedLoaded = false

    private static func loadLastNotified() {
        guard !lastNotifiedLoaded else { return }
        lastNotifiedLoaded = true
        if let d = UserDefaults.standard.dictionary(forKey: "chris.lastNotified") as? [String: String] {
            lastNotified = d
        }
    }

    private static func saveLastNotified() {
        UserDefaults.standard.set(lastNotified, forKey: "chris.lastNotified")
    }

    static func shouldNotify(chatId: String, msgId: String, at: String?) -> Bool {
        loadLastNotified()
        guard !chatId.isEmpty else { return true }
        if !msgId.isEmpty, lastNotified[chatId] == msgId { return false }
        if let d = TimeFmt.date(at), Date().timeIntervalSince(d) > 120 { return false }
        if !msgId.isEmpty { lastNotified[chatId] = msgId; saveLastNotified() }
        return true
    }

    static func clearChat(_ chatId: String) {
        guard !chatId.isEmpty else { return }
        UNUserNotificationCenter.current().getDeliveredNotifications { list in
            let ids = list.filter { ($0.request.content.userInfo["chatId"] as? String) == chatId }
                .map { $0.request.identifier }
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
        loadLastNotified()
        lastNotified[chatId] = nil
        saveLastNotified()
    }

    static func quickReplyFailed(chatId: String) {
        guard !chatId.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = Tr("回复失败")
        content.body = Tr("消息没有发出去，点此回到聊天重试")
        content.sound = .default
        content.userInfo = ["chatId": chatId, "kind": "message"]
        content.threadIdentifier = chatId
        let request = UNNotificationRequest(
            identifier: "reply-failed-" + UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
