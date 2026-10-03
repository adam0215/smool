import Foundation

/// Cross-applet handoffs live at the composition boundary. Feature views only use AppletContext.
extension NotchPresentation {
    var statusItems: [NotchStatusItem] {
        let preferences: [(String, Bool)] = [
            ("timers", settings.showTimerStatus),
            ("codex", settings.showCodexStatus)
        ]
        return preferences.compactMap { name, visible in
            guard visible, let applet = registry.applet(for: AppletID(rawValue: name)),
                  let status = applet.status else { return nil }
            return NotchStatusItem(id: applet.id, status: status)
        }
    }

    func updateBackgroundServices() {
        let id = AppletID(rawValue: "codex")
        let codex = registeredApplets.applet(for: id) as? CodexApplet
        codex?.setStatusMonitoring(settings.isEnabled(id) && settings.showCodexStatus)
    }

    func stopBackgroundServices() {
        (registeredApplets.applet(for: AppletID(rawValue: "codex")) as? CodexApplet)?.setStatusMonitoring(false)
    }

    func prepareCodexDraft(_ text: String) -> AppletID? {
        let id = AppletID(rawValue: "codex")
        guard let codex = registry.applet(for: id) as? CodexApplet else { return nil }
        codex.beginComposing(text)
        return id
    }

    func saveCapturedNote(_ text: String) -> AppletID? {
        let id = AppletID(rawValue: "notes")
        guard let notes = registry.applet(for: id) as? NotesApplet,
              notes.createNote(text: text) != nil else { return nil }
        notes.store.flush()
        return id
    }

    func addFiles(_ urls: [URL]) -> AppletID? {
        let id = AppletID(rawValue: "files")
        guard let files = registry.applet(for: id) as? FilesApplet else { return nil }
        files.add(urls: urls)
        return id
    }

    func finishPendingChanges() async {
        for applet in registeredApplets.applets { applet.deactivate() }
        if let files = registeredApplets.applet(for: AppletID(rawValue: "files")) as? FilesApplet {
            await files.store.finishPendingChanges()
        }
    }
}
