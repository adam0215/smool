import SwiftUI

struct NotchTabBar: View {
    let presentation: NotchPresentation
    let select: (AppletID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.everyMinute) { context in
                Text(greeting(at: context.date))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                GlassEffectContainer(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(presentation.registry.applets, id: \.id) { applet in
                            Button { select(applet.id) } label: {
                                applet.icon.view
                                    .foregroundStyle(.white.opacity(presentation.selection == applet.id ? 1 : 0.65))
                                    .frame(width: 26, height: 26)
                                    .glassEffect(.clear.tint(applet.tint.opacity(presentation.selection == applet.id ? 0.12 : 0.015)), in: .circle)
                                    .overlay { Circle().strokeBorder(.white.opacity(presentation.selection == applet.id ? 0.18 : 0), lineWidth: 0.5) }
                            }
                            .buttonStyle(.plain).focusable(false)
                            .accessibilityLabel(applet.title)
                            .accessibilityAddTraits(presentation.selection == applet.id ? .isSelected : [])
                            .help(applet.title)
                        }
                    }
                }

                Spacer(minLength: 8)
                if !presentation.activeApplet.pages.isEmpty { pageIndicators }
                TimelineView(.everyMinute) { _ in
                    if let battery = BatteryStatus.current() {
                        HStack(spacing: 3) {
                            Text("\(battery.percentage)%").font(.system(size: 9)).monospacedDigit()
                            Image(systemName: battery.symbolName).font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(battery.description)
                    }
                }
                NotchActionsMenu(presentation: presentation)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .padding(.top, presentation.layout.notch.obscuresCenter ? presentation.layout.headerSize.height : 0)
    }

    private var pageIndicators: some View {
        HStack(spacing: 0) {
            ForEach(presentation.activeApplet.pages) { page in
                Button(action: page.select) {
                    Capsule().fill(.white.opacity(page.isSelected ? 0.85 : 0.25))
                        .frame(width: page.isSelected ? 10 : 4, height: 4)
                        .frame(width: 14, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false)
                .accessibilityLabel(page.id)
                .accessibilityAddTraits(page.isSelected ? .isSelected : [])
                .help(page.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidor")
    }

    private func greeting(at date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let salutation: String
        switch hour {
        case 5..<10: salutation = "God morgon"
        case 10..<12: salutation = "God förmiddag"
        case 12..<18: salutation = "God eftermiddag"
        case 18..<23: salutation = "God kväll"
        default: salutation = "God natt"
        }
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
        return "\(salutation), \(name)"
    }
}
