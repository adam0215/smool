import SwiftUI

struct CodexUsageView: View {
    let service: CodexService

    var body: some View {
        VStack(spacing: 10) {
            if let limit = service.limits.first(where: { $0.isCodexWeek }) {
                let remaining = max(0, min(100, 100 - limit.usedPercent))
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: remaining / 100)
                        .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(remaining))%")
                        .font(.system(size: 58, weight: .medium))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .padding(16)
                }
                .frame(width: 156, height: 156)
                .padding(4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Codex, \(Int(remaining)) procent kvar av sjudagarsgränsen")

                if let reset = limit.resetAt {
                    Text("Återställs \(reset.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "sv_SE"))))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(service.isLoading ? "Hämtar användning…" : "Sjudagarsgränsen är inte tillgänglig")
                    .font(.caption)
                if let error = service.error {
                    Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
