import SwiftUI

struct CodexUsageView: View {
    let service: CodexService

    var body: some View {
        HStack(spacing: 24) {
            if let limit = service.limits.first(where: { $0.isCodexWeek }) {
                let remaining = max(0, min(100, 100 - limit.usedPercent))
                ZStack {
                    Circle().fill(.clear)
                        .modifier(CardGlass(shape: Circle()))
                        .overlay {
                            Circle().strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04), .white.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 0.75
                            )
                        }
                    Circle().stroke(.white.opacity(0.06), lineWidth: 6).padding(6)
                    Circle()
                        .trim(from: 0, to: remaining / 100)
                        .stroke(LinearGradient(colors: [.white, .white.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(6)
                    Text("\(Int(remaining))%")
                        .font(.system(size: 32, weight: .medium))
                        .monospacedDigit()
                }
                .frame(width: 100, height: 100)
                .padding(3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Codex, \(Int(remaining)) procent kvar av sjudagarsgränsen")

                if let reset = limit.resetAt {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Återställs").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(reset, format: .dateTime.day().month(.abbreviated).locale(Locale(identifier: "sv_SE")))
                            .font(.system(size: 24, weight: .medium))
                        Text(reset, format: .dateTime.hour().minute())
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(service.isLoading ? "Hämtar användning…" : "Användning är inte tillgänglig")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
