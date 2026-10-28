import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var quitting = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting, let model else { return .terminateNow }
        quitting = true
        Task { await model.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

@main struct EqualAgentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Equal Agents") {
            RootView().environmentObject(model).environment(\.locale, Locale(identifier: "en")).frame(minWidth: 1000, minHeight: 680)
                .onAppear { delegate.model = model; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 1240, height: 820)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
