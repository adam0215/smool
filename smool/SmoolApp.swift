import SwiftUI

@main
struct SmoolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = NotchPanelController()
    private var shortcut: GlobalShortcut?
    private var selectionShortcut: GlobalShortcut?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel.presentation.openSettings = { [weak self] in self?.showSettings() }
        panel.presentation.settings.onChange = { [weak self] in self?.panel.settingsDidChange() }
        panel.setDemoNotchEnabled(panel.presentation.settings.demoNotchEnabled)
        panel.start()
        configureMenu()

        do {
            shortcut = try GlobalShortcut { [weak self] in
                self?.panel.toggle()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Keyboard shortcut unavailable"
            alert.informativeText = "smool could not register ⌃⌥Space. You can still open it from the menu bar.\n\n\(error.localizedDescription)"
            alert.runModal()
        }

        do {
            selectionShortcut = try GlobalShortcut(command: .selection) { [weak self] in
                self?.panel.captureSelection()
            }
        } catch {
            statusItem?.button?.toolTip = "smool · ⌃⌥C is unavailable. Selection actions are available in the menu."
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            let saved = await panel.presentation.finishPendingChanges()
            sender.reply(toApplicationShouldTerminate: saved)
            if !saved { panel.showTerminationFailure() }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcut?.stop()
        selectionShortcut?.stop()
        panel.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.open()
        return false
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "smool")
        item.button?.toolTip = "smool · ⌃⌥Space"

        let menu = NSMenu()
        let toggle = menu.addItem(withTitle: "Show or hide smool", action: #selector(togglePanel), keyEquivalent: " ")
        toggle.keyEquivalentModifierMask = [.control, .option]
        toggle.target = self
        let capture = menu.addItem(withTitle: "Act on selected text", action: #selector(captureSelection), keyEquivalent: "c")
        capture.keyEquivalentModifierMask = [.control, .option]
        capture.target = self
        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Quit smool", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        panel.toggle()
    }

    @objc private func captureSelection() { panel.captureSelection() }

    @objc func showSettings() {
        panel.showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
