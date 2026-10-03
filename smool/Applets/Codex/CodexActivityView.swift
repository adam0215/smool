import SwiftUI

struct CodexActivityView: View {
    let presentation: CodexActivityPresentation
    let isLive: Bool
    var unavailableReason: String?

    var runningTools: [CodexActivityItem] { isLive ? presentation.runningTools : [] }
    var workingSummary: CodexActivityItem? { isLive ? presentation.workingSummary : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let message = presentation.latestMessage {
                    Text(activityMarkdown(message.text))
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .lineLimit(runningTools.isEmpty ? 6 : 4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let summary = workingSummary {
                    Text(activityMarkdown(summary.text))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                ForEach(runningTools) { tool in
                    VStack(alignment: .leading, spacing: 3) {
                        ShimmeringText(tool.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !tool.text.isEmpty {
                            Text(tool.text)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if let unavailableReason {
                    Text(unavailableReason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if !isLive, presentation.attention == .working {
                    ShimmeringText("Updating latest message…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

struct CodexHistoryPreviewView: View {
    let title: String
    let message: CodexActivityItem?
    var isLoading = false
    var isWorking = false
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShimmeringText(title, isActive: isWorking)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isWorking ? .secondary : .primary)
                .lineLimit(2)

            CodexMessagePreviewView(message: message, isLoading: isLoading, error: error)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct CodexMessagePreviewView: View {
    let message: CodexActivityItem?
    var isLoading = false
    var error: String?

    var body: some View {
        Group {
            if let message {
                Text(activityMarkdown(message.text))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            } else if isLoading {
                ShimmeringText("Reading latest message…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(error ?? "No message available")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func activityMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}
