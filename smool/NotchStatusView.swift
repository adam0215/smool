import SwiftUI

struct NotchStatusItem: Identifiable, Equatable {
    let id: AppletID
    let status: AppletStatus
}

/// Fixed side regions keep live information outside the camera cutout.
struct NotchStatusView: View {
    let items: [NotchStatusItem]
    let layout: NotchLayout
    let activate: (AppletID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            status(at: 0)
            if layout.notch.obscuresCenter {
                Color.clear.frame(width: layout.headerSize.width)
                    .allowsHitTesting(false)
            }
            status(at: 1)
        }
        .frame(height: layout.headerSize.height)
        .foregroundStyle(.white)
    }

    private func status(at index: Int) -> some View {
        Group {
            if items.indices.contains(index) {
                let item = items[index]
                Button { activate(item.id) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.status.symbol)
                            .foregroundStyle(item.status.kind == .needsAttention ? .orange : .white.opacity(0.75))
                        if let deadline = item.status.countdownDeadline {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(Self.remaining(until: deadline, at: context.date))
                            }
                        } else {
                            Text(item.status.label).lineLimit(1)
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.status.label)
                .accessibilityLabel(item.status.label)
            } else {
                Color.clear.allowsHitTesting(false)
            }
        }
        .frame(width: Self.sideWidth)
    }

    static let sideWidth: CGFloat = 112

    private static func remaining(until deadline: Date, at now: Date) -> String {
        let seconds = Int(max(0, min(604_800, ceil(deadline.timeIntervalSince(now)))))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func size(layout: NotchLayout, hasStatus: Bool) -> CGSize {
        guard hasStatus else { return layout.collapsedSize }
        return CGSize(width: (layout.notch.obscuresCenter ? layout.headerSize.width : 0) + sideWidth * 2,
                      height: layout.headerSize.height)
    }
}
