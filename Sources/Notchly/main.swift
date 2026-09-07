import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    static var retainedDelegate: AppDelegate?

    private var store: UsageStore!
    private var controller: NotchPanelController!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        store = UsageStore()
        controller = NotchPanelController(side: AppSettings.shared.side)
        controller.expandNowIfNeeded()
        controller.host(store: store)
        store.start()

        setupStatusItem()

        NotificationCenter.default.addObserver(
            forName: .openNotchlySettings, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.openSettings() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: OperationQueue.main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.store?.refreshAll() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.controller?.panel.place() }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.righthalf.filled", accessibilityDescription: "Notchly")
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh now", action: #selector(refreshClicked), keyEquivalent: "r")
        menu.addItem(withTitle: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notchly", action: #selector(quitClicked), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func refreshClicked() { store.refreshAll() }
    @objc private func settingsClicked() { openSettings() }
    @objc private func quitClicked() {
        controller.teardown()
        NSApp.terminate(nil)
    }

    @MainActor
    func applySide(_ side: NotchPanelSide) {
        controller.setSide(side)
    }

    @MainActor
    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "Notchly Settings"
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    AppDelegate.retainedDelegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
