import Carbon

@MainActor
final class GlobalShortcut {
    enum Command: UInt32 {
        case panel = 1, selection

        var keyCode: UInt32 {
            self == .panel ? UInt32(kVK_Space) : UInt32(kVK_ANSI_C)
        }
    }

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let command: Command
    private let action: () -> Void

    init(command: Command = .panel, action: @escaping () -> Void) throws {
        self.command = command
        self.action = action

        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }

                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == 0x534D4F4C else {
                    return OSStatus(eventNotHandledErr)
                }

                return MainActor.assumeIsolated {
                    let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                    guard identifier.id == shortcut.command.rawValue else { return OSStatus(eventNotHandledErr) }
                    shortcut.action()
                    return noErr
                }
            },
            1,
            &event,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        guard handlerStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(handlerStatus))
        }

        let identifier = EventHotKeyID(signature: 0x534D4F4C, id: command.rawValue)
        let status = RegisterEventHotKey(command.keyCode, UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)

        guard status == noErr else {
            stop()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
