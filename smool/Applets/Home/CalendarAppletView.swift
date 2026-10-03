import SwiftUI
import EventKit

struct CalendarAppletView: View {
    let service: CalendarService
    let close: () -> Void
    @FocusState private var focused: Bool
    @State private var selectedEvent = 0
    @State private var showsDetails = false

    private var event: EKEvent? {
        service.events.indices.contains(selectedEvent) ? service.events[selectedEvent] : service.events.first
    }

    var body: some View {
        HStack(spacing: 20) {
            Button(action: service.openCalendar) {
                VStack(spacing: 0) {
                    Text(service.day, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text(service.day, format: .dateTime.day())
                        .font(.system(size: 44, weight: .medium)).monospacedDigit()
                    Text(service.day, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(width: 72)
            }
            .buttonStyle(.plain).focusable(false)
            .accessibilityLabel("Open \(service.day.formatted(.dateTime.day().month(.wide).year())) in Calendar")

            VStack(alignment: .leading, spacing: 7) {
                if service.isLoading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        if service.isRequestingAccess {
                            Text("Allow access in the macOS dialog").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                } else if let message = service.message {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                    if service.needsPermission {
                        Button("Connect", action: connectCalendar)
                            .font(.system(size: 11)).buttonStyle(.plain)
                    }
                } else if let event {
                    HStack(spacing: 6) {
                        Circle().fill(Color(cgColor: event.calendar.cgColor)).frame(width: 5, height: 5)
                        Text(event.isAllDay ? "All day" : "\(event.startDate.formatted(date: .omitted, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                        Spacer()
                        Text("\(min(selectedEvent + 1, service.events.count)) / \(service.events.count)").foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    Button {
                        if showsDetails { service.openCalendar() }
                        else { showsDetails = true }
                    } label: {
                        HStack(spacing: 8) {
                            Text(event.title ?? "Untitled event")
                                .font(.system(size: 17, weight: .medium)).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: showsDetails ? "arrow.up.right" : "arrow.turn.down.left")
                                .font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).focusable(false)
                    if showsDetails {
                        Text([event.location, event.calendar.title].compactMap { $0 }.first { !$0.isEmpty } ?? "")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                } else {
                    Text("Nothing planned").font(.system(size: 17, weight: .medium))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.white.opacity(showsDetails ? 0.07 : 0.025), in: .rect(cornerRadius: 16))
        }
        .modifier(AppletPadding())
        .padding(.horizontal, NotchLayout.contentInset)
        .padding(.bottom, NotchLayout.contentInset)
        .focusable(interactions: .edit)
        .focused($focused)
        .onAppletFocusRestore { focused = true }
        .focusEffectDisabled()
        .task { await Task.yield(); focused = true }
        .task(id: service.day) {
            selectedEvent = 0
            showsDetails = false
            await service.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await service.load() }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { key in
            guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            showsDetails = false
            if key.key == .leftArrow || key.key == .rightArrow {
                service.moveDay(key.key == .leftArrow ? -1 : 1)
            } else {
                selectedEvent = min(max(0, selectedEvent + (key.key == .upArrow ? -1 : 1)), max(0, service.events.count - 1))
            }
            return .handled
        }
        .onKeyPress(.return) {
            if service.needsPermission { connectCalendar() }
            else if event != nil && !showsDetails { showsDetails = true }
            else { service.openCalendar() }
            return .handled
        }
        .onKeyPress(.escape) {
            if showsDetails { showsDetails = false }
            else { close() }
            return .handled
        }
        .notchHelp("←→ Change day · ↑↓ Select event\n↵ Details, then open Calendar\nesc Back · ? Close help")
    }

    private func connectCalendar() {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            Task { await service.load(requestAccess: true) }
            return
        }

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
