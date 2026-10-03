import SwiftUI

struct NotchStatusItem: Identifiable, Equatable {
    let id: AppletID
    let status: AppletStatus
}

struct NotchStatusView: View {
    let items: [NotchStatusItem]
    let layout: NotchLayout
    let activate: (AppletID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if layout.notch.obscuresCenter {
                Color.clear.frame(width: layout.headerSize.width)
                    .allowsHitTesting(false)
            }
            ForEach(items) { item in
                Button { activate(item.id) } label: {
                    statusIcon(item)
                        .foregroundStyle(statusColor(item.status))
                        .frame(width: 28, height: layout.headerSize.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(item.status.label)
                .accessibilityLabel(item.status.label)
            }
        }
        .padding(.trailing, items.isEmpty ? 0 : NotchLayout.statusTrailingInset)
        .frame(height: layout.headerSize.height)
    }

    private func statusColor(_ status: AppletStatus) -> Color {
        switch status.kind {
        case .needsAttention: .orange
        case .completed: .green
        case .working: .white.opacity(0.85)
        }
    }

    @ViewBuilder
    private func statusIcon(_ item: NotchStatusItem) -> some View {
        if item.id.rawValue == "codex" {
            AppletIcon.asset("Codex").image(size: 13)
        } else {
            Image(systemName: item.status.symbol)
                .font(.system(size: 12, weight: .medium))
        }
    }
}
