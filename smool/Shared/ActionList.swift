import SwiftUI

struct ActionList: View {
    var title = "Actions"
    let actions: [AppletAction]
    let dismiss: () -> Void
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                            Button { invoke(action) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: action.symbol).frame(width: 16)
                                    Text(action.id)
                                    Spacer(minLength: 12)
                                    if action.selected { Image(systemName: "checkmark").font(.caption2) }
                                    Text(action.shortcut).foregroundStyle(.secondary).font(.caption)
                                }
                                .font(.system(size: 12))
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(.white.opacity(highlighted == index ? 0.1 : 0), in: .rect(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).focusable(false)
                            .id(index)
                            .onHover { if $0 { highlighted = index } }
                            .accessibilityAddTraits(action.selected ? .isSelected : [])
                        }
                    }
                }
                .frame(height: min(CGFloat(actions.count) * 40, 320))
                .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
            }
        }
        .padding(8).frame(width: 300)
        .focusable(interactions: .edit).focused($focused).focusEffectDisabled()
        .task { await Task.yield(); focused = true }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { key in
            guard !actions.isEmpty else { return .ignored }
            highlighted = (highlighted + (key.key == .upArrow ? actions.count - 1 : 1)) % actions.count
            return .handled
        }
        .onChange(of: actions.count) { _, count in highlighted = min(highlighted, max(0, count - 1)) }
        .onKeyPress(.return) {
            guard actions.indices.contains(highlighted) else { return .ignored }
            invoke(actions[highlighted])
            return .handled
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func invoke(_ action: AppletAction) {
        dismiss()
        action.perform()
    }
}
