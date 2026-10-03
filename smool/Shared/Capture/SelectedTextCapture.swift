import AppKit
@preconcurrency import ApplicationServices

struct SelectedText: Sendable, Equatable {
    let text: String
    let applicationName: String
}

enum SelectionCaptureError: Error, LocalizedError, Equatable {
    case permission, noApplication, noSelection, unsupported, secureField, tooLong

    var errorDescription: String? {
        switch self {
        case .permission: "Allow Accessibility access for smool to read selected text."
        case .noApplication: "Select text in another app and press ⌃⌥C."
        case .noSelection: "No text is selected. Select text and press ⌃⌥C again."
        case .unsupported: "The app could not provide the selected text."
        case .secureField: "Text from password fields is not captured."
        case .tooLong: "The selection is too long. Select up to 64 kB of text."
        }
    }
}

enum SelectionPreview {
    case text(SelectedText)
    case failure(SelectionCaptureError)

    var selection: SelectedText? {
        if case .text(let text) = self { return text }
        return nil
    }

    var error: SelectionCaptureError? {
        if case .failure(let error) = self { return error }
        return nil
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
        let name = app.localizedName ?? "App"

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
