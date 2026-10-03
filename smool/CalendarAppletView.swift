import SwiftUI
import EventKit

struct CalendarAppletView: View {
    let service: CalendarService
    let close: () -> Void
    @FocusState private var focused: Bool
    @State private var selectedEvent = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(service.day, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 18, weight: .medium))

            if service.isLoading {
                ProgressView("Hämtar kalender…").font(.caption)
            } else if let message = service.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                if service.needsPermission {
                    Button("Öppna Systeminställningar", action: openSettings)
                    .buttonStyle(NotchControlStyle())
                }
            } else if service.events.isEmpty {
                Text("Inget planerat").foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(service.events.enumerated()), id: \.offset) { index, event in
                                HStack(alignment: .top, spacing: 12) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(cgColor: event.calendar.cgColor))
                                        .frame(width: 3, height: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.title ?? "Namnlös händelse")
                                            .font(.system(size: 13, weight: .medium))
                                        Text(event.isAllDay ? "Hela dagen" : "\(event.startDate.formatted(date: .omitted, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(index == selectedEvent ? 0.06 : 0), in: .rect(cornerRadius: 8))
                                .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: selectedEvent) { _, index in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Text("←→ dag   ·   ↑↓ händelser   ·   ↵ Kalender   ·   esc tillbaka")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(CardGlass(shape: RoundedRectangle(cornerRadius: 32), isSelected: true))
        .padding(.horizontal, NotchLayout.contentInset)
        .padding(.bottom, NotchLayout.contentInset)
        .focusable(interactions: .edit)
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .task(id: service.day) {
            selectedEvent = 0
            await service.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await service.load() }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { key in
            guard key.modifiers.isEmpty else { return .ignored }
            if key.key == .leftArrow || key.key == .rightArrow {
                service.moveDay(key.key == .leftArrow ? -1 : 1)
            } else {
                selectedEvent = min(max(0, selectedEvent + (key.key == .upArrow ? -1 : 1)), max(0, service.events.count - 1))
            }
            return .handled
        }
        .onKeyPress(.return) {
            if service.needsPermission { openSettings() }
            else { service.openCalendar() }
            return .handled
        }
        .onKeyPress(.escape) { close(); return .handled }
    }

    private func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
