import Foundation

@main
struct SelectedTextChecks {
    static func main() throws {
        let source = "  let café = 1\n"
        let selected = try SelectedTextCapture.validated(source, applicationName: "Editor")
        precondition(selected.text == source, "Preserve indentation and newlines")
        precondition(selected.applicationName == "Editor")
        for text in ["", " \n\t", String(repeating: "å", count: 32_769)] {
            do {
                _ = try SelectedTextCapture.validated(text, applicationName: "Test")
                preconditionFailure("Reject empty or oversized input")
            } catch is SelectionCaptureError { }
        }
        _ = try SelectedTextCapture.validated(String(repeating: "a", count: 65_536), applicationName: "Test")
        print("Selected text checks passed")
    }
}
