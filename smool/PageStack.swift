import SwiftUI

/// A stack owns vertical page navigation. Pages can enter their own editing scope.
struct PageStack<Page: Hashable, Content: View>: View {
    let pages: [Page]
    @Binding var selection: Page
    let title: (Page) -> String
    var showsTitle = true
    var elevated = true
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

    var body: some View {
        ZStack(alignment: .top) {
            if elevated {
                ForEach(Array(neighbors.enumerated()), id: \.element) { depth, page in
                    GlassEffectContainer(spacing: 0) {
                        Button { select(page) } label: {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 20)
                                .background(.black, in: .rect(cornerRadius: 16))
                                .modifier(CardGlass(shape: RoundedRectangle(cornerRadius: 16)))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .disabled(!isNavigating)
                        .accessibilityLabel("Visa \(title(page))")
                    }
                    .padding(.horizontal, CGFloat(neighbors.count - depth) * 12)
                    .padding(.top, CGFloat(depth) * 6)
                }
            }

            GlassEffectContainer(spacing: 0) {
                VStack(spacing: 10) {
                    if showsTitle {
                        HStack(spacing: 8) {
                            Text(title(selection))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(pages, id: \.self) { page in
                                    Circle().fill(.white.opacity(page == selection ? 0.65 : 0.15))
                                        .frame(width: 3, height: 3)
                                }
                            }
                            .accessibilityHidden(true)
                        }
                    }

                    content(selection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .id(selection)
                        .transition(.identity)
                        .clipped()
                }
                .modifier(NotchCard(elevated: elevated))
                .shadow(color: .black.opacity(elevated ? 0.5 : 0), radius: 8, y: -3)
            }
            .padding(.top, elevated ? CGFloat(neighbors.count) * 6 : 0)
        }
        .padding(.horizontal, NotchLayout.contentInset)
        .padding(.top, 0)
        .padding(.bottom, NotchLayout.contentInset)
        .focusable(interactions: .edit)
        .focused($stackFocused)
        .focusEffectDisabled()
        .task { await Task.yield(); stackFocused = isNavigating }
        .onChange(of: isNavigating) { _, navigating in
            stackFocused = navigating
        }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
            guard isNavigating, press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            move(press.key == .upArrow ? -1 : 1)
            return .handled
        }
        .notchHelp(isNavigating ? navigationHint ?? "↑↓ Byt kort\n↵ Öppna\n⌘1–4 Byt flik\n? Stäng hjälpen" : editingHint)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title(selection)), kort \(index + 1) av \(pages.count)")
    }

    private func move(_ offset: Int) {
        select(cyclingPage(in: pages, to: selection, offset: offset))
    }

    private func select(_ page: Page) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { selection = page }
    }
}
