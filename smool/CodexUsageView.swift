import SwiftUI

struct CodexUsageView: View {
    let service: CodexService
    @Binding var index: Int

    private var pageCount: Int { max(1, (service.limits.count + 1) / 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if service.limits.isEmpty {
                Text(service.isLoading ? "Hämtar användning…" : "Användning är inte tillgänglig")
                    .font(.system(size: 12, weight: .medium))
                Text(service.error ?? "Logga in på ditt konto i Codex och uppdatera.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            } else {
                ForEach(Array(service.limits.dropFirst(index * 2).prefix(2))) { limit in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(limit.title).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer()
                            Text("\(Int(max(0, min(100, 100 - limit.usedPercent))))% kvar").monospacedDigit()
                        }
                        .font(.system(size: 11, weight: .medium))
                        ProgressView(value: max(0, min(100, 100 - limit.usedPercent)), total: 100)
                            .tint(.white.opacity(0.65))
                        if let reset = limit.resetAt {
                            HStack(spacing: 3) {
                                Text("Återställs")
                                Text(reset, format: .dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "sv_SE")))
                            }
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button { Task { await service.refresh() } } label: {
                    ShortcutLabel("Uppdatera", keys: "⌘R")
                }
                    .buttonStyle(NotchControlStyle())
                    .disabled(service.isLoading)
                Spacer()
                if pageCount > 1 {
                    Button { index = max(0, index - 1) } label: { Text("←") }
                        .disabled(index == 0)
                        .accessibilityLabel("Föregående användningsgränser")
                    Text("\(index + 1) / \(pageCount)").foregroundStyle(.secondary)
                    Button { index = min(pageCount - 1, index + 1) } label: { Text("→") }
                        .disabled(index == pageCount - 1)
                        .accessibilityLabel("Nästa användningsgränser")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
        }
        .onChange(of: service.limits.count) { _, _ in index = min(index, pageCount - 1) }
    }
}
