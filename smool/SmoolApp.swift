import SwiftUI

@main
struct SmoolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panel = NotchPanelController()
    private var shortcut: GlobalShortcut?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: ["demoNotchEnabled": true])
        panel.setDemoNotchEnabled(UserDefaults.standard.bool(forKey: "demoNotchEnabled"))
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

        let demo = menu.addItem(withTitle: "Visa demonotch", action: #selector(toggleDemoNotch(_:)), keyEquivalent: "")
        demo.target = self
        demo.state = panel.demoNotchEnabled ? .on : .off
        demo.toolTip = "MacBook Pro 14 tum · referensmått 185 × 32 pt. Visas bara på skärmar utan notch."
        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Avsluta smool", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        panel.toggle()
    }

    @objc private func toggleDemoNotch(_ sender: NSMenuItem) {
        panel.setDemoNotchEnabled(!panel.demoNotchEnabled)
        UserDefaults.standard.set(panel.demoNotchEnabled, forKey: "demoNotchEnabled")
        sender.state = panel.demoNotchEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
