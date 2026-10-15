import SwiftUI

@main
struct XiaoAApp: App {
    @StateObject private var app = AppState()
    @StateObject private var store = ConfigStore()
    @StateObject private var learning = LearningStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(store)
                .environmentObject(learning)
                .preferredColorScheme(.light)
                .tint(Palette.teal)
                .task {
                    LessonReminder.reschedule(hour: store.config.reminderHour,
                                              minute: store.config.reminderMinute,
                                              enabled: store.config.remindersOn)
                }
        }
    }
}
