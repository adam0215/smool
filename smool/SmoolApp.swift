import SwiftUI

@main
struct SmoolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView(settings: delegate.panel.presentation.settings, registry: delegate.panel.presentation.registeredApplets)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Inställningar…") { delegate.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = NotchPanelController()
    private var settingsWindow: NSWindow?
    private var shortcut: GlobalShortcut?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel.presentation.openSettings = { [weak self] in self?.showSettings() }
        panel.presentation.settings.onChange = { [weak self] in self?.panel.settingsDidChange() }
        panel.setDemoNotchEnabled(panel.presentation.settings.demoNotchEnabled)
        configureMenu()

        do {
            shortcut = try GlobalShortcut { [weak self] in
                self?.panel.toggle()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Kortkommandot är upptaget"
            alert.informativeText = "smool kunde inte registrera ⌃⌥Space. Du kan fortfarande öppna panelen från menyfältet.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcut?.stop()
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
        let toggle = menu.addItem(withTitle: "Visa eller dölj smool", action: #selector(togglePanel), keyEquivalent: " ")
        toggle.keyEquivalentModifierMask = [.control, .option]
        toggle.target = self
        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Inställningar…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Avsluta smool", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        panel.toggle()
    }

    @objc func showSettings() {
        panel.close()
        let window: NSWindow
        if let settingsWindow {
            window = settingsWindow
        } else {
            let view = SettingsView(settings: panel.presentation.settings, registry: panel.presentation.registeredApplets)
            window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Inställningar"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
