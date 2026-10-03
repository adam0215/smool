import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let registry: AppletRegistry

    private var registeredIDs: [AppletID] { registry.applets.map(\.id) }
    private var orderedIDs: [AppletID] { settings.orderedIDs(in: registeredIDs) }
    private var frontIDs: [AppletID] { settings.frontIDs(in: registeredIDs) }
    private var unavailableFrontIDs: [AppletID] {
        settings.frontAppletIDs.filter { !registeredIDs.contains($0) }
    }

    var body: some View {
        TabView {
            general
                .tabItem { Label("Allmänt", systemImage: "gearshape") }

            applets
                .tabItem { Label("Applets", systemImage: "square.grid.2x2") }
        }
        .padding(16)
        .frame(width: 590, height: 600)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Visa demonotch", isOn: $settings.demoNotchEnabled)
                Toggle("Visa batteri i panelens överkant", isOn: $settings.showBattery)
            } header: {
                Text("Utseende")
            } footer: {
                Text("Demonotchen visas på skärmar som saknar en fysisk notch.")
            }

            Section {
                Toggle("Timers", isOn: $settings.showTimerStatus)
                Toggle("Codex", isOn: $settings.showCodexStatus)
            } header: {
                Text("Diskret status när panelen är stängd")
            } footer: {
                Text("Visa pågående timers och när Codex behöver din uppmärksamhet.")
            }

            Section("Tangentbord") {
                LabeledContent("Visa eller dölj smool", value: "⌃⌥Space")
                LabeledContent("Gör något med markerad text", value: "⌃⌥C")
                LabeledContent("Välj applet", value: "⌘1–9")
                LabeledContent("Nästa eller föregående applet", value: "⌃Tab / ⌃⇧Tab")
                LabeledContent("Inställningar", value: "⌘,")
            }
        }
        .formStyle(.grouped)
    }

    private var applets: some View {
        Form {
            Section {
                ForEach(orderedIDs, id: \.self) { id in
                    if let applet = registry.applet(for: id) {
                        appletRow(applet)
                    }
                }
            } header: {
                HStack {
                    Text("Applets och ordning")
                    Spacer()
                    Text("Framsida")
                }
            } footer: {
                Text("Välj upp till tre applets på framsidan. Klockan visas alltid. Pilarna ändrar ordningen på framsidan och bland flikarna, inklusive deras kortkommandon.")
            }

            if !unavailableFrontIDs.isEmpty {
                Section("Sparade val som inte är tillgängliga") {
                    ForEach(unavailableFrontIDs, id: \.self) { id in
                        HStack {
                            Text(id.rawValue)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Ta bort från framsidan") {
                                settings.setFront(false, for: id, in: registeredIDs)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func appletRow(_ applet: any Applet) -> some View {
        let id = applet.id
        let isHome = id.rawValue == "home"
        let enabled = settings.isEnabled(id)
        let selected = frontIDs.contains(id)
        let index = orderedIDs.firstIndex(of: id) ?? 0

        return HStack(spacing: 12) {
            applet.icon.view
                .frame(width: 18)
                .foregroundStyle(enabled ? .primary : .secondary)
                .accessibilityHidden(true)

            Toggle(applet.title, isOn: Binding(
                get: { settings.isEnabled(id) },
                set: { settings.setEnabled($0, for: id) }
            ))
            .disabled(isHome)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHome {
                Text("Alltid tillgänglig")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Button {
                        settings.move(id, offset: -1, in: registeredIDs)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index <= (orderedIDs.first?.rawValue == "home" ? 1 : 0))
                    .help("Flytta \(applet.title) uppåt")
                    .accessibilityLabel("Flytta \(applet.title) uppåt")

                    Button {
                        settings.move(id, offset: 1, in: registeredIDs)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == orderedIDs.count - 1)
                    .help("Flytta \(applet.title) nedåt")
                    .accessibilityLabel("Flytta \(applet.title) nedåt")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Toggle("Visa \(applet.title) på framsidan", isOn: Binding(
                    get: { frontIDs.contains(id) },
                    set: { settings.setFront($0, for: id, in: registeredIDs) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!enabled || (!selected && frontIDs.count + unavailableFrontIDs.count >= 3))
                .help("Visa \(applet.title) på framsidan")
                .frame(width: 50)
            }
        }
        .padding(.vertical, 4)
    }
}
