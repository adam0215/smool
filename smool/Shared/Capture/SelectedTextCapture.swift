import AppKit
@preconcurrency import ApplicationServices

struct SelectedText: Sendable, Equatable {
    let text: String
    let applicationName: String
}

enum SelectionCaptureError: Error, LocalizedError {
    case permission, noApplication, noSelection, unsupported, secureField, tooLong

    var errorDescription: String? {
        switch self {
        case .permission: "Tillåt hjälpmedelsåtkomst för smool för att läsa markerad text."
        case .noApplication: "Markera text i en annan app och tryck ⌃⌥C."
        case .noSelection: "Ingen text är markerad. Markera text och tryck ⌃⌥C igen."
        case .unsupported: "Appen kunde inte lämna den markerade texten."
        case .secureField: "Text från lösenordsfält hämtas inte."
        case .tooLong: "Markeringen är för lång. Välj högst 64 kB text."
        }
    }
}

enum SelectedTextCapture {
    /// Capture the target before smool becomes key. No clipboard reads or synthetic copying.
    @MainActor static func capture() async throws -> SelectedText {
        guard AXIsProcessTrusted() else { throw SelectionCaptureError.permission }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw SelectionCaptureError.noApplication
        }
        let pid = app.processIdentifier
        let name = app.localizedName ?? "Appen"

        return try await Task.detached(priority: .userInitiated) {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.5)
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
                  let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
                throw SelectionCaptureError.unsupported
            }
            let element = unsafeDowncast(focused, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(element, 0.5)
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            guard subrole as? String != kAXSecureTextFieldSubrole as String else {
                throw SelectionCaptureError.secureField
            }

            var selected: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected)
            guard result == .success else {
                throw result == .noValue ? SelectionCaptureError.noSelection : SelectionCaptureError.unsupported
            }
            return try validated(selected as? String ?? "", applicationName: name)
        }.value
    }

    static func validated(_ text: String, applicationName: String) throws -> SelectedText {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SelectionCaptureError.noSelection }
        guard text.utf8.count <= 65_536 else { throw SelectionCaptureError.tooLong }
        return SelectedText(text: text, applicationName: applicationName)
    }

    @MainActor static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
