import AppKit
import SwiftUI

@main
struct MozaControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var controller = MozaController.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(controller: controller)
        } label: {
            // Символ «руль» есть в SF Symbols начиная с macOS 13.
            Image(systemName: "steeringwheel")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Только иконка в строке меню, без значка в Dock.
        NSApp.setActivationPolicy(.accessory)
        // Подключаемся сразу при запуске, не дожидаясь первого клика по иконке.
        // Вызов с главного потока обязателен: подписка на HID вешается на его run loop.
        MozaController.shared.start()
    }
}
