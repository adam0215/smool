import SwiftUI

struct AudioAppletView: View {
    @Bindable var applet: AudioApplet
    var restoreFocus: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    private var service: AudioService { applet.service }

    var body: some View {
        VStack(spacing: 12) {
            if let direction = applet.picker {
                devicePicker(direction)
                    .transition(.opacity)
            } else {
                HStack(spacing: 24) {
                    VStack(spacing: 8) {
                        deviceControl(.output, index: 0)
                        deviceControl(.input, index: 1)
                    }
                    volumeControl
                }
                .transition(.opacity)
                Text(service.state.volume.isAdjustable
                     ? "←→ Output/mic · ↑↓ Volume · M Mute"
                     : "←→ Output/mic · Volume controlled by device")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            if let error = service.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(interactions: .edit)
        .focused($focused)
        .focusEffectDisabled()
        .onAppletFocusRestore { focused = true }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: applet.picker)
        .onAppear { service.start() }
        .onDisappear { service.stop() }
        .task { await Task.yield(); focused = true }
        .onKeyPress(keys: [.return, .space]) { key in
            guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            if applet.picker != nil { applet.selectDevice() }
            else { applet.openPicker(applet.selectedControl == 0 ? .output : .input) }
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { key in
            guard applet.picker != nil,
                  key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            _ = applet.handleArrow(key.key == .upArrow ? .up : .down, command: false)
            return .handled
        }
        .onKeyPress("m", phases: .down) { key in
            guard applet.picker == nil,
                  key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            service.toggleMute()
            return .handled
        }
        .onKeyPress(.escape) {
            guard applet.picker != nil else { return .ignored }
            applet.dismissOverlay()
            return .handled
        }
        .onChange(of: applet.picker) { _, picker in
            if picker == nil { restoreFocus() }
            focused = true
        }
    }

    private func deviceControl(_ direction: AudioDirection, index: Int) -> some View {
        Button { applet.openPicker(direction) } label: {
            HStack(spacing: 12) {
                Image(systemName: direction.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(applet.selectedControl == index ? .white : .secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 5) {
                    Text(direction.title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Text(service.state.selectedDevice(for: direction)?.name ?? "No device")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(.white.opacity(applet.selectedControl == index ? 0.07 : 0), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel("Choose \(direction.title.lowercased())")
        .accessibilityValue(service.state.selectedDevice(for: direction)?.name ?? "No device")
        .accessibilityAddTraits(applet.selectedControl == index ? .isSelected : [])
    }

    private var volumeControl: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .fill(.white.opacity(service.state.volume.isAdjustable ? 0.8 : 0.15))
                        .frame(height: geometry.size.height * CGFloat(service.state.volume.value))
                    Image(systemName: service.state.volume.isAdjustable && service.state.volume.value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(service.state.volume.value > 0.2 ? .black.opacity(0.7) : .white.opacity(0.7))
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 18))
                .modifier(FloatingGlass(cornerRadius: 18))
                .clipShape(.rect(cornerRadius: 18))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    service.setVolume(Float32(1 - value.location.y / geometry.size.height))
                })
                .accessibilityElement()
                .accessibilityLabel("Output volume")
                .accessibilityValue(service.state.volume.isAdjustable ? "\(Int(service.state.volume.value * 100)) percent" : "Fixed volume")
                .accessibilityAdjustableAction { direction in
                    service.setVolume(service.state.volume.value + (direction == .increment ? 0.05 : -0.05))
                }
                .accessibilityHint("Up and down arrows adjust volume by five percent. M toggles mute.")
            }
            .frame(width: 48, height: 106)
            Text(service.state.volume.isAdjustable ? "\(Int(service.state.volume.value * 100))%" : "Fixed")
                .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func devicePicker(_ direction: AudioDirection) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Choose \(direction.title.lowercased())").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            let devices = service.state.devices(for: direction)
            if devices.isEmpty {
                Text("No devices available").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                                Button {
                                    applet.selectedDeviceIndex = index
                                    applet.selectDevice()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: direction.symbol).frame(width: 20)
                                        Text(device.name).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 0)
                                        if device.id == service.state.selectedID(for: direction) {
                                            Image(systemName: "checkmark").foregroundStyle(.cyan)
                                        }
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 12).frame(height: 36)
                                    .background(.white.opacity(applet.selectedDeviceIndex == index ? 0.1 : 0), in: .rect(cornerRadius: 12))
                                    .contentShape(.rect(cornerRadius: 12))
                                }
                                .buttonStyle(.plain).focusable(false)
                                .accessibilityAddTraits(device.id == service.state.selectedID(for: direction) ? .isSelected : [])
                                .id(index)
                            }
                        }
                    }
                    .onChange(of: applet.selectedDeviceIndex) { _, index in proxy.scrollTo(index, anchor: .center) }
                    .onAppear { proxy.scrollTo(applet.selectedDeviceIndex, anchor: .center) }
                }
            }
        }
        .frame(height: 152)
    }
}
