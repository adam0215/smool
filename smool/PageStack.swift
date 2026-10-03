import SwiftUI

/// A stack owns vertical page navigation. Pages can enter their own editing scope.
struct PageStack<Page: Hashable, Content: View>: View {
    let pages: [Page]
    @Binding var selection: Page
    let title: (Page) -> String
    var isNavigating = true
    var editingHint = "⌘↵ skicka   ·   esc tillbaka"
    var navigationHint: String? = nil
    @ViewBuilder let content: (Page) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var stackFocused: Bool

    private var index: Int { pages.firstIndex(of: selection) ?? 0 }
    private var neighbors: [Page] {
        guard pages.count > 1 else { return [] }
        return (1...min(2, pages.count - 1)).reversed().map {
            cyclingPage(in: pages, to: selection, offset: $0)
        }
    }

    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: NotchLayout.bottomRadius - NotchLayout.contentInset,
            bottomTrailingRadius: NotchLayout.bottomRadius - NotchLayout.contentInset,
            topTrailingRadius: 16,
            style: .circular
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(neighbors.enumerated()), id: \.element) { depth, page in
                GlassEffectContainer(spacing: 0) {
                    Button { select(page) } label: {
                        Text(title(page))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .padding(.bottom, 14)
                            .background(.black, in: .rect(cornerRadius: 16))
                            .modifier(CardGlass(shape: RoundedRectangle(cornerRadius: 16)))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(!isNavigating)
                    .accessibilityLabel("Visa \(title(page))")
                }
                .padding(.horizontal, CGFloat(neighbors.count - depth) * 12)
                .padding(.top, CGFloat(depth) * 24)
            }

            GlassEffectContainer(spacing: 0) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Text(title(selection))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(index + 1) / \(pages.count)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        pageButton("chevron.up", offset: -1)
                        pageButton("chevron.down", offset: 1)
                    }

                    content(selection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .id(selection)
                        .transition(.identity)
                        .clipped()

                    Text(isNavigating ? navigationHint ?? "↑↓ kort   ·   ↵ öppna   ·   ⌘0–2 flik" : editingHint)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 2)
                }
                .padding(16)
                .modifier(CardGlass(shape: cardShape, isSelected: true))
                .shadow(color: .black.opacity(0.5), radius: 8, y: -3)
            }
            .padding(.top, CGFloat(neighbors.count) * 24)
        }
        .padding(.horizontal, NotchLayout.contentInset)
        .padding(.top, 0)
        .padding(.bottom, NotchLayout.contentInset)
        .focusable(interactions: .edit)
        .focused($stackFocused)
        .focusEffectDisabled()
        .onAppear { stackFocused = isNavigating }
        .onChange(of: isNavigating) { _, navigating in
            stackFocused = navigating
        }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
            guard isNavigating, press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            move(press.key == .upArrow ? -1 : 1)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title(selection)), kort \(index + 1) av \(pages.count)")
    }

    private func pageButton(_ symbol: String, offset: Int) -> some View {
        Button { move(offset) } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isNavigating || pages.count < 2)
        .accessibilityLabel(offset < 0 ? "Föregående kort" : "Nästa kort")
        .help(offset < 0 ? "Föregående kort · ↑" : "Nästa kort · ↓")
    }

    private func move(_ offset: Int) {
        select(cyclingPage(in: pages, to: selection, offset: offset))
    }

    private func select(_ page: Page) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { selection = page }
    }
}
