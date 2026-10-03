import SwiftUI

/// A stack owns vertical page navigation. Pages can enter their own editing scope.
struct PageStack<Page: Hashable, Content: View>: View {
    let pages: [Page]
    @Binding var selection: Page
    let title: (Page) -> String
    var isNavigating = true
    var autoFocus = true
    var editingHint = "⌘↵ skicka   ·   esc tillbaka"
    var navigationHint: String? = nil
    @ViewBuilder let content: (Page) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var stackFocused: Bool
    @State private var movement = 1

    private var index: Int { pages.firstIndex(of: selection) ?? 0 }
    private var neighbors: [Page] { pages.filter { $0 != selection }.prefix(2).map { $0 } }
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
                Button { select(page) } label: {
                    Text(title(page))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 16, alignment: .top)
                        .padding(.top, 3)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .modifier(CardGlass(shape: cardShape))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(!isNavigating)
                .padding(.horizontal, CGFloat(neighbors.count - depth) * 8)
                .padding(.top, CGFloat(depth) * 16)
                .padding(.bottom, 8)
                .accessibilityLabel("Visa \(title(page))")
            }

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(title(selection))
                        .font(.system(size: 11, weight: .medium))
                        .modifier(GlassInk(illumination: 1, isSelected: true))
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
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(y: CGFloat(movement) * 14).combined(with: .opacity),
                        removal: .offset(y: CGFloat(movement) * -14).combined(with: .opacity)
                    ))
                    .clipped()

                Text(isNavigating ? navigationHint ?? "↑↓ kort   ·   ↵ öppna   ·   ⌘0–2 flik" : editingHint)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }
            .padding(16)
            .modifier(CardGlass(shape: cardShape, isSelected: isNavigating))
            .padding(.top, CGFloat(neighbors.count) * 16)
        }
        .padding(.horizontal, NotchLayout.contentInset)
        .padding(.top, 0)
        .padding(.bottom, NotchLayout.contentInset)
        .focusable(isNavigating, interactions: .edit)
        .focused($stackFocused)
        .focusEffectDisabled()
        .onAppear { if autoFocus { stackFocused = true } }
        .onChange(of: isNavigating) { _, navigating in
            if autoFocus { stackFocused = navigating }
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard isNavigating, press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            select(adjacentPage(in: pages, to: selection, offset: press.key == .upArrow ? -1 : 1))
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title(selection)), kort \(index + 1) av \(pages.count)")
    }

    private func pageButton(_ symbol: String, offset: Int) -> some View {
        Button { select(adjacentPage(in: pages, to: selection, offset: offset)) } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isNavigating || adjacentPage(in: pages, to: selection, offset: offset) == selection)
        .accessibilityLabel(offset < 0 ? "Föregående kort" : "Nästa kort")
        .help(offset < 0 ? "Föregående kort · ↑" : "Nästa kort · ↓")
    }

    private func select(_ page: Page) {
        movement = (pages.firstIndex(of: page) ?? index) >= index ? 1 : -1
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { selection = page }
    }
}
