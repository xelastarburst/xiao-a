import UserNotifications

enum LessonReminder {
    private static let id = "daily-lesson"

    static func reschedule(hour: Int, minute: Int, enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "小A"
            content.body = "该学英语啦！今天 30 分钟，我们一起说。"
            content.sound = .default
            var time = DateComponents()
            time.hour = hour
            time.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
