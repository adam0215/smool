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
                    Image(systemName: item.status.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.status.kind == .needsAttention ? .orange : .white.opacity(0.85))
                        .frame(width: 28, height: layout.headerSize.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(item.status.label)
                .accessibilityLabel(item.status.label)
            }
        }
        .frame(height: layout.headerSize.height)
    }
}
