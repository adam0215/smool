import SwiftUI

struct AudioAppletView: View {
    @Bindable var applet: AudioApplet
    var restoreFocus: () -> Void = {}
    @FocusState private var focused: Bool

    private var service: AudioService { applet.service }

    var body: some View {
        VStack(spacing: 8) {
            deviceControl(.output, index: 0)
            deviceControl(.input, index: 1)
            volumeControl
            if let error = service.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusable(interactions: .edit)
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { service.start() }
        .onDisappear { service.stop() }
        .task { await Task.yield(); focused = true }
        .onKeyPress(keys: [.return, .space]) { key in
            guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty,
                  applet.selectedControl < 2 else { return .ignored }
            applet.picker = applet.selectedControl == 0 ? .output : .input
            return .handled
        }
        .onChange(of: applet.picker) { _, picker in
            if picker == nil { restoreFocus(); focused = true }
        }
        .notchHelp("↑↓ Choose control · ↵ Choose device\n←→ Adjust volume by 5%\nEsc Close devices · ? Close help")
    }

    private func deviceControl(_ direction: AudioDirection, index: Int) -> some View {
        Button {
            applet.selectedControl = index
            applet.picker = direction
        } label: {
            HStack(spacing: 10) {
                Image(systemName: direction.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(direction.title).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(service.state.selectedDevice(for: direction)?.name ?? "No device")
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.white.opacity(applet.selectedControl == index ? 0.09 : 0.035), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(applet.selectedControl == index ? 0.28 : 0), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(direction.title)
        .accessibilityValue(service.state.selectedDevice(for: direction)?.name ?? "No device")
        .accessibilityHint("Show available audio devices")
        .popover(isPresented: Binding(get: { applet.picker == direction }, set: { if !$0 { applet.picker = nil } })) {
            if service.state.devices(for: direction).isEmpty {
                Text("No devices available").font(.callout).padding(20)
            } else {
                ActionList(title: direction.title, actions: deviceActions(direction)) { applet.dismissOverlay() }
            }
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.1")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { Double(service.state.volume.value) }, set: { service.setVolume(Float32($0)) }), in: 0...1)
                .disabled(!service.state.volume.isAdjustable)
                .accessibilityLabel("Output volume")
                .accessibilityValue(service.state.volume.isAdjustable ? "\(Int(service.state.volume.value * 100)) percent" : "Fixed volume")
                .simultaneousGesture(TapGesture().onEnded { applet.selectedControl = 2 })
            Text(service.state.volume.isAdjustable ? "\(Int(service.state.volume.value * 100)) %" : "Fixed volume")
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 42, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.white.opacity(applet.selectedControl == 2 ? 0.09 : 0), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(applet.selectedControl == 2 ? 0.28 : 0), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .help(service.state.volume.isAdjustable ? "←→ Adjust volume" : "Volume is controlled by the audio device")
    }

    private func deviceActions(_ direction: AudioDirection) -> [AppletAction] {
        service.state.devices(for: direction).map { device in
            AppletAction(id: device.name, symbol: direction.symbol,
                         selected: device.id == service.state.selectedID(for: direction)) {
                service.select(device.id, for: direction)
            }
        }
    }
}
