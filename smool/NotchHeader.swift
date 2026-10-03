import SwiftUI

/// Places content beside the notch and supplies a center fallback for unobstructed displays.
/// Place ordinary content below this view in a VStack with zero spacing.
struct NotchHeader<Leading: View, Center: View, Trailing: View>: View {
    let layout: NotchLayout
    private let sideInset: CGFloat
    private let leading: Leading
    private let center: Center
    private let trailing: Trailing

    init(
        layout: NotchLayout,
        sideInset: CGFloat = 12,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.layout = layout
        self.sideInset = sideInset
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { geometry in
            let regions = layout.headerRegions(in: geometry.size.width)

            HStack(spacing: 0) {
                ZStack { leading }
                    .padding(.horizontal, sideInset)
                    .frame(width: regions.leading.width, height: regions.leading.height)
                    .clipped()
                    .contentShape(Rectangle())

                ZStack {
                    if !layout.notch.obscuresCenter {
                        center
                    }
                }
                .frame(width: regions.center.width, height: regions.center.height)
                .clipped()

                ZStack { trailing }
                    .padding(.horizontal, sideInset)
                    .frame(width: regions.trailing.width, height: regions.trailing.height)
                    .clipped()
                    .contentShape(Rectangle())
            }
        }
        .frame(height: layout.headerSize.height)
    }
}

#if DEBUG
#Preview("Utan notch") {
    NotchHeaderPreview(notch: .none)
}

#Preview("Fysisk notch") {
    NotchHeaderPreview(notch: .physical(ScreenNotch.referenceSize))
}

#Preview("Demonotch") {
    NotchHeaderPreview(notch: .simulated(ScreenNotch.referenceSize))
}

private struct NotchHeaderPreview: View {
    let notch: ScreenNotch

    var body: some View {
        NotchHeader(layout: NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), notch: notch)) {
            Image(systemName: "waveform")
        } center: {
            Text("smool")
        } trailing: {
            Text("12:34")
        }
        .frame(width: 440)
        .foregroundStyle(.white)
        .background(.black)
    }
}
#endif
